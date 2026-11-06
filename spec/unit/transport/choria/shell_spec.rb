# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'

describe Bolt::Transport::Choria do
  include_context 'choria transport'
  include_context 'choria task'

  describe '#generate_tmpdir_path' do
    it 'generates a path under the target tmpdir with a uuid suffix' do
      allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
      path = transport.generate_tmpdir_path(target)
      expect(path).to eq('/tmp/bolt-choria-test-uuid')
    end

    it 'respects custom tmpdir from target options' do
      inventory.set_config(target, %w[choria tmpdir], '/var/tmp')
      allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
      path = transport.generate_tmpdir_path(target)
      expect(path).to eq('/var/tmp/bolt-choria-test-uuid')
    end

    context 'on Windows targets' do
      before(:each) do
        stub_agents(target, %w[rpcutil shell], os_family: 'windows')
        transport.configure_client(target)
        transport.discover_agents([target])
      end

      it 'uses C:\Windows\Temp when default tmpdir is /tmp on a Windows target' do
        allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
        path = transport.generate_tmpdir_path(target)
        expect(path).to eq('C:\Windows\Temp\bolt-choria-test-uuid')
      end

      it 'respects custom tmpdir on Windows targets' do
        inventory.set_config(target, 'choria', 'tmpdir' => 'D:\bolt\tmp')
        allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
        path = transport.generate_tmpdir_path(target)
        expect(path).to eq('D:\bolt\tmp\bolt-choria-test-uuid')
      end
    end
  end

  describe '#batch_command' do
    include_context 'choria multi-target'

    it 'executes a command and returns stdout, stderr, exit_code' do
      stub_agents([target, target2], %w[rpcutil shell])
      stub_shell_start({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      stub_shell_list({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      stub_shell_status({ target => { handle: 'h1', stdout: 'hello', stderr: 'warn' },
                          target2 => { handle: 'h2', stdout: 'hello', stderr: 'warn' } })

      events = []
      callback = proc { |event| events << event }

      results = transport.batch_command([target, target2], 'echo hello', {}, [], &callback)
      expect(results.length).to eq(2)
      results.each { |result| expect(result.value).to eq('stdout' => 'hello', 'stderr' => 'warn', 'exit_code' => 0) }

      started_targets = events.select { |event| event[:type] == :node_start }.map { |event| event[:target] }
      finished_targets = events.select { |event| event[:type] == :node_result }.map { |event| event[:result].target }
      expect(started_targets).to contain_exactly(target, target2)
      expect(finished_targets).to contain_exactly(target, target2)
    end

    it 'fetches the output in groups of SHELL_STATUSES_BATCH_SIZE' do
      stub_const('Bolt::Transport::Choria::SHELL_STATUSES_BATCH_SIZE', 1)
      stub_agents([target, target2], %w[rpcutil shell])
      stub_shell_start({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      stub_shell_list({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      calls = []
      allow(mock_rpc_client).to receive(:statuses) do |args|
        calls << [mock_rpc_client.options[:filter]['identity'].dup, args[:handles]]
        [make_shell_statuses_result(target, 'h1', stdout: 'one'), make_shell_statuses_result(target2, 'h2', stdout: 'two')]
      end

      results = transport.batch_command([target, target2], 'hostname', {})

      expect(calls).to eq([[%w[node1.example.com], ['h1']], [%w[node2.example.com], ['h2']]])
      expect(results.map { |result| result.value['stdout'] }).to contain_exactly('one', 'two')
    end

    it 'fails only the targets of a shell.statuses group whose call fails' do
      stub_const('Bolt::Transport::Choria::SHELL_STATUSES_BATCH_SIZE', 1)
      stub_agents([target, target2], %w[rpcutil shell])
      stub_shell_start({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      stub_shell_list({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      allow(mock_rpc_client).to receive(:statuses) do
        raise StandardError, 'broker went away' if mock_rpc_client.options[:filter]['identity'] == %w[node2.example.com]

        [make_shell_statuses_result(target, 'h1', stdout: 'one')]
      end

      results = transport.batch_command([target, target2], 'hostname', {})

      expect(results.find { |result| result.target == target }.value['stdout']).to eq('one')
      expect(results.find { |result| result.target == target2 }.error_hash['kind']).to eq('bolt/choria-rpc-failed')
    end

    it 'fails only the targets of a shell.statuses group whose reply it cannot read' do
      stub_const('Bolt::Transport::Choria::SHELL_STATUSES_BATCH_SIZE', 1)
      stub_agents([target, target2], %w[rpcutil shell])
      stub_shell_start({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      stub_shell_list({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      allow(mock_rpc_client).to receive(:statuses) do
        if mock_rpc_client.options[:filter]['identity'] == %w[node2.example.com]
          [make_rpc_result(sender: target2, data: 'not a hash')]
        else
          [make_shell_statuses_result(target, 'h1', stdout: 'one')]
        end
      end

      results = transport.batch_command([target, target2], 'hostname', {})

      expect(results.find { |result| result.target == target }.value['stdout']).to eq('one')
      expect(results.find { |result| result.target == target2 }.error_hash['kind']).to eq('bolt/choria-result-processing-error')
    end

    it 'returns non-zero exit codes without raising' do
      stub_agents(target, %w[rpcutil shell])
      stub_shell_start
      stub_shell_list
      stub_shell_status(stdout: '', stderr: 'fail', exitcode: 42)
      stub_shell_kill

      result = transport.batch_command([target], 'exit 42').first
      expect(result.value['exit_code']).to eq(42)
    end

    it 'returns error when shell agent is not available' do
      stub_agents(target, %w[rpcutil bolt_tasks])

      result = transport.batch_command([target], 'echo hello').first
      expect(result.ok?).to be false
      expect(result.error_hash['msg']).to match(/shell.*agent.*not available/)
    end

    it 'fires error for targets without shell agent' do
      stub_agents(target, %w[rpcutil shell])
      stub_agents(target2, %w[rpcutil])

      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_list({ target => { handle: 'h1' } })
      stub_shell_status({ target => { handle: 'h1', stdout: 'hello' } })

      results = transport.batch_command([target, target2], 'echo hello')
      expect(results.length).to eq(2)

      ok_results = results.select(&:ok?)
      error_results = results.reject(&:ok?)
      expect(ok_results.length).to eq(1)
      expect(ok_results.first.target).to eq(target)
      expect(error_results.length).to eq(1)
      expect(error_results.first.target).to eq(target2)
      expect(error_results.first.error_hash['msg']).to match(/shell.*agent.*not available/)
    end

    it 'returns timeout error when command exceeds command-timeout' do
      stub_agents(target, %w[rpcutil shell])
      stub_shell_start
      stub_shell_kill

      # shell.list always reports the process as still running
      list_data = {
        jobs: { 'test-handle-uuid' => { 'id' => 'test-handle-uuid', 'status' => 'running' } }
      }
      allow(mock_rpc_client).to receive(:list).and_return(
        [make_rpc_result(sender: target, data: list_data)]
      )

      # Force immediate timeout via monotonic clock
      allow(Process).to receive(:clock_gettime).and_return(0, 0, 100)
      inventory.set_config(target, %w[choria command-timeout], 1)

      results = transport.batch_command([target], 'sleep 999', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      expect(results.first.error_hash['kind']).to eq('bolt/choria-command-timeout')
      expect(results.first.error_hash['msg']).to match(/timed out/)
    end

    describe 'Windows targets' do
      it 'wraps commands in PowerShell encoding for Windows targets' do
        stub_agents(target, %w[rpcutil shell], os_family: 'windows')

        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end
        stub_shell_list
        stub_shell_status(stdout: 'ok')

        transport.batch_command([target], 'hostname', {})
        expect(captured_cmd).to start_with('powershell.exe -NoProfile -NonInteractive -EncodedCommand ')
      end
    end

    describe 'env_vars' do
      before(:each) do
        stub_agents(target, %w[rpcutil shell])
        stub_shell_start
        stub_shell_list
        stub_shell_status(stdout: 'ok')
        stub_shell_kill
      end

      it 'passes env_vars to the command via /usr/bin/env and a shell' do
        expect(mock_rpc_client).to receive(:start) do |args|
          expect(args[:command]).to eq('/usr/bin/env MY_VAR=hello sh -c mycommand')
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_command([target], 'mycommand', { env_vars: { 'MY_VAR' => 'hello' } })
      end

      it 'builds a command whose own expansions and compound parts see the variables' do
        skip 'Needs a POSIX shell' if Bolt::Util.windows?

        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_command([target], 'echo "$MY_VAR" && printenv MY_VAR', { env_vars: { 'MY_VAR' => 'hello world' } })
        # The shell agent starts the command string the way Process.spawn does
        expect(IO.popen(captured_cmd, &:read)).to eq("hello world\nhello world\n")
      end

      it 'sets the variables in PowerShell before the unchanged command on Windows targets' do
        stub_agents(target, %w[rpcutil shell], os_family: 'windows')
        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_command([target], '$greeting = $env:MY_VAR; Write-Output $greeting',
                                { env_vars: { 'MY_VAR' => 'hello' } })
        script = Base64.decode64(captured_cmd.split.last).force_encoding('UTF-16LE').encode('UTF-8')
        expect(script).to eq("$env:MY_VAR = 'hello'; $greeting = $env:MY_VAR; Write-Output $greeting")
      end

      it 'accepts values that are not strings on Windows targets' do
        stub_agents(target, %w[rpcutil shell], os_family: 'windows')
        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_command([target], 'mycommand', { env_vars: { 'COUNT' => 5, 'FLAG' => true, 'EMPTY' => nil } })
        script = Base64.decode64(captured_cmd.split.last).force_encoding('UTF-16LE').encode('UTF-8')
        expect(script).to eq("$env:COUNT = '5'; $env:FLAG = 'true'; $env:EMPTY = ''; mycommand")
      end
    end

    describe 'error messages' do
      it 'includes the actual error from shell.start in the error message' do
        stub_agents(target, %w[rpcutil shell])

        start_result = make_rpc_result(sender: target, statuscode: 5,
                                       statusmsg: 'Unknown action start for agent shell')
        allow(mock_rpc_client).to receive(:start).and_return([start_result])

        results = transport.batch_command([target], 'hostname', {})
        expect(results.length).to eq(1)
        expect(results.first.ok?).to be false
        expect(results.first.error_hash['msg']).to include('Unknown action start for agent shell')
      end

      it 'reports a shell.start reply with statuscode 1 as an RPC error with its status message, without polling' do
        stub_agents(target, %w[rpcutil shell])
        refused = make_rpc_result(sender: target, statuscode: 1,
                                  statusmsg: 'You are not authorized to call this agent or action', data: {})
        allow(mock_rpc_client).to receive(:start).and_return([refused])
        expect(mock_rpc_client).not_to receive(:list)

        results = transport.batch_command([target], 'hostname', {})
        expect(results.length).to eq(1)
        expect(results.first.error_hash['kind']).to eq('bolt/choria-rpc-error')
        expect(results.first.error_hash['msg'])
          .to eq('shell.start on choria://node1.example.com returned RPC error: You are not authorized to call this agent or action (code 1)')
      end

      it 'returns error results for all targets when start raises, without polling' do
        stub_agents(target, %w[rpcutil shell])

        allow(mock_rpc_client).to receive(:start).and_raise(StandardError, 'NATS broker down')
        expect(mock_rpc_client).not_to receive(:list)
        expect(transport).not_to receive(:sleep)

        results = transport.batch_command([target], 'hostname', {})
        expect(results.length).to eq(1)
        expect(results.first.ok?).to be false
        expect(results.first.error_hash['kind']).to eq('bolt/choria-rpc-failed')
        expect(results.first.error_hash['msg']).to match(/NATS broker down/)
      end
    end
  end

  describe '#batch_script' do
    let(:script_path) { '/tmp/test_script.sh' }
    let(:script_content) { "#!/bin/bash\necho hello" }

    include_context 'choria multi-target'
    include_context 'choria script file stubs'

    it 'uploads script, makes executable, and runs it on multiple targets' do
      stub_agents([target, target2], %w[rpcutil shell])
      stub_shell_run({ target => {}, target2 => {} })
      stub_shell_start({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      stub_shell_list({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
      stub_shell_status({ target => { handle: 'h1', stdout: 'hello' },
                          target2 => { handle: 'h2', stdout: 'hello' } })

      events = []
      callback = proc { |event| events << event }

      results = transport.batch_script([target, target2], script_path, [], {}, [], &callback)
      expect(results.length).to eq(2)
      results.each { |result| expect(result.value).to eq('stdout' => 'hello', 'stderr' => '', 'exit_code' => 0) }

      starts = events.select { |event| event[:type] == :node_start }
      finishes = events.select { |event| event[:type] == :node_result }
      expect(starts.length).to eq(2)
      expect(finishes.length).to eq(2)
    end

    describe 'command building' do
      before(:each) do
        stub_agents(target, %w[rpcutil shell])
        stub_shell_run
        stub_shell_start
        stub_shell_list
        stub_shell_status(stdout: 'hello')
        stub_shell_kill
      end

      it 'escapes script arguments' do
        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_script([target], script_path, ['arg with spaces'], {}, [])
        expect(captured_cmd).to include("arg\\ with\\ spaces")
      end

      it 'prepends interpreter when script_interpreter option is set' do
        inventory.set_config(target, %w[choria interpreters .sh], '/usr/local/bin/bash')

        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_script([target], script_path, [], { script_interpreter: true }, [])
        expect(captured_cmd).to match(%r{/usr/local/bin/bash\s.*/test_script\.sh})
      end

      it 'does not prepend interpreter when script_interpreter option is not set' do
        inventory.set_config(target, %w[choria interpreters .sh], '/usr/local/bin/bash')

        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_script([target], script_path, [], {}, [])
        expect(captured_cmd).not_to include('/usr/local/bin/bash')
      end

      it 'passes env_vars to the script via /usr/bin/env' do
        captured_cmd = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          captured_cmd = args[:command]
          [make_rpc_result(sender: target, data: { handle: 'test-handle-uuid' })]
        end

        transport.batch_script([target], script_path, ['arg'], { env_vars: { 'MY_VAR' => 'hello world' } }, [])
        expect(captured_cmd).to eq('/usr/bin/env MY_VAR=hello\ world /tmp/bolt-choria-test-uuid/test_script.sh arg')
      end

      it 'rejects an unsafe env var name before any shell agent call' do
        expect(mock_rpc_client).not_to receive(:run)
        expect(mock_rpc_client).not_to receive(:start)

        expect {
          transport.batch_script([target], script_path, [], { env_vars: { 'MY-VAR' => '1' } }, [])
        }.to raise_error(Bolt::Error, /Unsafe environment variable name 'MY-VAR'/)
      end
    end

    describe 'infrastructure step failures' do
      before(:each) do
        stub_agents([target, target2], %w[rpcutil shell])
      end

      it 'excludes target that fails mkdir and continues with remaining' do
        run_calls = 0
        allow(mock_rpc_client).to receive(:run) do
          run_calls += 1
          if run_calls == 1
            [
              make_rpc_result(sender: target, data: { stdout: '', stderr: '', exitcode: 0 }),
              make_rpc_result(sender: target2, data: { stdout: '', stderr: 'permission denied', exitcode: 1 })
            ]
          else
            [make_rpc_result(sender: target, data: { stdout: '', stderr: '', exitcode: 0 })]
          end
        end

        stub_shell_start({ target => { handle: 'h1' } })
        stub_shell_list({ target => { handle: 'h1' } })
        stub_shell_status({ target => { handle: 'h1', stdout: 'hello' } })

        events = []
        results = transport.batch_script([target, target2], script_path, [], {}, [], &proc { |event| events << event })

        expect(results.length).to eq(2)

        ok_results = results.select(&:ok?)
        error_results = results.reject(&:ok?)
        expect(ok_results.length).to eq(1)
        expect(ok_results.first.target).to eq(target)
        expect(error_results.length).to eq(1)
        expect(error_results.first.target).to eq(target2)
        expect(error_results.first.error_hash['kind']).to eq('bolt/choria-operation-failed')
        expect(error_results.first.error_hash['msg']).to match(/permission denied/)

        started_targets = events.select { |event| event[:type] == :node_start }.map { |event| event[:target] }
        finished_targets = events.select { |event| event[:type] == :node_result }.map { |event| event[:result].target }
        expect(started_targets).to contain_exactly(target, target2)
        expect(finished_targets).to contain_exactly(target, target2)
      end

      it 'excludes a target that fails the upload and starts the script on the rest' do
        allow(mock_rpc_client).to receive(:run) do |args|
          failing = args[:command].include?('base64 -d') ? ['node2.example.com'] : []
          mock_rpc_client.options[:filter]['identity'].map do |name|
            exitcode = failing.include?(name) ? 1 : 0
            make_shell_run_result(name, stderr: exitcode.zero? ? '' : 'disk full', exitcode: exitcode)
          end
        end
        started = nil
        allow(mock_rpc_client).to receive(:start) do
          started = mock_rpc_client.options[:filter]['identity'].dup
          [make_shell_start_result(target, handle: 'h1')]
        end
        stub_shell_list({ target => { handle: 'h1' } })
        stub_shell_status({ target => { handle: 'h1', stdout: 'hello' } })

        results = transport.batch_script([target, target2], script_path, [], {})

        expect(results.length).to eq(2)
        expect(results.find { |result| result.target == target }.value['stdout']).to eq('hello')
        failed = results.find { |result| result.target == target2 }
        expect(failed.error_hash['kind']).to eq('bolt/choria-operation-failed')
        expect(failed.error_hash['msg'])
          .to match(%r{\Aupload /tmp/bolt-choria-test-uuid/test_script\.sh failed on .+ \(exit code 1\): disk full})
        expect(started).to eq(['node1.example.com'])
      end

      it 'excludes a target that fails the chmod and starts the script on the rest' do
        allow(mock_rpc_client).to receive(:run) do |args|
          failing = args[:command].start_with?('chmod u+x') ? ['node2.example.com'] : []
          mock_rpc_client.options[:filter]['identity'].map do |name|
            exitcode = failing.include?(name) ? 1 : 0
            make_shell_run_result(name, stderr: exitcode.zero? ? '' : 'read-only file system', exitcode: exitcode)
          end
        end
        started = nil
        allow(mock_rpc_client).to receive(:start) do
          started = mock_rpc_client.options[:filter]['identity'].dup
          [make_shell_start_result(target, handle: 'h1')]
        end
        stub_shell_list({ target => { handle: 'h1' } })
        stub_shell_status({ target => { handle: 'h1', stdout: 'hello' } })

        results = transport.batch_script([target, target2], script_path, [], {})

        expect(results.length).to eq(2)
        expect(results.find { |result| result.target == target }.value['stdout']).to eq('hello')
        failed = results.find { |result| result.target == target2 }
        expect(failed.error_hash['kind']).to eq('bolt/choria-operation-failed')
        expect(failed.error_hash['msg']).to match(/\Achmod script failed on .+ \(exit code 1\): read-only file system/)
        expect(started).to eq(['node1.example.com'])
      end

      it 'returns all errors when all targets fail infrastructure setup' do
        stub_shell_run({ target => { stderr: 'no space', exitcode: 1 },
                         target2 => { stderr: 'no space', exitcode: 1 } })

        results = transport.batch_script([target, target2], script_path, [], {})
        expect(results.length).to eq(2)
        results.each do |result|
          expect(result.ok?).to be false
          expect(result.error_hash['kind']).to eq('bolt/choria-operation-failed')
        end
      end
    end

    context 'on a Windows target' do
      before(:each) do
        stub_agents(target, %w[rpcutil shell], os_family: 'windows')
      end

      it 'creates the tmpdir, uploads the script and removes the tmpdir without a chmod' do
        scripts = []
        allow(mock_rpc_client).to receive(:run) do |args|
          scripts << Base64.decode64(args[:command].split.last).force_encoding('UTF-16LE').encode('UTF-8')
          [make_rpc_result(sender: target, data: { exitcode: 0 })]
        end
        start_script = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          start_script = Base64.decode64(args[:command].split.last).force_encoding('UTF-16LE').encode('UTF-8')
          [make_shell_start_result(target, handle: 'h1')]
        end
        stub_shell_list({ target => { handle: 'h1' } })
        stub_shell_status({ target => { handle: 'h1', stdout: 'hello' } })

        results = transport.batch_script([target], script_path, ['x y'], {}, [])

        expect(results.first.value['stdout']).to eq('hello')
        expect(scripts).to match([
                                   "New-Item -ItemType Directory -Force -Path 'C:\\Windows\\Temp\\bolt-choria-test-uuid'",
                                   a_string_starting_with("[IO.File]::WriteAllBytes('C:\\Windows\\Temp\\bolt-choria-test-uuid\\test_script.sh', "),
                                   "Remove-Item -Recurse -Force -Path 'C:\\Windows\\Temp\\bolt-choria-test-uuid'"
                                 ])
        expect(start_script).to include("'C:\\Windows\\Temp\\bolt-choria-test-uuid\\test_script.sh' 'x y'")
      end

      it 'runs the script through the PowerShell call operator, with and without env vars' do
        start_script = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          start_script = Base64.decode64(args[:command].split.last).force_encoding('UTF-16LE').encode('UTF-8')
          [make_shell_start_result(target, handle: 'h1')]
        end
        stub_shell_run
        stub_shell_list({ target => { handle: 'h1' } })
        stub_shell_status({ target => { handle: 'h1', stdout: 'hello' } })

        transport.batch_script([target], script_path, ['x y'], {}, [])
        expect(start_script).to eq("& 'C:\\Windows\\Temp\\bolt-choria-test-uuid\\test_script.sh' 'x y'")

        transport.batch_script([target], script_path, ['x y'], { env_vars: { 'MY_VAR' => 'v' } }, [])
        expect(start_script).to eq("$env:MY_VAR = 'v'; & 'C:\\Windows\\Temp\\bolt-choria-test-uuid\\test_script.sh' 'x y'")
      end

      it 'passes script arguments that are not strings as strings' do
        start_script = nil
        allow(mock_rpc_client).to receive(:start) do |args|
          start_script = Base64.decode64(args[:command].split.last).force_encoding('UTF-16LE').encode('UTF-8')
          [make_shell_start_result(target, handle: 'h1')]
        end
        stub_shell_run
        stub_shell_list({ target => { handle: 'h1' } })
        stub_shell_status({ target => { handle: 'h1', stdout: 'hello' } })

        results = transport.batch_script([target], script_path, [5, true], {}, [])

        expect(results.first.value['stdout']).to eq('hello')
        expect(start_script).to eq("& 'C:\\Windows\\Temp\\bolt-choria-test-uuid\\test_script.sh' '5' 'true'")
      end
    end
  end

  describe '#run_task_via_shell' do
    before(:each) do
      inventory.set_config(target, %w[choria task-agent], 'shell')
      stub_agents(target, %w[rpcutil shell])
      stub_shell_run
      stub_shell_start
      stub_shell_list
      stub_shell_status(stdout: '{"result":"ok"}')
      stub_shell_kill

      allow(File).to receive(:binread).and_call_original
      allow(File).to receive(:binread).with(task_executable).and_return(task_content)
      allow(File).to receive(:basename).and_call_original
      allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
    end

    it 'uploads task file, makes executable, and runs it' do
      result = transport.batch_task([target], task, {}).first
      expect(result.value).to eq('result' => 'ok')
    end

    it 'removes the tmpdir when an upload is interrupted' do
      commands = []
      allow(mock_rpc_client).to receive(:run) do |args|
        commands << args[:command]
        raise Interrupt if args[:command].include?('base64 -d')

        [make_rpc_result(sender: target, data: { exitcode: 0 })]
      end

      expect { transport.batch_task([target], task, {}) }.to raise_error(Interrupt)
      expect(commands.last).to eq('rm -rf /tmp/bolt-choria-test-uuid')
    end

    it 'removes the tmpdir when building the task command raises after the uploads' do
      commands = []
      allow(mock_rpc_client).to receive(:run) do |args|
        commands << args[:command]
        [make_rpc_result(sender: target, data: { exitcode: 0 })]
      end

      expect { transport.batch_task([target], task, { 'a;b' => 'value' }) }
        .to raise_error(Bolt::Error, /Unsafe environment variable name 'PT_a;b' in task argument/)
      expect(commands.last).to eq('rm -rf /tmp/bolt-choria-test-uuid')
    end

    it 'creates, uses and removes the tmpdir it generated' do
      allow(SecureRandom).to receive(:uuid).and_return('uuid-1', 'uuid-2')
      commands = []
      allow(mock_rpc_client).to receive(:run) do |args|
        commands << args[:command]
        [make_rpc_result(sender: target, data: { exitcode: 0 })]
      end
      start_command = nil
      allow(mock_rpc_client).to receive(:start) do |args|
        start_command = args[:command]
        [make_shell_start_result(target)]
      end

      transport.batch_task([target], task, {})

      expect(commands).to match([
                                  'mkdir -m 700 -p /tmp/bolt-choria-uuid-1',
                                  a_string_matching(%r{\| base64 -d > /tmp/bolt-choria-uuid-1/mytask\.sh\z}),
                                  'chmod u+x /tmp/bolt-choria-uuid-1/mytask.sh',
                                  'rm -rf /tmp/bolt-choria-uuid-1'
                                ])
      expect(start_command).to include('/tmp/bolt-choria-uuid-1/mytask.sh')
    end

    it 'sends no poll and does not sleep when no target gets past the mkdir' do
      stub_shell_run(stderr: 'no space', exitcode: 1)
      expect(mock_rpc_client).not_to receive(:start)
      expect(mock_rpc_client).not_to receive(:list)
      expect(transport).not_to receive(:sleep)

      results = transport.batch_task([target], task, {})

      expect(results.length).to eq(1)
      expect(results.first.error_hash['kind']).to eq('bolt/choria-operation-failed')
      expect(results.first.error_hash['msg']).to match(/\Amkdir tmpdir failed on .+ \(exit code 1\): no space/)
    end

    it 'excludes a target that fails the task upload and starts the task on the rest' do
      stub_agents([target, target2], %w[rpcutil shell])
      inventory.set_config(target2, %w[choria task-agent], 'shell')
      allow(mock_rpc_client).to receive(:run) do |args|
        failing = args[:command].include?('base64 -d') ? ['node2.example.com'] : []
        mock_rpc_client.options[:filter]['identity'].map do |name|
          exitcode = failing.include?(name) ? 1 : 0
          make_shell_run_result(name, stderr: exitcode.zero? ? '' : 'disk full', exitcode: exitcode)
        end
      end
      started = nil
      allow(mock_rpc_client).to receive(:start) do
        started = mock_rpc_client.options[:filter]['identity'].dup
        [make_shell_start_result(target)]
      end

      results = transport.batch_task([target, target2], task, {})

      expect(results.length).to eq(2)
      expect(results.find { |result| result.target == target }.value).to eq('result' => 'ok')
      failed = results.find { |result| result.target == target2 }
      expect(failed.error_hash['kind']).to eq('bolt/choria-operation-failed')
      expect(failed.error_hash['msg'])
        .to match(%r{\Aupload /tmp/bolt-choria-test-uuid/mytask\.sh failed on .+ \(exit code 1\): disk full})
      expect(started).to eq(['node1.example.com'])
    end

    it 'excludes a target that fails the task chmod and starts the task on the rest' do
      stub_agents([target, target2], %w[rpcutil shell])
      inventory.set_config(target2, %w[choria task-agent], 'shell')
      allow(mock_rpc_client).to receive(:run) do |args|
        failing = args[:command].start_with?('chmod u+x') ? ['node2.example.com'] : []
        mock_rpc_client.options[:filter]['identity'].map do |name|
          exitcode = failing.include?(name) ? 1 : 0
          make_shell_run_result(name, stderr: exitcode.zero? ? '' : 'read-only file system', exitcode: exitcode)
        end
      end
      started = nil
      allow(mock_rpc_client).to receive(:start) do
        started = mock_rpc_client.options[:filter]['identity'].dup
        [make_shell_start_result(target)]
      end

      results = transport.batch_task([target, target2], task, {})

      expect(results.length).to eq(2)
      expect(results.find { |result| result.target == target }.value).to eq('result' => 'ok')
      failed = results.find { |result| result.target == target2 }
      expect(failed.error_hash['kind']).to eq('bolt/choria-operation-failed')
      expect(failed.error_hash['msg']).to match(/\Achmod task failed on .+ \(exit code 1\): read-only file system/)
      expect(started).to eq(['node1.example.com'])
    end

    # Command-building details (stdin/environment/both input methods,
    # JSON serialization, interpreter selection) are covered by the
    # pure function tests for #build_task_command in command_builders_spec.

    it 'does not mutate the original arguments hash' do
      original_args = { 'key' => 'value' }
      original_args_dup = original_args.dup

      extra_task = Bolt::Task.new(
        task_name,
        { 'input_method' => 'both', 'files' => ['mymod/lib/helper.rb'] },
        [
          { 'name' => 'mytask.sh', 'path' => task_executable },
          { 'name' => 'mymod/lib/helper.rb', 'path' => '/path/to/mymod/lib/helper.rb' }
        ]
      )
      allow(File).to receive(:binread).with('/path/to/mymod/lib/helper.rb').and_return('# helper')

      transport.batch_task([target], extra_task, original_args)

      expect(original_args).to eq(original_args_dup)
    end

    it 'handles tasks with extra files' do
      extra_task = Bolt::Task.new(
        task_name,
        { 'input_method' => 'both', 'files' => ['mymod/lib/helper.rb'] },
        [
          { 'name' => 'mytask.sh', 'path' => task_executable },
          { 'name' => 'mymod/lib/helper.rb', 'path' => '/path/to/mymod/lib/helper.rb' }
        ]
      )
      allow(File).to receive(:binread).with('/path/to/mymod/lib/helper.rb').and_return('# helper')

      result = transport.batch_task([target], extra_task, {}).first
      expect(result.ok?).to be true
      expect(result.value).to eq('result' => 'ok')
    end
  end

  describe '#shell_run' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'returns empty hash when all targets succeed' do
      stub_shell_run({ target => {}, target2 => {} })

      failures = transport.shell_run([target, target2], 'echo ok',
                                     description: 'test')
      expect(failures).to be_empty
    end

    it 'returns failures for non-responding targets' do
      stub_shell_run({ target => {} })

      failures = transport.shell_run([target, target2], 'echo ok',
                                     description: 'test')
      expect(failures.keys).to eq([target2])
      expect(failures[target2][:error]).to match(/No response/)
    end

    it 'returns failures for non-zero exit codes' do
      stub_shell_run({ target => {},
                       target2 => { exitcode: 1, stderr: 'Permission denied' } })

      failures = transport.shell_run([target, target2], 'mkdir /foo',
                                     description: 'mkdir')
      expect(failures.keys).to eq([target2])
      expect(failures[target2][:error]).to match(/exit code 1/)
    end

    it 'returns all targets as failed when RPC call raises' do
      allow(mock_rpc_client).to receive(:run).and_raise(StandardError, 'NATS timeout')

      failures = transport.shell_run([target, target2], 'echo ok',
                                     description: 'test')
      expect(failures.keys).to contain_exactly(target, target2)
      expect(failures[target][:error]).to match(/NATS timeout/)
    end

    it 'returns failures for non-zero RPC statuscodes' do
      allow(mock_rpc_client).to receive(:run).and_return([
                                                           make_shell_run_result(target),
                                                           make_rpc_result(sender: target2, statuscode: 5,
                                                                           statusmsg: 'Authorization denied', data: {})
                                                         ])

      failures = transport.shell_run([target, target2], 'echo ok',
                                     description: 'test')
      expect(failures.keys).to eq([target2])
      expect(failures[target2][:error]).to match(/test on .+ returned RPC error: Authorization denied/)
    end
  end

  describe '#shell_start' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'returns error output hashes for all targets when RPC call raises' do
      allow(mock_rpc_client).to receive(:start).and_raise(StandardError, 'NATS connection lost')

      pending_map, errors = transport.shell_start([target, target2], 'echo hi')
      expect(pending_map).to be_empty
      expect(errors.length).to eq(2)
      errors.each_value do |output|
        expect(output[:error_kind]).to eq('bolt/choria-rpc-failed')
        expect(output[:error]).to match(/NATS connection lost/)
      end
    end

    it 'handles nil data from shell.start gracefully' do
      stub_agents(target, %w[rpcutil shell])

      start_result = make_rpc_result(sender: target, statuscode: 0, data: nil)
      allow(mock_rpc_client).to receive(:start).and_return([start_result])

      results = transport.batch_command([target], 'hostname', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      expect(results.first.error_hash['msg']).to match(/no handle/)
    end
  end

  describe '#upload_file_content' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'base64-encodes content and runs via shell_run' do
      content = "binary\x00content\nwith\tnewlines"

      allow(mock_rpc_client).to receive(:run) do |args|
        expect(args[:command]).to match(%r{printf '%s' .+ \| base64 -d > /remote/path})
        [make_rpc_result(sender: target, data: { stdout: '', stderr: '', exitcode: 0 })]
      end

      failures = transport.upload_file_content([target], content, '/remote/path')
      expect(failures).to be_empty
    end

    it 'returns failures from underlying shell_run' do
      allow(mock_rpc_client).to receive(:run).and_return([
                                                           make_rpc_result(sender: target,
                                                                           data: { stdout: '', stderr: 'disk full', exitcode: 1 })
                                                         ])

      failures = transport.upload_file_content([target], 'data', '/remote/path')
      expect(failures).to have_key(target)
      expect(failures[target][:error]).to match(/disk full/)
    end

    it 'writes an empty file for empty content' do
      commands = []
      allow(mock_rpc_client).to receive(:run) do |args|
        commands << args[:command]
        [make_shell_run_result(target)]
      end

      transport.upload_file_content([target], '', '/tmp/dir/file')

      expect(commands).to eq(["printf '%s' '' | base64 -d > /tmp/dir/file"])
    end

    context 'with content larger than 1 chunk' do
      before(:each) do
        stub_const('Bolt::Transport::Choria::POSIX_UPLOAD_CHUNK_BYTES', 4)
        stub_const('Bolt::Transport::Choria::WINDOWS_UPLOAD_CHUNK_BYTES', 4)
      end

      it 'uploads it in pieces that rebuild the whole file' do
        skip 'Needs a POSIX shell' if Bolt::Util.windows?

        content = "binary \x00\xFF and text"
        Dir.mktmpdir do |dir|
          destination = File.join(dir, 'file')
          commands = []
          allow(mock_rpc_client).to receive(:run) do |args|
            commands << args[:command]
            # The shell agent starts the command string the way system does
            system(args[:command], exception: true)
            [make_shell_run_result(target)]
          end

          expect(transport.upload_file_content([target], content, destination)).to be_empty
          expect(commands.length).to eq((content.bytesize / 4.0).ceil)
          expect(File.binread(destination)).to eq(content.b)
        end
      end

      it 'sends no later chunks to a target that failed one' do
        recipients = []
        allow(mock_rpc_client).to receive(:run) do
          recipients << mock_rpc_client.options[:filter]['identity'].dup
          [make_shell_run_result(target), make_shell_run_result(target2, stderr: 'disk full', exitcode: 1)]
        end

        failures = transport.upload_file_content([target, target2], 'abcdefgh', '/tmp/dir/file')

        expect(failures.keys).to eq([target2])
        expect(recipients).to eq([%w[node1.example.com node2.example.com], %w[node1.example.com]])
      end

      it 'adds the later chunks to the file on Windows targets' do
        stub_agents(target, %w[rpcutil shell], os_family: 'windows')
        transport.discover_agents([target])
        scripts = []
        allow(mock_rpc_client).to receive(:run) do |args|
          scripts << Base64.decode64(args[:command].split.last).force_encoding('UTF-16LE').encode('UTF-8')
          [make_shell_run_result(target)]
        end

        transport.upload_file_content([target], 'abcdef', 'C:\temp\file')

        expect(scripts).to eq([
                                "[IO.File]::WriteAllBytes('C:\\temp\\file', [Convert]::FromBase64String('YWJjZA=='))",
                                "$bytes = [Convert]::FromBase64String('ZWY='); $stream = [IO.File]::Open('C:\\temp\\file', 'Append', 'Write'); " \
                                'try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Close() }'
                              ])
      end
    end
  end

  describe '#cleanup_tmpdir' do
    before(:each) do
      stub_agents(target, %w[rpcutil shell])
    end

    it 'skips cleanup when cleanup option is false' do
      inventory.set_config(target, %w[choria cleanup], false)
      stub_shell_start
      stub_shell_list
      stub_shell_status(stdout: 'ok')
      allow(File).to receive(:binread).and_return('#!/bin/bash\necho hi')

      run_commands = []
      allow(mock_rpc_client).to receive(:run) do |args|
        run_commands << args[:command]
        [make_rpc_result(sender: target, data: { exitcode: 0 })]
      end

      transport.batch_script([target], task_executable, [], {})
      expect(run_commands).not_to include(match(/rm -rf/))
    end

    it 'does not mask task results when cleanup fails' do
      stub_shell_start
      stub_shell_list
      stub_shell_status(stdout: 'task output')
      allow(File).to receive(:binread).and_return("#!/bin/bash\necho hi")

      allow(mock_rpc_client).to receive(:run) do |args|
        if args[:command]&.include?('rm -rf')
          raise StandardError, 'NATS timeout during cleanup'
        end

        [make_rpc_result(sender: target, data: { exitcode: 0 })]
      end

      results = transport.batch_script([target], task_executable, [], {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be true
    end

    it 'refuses to delete paths that do not start with bolt-choria-' do
      transport.configure_client(target)

      expect(mock_rpc_client).not_to receive(:run)
      transport.cleanup_tmpdir([target], '/tmp/some-other-dir')
    end

    context 'on a Windows target' do
      before(:each) do
        stub_agents(target, %w[rpcutil shell], os_family: 'windows')
        transport.configure_client(target)
        transport.discover_agents([target])
      end

      it 'removes a tmpdir whose path is joined with backslashes' do
        scripts = []
        allow(mock_rpc_client).to receive(:run) do |args|
          encoded = args[:command].split.last
          scripts << Base64.decode64(encoded).force_encoding('UTF-16LE').encode('UTF-8')
          [make_rpc_result(sender: target, data: { exitcode: 0 })]
        end

        transport.cleanup_tmpdir([target], 'C:\Windows\Temp\bolt-choria-test-uuid')

        expect(scripts).to eq(["Remove-Item -Recurse -Force -Path 'C:\\Windows\\Temp\\bolt-choria-test-uuid'"])
      end

      it 'refuses to delete a backslash path whose last part does not start with bolt-choria-' do
        expect(mock_rpc_client).not_to receive(:run)
        transport.cleanup_tmpdir([target], 'C:\Windows\Temp')
      end
    end
  end

  describe '#shell_statuses' do
    before(:each) do
      stub_agents(target, %w[rpcutil shell])
    end

    it 'returns error result when status is failed' do
      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_list({ target => { handle: 'h1', status: 'failed' } })
      stub_shell_status({ target => { handle: 'h1', status: 'failed', stderr: 'exec format error', exitcode: nil } })
      stub_shell_kill

      results = transport.batch_command([target], 'bad_command', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      expect(results.first.error_hash['kind']).to eq('bolt/choria-process-failed')
    end

    it 'returns error result when status is error (handle not found)' do
      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_list({ target => { handle: 'h1', status: 'stopped' } })
      stub_shell_kill

      allow(mock_rpc_client).to receive(:statuses).and_return([
                                                                make_rpc_result(sender: target, data: {
                                                                                  statuses: { 'h1' => { 'status' => 'error' } }
                                                                                })
                                                              ])

      results = transport.batch_command([target], 'hostname', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      expect(results.first.error_hash['kind']).to eq('bolt/choria-handle-not-found')
    end

    it 'returns error result when statuses data is nil' do
      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_list({ target => { handle: 'h1' } })
      stub_shell_kill

      allow(mock_rpc_client).to receive(:statuses).and_return([
                                                                make_rpc_result(sender: target, data: { statuses: nil })
                                                              ])

      results = transport.batch_command([target], 'hostname', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      expect(results.first.error_hash['kind']).to eq('bolt/choria-missing-data')
    end

    it 'returns error result when specific handle is missing from statuses' do
      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_list({ target => { handle: 'h1' } })
      stub_shell_kill

      statuses_data = {
        statuses: { 'wrong-handle' => { 'status' => 'stopped', 'stdout' => 'ok' } }
      }
      allow(mock_rpc_client).to receive(:statuses).and_return(
        [make_rpc_result(sender: target, data: statuses_data)]
      )

      results = transport.batch_command([target], 'hostname', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      expect(results.first.error_hash['kind']).to eq('bolt/choria-missing-data')
      expect(results.first.error_hash['msg']).to match(/did not include handle/)
    end

    it 'returns error results for all targets when statuses raises' do
      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_list({ target => { handle: 'h1' } })

      allow(mock_rpc_client).to receive(:statuses).and_raise(StandardError, 'NATS timeout')

      results = transport.batch_command([target], 'hostname', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      # The exception is caught by rpc_request's rescue (before shell_statuses'
      # rescue), which returns it as a rpc-failed error for the target.
      expect(results.first.error_hash['kind']).to eq('bolt/choria-rpc-failed')
      expect(results.first.error_hash['msg']).to match(/NATS timeout/)
    end
  end

  describe '#shell_list' do
    before(:each) do
      stub_agents(target, %w[rpcutil shell])
    end

    it 'returns error when handle is not found in shell.list response' do
      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_kill

      allow(mock_rpc_client).to receive(:list).and_return([
                                                            make_rpc_result(sender: target,
                                                                            data: { jobs: { 'other-handle' => { 'status' => 'stopped' } } })
                                                          ])

      results = transport.batch_command([target], 'hostname', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
      expect(results.first.error_hash['kind']).to eq('bolt/choria-handle-not-found')
    end

    it 'returns error when shell.list responds with nil data' do
      stub_shell_start({ target => { handle: 'h1' } })
      stub_shell_kill

      allow(mock_rpc_client).to receive(:list).and_return([
                                                            make_rpc_result(sender: target, data: nil)
                                                          ])

      results = transport.batch_command([target], 'hostname', {})
      expect(results.length).to eq(1)
      expect(results.first.ok?).to be false
    end
  end

  describe '#wait_for_shell_results' do
    describe 'persistent poll failure' do
      before(:each) do
        stub_agents(target, %w[rpcutil shell])
      end

      it 'fails all targets after 3 consecutive poll RPC failures' do
        stub_shell_start({ target => { handle: 'h1' } })
        stub_shell_kill

        allow(mock_rpc_client).to receive(:list)
          .and_raise(StandardError, 'NATS connection lost')

        results = transport.batch_command([target], 'hostname', {})
        expect(results.length).to eq(1)
        expect(results.first.ok?).to be false
        expect(results.first.error_hash['kind']).to eq('bolt/choria-poll-failed')
        expect(results.first.error_hash['msg']).to match(/failed persistently/)
      end
    end

    describe 'RPC error statuscode during polling' do
      before(:each) do
        stub_agents(target, %w[rpcutil shell])
      end

      it 'returns error result immediately when shell.list returns non-zero statuscode' do
        stub_shell_start({ target => { handle: 'h1' } })
        stub_shell_kill

        list_result = make_rpc_result(sender: target, statuscode: 4, statusmsg: 'Authorization denied')
        allow(mock_rpc_client).to receive(:list).and_return([list_result])

        results = transport.batch_command([target], 'hostname', {})
        expect(results.length).to eq(1)
        expect(results.first.ok?).to be false
        expect(results.first.error_hash['kind']).to eq('bolt/choria-rpc-error')
        expect(results.first.error_hash['msg']).to match(/Authorization denied/)
        expect(results.first.error_hash['msg']).to match(/code 4/)
      end
    end

    describe 'partial target failures during polling' do
      before(:each) do
        transport.configure_client(target)
      end

      it 'completes unaffected targets when one target does not respond to statuses' do
        stub_agents([target, target2], %w[rpcutil shell])

        stub_shell_start({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
        stub_shell_list({ target => { handle: 'h1' }, target2 => { handle: 'h2' } })
        # Only target2 responds to shell.statuses. target does not respond,
        # so rpc_request will put it in errors as a no-response error.
        stub_shell_status({ target2 => { handle: 'h2', stdout: 'hello' } })
        stub_shell_kill

        results = transport.batch_command([target, target2], 'hostname', {})
        expect(results.length).to eq(2)

        ok_results = results.select(&:ok?)
        error_results = results.reject(&:ok?)
        expect(ok_results.length).to eq(1)
        expect(ok_results.first.target).to eq(target2)
        expect(error_results.length).to eq(1)
        expect(error_results.first.target).to eq(target)
        expect(error_results.first.error_hash['msg']).to match(/No response/)
      end
    end
  end

  describe '#kill_timed_out_processes' do
    before(:each) { transport.configure_client(target) }

    it 'still returns timeout error and warns when kill fails' do
      pending_map = { target => { handle: 'h1' } }
      warnings = []

      # shell_list never finds completion, so the loop times out
      allow(transport).to receive(:shell_list).and_return([{}, {}, false])
      allow(mock_rpc_client).to receive(:kill).and_return(
        [make_rpc_result(sender: target, statuscode: 5, statusmsg: 'Could not kill the process')]
      )
      allow(transport.logger).to receive(:warn) { |*args, &block| warnings << (block ? block.call : args.first) }

      inventory.set_config(target, %w[choria command-timeout], 1)
      outputs = transport.wait_for_shell_results(pending_map, 1)

      expect(outputs.length).to eq(1)
      expect(outputs[target][:error_kind]).to eq('bolt/choria-command-timeout')
      expect(warnings).to include(
        'Failed to kill process on choria://node1.example.com: shell.kill on ' \
        'choria://node1.example.com returned RPC error: Could not kill the process (code 5)'
      )
    end

    it 'still returns timeout error and warns when kill answers statuscode 1' do
      pending_map = { target => { handle: 'h1' } }
      warnings = []

      allow(transport).to receive(:shell_list).and_return([{}, {}, false])
      allow(mock_rpc_client).to receive(:kill).and_return(
        [make_rpc_result(sender: target, statuscode: 1, statusmsg: 'You are not authorized to call this agent or action', data: {})]
      )
      allow(transport.logger).to receive(:warn) { |*args, &block| warnings << (block ? block.call : args.first) }

      inventory.set_config(target, %w[choria command-timeout], 1)
      outputs = transport.wait_for_shell_results(pending_map, 1)

      expect(outputs[target][:error_kind]).to eq('bolt/choria-command-timeout')
      expect(warnings).to include(
        'Failed to kill process on choria://node1.example.com: shell.kill on choria://node1.example.com ' \
        'returned RPC error: You are not authorized to call this agent or action (code 1)'
      )
    end

    it 'still returns timeout error and warns when kill raises' do
      pending_map = { target => { handle: 'h1' } }
      warnings = []

      allow(transport).to receive(:shell_list).and_return([{}, {}, false])
      allow(mock_rpc_client).to receive(:kill).and_raise(StandardError, 'NATS timeout on kill')
      allow(transport.logger).to receive(:warn) { |*args, &block| warnings << (block ? block.call : args.first) }

      inventory.set_config(target, %w[choria command-timeout], 1)
      outputs = transport.wait_for_shell_results(pending_map, 1)

      expect(outputs[target][:error_kind]).to eq('bolt/choria-command-timeout')
      expect(warnings).to include(
        'Failed to kill process on choria://node1.example.com: shell.kill failed on ' \
        'choria://node1.example.com: NATS timeout on kill'
      )
    end
  end

  describe 'shell job directories' do
    include_context 'choria multi-target'

    let(:handle) { '0f2d8c4e-1b3a-4c5d-8e9f-0a1b2c3d4e5f' }
    let(:handle2) { '9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d' }
    let(:removals) { [] }

    def start_two_jobs(first_handle, second_handle)
      stub_shell_start({ target => { handle: first_handle }, target2 => { handle: second_handle } })
      stub_shell_list({ target => { handle: first_handle }, target2 => { handle: second_handle } })
      stub_shell_status({ target => { handle: first_handle, stdout: 'ok' }, target2 => { handle: second_handle, stdout: 'ok' } })
      allow(mock_rpc_client).to receive(:run) do |args|
        removals << [mock_rpc_client.options[:filter]['identity'].dup, args[:command]]
        [make_shell_run_result(target), make_shell_run_result(target2)]
      end
    end

    it 'removes the directories of the jobs that finished' do
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs(handle, handle2)

      results = transport.batch_command([target, target2], 'hostname', {})

      expect(results.map { |result| result.value['stdout'] }).to eq(%w[ok ok])
      expect(removals).to eq([[%w[node1.example.com node2.example.com],
                               "rm -rf /var/run/mcollective-shell/#{handle} /var/run/mcollective-shell/#{handle2}"]])
    end

    it 'keeps the directory of a job that timed out' do
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs(handle, handle2)
      allow(mock_rpc_client).to receive(:list).and_return([make_shell_list_result(target, handle),
                                                           make_shell_list_result(target2, handle2, status: 'running')])
      stub_shell_kill
      allow(Process).to receive(:clock_gettime).and_return(0, 0, 100)
      inventory.set_config(target, %w[choria command-timeout], 1)

      results = transport.batch_command([target, target2], 'hostname', {})

      expect(results.find { |result| result.target == target2 }.error_hash['kind']).to eq('bolt/choria-command-timeout')
      expect(removals).to eq([[%w[node1.example.com], "rm -rf /var/run/mcollective-shell/#{handle}"]])
    end

    it 'keeps the directory on a target that stopped answering' do
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs(handle, handle2)
      allow(mock_rpc_client).to receive(:list).and_return([make_shell_list_result(target, handle)])

      results = transport.batch_command([target, target2], 'hostname', {})

      expect(results.find { |result| result.target == target2 }.error_hash['kind']).to eq('bolt/choria-no-response')
      expect(removals).to eq([[%w[node1.example.com], "rm -rf /var/run/mcollective-shell/#{handle}"]])
    end

    it 'keeps the results and warns when the removal fails' do
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs(handle, handle2)
      allow(mock_rpc_client).to receive(:run).and_raise(StandardError, 'broker went away')
      warnings = []
      allow(transport.logger).to receive(:warn) { |*args, &block| warnings << (block ? block.call : args.first) }

      results = transport.batch_command([target, target2], 'hostname', {})

      expect(results.map { |result| result.value['stdout'] }).to eq(%w[ok ok])
      expect(warnings).to include(a_string_including('broker went away'))
    end

    it 'sends each platform its own removal command' do
      stub_agents(target, %w[rpcutil shell], os_family: 'windows')
      stub_agents(target2, %w[rpcutil shell])
      transport.discover_agents([target, target2])
      allow(mock_rpc_client).to receive(:run) do |args|
        removals << [mock_rpc_client.options[:filter]['identity'].dup, args[:command]]
        [make_shell_run_result(target), make_shell_run_result(target2)]
      end

      transport.remove_job_dirs({ target => { handle: handle }, target2 => { handle: handle2 } })

      expect(removals.to_h.keys).to contain_exactly(%w[node1.example.com], %w[node2.example.com])
      expect(removals.to_h[%w[node1.example.com]]).to start_with('powershell.exe ')
      expect(removals.to_h[%w[node2.example.com]]).to eq("rm -rf /var/run/mcollective-shell/#{handle2}")
    end

    it 'removes the directories in groups of SHELL_JOB_DIR_BATCH_SIZE' do
      stub_const('Bolt::Transport::Choria::SHELL_JOB_DIR_BATCH_SIZE', 1)
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs(handle, handle2)

      transport.batch_command([target, target2], 'hostname', {})

      expect(removals).to eq([[%w[node1.example.com], "rm -rf /var/run/mcollective-shell/#{handle}"],
                              [%w[node2.example.com], "rm -rf /var/run/mcollective-shell/#{handle2}"]])
    end

    it 'removes the directories under the agent path on Windows targets' do
      stub_agents([target, target2], %w[rpcutil shell], os_family: 'windows')
      start_two_jobs(handle, handle2)

      transport.batch_command([target, target2], 'hostname', {})

      script = Base64.decode64(removals.first.last.split.last).force_encoding('UTF-16LE').encode('UTF-8')
      expect(script).to eq("foreach ($path in @('C:/ProgramData/mcollective-shell/#{handle}', " \
                           "'C:/ProgramData/mcollective-shell/#{handle2}')) { if (Test-Path -LiteralPath $path) " \
                           '{ Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop } }')
    end

    it 'leaves out a handle that is not a UUID' do
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs('../../etc', handle2)

      transport.batch_command([target, target2], 'hostname', {})

      expect(removals).to eq([[%w[node2.example.com], "rm -rf /var/run/mcollective-shell/#{handle2}"]])
    end

    it 'leaves out a handle with more text after the UUID' do
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs("#{handle}\necho injected", handle2)

      transport.batch_command([target, target2], 'hostname', {})

      expect(removals).to eq([[%w[node2.example.com], "rm -rf /var/run/mcollective-shell/#{handle2}"]])
    end

    it 'keeps the directory of a target whose cleanup option is off' do
      inventory.set_config(target, %w[choria cleanup], false)
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs(handle, handle2)

      transport.batch_command([target, target2], 'hostname', {})

      expect(removals).to eq([[%w[node2.example.com], "rm -rf /var/run/mcollective-shell/#{handle2}"]])
    end

    it 'keeps the directories when cleanup is false' do
      inventory.set_config(target, %w[choria cleanup], false)
      inventory.set_config(target2, %w[choria cleanup], false)
      stub_agents([target, target2], %w[rpcutil shell])
      start_two_jobs(handle, handle2)

      transport.batch_command([target, target2], 'hostname', {})

      expect(removals).to be_empty
    end
  end
end
