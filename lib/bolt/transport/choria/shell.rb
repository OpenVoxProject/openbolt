# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # Terminal shell job statuses that indicate the process has finished.
      SHELL_DONE_STATUSES = %w[stopped failed].freeze

      # The shell agent names each job with SecureRandom.uuid. A handle is
      # checked against this before it goes into a command, since 1 command
      # that removes job directories goes to every target of its group.
      SHELL_HANDLE_PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      # Job directories removed per shell.run call. 40 Windows paths stay
      # well inside the shell DDL's 10,240-character command limit after
      # the PowerShell wrapper's UTF-16LE base64 encoding.
      SHELL_JOB_DIR_BATCH_SIZE = 40

      # Targets per shell.statuses call. Every target answers for each
      # handle of its call, so 1 call for a large batch of finished jobs
      # would make each reply grow with the batch, past the broker's 1 MiB
      # limit at a few thousand targets.
      SHELL_STATUSES_BATCH_SIZE = 200

      # Bytes of file content per upload command. The shell DDL caps a
      # command at 10,240 characters and the content goes in as base64. On
      # Windows the PowerShell wrapper then encodes the whole command as
      # UTF-16LE base64 again, so its chunks are smaller.
      POSIX_UPLOAD_CHUNK_BYTES = 6_000
      WINDOWS_UPLOAD_CHUNK_BYTES = 2_000

      # Run a command on targets via the shell agent. Assumes all targets in
      # the batch are the same platform (POSIX or Windows). Mixed-platform
      # batches use the first capable target's platform for command syntax.
      #
      # @param targets [Array<Bolt::Target>] Targets in a single collective batch
      # @param command [String] Shell command to execute
      # @param options [Hash] Execution options - supports :env_vars for environment variables
      # @param position [Array] Positional info for result tracking
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>] Results for all targets
      def batch_command(targets, command, options = {}, position = [], &callback)
        result_opts = { action: 'command', name: command, position: position }
        shell_targets, results = prepare_targets(targets, 'shell', result_opts, &callback)
        return results if shell_targets.empty?

        logger.debug { "Running command via shell agent on #{target_count(shell_targets)}" }

        first_target = shell_targets.first
        timeout = first_target.options['command-timeout']
        env_vars = options[:env_vars]
        # The agent's shell expands the command before /usr/bin/env sets the
        # variables, so on POSIX a command with shell metacharacters runs in a
        # shell of its own that sees them, like it does with the SSH
        # transport. The characters are the ones Ruby's Process.spawn runs a
        # command through a shell for, with the backtick as \x60. A command
        # without any has nothing for a shell to expand, so it runs straight
        # from /usr/bin/env and shell.kill still reaches it
        needs_shell = command.match?(/[*?{}\[\]<>()~&|\\$;'\x60"\n#]/)
        command = "sh -c #{Shellwords.shellescape(command)}" if env_vars&.any? && needs_shell && !windows_target?(first_target)
        command = prepend_env_vars(first_target, command, env_vars, 'run_command env_vars')

        pending, start_failures = shell_start(shell_targets, command)
        results += emit_results(start_failures, **result_opts, &callback)
        results += emit_results(wait_for_shell_results(pending, timeout), **result_opts, &callback)

        results
      end

      # Run a script on targets via the shell agent. Assumes all targets in
      # the batch are the same platform (POSIX or Windows). Mixed-platform
      # batches use the first capable target's platform for infrastructure
      # commands (mkdir, upload, chmod, cleanup).
      #
      # @param targets [Array<Bolt::Target>] Targets in a single collective batch
      # @param script [String] Local path to the script file
      # @param arguments [Array<String>] Command-line arguments to pass to the script
      # @param options [Hash] Execution options; supports :script_interpreter and :env_vars
      # @param position [Array] Positional info for result tracking
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>] Results for all targets
      def batch_script(targets, script, arguments, options = {}, position = [], &callback)
        result_opts = { action: 'script', name: script, position: position }
        shell_targets, results = prepare_targets(targets, 'shell', result_opts, &callback)
        return results if shell_targets.empty?

        logger.debug { "Running script via shell agent on #{target_count(shell_targets)}" }

        first_target = shell_targets.first
        arguments = unwrap_sensitive_args(arguments)
        timeout = first_target.options['command-timeout']
        tmpdir = generate_tmpdir_path(first_target)
        remote_path = join_path(first_target, tmpdir, File.basename(script))
        run_file = run_file_path(first_target, tmpdir)

        # Built before the first shell agent call, so a rejected env var name
        # fails before the script reaches the nodes
        interpreter = select_interpreter(script, first_target.options['interpreters']) if options[:script_interpreter]
        cmd_parts = [executable_command(first_target, remote_path, interpreter)]
        cmd_parts += arguments.map { |arg| escape_arg(first_target, arg) }
        command = prepend_env_vars(first_target, cmd_parts.join(' '), options[:env_vars], 'run_script env_vars')

        script_content = File.binread(script)

        begin
          active_targets = shell_targets

          # Create a temp directory with restricted permissions
          failures = shell_run(active_targets, make_tmpdir_command(first_target, tmpdir), description: "make tmpdir #{tmpdir}")
          results += emit_results(failures, **result_opts, &callback)
          active_targets -= failures.keys

          # Upload the script file and make it executable
          if active_targets.any?
            active_targets, stage_results = stage_executable(active_targets, first_target, script_content,
                                                             remote_path, result_opts, &callback)
            results += stage_results
          end

          if active_targets.any?
            active_targets, run_file_results = stage_run_file(active_targets, first_target, command, run_file,
                                                              result_opts, &callback)
            results += run_file_results
          end

          # Execute the script asynchronously and poll for completion
          if active_targets.any?
            pending, start_failures = shell_start(active_targets, run_file_command(first_target, run_file))
            results += emit_results(start_failures, **result_opts, &callback)
            results += emit_results(wait_for_shell_results(pending, timeout), **result_opts, &callback)
          end
        ensure
          cleanup_tmpdir(shell_targets, tmpdir)
        end

        results
      end

      # Generate a unique remote tmpdir path for batch operations.
      #
      # @param target [Bolt::Target] Target whose platform and tmpdir config determine the base path
      # @return [String] Absolute path to a unique temporary directory
      def generate_tmpdir_path(target)
        base = target.options['tmpdir']
        base = 'C:\Windows\Temp' if base == '/tmp' && windows_target?(target)
        join_path(target, base, "bolt-choria-#{SecureRandom.uuid}")
      end

      # Clean up a remote tmpdir on targets, logging per-target failures.
      # Used in ensure blocks after batch_script and batch_task_shell.
      #
      # @param targets [Array<Bolt::Target>] Targets to clean up on
      # @param tmpdir [String] Absolute path to the temporary directory to remove
      def cleanup_tmpdir(targets, tmpdir)
        return unless targets.first.options['cleanup']

        # A Windows target's tmpdir is joined with backslashes, which
        # File.basename does not split on when the controller runs on Linux.
        unless tmpdir.split(%r{[/\\]}).last.to_s.start_with?('bolt-choria-')
          logger.warn { "Refusing to delete unexpected tmpdir path: #{tmpdir}" }
          return
        end

        begin
          failures = shell_run(targets, cleanup_dir_command(targets.first, tmpdir), description: "remove #{tmpdir}")
          failures.each do |target, failure|
            logger.warn { "Cleanup failed on #{target.safe_name}. Task data may remain in #{tmpdir}. #{failure[:error]}" }
          end
        rescue StandardError => e
          logger.warn { "Cleanup of #{tmpdir} failed on all targets: #{e.message}" }
        end
      end

      # Run a task via the shell agent. Groups targets by implementation to
      # support mixed-platform batches. Starts all groups before polling so
      # tasks execute concurrently on nodes across implementations.
      #
      # @param targets [Array<Bolt::Target>] Targets that have the shell agent
      # @param task [Bolt::Task] Task to execute
      # @param arguments [Hash] Task parameter names to values
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>] Results for all targets
      def run_task_via_shell(targets, task, arguments, result_opts, &callback)
        logger.debug { "Running task #{task.name} via shell agent on #{target_count(targets)}" }
        groups, results = group_by_implementation(targets, task, result_opts, &callback)
        all_pending = {}
        cleanup_entries = []

        # Each implementation group gets its own tmpdir because different
        # platforms need different base paths (e.g., /tmp vs C:\Windows\Temp).
        begin
          groups.each do |implementation, impl_targets|
            tmpdir = generate_tmpdir_path(impl_targets.first)
            cleanup_entries << { targets: impl_targets, tmpdir: tmpdir }
            start_result = upload_and_start_task(impl_targets, task, implementation, tmpdir,
                                                 arguments, result_opts, &callback)
            results += start_result[:failed_results]
            all_pending.merge!(start_result[:pending])
          end

          # Poll all handles in one loop. Unlike bolt_tasks (which needs
          # separate polls per task_id), shell handles are interchangeable.
          timeout = targets.first.options['task-timeout']
          results += emit_results(wait_for_shell_results(all_pending, timeout), **result_opts, &callback)
        ensure
          cleanup_entries.each { |entry| cleanup_tmpdir(entry[:targets], entry[:tmpdir]) }
        end

        results
      end

      # Upload task files and start execution for one implementation group.
      #
      # @param targets [Array<Bolt::Target>] Targets sharing the same implementation
      # @param task [Bolt::Task] Task being executed
      # @param implementation [Hash] Task implementation with 'path', 'name', 'input_method', 'files' keys
      # @param tmpdir [String] Remote tmpdir path to create, which the caller cleans up
      # @param arguments [Hash] Task parameter names to values
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Hash] with keys:
      #   - :failed_results [Array<Bolt::Result>] Error results from setup phase
      #   - :pending [Hash] Targets mapped to { handle: uuid } for polling
      def upload_and_start_task(targets, task, implementation, tmpdir, arguments, result_opts, &callback)
        arguments = arguments.dup
        executable = implementation['path']
        input_method = implementation['input_method']
        extra_files = implementation['files']
        first_target = targets.first

        executable_content = File.binread(executable)
        extra_file_contents = {}
        extra_files.each do |file|
          validate_file_name!(file['name'])
          extra_file_contents[file['name']] = File.binread(file['path'])
        end

        failed_results = []
        active_targets = targets
        task_dir = tmpdir

        # Create the tmpdir
        failures = shell_run(active_targets, make_tmpdir_command(first_target, tmpdir), description: "make tmpdir #{tmpdir}")
        failed_results += emit_results(failures, **result_opts, &callback)
        active_targets -= failures.keys

        # Tasks with extra files get a module-layout directory tree in
        # tmpdir, and _installdir is set so the task can find them.
        # Simple tasks go directly in tmpdir with no _installdir.
        if active_targets.any? && extra_files.any?
          arguments['_installdir'] = tmpdir
          task_dir = join_path(first_target, tmpdir, task.tasks_dir)

          # Create subdirectories for the task and its dependencies
          extra_dirs = extra_files.map { |file| join_path(first_target, tmpdir, File.dirname(file['name'])) }.uniq
          all_dirs = [task_dir] + extra_dirs
          failures = shell_run(active_targets, make_dir_command(first_target, *all_dirs),
                               description: "create subdirectories in '#{tmpdir}'")
          failed_results += emit_results(failures, **result_opts, &callback)
          active_targets -= failures.keys

          # Upload each dependency file to its module-relative path
          extra_files.each do |file|
            break if active_targets.empty?

            failures = upload_file_content(active_targets, extra_file_contents[file['name']],
                                           join_path(first_target, tmpdir, file['name']))
            failed_results += emit_results(failures, **result_opts, &callback)
            active_targets -= failures.keys
          end
        end

        # Upload the main task executable and make it executable
        if active_targets.any?
          remote_task_path = join_path(first_target, task_dir, File.basename(executable))
          active_targets, stage_results = stage_executable(active_targets, first_target, executable_content,
                                                           remote_task_path, result_opts, &callback)
          failed_results += stage_results
        end

        run_file = run_file_path(first_target, tmpdir)
        if active_targets.any?
          full_cmd = build_task_command(first_target, remote_task_path, arguments, input_method,
                                        first_target.options['interpreters'])
          # build_task_command pipes the task input into the task for these methods
          pipeline = Bolt::Task::STDIN_METHODS.include?(input_method)
          active_targets, run_file_results = stage_run_file(active_targets, first_target, full_cmd, run_file,
                                                            result_opts, pipeline: pipeline, &callback)
          failed_results += run_file_results
        end

        # Start the task asynchronously
        pending = {}
        if active_targets.any?
          pending, start_failures = shell_start(active_targets, run_file_command(first_target, run_file))
          failed_results += emit_results(start_failures, **result_opts, &callback)
        end

        { failed_results: failed_results, pending: pending }
      end

      # Upload an executable to the same path on the targets and make it
      # executable (no-op on Windows), emitting a result for each target
      # that fails a step.
      #
      # @param targets [Array<Bolt::Target>] Targets to stage the executable on, at least 1
      # @param first_target [Bolt::Target] Target whose platform determines the commands
      # @param content [String] Raw file content (binary-safe)
      # @param remote_path [String] Absolute path on the remote node
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc] Called with :node_result events
      # @return [Array] 2-element array:
      #   - [Array<Bolt::Target>] Targets that have the executable in place
      #   - [Array<Bolt::Result>] Error results for the targets that failed a step
      def stage_executable(targets, first_target, content, remote_path, result_opts, &callback)
        failures = upload_file_content(targets, content, remote_path)
        results = emit_results(failures, **result_opts, &callback)
        targets -= failures.keys

        chmod_cmd = make_executable_command(first_target, remote_path)
        if targets.any? && chmod_cmd
          failures = shell_run(targets, chmod_cmd, description: "make file '#{remote_path}' executable")
          results += emit_results(failures, **result_opts, &callback)
          targets -= failures.keys
        end

        [targets, results]
      end

      # Upload a job's command to its run file, emitting a result for each
      # target that fails. The command goes to the nodes through shell.run,
      # which removes its own job directory when the upload finishes, so the
      # values in it are not kept the way a shell.start command is.
      #
      # @param targets [Array<Bolt::Target>] Targets to upload the run file to, at least 1
      # @param first_target [Bolt::Target] Target whose platform determines the file content
      # @param command [String] The command the run file contains
      # @param run_file [String] Absolute path to the run file on the remote node
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param pipeline [Boolean] Whether the command is a pipeline, default is false
      # @param callback [Proc] Called with :node_result events
      # @return [Array] 2-element array:
      #   - [Array<Bolt::Target>] Targets that have the run file
      #   - [Array<Bolt::Result>] Error results for the targets that failed the upload
      def stage_run_file(targets, first_target, command, run_file, result_opts, pipeline: false, &callback)
        content = run_file_content(first_target, command, pipeline: pipeline)
        failures = upload_file_content(targets, content, run_file)
        [targets - failures.keys, emit_results(failures, **result_opts, &callback)]
      end

      # Execute a synchronous command on targets via the shell.run RPC action.
      # Used for internal prep/cleanup (mkdir, chmod, etc.) that completes quickly.
      # Returns only failures since successes don't need to be reported. A
      # command that exits non-zero gets the file error the other transports
      # report for a failed preparation step, "Could not" followed by the
      # description and the command's stderr. A target that didn't answer the
      # call keeps the error of the call.
      #
      # @param targets [Array<Bolt::Target>] Targets to run the command on
      # @param command [String] Shell command to execute
      # @param description [String] What the command does, as the words that follow "Could not" in
      #   the error, like "make tmpdir /tmp/x". It also names the call in logs and RPC errors.
      # @return [Hash{Bolt::Target => Hash}] Failures only; empty hash means all succeeded
      def shell_run(targets, command, description:)
        command = powershell_cmd(command) if windows_target?(targets.first)
        response = rpc_request('shell', targets, description) do |client|
          client.run(command: command)
        end

        # Check that the exit code is 0 for each successful RPC response,
        # treating nonzero exit codes as failures.
        failures = response[:errors]
        response[:responded].each do |target, data|
          data ||= {}
          exitcode = exitcode_from(data[:exitcode], target, description)
          next if exitcode.zero?

          failures[target] = error_output("Could not #{description}: #{data[:stderr]}", 'puppetlabs.tasks/task_file_error',
                                          stdout: data[:stdout], stderr: data[:stderr], exitcode: exitcode)
        end

        failures
      end

      # Upload file content to the same path on multiple targets via base64,
      # in chunks that each fit in 1 shell.run command. The first chunk
      # replaces the file and the rest add to it. A target that fails a
      # chunk gets no later ones.
      #
      # @param targets [Array<Bolt::Target>] Targets to upload to
      # @param content [String] Raw file content (binary-safe)
      # @param destination [String] Absolute path on the remote node
      # @return [Hash{Bolt::Target => Hash}] Failures only; empty hash means all succeeded
      def upload_file_content(targets, content, destination)
        logger.debug { "Uploading #{content.bytesize} bytes to #{destination} on #{target_count(targets)}" }
        chunk_size = windows_target?(targets.first) ? WINDOWS_UPLOAD_CHUNK_BYTES : POSIX_UPLOAD_CHUNK_BYTES
        chunks = (0...content.bytesize).step(chunk_size).map { |offset| content.byteslice(offset, chunk_size) }
        chunks = [''] if chunks.empty?

        failures = {}
        remaining = targets
        chunks.each_with_index do |chunk, index|
          break if remaining.empty?

          command = upload_file_command(remaining.first, Base64.strict_encode64(chunk), destination,
                                        append: index.positive?)
          chunk_failures = shell_run(remaining, command, description: "copy file to #{destination}")
          failures.merge!(chunk_failures)
          remaining -= chunk_failures.keys
        end
        failures
      end

      # Start an async command on targets via the shell.start RPC action.
      # Returns handles for polling with wait_for_shell_results.
      #
      # @param targets [Array<Bolt::Target>] Targets to start the command on
      # @param command [String] Shell command to execute
      # @return [Array] Two-element array:
      #   - pending [Hash] Targets mapped to { handle: uuid_string }
      #   - failures [Hash] Targets mapped to error output hashes
      def shell_start(targets, command)
        command = powershell_cmd(command) if windows_target?(targets.first)
        response = rpc_request('shell', targets, 'shell.start') do |client|
          client.start(command: command)
        end
        failures = response[:errors]

        pending, no_handle = response[:responded].partition { |_target, data| data&.dig(:handle) }.map(&:to_h)
        pending.each { |target, data| logger.debug { "Started command on #{target.safe_name}, handle: #{data[:handle]}" } }

        no_handle.each_key do |target|
          failures[target] = error_output("shell.start on #{target.safe_name} returned success but no handle",
                                          'bolt/choria-missing-handle')
        end

        [pending, failures]
      end

      # Wait for async shell handles to complete, fetch their output via
      # shell_statuses, kill timed-out processes, and then remove the job
      # directories the shell agent keeps for the jobs that finished.
      #
      # @param pending [Hash{Bolt::Target => Hash}] Targets to poll, each mapped to { handle: uuid_string }
      # @param timeout [Numeric] Maximum seconds to wait before killing remaining processes
      # @return [Hash{Bolt::Target => Hash}] Output hash for every target (success and error)
      def wait_for_shell_results(pending, timeout)
        finished_jobs = {}
        poll_result = poll_with_retries(pending, timeout, 'shell.list') do |remaining|
          finished, failed, rpc_failed = shell_list(remaining)
          next { rpc_failed: true } if rpc_failed

          finished_jobs.merge!(finished)
          done = failed
          unless finished.empty?
            logger.debug { "Fetching output from #{target_count(finished)}" }
            done.merge!(shell_statuses(finished))
          end

          { rpc_failed: false, done: done }
        end

        remaining_errors = {}
        unless poll_result[:remaining].empty?
          kill_timed_out_processes(poll_result[:remaining])
          poll_result[:remaining].each_key do |target|
            remaining_errors[target] = error_output(
              "Command timed out after #{timeout} seconds on #{target.safe_name}",
              'bolt/choria-command-timeout'
            )
          end
        end

        results = poll_result[:completed].merge(remaining_errors)
        # A job that timed out, or whose node stopped answering, may still be
        # running, so its directory stays
        remove_job_dirs(finished_jobs)
        results
      end

      # One round of the shell.list RPC action to check which handles have
      # completed. Targets not yet done are omitted from the return value.
      #
      # @param remaining [Hash{Bolt::Target => Hash}] Targets still pending, each mapped to
      #   { handle: uuid_string }
      # @return [Array] 3-element array:
      #   - finished [Hash{Bolt::Target => Hash}] Targets whose process finished, mapped to
      #     { handle: uuid_string }
      #   - failed [Hash{Bolt::Target => Hash}] Targets whose poll failed, mapped to error hashes
      #   - rpc_failed [Boolean] True when the entire RPC call failed
      def shell_list(remaining)
        response = rpc_request('shell', remaining.keys, 'shell.list') do |client|
          client.list
        end
        return [{}, {}, true] if response[:rpc_failed]

        finished = {}
        failed = response[:errors]
        logger.debug { "shell.list: #{target_count(response[:responded])} responded, #{target_count(failed)} failed" } unless failed.empty?

        response[:responded].each do |target, data|
          if data.nil?
            failed[target] = error_output("shell.list on #{target.safe_name} returned success but no data",
                                          'bolt/choria-missing-data')
            next
          end

          handle = remaining[target][:handle]
          job = data.dig(:jobs, handle)

          unless job
            logger.debug {
              job_handles = data[:jobs]&.keys || []
              "shell.list on #{target.safe_name}: handle #{handle} not found, " \
              "available handles: #{job_handles.inspect}"
            }
            failed[target] = error_output(
              "Handle #{handle} not found in shell.list on #{target.safe_name}. " \
              "The process may have been cleaned up or the agent may have restarted.",
              'bolt/choria-handle-not-found'
            )
            next
          end

          status = job['status']&.to_s
          logger.debug { "shell.list on #{target.safe_name}: handle #{handle} status: #{status}" }
          finished[target] = remaining[target] if SHELL_DONE_STATUSES.include?(status)
        end

        [finished, failed, false]
      end

      # Fetch stdout/stderr/exitcode from completed targets via the
      # shell.statuses RPC action, SHELL_STATUSES_BATCH_SIZE targets per
      # call. Requires shell agent >= 1.2.1.
      #
      # @param targets [Hash{Bolt::Target => Hash}] Completed targets mapped to { handle: uuid_string }
      # @return [Hash{Bolt::Target => Hash}] Output hash for each target
      def shell_statuses(targets)
        targets.each_slice(SHELL_STATUSES_BATCH_SIZE).with_object({}) do |batch, results|
          results.merge!(shell_statuses_batch(batch.to_h))
        end
      end

      # One shell.statuses call for the given targets.
      #
      # @param targets [Hash{Bolt::Target => Hash}] Completed targets mapped to { handle: uuid_string }
      # @return [Hash{Bolt::Target => Hash}] Output hash for each target
      def shell_statuses_batch(targets)
        handles = targets.transform_values { |data| data[:handle] }
        logger.debug { "Fetching shell.statuses for #{target_count(targets)}" }

        results = {}
        response = rpc_request('shell', targets.keys, 'shell.statuses') do |client|
          client.statuses(handles: handles.values)
        end

        response[:errors].each do |target, fail_output|
          results[target] = fail_output
        end

        response[:responded].each do |target, data|
          statuses = data&.dig(:statuses)
          handle = handles[target]

          unless statuses
            results[target] = error_output(
              "shell.statuses on #{target.safe_name} returned no data",
              'bolt/choria-missing-data'
            )
            next
          end

          status_data = statuses[handle]
          unless status_data
            results[target] = error_output(
              "shell.statuses on #{target.safe_name} did not include handle #{handle}",
              'bolt/choria-missing-data'
            )
            next
          end

          status = status_data['status']&.to_s
          stdout = status_data['stdout']
          stderr = status_data['stderr']
          error_msg = status_data['error']

          if status == 'error'
            results[target] = error_output(
              "Handle #{handle} not found on #{target.safe_name}: #{error_msg}",
              'bolt/choria-handle-not-found'
            )
          elsif status == 'failed'
            results[target] = error_output(
              "Process failed on #{target.safe_name}: #{stderr}",
              'bolt/choria-process-failed',
              stdout: stdout, stderr: stderr
            )
          else
            exitcode = exitcode_from(status_data['exitcode'], target, 'shell.statuses')
            results[target] = output(stdout: stdout, stderr: stderr, exitcode: exitcode)
          end
        end

        results
      rescue StandardError => e
        raise if e.is_a?(Bolt::Error)

        logger.warn { "shell.statuses RPC call failed: #{e.class}: #{e.message}" }
        targets.each_key do |target|
          results[target] ||= error_output(
            "Fetching output from #{target.safe_name} failed: #{e.class}: #{e.message}",
            'bolt/choria-result-processing-error'
          )
        end
        results
      end

      # Kill processes on timed-out targets. Sequential because each target
      # has a unique handle, requiring a separate shell.kill RPC call per target.
      # A future batched kill action (like shell.statuses) would eliminate this.
      #
      # @param targets [Hash{Bolt::Target => Hash}] Timed-out targets mapped to { handle: uuid_string }
      def kill_timed_out_processes(targets)
        logger.debug { "Killing timed-out processes on #{target_count(targets)}" }
        targets.each do |target, state|
          response = rpc_request('shell', target, 'shell.kill') do |client|
            client.kill(handle: state[:handle])
          end
          response[:errors].each_value do |output|
            logger.warn { "Failed to kill process on #{target.safe_name}: #{output[:error]}" }
          end
        end
      end

      # Remove the job directories of the given handles on the targets whose
      # cleanup option is on. The shell agent's start action keeps a
      # directory per job, with the command and its output, and shell.list
      # returns every one of them, so without this each node's list reply
      # grows with every job OpenBolt ever started there. A node with a
      # custom plugin.shell.state_path keeps its directories, since the
      # client cannot read that setting.
      #
      # @param finished [Hash{Bolt::Target => Hash}] Targets whose job finished, mapped to { handle: uuid_string }
      def remove_job_dirs(finished)
        cleanup_jobs = finished.select { |target, _state| target.options['cleanup'] }
        jobs, unexpected = cleanup_jobs.partition { |_target, state| SHELL_HANDLE_PATTERN.match?(state[:handle].to_s) }
        unexpected.each do |target, state|
          logger.warn { "Not removing the shell job directory on #{target.safe_name} for unexpected handle #{state[:handle].inspect}" }
        end

        jobs.group_by { |target, _state| windows_target?(target) }.each_value do |platform_jobs|
          platform_jobs.each_slice(SHELL_JOB_DIR_BATCH_SIZE) do |batch|
            targets = batch.map(&:first)
            command = remove_job_dirs_command(targets.first, batch.map { |_target, state| state[:handle] })
            shell_run(targets, command, description: 'remove the shell job directories').each do |target, failure|
              logger.warn { "Removing the shell job directory failed on #{target.safe_name}: #{failure[:error]}" }
            end
          end
        end
      rescue StandardError => e
        logger.warn { "Removing shell job directories failed: #{e.message}" }
      end
    end
  end
end
