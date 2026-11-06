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

      # Build the command that creates a tmpdir. Like mkdir -m 700 on POSIX,
      # the Windows command leaves the tmpdir open only to the account the
      # agent runs as and to the Administrators group, which the directories
      # and files in it inherit, and it fails when it cannot set that.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param tmpdir [String] Absolute path to the tmpdir on the remote node
      # @return [String] Shell command
      def make_tmpdir_command(target, tmpdir)
        return make_dir_command(target, tmpdir) unless windows_target?(target)

        "$ErrorActionPreference = 'Stop'; $dir = '#{ps_escape(tmpdir)}'; " \
          '$null = New-Item -ItemType Directory -Force -Path $dir; ' \
          '$acl = Get-Acl -LiteralPath $dir; $acl.SetAccessRuleProtection($true, $false); ' \
          'foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, ' \
          "(New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))) { " \
          '$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, ' \
          "'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))) }; " \
          'Set-Acl -LiteralPath $dir -AclObject $acl'
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

      # Build a command that removes the shell agent's job directories for
      # the given handles, under the agent's default state path. A handle
      # without a directory on the target is skipped, so 1 command can
      # contain the handles of every target it goes to. On Windows a failed
      # removal stops the command, so it exits 1 like a failed rm does.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param handles [Array<String>] Job handles, each checked to be a UUID
      # @return [String] Shell command
      def remove_job_dirs_command(target, handles)
        if windows_target?(target)
          paths = handles.map { |handle| "'C:/ProgramData/mcollective-shell/#{handle}'" }.join(', ')
          "foreach ($path in @(#{paths})) { if (Test-Path -LiteralPath $path) { " \
            'Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop } }'
        else
          "rm -rf #{handles.map { |handle| "/var/run/mcollective-shell/#{handle}" }.join(' ')}"
        end
      end

      # Build a command that writes base64-encoded content to a file
      # after decoding the content. Requires base64 CLI on POSIX targets.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param content_b64 [String] Base64-encoded file content
      # @param dest [String] Absolute destination path on the remote node
      # @param append [Boolean] Whether to add the content to the end of the file instead of replacing it
      # @return [String] Shell command
      def upload_file_command(target, content_b64, dest, append: false)
        if windows_target?(target) && append
          "$bytes = [Convert]::FromBase64String('#{content_b64}'); " \
            "$stream = [IO.File]::Open('#{ps_escape(dest)}', 'Append', 'Write'); " \
            'try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Close() }'
        elsif windows_target?(target)
          "[IO.File]::WriteAllBytes('#{ps_escape(dest)}', " \
            "[Convert]::FromBase64String('#{content_b64}'))"
        else
          "printf '%s' #{Shellwords.shellescape(content_b64)} | base64 -d #{append ? '>>' : '>'} #{Shellwords.shellescape(dest)}"
        end
      end

      # The path of the run file in a tmpdir. A script or task command can
      # contain arguments, env var values and task parameters, so it goes to
      # the nodes in this file instead of as the shell agent's start command,
      # which the agent keeps on disk and returns in shell.list replies.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param tmpdir [String] Absolute path to the tmpdir on the remote node
      # @return [String] Absolute path to the run file
      def run_file_path(target, tmpdir)
        join_path(target, tmpdir, windows_target?(target) ? 'bolt_run.ps1' : 'bolt_run.sh')
      end

      # Build the content of a run file. On POSIX it removes itself as soon
      # as sh starts reading it, which keeps reading from the open file. A
      # single command then replaces sh through exec, so shell.kill reaches
      # it. A pipeline doesn't, since exec would run printf as its own
      # process with the task input in its arguments. On Windows the content
      # runs in a script block, which would hide a failing last command from
      # powershell.exe, so it exits 1 then, as the command itself would.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param command [String] The command the run file contains
      # @param pipeline [Boolean] Whether the command is a pipeline, default is false
      # @return [String] File content
      def run_file_content(target, command, pipeline: false)
        return "#{command}\nif (-not $?) { exit 1 }" if windows_target?(target)

        "rm -f -- \"$0\"\n#{'exec ' unless pipeline}#{command}\n"
      end

      # Build the start command that runs a run file. On Windows it reads the
      # file and removes it before running what was in it.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param path [String] Absolute path to the run file
      # @return [String] Shell command
      def run_file_command(target, path)
        if windows_target?(target)
          "$boltRunFile = '#{ps_escape(path)}'; $boltRunScript = [IO.File]::ReadAllText($boltRunFile); " \
            'Remove-Item -LiteralPath $boltRunFile -Force; & ([ScriptBlock]::Create($boltRunScript))'
        else
          "sh #{Shellwords.shellescape(path)}"
        end
      end

      # Prepend environment variables to a command string.
      # Returns the command unchanged if env_vars is nil or empty.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param command [String] The command to prepend env vars to
      # @param env_vars [Hash{String => Object}, nil] Variable names to values, which become strings
      # @param context [String] Description for error messages (e.g., 'task argument')
      # @return [String] Command with env vars prepended
      def prepend_env_vars(target, command, env_vars, context)
        return command unless env_vars&.any?

        if windows_target?(target)
          "#{powershell_env_statements(env_vars, context)}; #{command}"
        else
          env_vars.each_key { |key| validate_env_key!(key, context) }
          env_str = env_vars.map { |key, val| "#{key}=#{Shellwords.shellescape(val)}" }.join(' ')
          "/usr/bin/env #{env_str} #{command}"
        end
      end

      # Build the PowerShell statements that set environment variables,
      # after validating each name.
      #
      # @param env_vars [Hash{String => Object}] Variable names to values, which become strings
      # @param context [String] Description for error messages (e.g., 'task argument')
      # @return [String] The statements joined with '; '
      def powershell_env_statements(env_vars, context)
        env_vars.each_key { |key| validate_env_key!(key, context) }
        env_vars.map { |key, val| "$env:#{key} = '#{ps_escape(val.to_s)}'" }.join('; ')
      end

      # Build a command that pipes data to another command via stdin.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param data [String] Data to pipe (typically JSON task arguments)
      # @param command [String] The command to receive stdin, which on Windows must
      #   be a PowerShell command such as one from executable_command
      # @return [String] Shell command with stdin piping
      def stdin_pipe_command(target, data, command)
        if windows_target?(target)
          # Use a here-string (@'...'@) to avoid escaping issues with
          # large JSON payloads. Its content is literal as long as no line
          # starts with a single quote character and @, which single-line
          # JSON never does.
          "@'\n#{data}\n'@ | #{command}"
        else
          "printf '%s' #{Shellwords.shellescape(data)} | #{command}"
        end
      end

      # Escape a value for use as a shell argument on the target platform.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param str [Object] The value to escape, turned into a string first
      # @return [String] Escaped string (single-quoted on Windows, sh-escaped on POSIX)
      def escape_arg(target, str)
        windows_target?(target) ? "'#{ps_escape(str.to_s)}'" : Shellwords.shellescape(str)
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

      # Build the command that runs an executable, through the interpreter
      # when one is given. On Windows it starts with the call operator,
      # since PowerShell treats a quoted path as a string.
      #
      # @param target [Bolt::Target] Used for platform detection
      # @param path [String] Absolute path to the executable on the remote node
      # @param interpreter [String, Array<String>, nil] Interpreter command, or nil to run the file directly
      # @return [String] Shell command
      def executable_command(target, path, interpreter)
        command = (Array(interpreter) + [path]).map { |part| escape_arg(target, part) }.join(' ')
        windows_target?(target) ? "& #{command}" : command
      end

      # Build the full command string for task execution via the shell agent,
      # handling interpreter selection, environment variable injection, and
      # stdin piping.
      #
      # @param target [Bolt::Target] Target (used for platform detection)
      # @param remote_task_path [String] Absolute path to the task executable on the remote node
      # @param arguments [Hash] Task parameter names to values
      # @param input_method [String] How to pass arguments: 'stdin', 'environment', 'both', or 'powershell'
      # @param interpreter_options [Hash{String => String}] File extension to interpreter path mapping
      # @return [String] The fully constructed shell command
      def build_task_command(target, remote_task_path, arguments, input_method, interpreter_options)
        if input_method == 'powershell' && windows_target?(target) && File.extname(remote_task_path).casecmp?('.ps1')
          # The arguments become the script's named parameters, like they
          # do with the WinRM transport
          return Bolt::Shell::Powershell::Snippets.json_functions +
                 Bolt::Shell::Powershell::Snippets.ps_task(remote_task_path, arguments)
        end

        interpreter = select_interpreter(remote_task_path, interpreter_options)
        cmd = executable_command(target, remote_task_path, interpreter)

        needs_env = Bolt::Task::ENVIRONMENT_METHODS.include?(input_method)
        needs_stdin = Bolt::Task::STDIN_METHODS.include?(input_method)

        if needs_env && needs_stdin && windows_target?(target)
          # On Windows, piping stdin into a multi-statement command
          # requires a script block. Pipeline data doesn't automatically
          # flow through a script block to inner commands, so we
          # explicitly forward $input via a pipe.
          env_statements = powershell_env_statements(envify_params(arguments), 'task argument')
          cmd = stdin_pipe_command(target, arguments.to_json,
                                   "& { #{env_statements}; $input | #{cmd} }")
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
