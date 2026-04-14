# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # Polling interval between rounds, used by poll_task_status
      # and wait_for_shell_results. Each round makes one batched RPC call
      # regardless of target count, so a 1-second interval balances
      # responsiveness against broker load.
      POLL_INTERVAL_SECONDS = 1

      # Matches Windows absolute paths like C:\temp or D:/foo.
      # Used by validate_file_name! and Config::Transport::Choria#absolute_path?.
      WINDOWS_PATH_REGEX = %r{\A[A-Za-z]:[\\/]}

      def target_count(targets)
        count = targets.is_a?(Hash) ? targets.size : targets.length
        "#{count} #{count == 1 ? 'target' : 'targets'}"
      end

      # Shared polling loop for bolt_tasks and shell polling. Handles sleep
      # timing, round counting, RPC failure retry, and deadline enforcement.
      #
      # The block receives the remaining targets each round and returns:
      #   { done: {target => output_hash}, rpc_failed: bool }
      #
      # @param targets [Array, Hash] Initial targets to poll (duped internally)
      # @param timeout [Numeric] Maximum seconds before exiting
      # @param context [String] Label for log messages
      # @return [Hash] with keys:
      #   - :completed [Hash{Target => Hash}] All finished target outputs
      #   - :remaining [Array, Hash] Targets still pending when the loop exited
      #   - :rpc_persistent_failure [Boolean] True if loop exited due to persistent RPC failures
      def poll_with_retries(targets, timeout, context)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        remaining = targets.dup
        completed = {}
        poll_failures = 0
        poll_round = 0

        until remaining.empty?
          sleep(POLL_INTERVAL_SECONDS)
          poll_round += 1
          logger.debug { "Poll round #{poll_round}: #{target_count(remaining)} still pending" }

          round = yield(remaining)

          if round[:rpc_failed]
            poll_failures += 1
            logger.warn { "#{context} poll failed (attempt #{poll_failures}/#{RPC_FAILURE_RETRIES})" }
            break if poll_failures >= RPC_FAILURE_RETRIES

            next
          end
          poll_failures = 0

          round[:done].each do |target, output|
            completed[target] = output
            remaining.delete(target)
          end

          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        end

        { completed: completed, remaining: remaining,
          rpc_persistent_failure: poll_failures >= RPC_FAILURE_RETRIES }
      end

      # Build a Bolt::Result from an output hash. Handles both success and
      # error cases based on the presence of the :error key.
      #
      # @param target [Bolt::Target] The target this result belongs to
      # @param data [Hash] Output hash with keys :stdout, :stderr, :exitcode, and
      #   optionally :error and :error_kind for failures
      # @param action [String] One of 'task', 'command', or 'script'
      # @param name [String] Task/command/script name for result metadata
      # @param position [Array] Positional info for result tracking
      # @return [Bolt::Result] The constructed result
      def build_result(target, data, action:, name:, position:)
        if data[:error]
          Bolt::Result.from_exception(
            target, Bolt::Error.new(data[:error], data[:error_kind]),
            action: action, position: position
          )
        elsif action == 'task'
          Bolt::Result.for_task(target, data[:stdout], data[:stderr],
                                data[:exitcode], name, position)
        elsif %w[command script].include?(action)
          Bolt::Result.for_command(
            target,
            { 'stdout' => data[:stdout], 'stderr' => data[:stderr], 'exit_code' => data[:exitcode] },
            action, name, position
          )
        else
          raise Bolt::Error.new(
            "Unknown action '#{action}' in build_result",
            'bolt/choria-unknown-action'
          )
        end
      end

      # Convert a hash of { target => output } into Results, fire callbacks,
      # and return the Results array. When fire_node_start is true, fires a
      # :node_start callback before each :node_result.
      #
      # @param target_outputs [Hash{Bolt::Target => Hash}] Map of targets to output hashes
      # @param action [String] One of 'task', 'command', or 'script'
      # @param name [String] Task/command/script name for result metadata
      # @param position [Array] Positional info for result tracking
      # @param fire_node_start [Boolean] Whether to emit :node_start before each result
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>] Results for all targets in the hash
      def emit_results(target_outputs, action:, name:, position:, fire_node_start: false, &callback)
        target_outputs.map do |target, data|
          callback&.call(type: :node_start, target: target) if fire_node_start
          result = build_result(target, data, action: action, name: name, position: position)
          callback&.call(type: :node_result, result: result)
          result
        end
      end

      # Build an output hash from command/task output.
      def output(stdout: nil, stderr: nil, exitcode: nil)
        { stdout: stdout || '', stderr: stderr || '', exitcode: exitcode || 0 }
      end

      # Build an error output hash. When actual output is available (e.g.
      # a command ran but failed), pass it through so the user sees it.
      def error_output(message, kind, stdout: nil, stderr: nil, exitcode: 1)
        output(stdout: stdout, stderr: stderr, exitcode: exitcode)
          .merge(error: message, error_kind: kind)
      end

      # Extract exit code from RPC response data, defaulting to 1 with a
      # warning if the agent returned nil.
      #
      # @param data [Hash] RPC response data containing :exitcode
      # @param target [Bolt::Target] Target for logging context
      # @param context [String] Human-readable label for the log message
      # @return [Integer] The exit code from the data, or 1 if nil
      def exitcode_from(data, target, context)
        exitcode = data[:exitcode] || data['exitcode']
        if exitcode.nil?
          logger.warn {
            "Agent on #{target.safe_name} returned no exit code for #{context}. " \
            "Defaulting to exit code 1. This usually indicates an agent-level error."
          }
          exitcode = 1
        end
        exitcode
      end

      # Validate that a file name does not contain path traversal sequences
      # or absolute paths. Checks both POSIX and Windows conventions.
      # Raises Bolt::Error on violations.
      #
      # @param name [String] Task file name to validate
      def validate_file_name!(name)
        if name.include?("\0")
          raise Bolt::Error.new(
            "Invalid null byte in task file name: #{name.inspect}",
            'bolt/invalid-task-filename'
          )
        end

        if name.start_with?('/') || name.match?(WINDOWS_PATH_REGEX)
          raise Bolt::Error.new(
            "Absolute path not allowed in task file name: '#{name}'",
            'bolt/invalid-task-filename'
          )
        end

        if name.split(%r{[/\\]}).include?('..')
          raise Bolt::Error.new(
            "Path traversal detected in task file name: '#{name}'",
            'bolt/path-traversal'
          )
        end
      end

      # Validate an environment variable key is safe for shell interpolation.
      #
      # @param key [String] Environment variable name to validate
      # @param context [String] Description for error messages
      def validate_env_key!(key, context)
        safe_pattern = /\A[A-Za-z_][A-Za-z0-9_]*\z/
        return if safe_pattern.match?(key)

        raise Bolt::Error.new(
          "Unsafe environment variable name '#{key}' in #{context}. " \
          "Names must match #{safe_pattern.source}",
          'bolt/invalid-env-var-name'
        )
      end
    end
  end
end
