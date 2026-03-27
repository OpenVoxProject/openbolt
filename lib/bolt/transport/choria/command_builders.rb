# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # Platform-aware command builders. These generate the right shell
      # commands based on whether the target is Windows (PowerShell) or
      # POSIX (sh). OS is detected during agent discovery via the
      # os.family fact.

      # Build a mkdir command for one or more directories.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param paths [Array<String>] Absolute directory paths to create
      # @return [String] Shell command
      def make_dir_command(target, *paths)
        if windows_target?(target)
          escaped = paths.map { |path| "'#{ps_escape(path)}'" }.join(', ')
          "New-Item -ItemType Directory -Force -Path #{escaped}"
        else
          escaped = paths.map { |path| Shellwords.shellescape(path) }.join(' ')
          "mkdir -m 700 -p #{escaped}"
        end
      end

      # Build a chmod +x command. Returns nil on Windows (not needed).
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param path [String] Absolute path to the file
      # @return [String, nil] Shell command or nil
      def make_executable_command(target, path)
        windows_target?(target) ? nil : "chmod u+x #{Shellwords.shellescape(path)}"
      end

      # Build a recursive directory removal command.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param path [String] Absolute path to the directory
      # @return [String] Shell command
      def cleanup_dir_command(target, path)
        windows_target?(target) ?
          "Remove-Item -Recurse -Force -Path '#{ps_escape(path)}'" :
          "rm -rf #{Shellwords.shellescape(path)}"
      end

      # Build a command that writes base64-encoded content to a file
      # after decoding the content. Requires base64 CLI on POSIX targets.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param content_b64 [String] Base64-encoded file content
      # @param dest [String] Absolute destination path on the remote node
      # @return [String] Shell command
      def upload_file_command(target, content_b64, dest)
        if windows_target?(target)
          "[IO.File]::WriteAllBytes('#{ps_escape(dest)}', " \
            "[Convert]::FromBase64String('#{content_b64}'))"
        else
          "printf '%s' #{Shellwords.shellescape(content_b64)} | base64 -d > #{Shellwords.shellescape(dest)}"
        end
      end

      # Prepend environment variables to a command string.
      # Returns the command unchanged if env_vars is nil or empty.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param command [String] The command to prepend env vars to
      # @param env_vars [Hash{String => String}, nil] Variable names to values
      # @param context [String] Description for error messages (e.g., 'task argument')
      # @return [String] Command with env vars prepended
      def prepend_env_vars(target, command, env_vars, context)
        return command unless env_vars&.any?

        env_vars.each_key { |key| validate_env_key!(key, context) }

        if windows_target?(target)
          set_stmts = env_vars.map { |key, val| "$env:#{key} = '#{ps_escape(val)}'" }
          "#{set_stmts.join('; ')}; & #{command}"
        else
          env_str = env_vars.map { |key, val| "#{key}=#{Shellwords.shellescape(val)}" }.join(' ')
          "/usr/bin/env #{env_str} #{command}"
        end
      end

      # Build a command that pipes data to another command via stdin.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param data [String] Data to pipe (typically JSON task arguments)
      # @param command [String] The command to receive stdin
      # @return [String] Shell command with stdin piping
      def stdin_pipe_command(target, data, command)
        if windows_target?(target)
          # Use a here-string (@'...'@) to avoid escaping issues with
          # large JSON payloads. Content between @' and '@ is literal.
          "@'\n#{data}\n'@ | & #{command}"
        else
          "printf '%s' #{Shellwords.shellescape(data)} | #{command}"
        end
      end

      # Escape a string for use as a shell argument on the target platform.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param str [String] The string to escape
      # @return [String] Escaped string (single-quoted on Windows, sh-escaped on POSIX)
      def escape_arg(target, str)
        windows_target?(target) ? "'#{ps_escape(str)}'" : Shellwords.shellescape(str)
      end

      # Join path segments using the target platform's separator.
      # Normalizes embedded forward slashes to backslashes on Windows.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param parts [Array<String>] Path segments to join
      # @return [String] Joined path
      def join_path(target, *parts)
        sep = windows_target?(target) ? '\\' : '/'
        parts = parts.map { |part| part.tr('/', sep) } if sep != '/'
        parts.join(sep)
      end

      # Wrap a PowerShell script for execution via shell agent. Uses
      # -EncodedCommand with Base64-encoded UTF-16LE (the encoding
      # Microsoft requires for -EncodedCommand) to avoid all quoting
      # issues with cmd.exe and PowerShell metacharacters.
      #
      # @param script [String] PowerShell script to encode and wrap
      # @return [String] powershell.exe command with -EncodedCommand
      def powershell_cmd(script)
        "powershell.exe -NoProfile -NonInteractive -EncodedCommand #{Base64.strict_encode64(script.encode('UTF-16LE'))}"
      end

      # Escape single quotes for use inside PowerShell single-quoted strings.
      #
      # @param str [String] String to escape
      # @return [String] String with single quotes doubled
      def ps_escape(str)
        str.gsub("'", "''")
      end

      # Build the full command string for task execution via the shell agent,
      # handling interpreter selection, environment variable injection, and
      # stdin piping.
      #
      # @param target [Bolt::Target] Target (used for platform detection)
      # @param remote_task_path [String] Absolute path to the task executable on the remote node
      # @param arguments [Hash] Task parameter names to values
      # @param input_method [String] How to pass arguments: 'stdin', 'environment', or 'both'
      # @param interpreter_options [Hash{String => String}] File extension to interpreter path mapping
      # @return [String] The fully constructed shell command
      def build_task_command(target, remote_task_path, arguments, input_method, interpreter_options)
        interpreter = select_interpreter(remote_task_path, interpreter_options)
        cmd = interpreter ?
          "#{Array(interpreter).map { |part| escape_arg(target, part) }.join(' ')} #{escape_arg(target, remote_task_path)}" :
          escape_arg(target, remote_task_path)

        needs_env = Bolt::Task::ENVIRONMENT_METHODS.include?(input_method)
        needs_stdin = Bolt::Task::STDIN_METHODS.include?(input_method)

        if needs_env && needs_stdin && windows_target?(target)
          # On Windows, piping stdin into a multi-statement command
          # requires a script block. Pipeline data doesn't automatically
          # flow through a script block to inner commands, so we
          # explicitly forward $input via a pipe.
          env_params = envify_params(arguments)
          env_params.each_key { |key| validate_env_key!(key, 'task argument') }
          set_stmts = env_params.map { |key, val| "$env:#{key} = '#{ps_escape(val)}'" }
          cmd = stdin_pipe_command(target, arguments.to_json,
                                   "{ #{set_stmts.join('; ')}; $input | & #{cmd} }")
        else
          if needs_env
            cmd = prepend_env_vars(target, cmd, envify_params(arguments), 'task argument')
          end

          if needs_stdin
            cmd = stdin_pipe_command(target, arguments.to_json, cmd)
          end
        end

        cmd
      end

      # Convert task arguments to PT_-prefixed environment variable hash.
      # Duplicated from Bolt::Shell#envify_params. We don't use Bolt::Shell
      # classes because they interleave command building with connection-based
      # execution (IO pipes, sudo prompts). With the Choria transport, we just
      # need to build the command and send it via RPC so all the shell agents
      # on the targets can execute it themselves.
      #
      # @param params [Hash{String => Object}] Task parameter names to values
      # @return [Hash{String => String}] Environment variables with PT_ prefix
      def envify_params(params)
        params.each_with_object({}) do |(key, val), env|
          val = val.to_json unless val.is_a?(String)
          env["PT_#{key}"] = val
        end
      end
    end
  end
end
