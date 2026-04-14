# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # Terminal shell job statuses that indicate the process has finished.
      SHELL_DONE_STATUSES = %w[stopped failed].freeze

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
        command = prepend_env_vars(first_target, command, options[:env_vars], 'run_command env_vars')

        shell_targets.each { |target| callback&.call(type: :node_start, target: target) }

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
      # @param options [Hash] Execution options; supports :script_interpreter
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

        script_content = File.binread(script)

        shell_targets.each { |target| callback&.call(type: :node_start, target: target) }

        begin
          remote_path = join_path(first_target, tmpdir, File.basename(script))
          active_targets = shell_targets.dup

          # Create a temp directory with restricted permissions
          failures = shell_run(active_targets,
                               make_dir_command(first_target, tmpdir),
                               description: 'mkdir tmpdir')
          results += emit_results(failures, **result_opts, &callback)
          active_targets -= failures.keys

          # Upload the script file
          if active_targets.any?
            failures = upload_file_content(active_targets, script_content, remote_path)
            results += emit_results(failures, **result_opts, &callback)
            active_targets -= failures.keys
          end

          # Make the script executable (no-op on Windows)
          chmod_cmd = make_executable_command(first_target, remote_path)
          if active_targets.any? && chmod_cmd
            failures = shell_run(active_targets, chmod_cmd, description: 'chmod script')
            results += emit_results(failures, **result_opts, &callback)
            active_targets -= failures.keys
          end

          # Execute the script asynchronously and poll for completion
          if active_targets.any?
            interpreter = select_interpreter(script, first_target.options['interpreters'])
            cmd_parts = []
            cmd_parts += Array(interpreter).map { |part| escape_arg(first_target, part) } if interpreter && options[:script_interpreter]
            cmd_parts << escape_arg(first_target, remote_path)
            cmd_parts += arguments.map { |arg| escape_arg(first_target, arg) }

            pending, start_failures = shell_start(active_targets, cmd_parts.join(' '))
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
        return unless targets.first.options.fetch('cleanup', true)

        unless File.basename(tmpdir).start_with?('bolt-choria-')
          logger.warn { "Refusing to delete unexpected tmpdir path: #{tmpdir}" }
          return
        end

        begin
          failures = shell_run(targets, cleanup_dir_command(targets.first, tmpdir),
                               description: 'cleanup tmpdir')
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
        results = []
        all_pending = {}
        cleanup_entries = []

        # Each implementation group gets its own tmpdir because different
        # platforms need different base paths (e.g., /tmp vs C:\Windows\Temp).
        begin
          targets.group_by { |target| select_implementation(target, task) }.each do |implementation, impl_targets|
            start_result = upload_and_start_task(impl_targets, task, implementation,
                                                 arguments, result_opts, &callback)
            results += start_result[:failed_results]
            all_pending.merge!(start_result[:pending])
            cleanup_entries << { targets: impl_targets, tmpdir: start_result[:tmpdir] }
          end

          # Poll all handles in one loop. Unlike bolt_tasks (which needs
          # separate polls per task_id), shell handles are interchangeable.
          unless all_pending.empty?
            timeout = targets.first.options['task-timeout']
            results += emit_results(wait_for_shell_results(all_pending, timeout), **result_opts, &callback)
          end
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
      # @param arguments [Hash] Task parameter names to values
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Hash] with keys:
      #   - :failed_results [Array<Bolt::Result>] Error results from setup phase
      #   - :pending [Hash] Targets mapped to { handle: uuid } for polling
      #   - :tmpdir [String] Remote tmpdir path for cleanup
      def upload_and_start_task(targets, task, implementation, arguments, result_opts, &callback)
        arguments = arguments.dup
        executable = implementation['path']
        input_method = implementation['input_method']
        extra_files = implementation['files']
        first_target = targets.first
        tmpdir = generate_tmpdir_path(first_target)

        executable_content = File.binread(executable)
        extra_file_contents = {}
        extra_files.each do |file|
          validate_file_name!(file['name'])
          extra_file_contents[file['name']] = File.binread(file['path'])
        end

        failed_results = []
        active_targets = targets.dup
        task_dir = tmpdir

        # Create the tmpdir
        failures = shell_run(active_targets,
                             make_dir_command(first_target, tmpdir),
                             description: 'mkdir tmpdir')
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
          failures = shell_run(active_targets,
                               make_dir_command(first_target, *all_dirs),
                               description: 'mkdir task dirs')
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

        # Upload the main task executable
        remote_task_path = join_path(first_target, task_dir, File.basename(executable)) if active_targets.any?
        if remote_task_path
          failures = upload_file_content(active_targets, executable_content, remote_task_path)
          failed_results += emit_results(failures, **result_opts, &callback)
          active_targets -= failures.keys
        end

        # Make the task executable (no-op on Windows)
        chmod_cmd = make_executable_command(first_target, remote_task_path) if remote_task_path
        if active_targets.any? && chmod_cmd
          failures = shell_run(active_targets, chmod_cmd, description: 'chmod task')
          failed_results += emit_results(failures, **result_opts, &callback)
          active_targets -= failures.keys
        end

        # Start the task asynchronously
        pending = {}
        if active_targets.any? && remote_task_path
          full_cmd = build_task_command(first_target, remote_task_path, arguments, input_method,
                                        first_target.options['interpreters'])
          pending, start_failures = shell_start(active_targets, full_cmd)
          failed_results += emit_results(start_failures, **result_opts, &callback)
        end

        { failed_results: failed_results, pending: pending, tmpdir: tmpdir }
      end

      # Execute a synchronous command on targets via the shell.run RPC action.
      # Used for internal prep/cleanup (mkdir, chmod, etc.) that completes quickly.
      # Returns only failures since successes don't need to be reported.
      #
      # @param targets [Array<Bolt::Target>] Targets to run the command on
      # @param command [String] Shell command to execute
      # @param description [String, nil] Human-readable label for logging (defaults to command)
      # @return [Hash{Bolt::Target => Hash}] Failures only; empty hash means all succeeded
      def shell_run(targets, command, description: nil)
        label = description || command
        command = powershell_cmd(command) if windows_target?(targets.first)
        response = rpc_request('shell', targets, label) do |client|
          client.run(command: command)
        end

        # Check that the exit code is 0 for each successful RPC response,
        # treating nonzero exit codes as failures.
        failures = response[:errors]
        response[:responded].each do |target, data|
          data ||= {}
          exitcode = exitcode_from(data, target, label)
          next if exitcode.zero?

          failures[target] = error_output(
            "#{label} failed on #{target.safe_name} (exit code #{exitcode}): #{data[:stderr]}",
            'bolt/choria-operation-failed',
            stdout: data[:stdout], stderr: data[:stderr], exitcode: exitcode
          )
        end

        failures
      end

      # Upload file content to the same path on multiple targets via base64.
      # The entire file is base64-encoded and sent as a single RPC message,
      # so file size is limited by the NATS max message size (default 1MB,
      # configurable via plugin.choria.network.client_max_payload in the
      # Choria broker config). Base64 adds ~33% overhead, so the effective
      # file size limit is roughly 750KB with default settings.
      # Once the file-transfer agent is implemented, we'll use chunked
      # transfers via that agent instead when it's available, removing this
      # size limitation.
      #
      # @param targets [Array<Bolt::Target>] Targets to upload to
      # @param content [String] Raw file content (binary-safe)
      # @param destination [String] Absolute path on the remote node
      # @return [Hash{Bolt::Target => Hash}] Failures only; empty hash means all succeeded
      def upload_file_content(targets, content, destination)
        logger.debug { "Uploading #{content.bytesize} bytes to #{destination} on #{target_count(targets)}" }
        encoded = Base64.strict_encode64(content)
        command = upload_file_command(targets.first, encoded, destination)
        shell_run(targets, command, description: "upload #{destination}")
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
      # shell_statuses, and kill timed-out processes.
      #
      # @param pending [Hash{Bolt::Target => Hash}] Targets to poll, each mapped to { handle: uuid_string }
      # @param timeout [Numeric] Maximum seconds to wait before killing remaining processes
      # @return [Hash{Bolt::Target => Hash}] Output hash for every target (success and error)
      def wait_for_shell_results(pending, timeout)
        return {} if pending.empty?

        poll_result = poll_with_retries(pending, timeout, 'shell.list') do |remaining|
          completed, rpc_failed = shell_list(remaining)
          next { rpc_failed: true, done: {} } if rpc_failed

          done = {}
          fetch_targets = {}
          completed.each do |target, value|
            if value[:error]
              done[target] = value
            else
              fetch_targets[target] = value
            end
          end

          unless fetch_targets.empty?
            logger.debug { "Fetching output from #{target_count(fetch_targets)}" }
            fetched = shell_statuses(fetch_targets)
            fetch_targets.each_key do |target|
              done[target] = fetched[target] || error_output(
                "Command completed on #{target.safe_name} but output could not be fetched",
                'bolt/choria-result-processing-error'
              )
            end
          end

          { rpc_failed: false, done: done }
        end

        remaining_errors = {}
        unless poll_result[:remaining].empty?
          if poll_result[:rpc_persistent_failure]
            poll_result[:remaining].each_key do |target|
              remaining_errors[target] = error_output(
                "RPC requests to poll shell status on #{target.safe_name} failed persistently",
                'bolt/choria-poll-failed'
              )
            end
          else
            kill_timed_out_processes(poll_result[:remaining])
            poll_result[:remaining].each_key do |target|
              remaining_errors[target] = error_output(
                "Command timed out after #{timeout} seconds on #{target.safe_name}",
                'bolt/choria-command-timeout'
              )
            end
          end
        end

        poll_result[:completed].merge(remaining_errors)
      end

      # One round of the shell.list RPC action to check which handles have
      # completed. Targets not yet done are omitted from the return value.
      #
      # @param remaining [Hash{Bolt::Target => Hash}] Targets still pending, each mapped to
      #   { handle: uuid_string }
      # @return [Array] Two-element array:
      #   - done [Hash{Bolt::Target => Hash}] Completed targets mapped to handle state or error hash
      #   - rpc_failed [Boolean] True when the entire RPC call failed
      def shell_list(remaining)
        response = rpc_request('shell', remaining.keys, 'shell.list') do |client|
          client.list
        end
        return [{}, true] if response[:rpc_failed]

        done = response[:errors]
        logger.debug { "shell.list: #{target_count(response[:responded])} responded, #{target_count(done)} failed" } unless done.empty?

        response[:responded].each do |target, data|
          if data.nil?
            done[target] = error_output("shell.list on #{target.safe_name} returned success but no data",
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
            done[target] = error_output(
              "Handle #{handle} not found in shell.list on #{target.safe_name}. " \
              "The process may have been cleaned up or the agent may have restarted.",
              'bolt/choria-handle-not-found'
            )
            next
          end

          status = job['status']&.to_s
          logger.debug { "shell.list on #{target.safe_name}: handle #{handle} status: #{status}" }
          done[target] = remaining[target] if SHELL_DONE_STATUSES.include?(status)
        end

        [done, false]
      end

      # Fetch stdout/stderr/exitcode from completed targets via the
      # shell.statuses RPC action. Requires shell agent >= 1.2.1.
      #
      # @param targets [Hash{Bolt::Target => Hash}] Completed targets mapped to { handle: uuid_string }
      # @return [Hash{Bolt::Target => Hash}] Output hash for each target
      def shell_statuses(targets)
        handles = targets.transform_values { |data| data[:handle] }
        logger.debug { "Fetching shell.statuses for #{target_count(targets.keys)}" }

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
              stdout: stdout, stderr: stderr, exitcode: 1
            )
          else
            exitcode = exitcode_from(status_data, target, 'shell.statuses')
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
          rpc_request('shell', target, 'shell.kill') do |client|
            client.kill(handle: state[:handle])
          end
        rescue StandardError => e
          logger.warn { "Failed to kill process on #{target.safe_name}: #{e.message}" }
        end
      end
    end
  end
end
