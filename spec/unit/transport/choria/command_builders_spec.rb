# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'

describe 'Bolt::Transport::Choria command builders' do
  include_context 'choria transport'

  describe '#stdin_pipe_command (POSIX)' do
    it 'pipes data via printf without trailing newline' do
      cmd = transport.stdin_pipe_command(target, '{"key":"value"}', '/tmp/task.sh')
      expect(cmd).to eq("printf '%s' \\{\\\"key\\\":\\\"value\\\"\\} | /tmp/task.sh")
    end

    it 'escapes special shell characters in data' do
      cmd = transport.stdin_pipe_command(target, 'data with $pecial & chars', 'mycmd')
      expect(cmd).to start_with("printf '%s'")
      expect(cmd).to end_with('| mycmd')
    end
  end

  describe '#escape_arg (POSIX)' do
    it 'escapes spaces' do
      result = transport.escape_arg(target, 'arg with spaces')
      expect(result).to eq('arg\ with\ spaces')
    end

    it 'escapes single quotes' do
      result = transport.escape_arg(target, "it's")
      expect(result).to eq("it\\'s")
    end

    it 'returns empty string for empty input' do
      result = transport.escape_arg(target, '')
      expect(result).to eq("''")
    end
  end

  describe '#join_path (POSIX)' do
    it 'uses forward slash as separator' do
      result = transport.join_path(target, '/tmp', 'bolt-dir', 'mytask.sh')
      expect(result).to eq('/tmp/bolt-dir/mytask.sh')
    end
  end

  describe '#make_dir_command (POSIX)' do
    it 'generates a mkdir command with mode 700' do
      cmd = transport.make_dir_command(target, '/tmp/bolt-choria-test')
      expect(cmd).to eq('mkdir -m 700 -p /tmp/bolt-choria-test')
    end

    it 'joins multiple paths into a space-separated list' do
      cmd = transport.make_dir_command(target, '/tmp/bolt-dir', '/tmp/bolt-dir/lib')
      expect(cmd).to eq('mkdir -m 700 -p /tmp/bolt-dir /tmp/bolt-dir/lib')
    end
  end

  describe '#prepend_env_vars' do
    it 'returns command unchanged when env_vars is nil' do
      result = transport.prepend_env_vars(target, 'echo hello', nil, 'test')
      expect(result).to eq('echo hello')
    end

    it 'returns command unchanged when env_vars is empty' do
      result = transport.prepend_env_vars(target, 'echo hello', {}, 'test')
      expect(result).to eq('echo hello')
    end

    it 'prepends /usr/bin/env with escaped variables' do
      result = transport.prepend_env_vars(target, 'mycommand', { 'FOO' => 'bar baz' }, 'test')
      expect(result).to eq('/usr/bin/env FOO=bar\ baz mycommand')
    end

    it 'handles multiple variables' do
      result = transport.prepend_env_vars(target, 'cmd', { 'A' => '1', 'B' => '2' }, 'test')
      expect(result).to eq('/usr/bin/env A=1 B=2 cmd')
    end
  end

  describe '#build_task_command' do
    it 'builds a command with stdin piping when input_method is stdin' do
      cmd = transport.build_task_command(target, '/tmp/mytask.sh', { 'key' => 'value' }, 'stdin', nil)
      expect(cmd).to eq("printf '%s' \\{\\\"key\\\":\\\"value\\\"\\} | /tmp/mytask.sh")
    end

    it 'builds a command with environment variables when input_method is environment' do
      cmd = transport.build_task_command(target, '/tmp/mytask.sh', { 'key' => 'value' }, 'environment', nil)
      expect(cmd).to eq('/usr/bin/env PT_key=value /tmp/mytask.sh')
    end

    it 'builds a command with both stdin and environment when input_method is both' do
      cmd = transport.build_task_command(target, '/tmp/mytask.sh', { 'key' => 'value' }, 'both', nil)
      expect(cmd).to eq("printf '%s' \\{\\\"key\\\":\\\"value\\\"\\} | /usr/bin/env PT_key=value /tmp/mytask.sh")
    end

    it 'JSON-serializes non-string argument values for environment variables' do
      cmd = transport.build_task_command(target, '/tmp/mytask.sh',
                                         { 'config' => { 'nested' => true }, 'count' => 42 },
                                         'environment', nil)
      expect(cmd).to eq('/usr/bin/env PT_config=\{\"nested\":true\} PT_count=42 /tmp/mytask.sh')
    end

    it 'uses configured interpreter for the task file extension' do
      cmd = transport.build_task_command(target, '/tmp/mytask.sh', {}, 'both', { '.sh' => '/opt/bash5/bin/bash' })
      expect(cmd).to match(%r{/opt/bash5/bin/bash\s.*/mytask\.sh})
    end

    it 'uses interpreter with multiple path elements' do
      cmd = transport.build_task_command(target, '/tmp/mytask.sh', {}, 'both', { '.sh' => ['/usr/bin/env', 'bash'] })
      expect(cmd).to match(%r{/usr/bin/env bash\s.*/mytask\.sh})
    end

    it 'uses no interpreter when none is configured' do
      cmd = transport.build_task_command(target, '/tmp/mytask.sh', {}, 'both', nil)
      expect(cmd).to eq("printf '%s' \\{\\} | /tmp/mytask.sh")
    end
  end

  describe 'Windows command builders' do
    before(:each) do
      stub_agents(target, %w[rpcutil shell], os_family: 'windows')
      transport.configure_client(target)
      transport.discover_agents([target])
    end

    describe '#make_dir_command' do
      it 'generates a PowerShell New-Item command' do
        cmd = transport.make_dir_command(target, 'C:\Windows\Temp\bolt-test')
        expect(cmd).to eq("New-Item -ItemType Directory -Force -Path 'C:\\Windows\\Temp\\bolt-test'")
      end

      it 'joins multiple paths into a comma-separated list' do
        cmd = transport.make_dir_command(target, 'C:\temp\bolt-dir', 'C:\temp\bolt-dir\lib')
        expect(cmd).to eq("New-Item -ItemType Directory -Force -Path 'C:\\temp\\bolt-dir', 'C:\\temp\\bolt-dir\\lib'")
      end
    end

    describe '#make_executable_command' do
      it 'returns nil because Windows does not need chmod' do
        result = transport.make_executable_command(target, 'C:\temp\mytask.ps1')
        expect(result).to be_nil
      end
    end

    describe '#cleanup_dir_command' do
      it 'generates a PowerShell Remove-Item command' do
        cmd = transport.cleanup_dir_command(target, 'C:\Windows\Temp\bolt-test')
        expect(cmd).to eq("Remove-Item -Recurse -Force -Path 'C:\\Windows\\Temp\\bolt-test'")
      end
    end

    describe '#upload_file_command' do
      it 'generates a PowerShell IO.File WriteAllBytes command' do
        content_b64 = Base64.strict_encode64('test content')
        cmd = transport.upload_file_command(target, content_b64, 'C:\temp\myfile.txt')
        expect(cmd).to eq("[IO.File]::WriteAllBytes('C:\\temp\\myfile.txt', " \
                          "[Convert]::FromBase64String('#{content_b64}'))")
      end
    end

    describe '#prepend_env_vars' do
      it 'generates $env: syntax' do
        cmd = transport.prepend_env_vars(target, 'mycommand', { 'FOO' => 'bar' }, 'test')
        expect(cmd).to eq("$env:FOO = 'bar'; & mycommand")
      end

      it 'handles multiple environment variables' do
        cmd = transport.prepend_env_vars(target, 'cmd', { 'A' => '1', 'B' => '2' }, 'test')
        expect(cmd).to eq("$env:A = '1'; $env:B = '2'; & cmd")
      end
    end

    describe '#stdin_pipe_command' do
      it 'generates a here-string pipe' do
        cmd = transport.stdin_pipe_command(target, '{"key":"value"}', 'mytask.ps1')
        expect(cmd).to eq("@'\n{\"key\":\"value\"}\n'@ | & mytask.ps1")
      end
    end

    describe '#escape_arg' do
      it 'wraps the argument in single quotes' do
        result = transport.escape_arg(target, 'my argument')
        expect(result).to eq("'my argument'")
      end

      it 'escapes single quotes by doubling them' do
        result = transport.escape_arg(target, "it's a test")
        expect(result).to eq("'it''s a test'")
      end
    end

    describe '#join_path' do
      it 'uses backslash as separator' do
        result = transport.join_path(target, 'C:\temp', 'bolt-dir', 'mytask.ps1')
        expect(result).to eq('C:\temp\bolt-dir\mytask.ps1')
      end
    end

    describe '#powershell_cmd' do
      it 'uses -EncodedCommand with Base64-encoded UTF-16LE' do
        cmd = transport.powershell_cmd('Write-Host "hello"')
        expect(cmd).to start_with('powershell.exe -NoProfile -NonInteractive -EncodedCommand ')
        encoded_part = cmd.split('-EncodedCommand ').last
        decoded = Base64.decode64(encoded_part).force_encoding('UTF-16LE').encode('UTF-8')
        expect(decoded).to eq('Write-Host "hello"')
      end
    end

    describe '#build_task_command' do
      it 'builds a command with PowerShell syntax for stdin piping' do
        cmd = transport.build_task_command(target, 'C:\temp\mytask.ps1',
                                           { 'key' => 'value' }, 'stdin', nil)
        expect(cmd).to eq("@'\n{\"key\":\"value\"}\n'@ | & 'C:\\temp\\mytask.ps1'")
      end

      it 'builds a command with $env: syntax for environment input_method' do
        cmd = transport.build_task_command(target, 'C:\temp\mytask.ps1',
                                           { 'key' => 'value' }, 'environment', nil)
        expect(cmd).to eq("$env:PT_key = 'value'; & 'C:\\temp\\mytask.ps1'")
      end

      it 'builds a command with both stdin and environment for both input_method' do
        cmd = transport.build_task_command(target, 'C:\temp\mytask.ps1',
                                           { 'key' => 'value' }, 'both', nil)
        expect(cmd).to eq("@'\n{\"key\":\"value\"}\n'@ | & { $env:PT_key = 'value'; $input | & 'C:\\temp\\mytask.ps1' }")
      end
    end
  end
end
