# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'

describe 'Bolt::Transport::Choria helpers' do
  include_context 'choria transport'

  describe '#build_result' do
    it 'builds a successful command Result with stdout, stderr, and exit_code' do
      output = { stdout: 'hello', stderr: 'warn', exitcode: 0 }
      result = transport.build_result(target, output, action: 'command', name: 'echo hello', position: [])

      expect(result.ok?).to be true
      expect(result.value['stdout']).to eq('hello')
      expect(result.value['stderr']).to eq('warn')
      expect(result.value['exit_code']).to eq(0)
    end

    it 'builds a successful script Result with stdout, stderr, and exit_code' do
      output = { stdout: 'script output', stderr: '', exitcode: 0 }
      result = transport.build_result(target, output, action: 'script', name: 'myscript.sh', position: [])

      expect(result.ok?).to be true
      expect(result.value['stdout']).to eq('script output')
      expect(result.value['stderr']).to eq('')
      expect(result.value['exit_code']).to eq(0)
    end

    it 'builds a successful task Result' do
      output = { stdout: '{"result": true}', stderr: '', exitcode: 0 }
      result = transport.build_result(target, output, action: 'task', name: 'my_task', position: [])

      expect(result.ok?).to be true
      expect(result.value).to include('result' => true)
    end

    it 'builds a failed command Result when exit code is non-zero' do
      output = { stdout: 'partial', stderr: 'error output', exitcode: 2 }
      result = transport.build_result(target, output, action: 'command', name: 'failing_cmd', position: [])

      expect(result.ok?).to be false
      expect(result.value['stdout']).to eq('partial')
      expect(result.value['stderr']).to eq('error output')
      expect(result.value['exit_code']).to eq(2)
      expect(result.error_hash['kind']).to eq('puppetlabs.tasks/command-error')
      expect(result.error_hash['msg']).to include('exit code 2')
    end

    it 'builds a failed script Result when exit code is non-zero' do
      output = { stdout: '', stderr: 'script failed', exitcode: 4 }
      result = transport.build_result(target, output, action: 'script', name: 'failing_script.sh', position: [])

      expect(result.ok?).to be false
      expect(result.value['stdout']).to eq('')
      expect(result.value['stderr']).to eq('script failed')
      expect(result.value['exit_code']).to eq(4)
      expect(result.error_hash['kind']).to eq('puppetlabs.tasks/command-error')
      expect(result.error_hash['msg']).to include('exit code 4')
    end

    it 'builds a failed task Result when exit code is non-zero' do
      output = { stdout: '', stderr: 'task error output', exitcode: 3 }
      result = transport.build_result(target, output, action: 'task', name: 'my_task', position: [])

      expect(result.ok?).to be false
      expect(result.error_hash['kind']).to eq('puppetlabs.tasks/task-error')
      expect(result.error_hash['msg']).to include('exit code 3')
    end

    it 'builds an error Result for command when output has :error key' do
      output = { stdout: '', stderr: '', exitcode: 1,
                 error: 'something failed', error_kind: 'bolt/choria-rpc-error' }
      result = transport.build_result(target, output, action: 'command', name: 'echo hi', position: [])

      expect(result.ok?).to be false
      expect(result.error_hash['kind']).to eq('bolt/choria-rpc-error')
      expect(result.error_hash['msg']).to eq('something failed')
    end

    it 'builds an error Result for task when output has :error key' do
      output = { stdout: '', stderr: '', exitcode: 1,
                 error: 'task failed', error_kind: 'bolt/task-error' }
      result = transport.build_result(target, output, action: 'task', name: 'my_task', position: [])

      expect(result.ok?).to be false
      expect(result.error_hash['kind']).to eq('bolt/task-error')
      expect(result.error_hash['msg']).to eq('task failed')
    end

    it 'raises Bolt::Error for unknown action' do
      output = { stdout: '', stderr: '', exitcode: 0 }

      expect {
        transport.build_result(target, output, action: 'unknown', name: 'x', position: [])
      }.to raise_error(Bolt::Error, /Unknown action 'unknown'/)
    end

    it 'prioritizes error key over action type' do
      output = { stdout: 'some output', stderr: 'some error', exitcode: 1,
                 error: 'override error', error_kind: 'bolt/test-error' }
      result = transport.build_result(target, output, action: 'task', name: 'my_task', position: [])

      expect(result.ok?).to be false
      expect(result.error_hash['kind']).to eq('bolt/test-error')
      expect(result.error_hash['msg']).to eq('override error')
    end
  end

  describe '#error_output' do
    it 'builds an error hash with default values' do
      result = transport.error_output('bad thing happened', 'bolt/test-error')

      expect(result[:error]).to eq('bad thing happened')
      expect(result[:error_kind]).to eq('bolt/test-error')
      expect(result[:stdout]).to eq('')
      expect(result[:stderr]).to eq('')
      expect(result[:exitcode]).to eq(1)
    end

    it 'preserves provided stdout, stderr, and exitcode' do
      result = transport.error_output('failed', 'bolt/test-error',
                                      stdout: 'partial output', stderr: 'error details', exitcode: 42)

      expect(result[:stdout]).to eq('partial output')
      expect(result[:stderr]).to eq('error details')
      expect(result[:exitcode]).to eq(42)
      expect(result[:error]).to eq('failed')
    end
  end

  describe '#exitcode_from' do
    it 'returns the exitcode from data when present' do
      result = transport.exitcode_from({ exitcode: 42 }, target, 'test command')
      expect(result).to eq(42)
    end

    it 'defaults to 1 and logs a warning when exitcode is nil' do
      logger = transport.logger
      expect(logger).to receive(:warn)

      result = transport.exitcode_from({ exitcode: nil }, target, 'test command')
      expect(result).to eq(1)
    end

    it 'defaults to 1 when exitcode key is missing' do
      logger = transport.logger
      expect(logger).to receive(:warn)

      result = transport.exitcode_from({}, target, 'test command')
      expect(result).to eq(1)
    end

    it 'returns the exitcode when accessed via string key' do
      result = transport.exitcode_from({ 'exitcode' => 42 }, target, 'test command')
      expect(result).to eq(42)
    end
  end

  describe '#validate_env_key!' do
    it 'allows valid POSIX environment variable names' do
      expect { transport.validate_env_key!('MY_VAR_123', 'test') }.not_to raise_error
      expect { transport.validate_env_key!('_UNDER', 'test') }.not_to raise_error
    end

    it 'rejects env key with backticks' do
      expect {
        transport.validate_env_key!('`whoami`', 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end

    it 'rejects env key with newline' do
      expect {
        transport.validate_env_key!("FOO\nBAR=injected", 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end

    it 'rejects env key with null byte' do
      expect {
        transport.validate_env_key!("FOO\x00BAR", 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end

    it 'rejects env key with spaces' do
      expect {
        transport.validate_env_key!('FOO BAR', 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end

    it 'rejects env key with equals sign' do
      expect {
        transport.validate_env_key!('FOO=BAR', 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end

    it 'rejects env key starting with digit' do
      expect {
        transport.validate_env_key!('9VAR', 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end

    it 'rejects empty env key' do
      expect {
        transport.validate_env_key!('', 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end

    it 'rejects env key with shell metacharacters' do
      expect {
        transport.validate_env_key!('BAD$(evil)', 'test')
      }.to raise_error(Bolt::Error, /Unsafe environment variable name/)
    end
  end

  describe '#validate_file_name!' do
    it 'accepts a simple file name' do
      expect { transport.validate_file_name!('mytask.sh') }.not_to raise_error
    end

    it 'accepts a module-relative path without traversal' do
      expect { transport.validate_file_name!('mymod/files/helper.rb') }.not_to raise_error
    end

    it 'rejects file names with null bytes' do
      expect {
        transport.validate_file_name!("legit.sh\x00../../etc/passwd")
      }.to raise_error(Bolt::Error, /Invalid null byte/)
    end

    it 'rejects absolute paths' do
      expect {
        transport.validate_file_name!('/etc/passwd')
      }.to raise_error(Bolt::Error, /Absolute path not allowed/)
    end

    it 'rejects path traversal with ..' do
      expect {
        transport.validate_file_name!('../../etc/shadow')
      }.to raise_error(Bolt::Error, /Path traversal detected/)
    end

    it 'rejects .. that stays within bounds' do
      expect {
        transport.validate_file_name!('mymod/tasks/../tasks/file.sh')
      }.to raise_error(Bolt::Error, /Path traversal detected/)
    end

    it 'rejects trailing ..' do
      expect {
        transport.validate_file_name!('mymod/..')
      }.to raise_error(Bolt::Error, /Path traversal detected/)
    end

    it 'rejects bare .. as file name' do
      expect {
        transport.validate_file_name!('..')
      }.to raise_error(Bolt::Error, /Path traversal detected/)
    end

    it 'does not reject names containing .. as a substring in a segment' do
      # "foo..bar" has no ".." path segment, so it should be allowed
      expect { transport.validate_file_name!('foo..bar') }.not_to raise_error
    end

    it 'rejects Windows absolute paths like C:\Windows\cmd.exe' do
      expect {
        transport.validate_file_name!('C:\Windows\cmd.exe')
      }.to raise_error(Bolt::Error, /Absolute path not allowed/)
    end

    it 'rejects backslash traversal like ..\..\..\etc\passwd' do
      expect {
        transport.validate_file_name!('..\..\..\etc\passwd')
      }.to raise_error(Bolt::Error, /Path traversal detected/)
    end

    it 'accepts valid backslash-separated paths like mymod\tasks\mytask.ps1' do
      expect { transport.validate_file_name!('mymod\tasks\mytask.ps1') }.not_to raise_error
    end
  end

  describe '#poll_with_retries' do
    it 'returns completed targets from each round' do
      rounds = [
        { rpc_failed: false, done: { target => { stdout: 'ok', stderr: '', exitcode: 0 } } }
      ]
      result = transport.poll_with_retries([target], 30, 'test') { rounds.shift }

      expect(result[:completed][target][:stdout]).to eq('ok')
      expect(result[:remaining]).to be_empty
      expect(result[:rpc_persistent_failure]).to be false
    end

    it 'retries on rpc_failed and gives up after RPC_FAILURE_RETRIES' do
      round = { rpc_failed: true, done: {} }
      result = transport.poll_with_retries([target], 30, 'test') { round }

      expect(result[:remaining]).to include(target)
      expect(result[:rpc_persistent_failure]).to be true
      expect(result[:completed]).to be_empty
    end

    it 'resets failure counter after a successful round' do
      rounds = [
        { rpc_failed: true, done: {} },
        { rpc_failed: true, done: {} },
        { rpc_failed: false, done: { target => { stdout: 'recovered', stderr: '', exitcode: 0 } } }
      ]
      result = transport.poll_with_retries([target], 30, 'test') { rounds.shift }

      expect(result[:completed][target][:stdout]).to eq('recovered')
      expect(result[:remaining]).to be_empty
      expect(result[:rpc_persistent_failure]).to be false
    end

    it 'stops when deadline is exceeded' do
      allow(Process).to receive(:clock_gettime).and_return(0, 0, 100)
      result = transport.poll_with_retries([target], 5, 'test') do
        { rpc_failed: false, done: {} }
      end

      expect(result[:remaining]).to include(target)
      expect(result[:rpc_persistent_failure]).to be false
    end

    it 'works with Hash targets (shell handles)' do
      pending_handles = { target => { handle: 'abc-123' } }
      result = transport.poll_with_retries(pending_handles, 30, 'test') do |_remaining|
        { rpc_failed: false, done: { target => { stdout: 'done', stderr: '', exitcode: 0 } } }
      end

      expect(result[:completed][target][:stdout]).to eq('done')
      expect(result[:remaining]).to be_empty
    end

    it 'does not mutate the original targets collection' do
      original = [target]
      transport.poll_with_retries(original, 30, 'test') do
        { rpc_failed: false, done: { target => { stdout: '', stderr: '', exitcode: 0 } } }
      end

      expect(original).to eq([target])
    end
  end
end
