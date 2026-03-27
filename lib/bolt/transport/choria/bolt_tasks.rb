# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # Run a task via the bolt_tasks agent. Groups targets by implementation
      # to support mixed-platform batches. Starts all groups before polling any
      # of them so tasks execute concurrently on nodes across implementations.
      #
      # @param targets [Array<Bolt::Target>] Targets that have the bolt_tasks agent
      # @param task [Bolt::Task] Task to execute
      # @param arguments [Hash] Task parameter names to values
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>] Results for all targets
      def run_task_via_bolt_tasks(targets, task, arguments, result_opts, &callback)
        logger.debug { "Running task #{task.name} via bolt_tasks agent on #{target_count(targets)}" }
        results = []

        # Start all implementation groups. Each gets its own download +
        # run_no_wait sequence. Tasks begin executing on nodes as soon as
        # run_no_wait returns.
        started_groups = []
        targets.group_by { |target| select_implementation(target, task) }.each do |implementation, impl_targets|
          start_result = download_and_start_task(impl_targets, task, implementation,
                                                 arguments, result_opts, &callback)
          results += start_result[:failed_results]
          started_groups << start_result if start_result[:task_id]
        end

        # Poll each group. Tasks are already running concurrently on nodes,
        # so wall time is dominated by the longest task, not the sum.
        # Each group has a different task_id, so they must be polled separately.
        started_groups.each do |group|
          output_by_target = poll_task_status(group[:targets], group[:task_id], task)
          results += emit_results(output_by_target, **result_opts, &callback)
        end

        results
      end

      # Download task files from the server and start execution for one
      # implementation group via bolt_tasks.download and bolt_tasks.run_no_wait.
      #
      # @param targets [Array<Bolt::Target>] Targets sharing the same implementation
      # @param task [Bolt::Task] Task being executed
      # @param implementation [Hash] Task implementation with 'path', 'name', 'input_method', 'files' keys
      # @param arguments [Hash] Task parameter names to values
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Hash] with keys:
      #   - :failed_results [Array<Bolt::Result>] Error results from setup phase
      #   - :targets [Array<Bolt::Target>] Targets that successfully started
      #   - :task_id [String, nil] Shared task ID for polling, nil if nothing started
      def download_and_start_task(targets, task, implementation, arguments, result_opts, &callback)
        environment = targets.first.options['puppet-environment']
        input_method = implementation['input_method']
        impl_files = [{ 'name' => File.basename(implementation['name']), 'path' => implementation['path'] }] +
                     (implementation['files'] || [])
        file_specs_json = impl_files.map { |file| task_file_spec(file, task.module_name, environment) }.to_json

        # The failed_results reference will get updated and if we ever end up without
        # any targets left to act on, we can return it immediately.
        failed_results = []
        none_started_result = { failed_results: failed_results, targets: [], task_id: nil }

        # Download task files
        logger.debug { "Downloading task #{task.name} files via bolt_tasks to #{target_count(targets)}" }
        response = rpc_request('bolt_tasks', targets, 'bolt_tasks.download') do |client|
          client.download(task: task.name, files: file_specs_json, environment: environment)
        end
        # The bolt_tasks agent uses reply.fail! with statuscode 1 for download
        # failures, which rpc_request routes to :responded since statuscode 0-1
        # means the action completed. Check rpc_statuscodes to catch these and
        # report the download failure clearly instead of letting run_no_wait
        # fail with a confusing "task not available" error.
        dl_errors = response[:errors]
        response[:rpc_statuscodes].each do |target, code|
          next if code.zero? || dl_errors.key?(target)

          dl_errors[target] = error_output(
            "bolt_tasks.download on #{target.safe_name} failed to download task files",
            'bolt/choria-download-failed'
          )
        end
        # Must use concat rather than += to preserve reference to failed_results for early return
        failed_results.concat(emit_results(dl_errors, **result_opts, &callback))
        remaining = response[:responded].keys - dl_errors.keys
        return none_started_result if remaining.empty?

        # Start task execution
        logger.debug { "Starting task #{task.name} on #{target_count(remaining)}" }
        response = rpc_request('bolt_tasks', remaining, 'bolt_tasks.run_no_wait') do |client|
          client.run_no_wait(task: task.name, input_method: input_method,
                             files: file_specs_json, input: arguments.to_json)
        end
        failed_results.concat(emit_results(response[:errors], **result_opts, &callback))
        return none_started_result if response[:responded].empty?

        # Extract the shared task_id (all targets get the same one from
        # the single run_no_wait call that fanned out to all of them)
        task_id = response[:responded].values.first&.dig(:task_id)
        unless task_id
          no_id_errors = response[:responded].each_with_object({}) do |(target, _), errors|
            errors[target] = error_output(
              "bolt_tasks.run_no_wait on #{target.safe_name} succeeded but returned no task_id",
              'bolt/choria-missing-task-id'
            )
          end
          failed_results.concat(emit_results(no_id_errors, **result_opts, &callback))
          return none_started_result
        end

        logger.debug { "Started task #{task.name} on #{target_count(response[:responded])}, task_id: #{task_id}" }
        { failed_results: failed_results, targets: response[:responded].keys, task_id: task_id }
      end

      # Poll bolt_tasks.task_status until all targets complete or timeout.
      #
      # @param targets [Array<Bolt::Target>] Targets that were started successfully
      # @param task_id [String] Shared task ID from run_no_wait
      # @param task [Bolt::Task] Task being polled (used for timeout and error messages)
      # @return [Hash{Bolt::Target => Hash}] Output hash for every target (success and error)
      def poll_task_status(targets, task_id, task)
        timeout = targets.first.options['task-timeout']

        poll_result = poll_with_retries(targets, timeout, 'bolt_tasks.task_status') do |remaining|
          response = rpc_request('bolt_tasks', remaining, 'bolt_tasks.task_status') do |client|
            client.task_status(task_id: task_id)
          end
          next { rpc_failed: true, done: {} } if response[:rpc_failed]

          done = response[:errors].dup

          response[:responded].each do |target, data|
            if data.nil?
              done[target] = error_output(
                "bolt_tasks.task_status on #{target.safe_name} returned success but no data",
                'bolt/choria-missing-data'
              )
              next
            end
            next unless data[:completed]

            done[target] = extract_task_output(data, target)
          end

          { rpc_failed: false, done: done }
        end

        remaining_errors = poll_result[:remaining].each_with_object({}) do |target, errors|
          errors[target] =
            if poll_result[:rpc_persistent_failure]
              error_output("RPC requests to poll task status on #{target.safe_name} failed persistently",
                           'bolt/choria-poll-failed')
            else
              error_output("Task #{task.name} timed out after #{timeout} seconds on #{target.safe_name}",
                           'bolt/choria-task-timeout')
            end
        end

        poll_result[:completed].merge(remaining_errors)
      end

      # Extract stdout, stderr, and exitcode from a bolt_tasks task_status response.
      #
      # @param data [Hash] Task_status response data with :stdout, :stderr, :exitcode keys
      # @param target [Bolt::Target] Target for logging and stdout unwrapping context
      # @return [Hash] Output hash from output() or error_output()
      def extract_task_output(data, target)
        exitcode = exitcode_from(data, target, 'task')
        output(stdout: unwrap_bolt_tasks_stdout(data[:stdout]),
               stderr: data[:stderr], exitcode: exitcode)
      end

      # Build a file spec hash for the bolt_tasks download action. Computes
      # the Puppet Server file_content URI based on the file's module-relative path.
      #
      # @param file [Hash] With 'name' (module-relative path) and 'path' (local absolute path)
      # @param module_name [String] Task's module name (used for simple task files)
      # @param environment [String] Puppet environment name for the URI params
      # @return [Hash] File spec with 'filename', 'sha256', 'size_bytes', and 'uri' keys
      def task_file_spec(file, module_name, environment)
        file_name = file['name']
        validate_file_name!(file_name)
        file_path = file['path']

        parts = file_name.split('/', 3)
        path = if parts.length == 3
                 mod, subdir, rest = parts
                 case subdir
                 when 'files'
                   "/puppet/v3/file_content/modules/#{mod}/#{rest}"
                 when 'lib'
                   "/puppet/v3/file_content/plugins/#{mod}/#{rest}"
                 else
                   "/puppet/v3/file_content/tasks/#{mod}/#{rest}"
                 end
               else
                 "/puppet/v3/file_content/tasks/#{module_name}/#{file_name}"
               end

        {
          'filename' => file_name,
          'sha256' => Digest::SHA256.file(file_path).hexdigest,
          'size_bytes' => File.size(file_path),
          'uri' => {
            'path' => path,
            'params' => { 'environment' => environment }
          }
        }
      end

      # Fix double-encoding in the bolt_tasks agent's wrapper error path.
      #
      # Normally, create_task_stdout returns a Hash and reply_task_status
      # calls .to_json on it, producing a single JSON string like:
      #   '{"_output":"hello world"}'
      #
      # But for wrapper errors, create_task_stdout returns an already
      # JSON-encoded String. reply_task_status still calls .to_json on
      # it, encoding it a second time. The result is a JSON string whose
      # value is itself a JSON string:
      #   '"{\\"_error\\":{\\"kind\\":\\"choria.tasks/wrapper-error\\",...}}"'
      #
      # We parse one layer of JSON. In the normal case, that produces a
      # Hash and we return the original string. In the double-encoded
      # case, it produces a String (the inner JSON), which we return so
      # Result.for_task can parse it.
      #
      # @param agent_stdout [String, nil] JSON-encoded stdout from the bolt_tasks agent
      # @return [String, nil] JSON string suitable for Result.for_task
      def unwrap_bolt_tasks_stdout(agent_stdout)
        return agent_stdout unless agent_stdout.is_a?(String)

        parsed = begin
          JSON.parse(agent_stdout)
        rescue JSON::ParserError
          return agent_stdout
        end

        # Normal case: parsed is a Hash, return the original JSON string.
        # Double-encoded case: parsed is a String (the inner JSON), return it.
        parsed.is_a?(String) ? parsed : agent_stdout
      end
    end
  end
end
