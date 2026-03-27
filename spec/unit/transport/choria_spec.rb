# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'
require 'bolt_spec/sensitive'

describe Bolt::Transport::Choria do
  include_context 'choria transport'
  include_context 'choria task'
  include BoltSpec::Sensitive

  describe '#provided_features' do
    it 'includes shell and powershell' do
      expect(transport.provided_features).to eq(%w[shell powershell])
    end
  end

  describe '#select_implementation' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'selects the shell implementation for a Linux target' do
      stub_agents(target, %w[rpcutil shell], os_family: 'RedHat')
      transport.discover_agents([target])

      impl = transport.select_implementation(target, cross_platform_task)
      expect(impl['name']).to eq('crosstask.sh')
    end

    it 'selects the powershell implementation for a Windows target' do
      stub_agents(target, %w[rpcutil shell], os_family: 'windows')
      transport.discover_agents([target])

      impl = transport.select_implementation(target, cross_platform_task)
      expect(impl['name']).to eq('crosstask.ps1')
    end

    it 'raises when a Linux target runs a Windows-only task' do
      stub_agents(target, %w[rpcutil shell], os_family: 'RedHat')
      transport.discover_agents([target])

      expect {
        transport.select_implementation(target, windows_only_task)
      }.to raise_error(Bolt::Error, /No suitable implementation/)
    end

    it 'raises when a Windows target runs a Linux-only task' do
      stub_agents(target, %w[rpcutil shell], os_family: 'windows')
      transport.discover_agents([target])

      expect {
        transport.select_implementation(target, linux_only_task)
      }.to raise_error(Bolt::Error, /No suitable implementation/)
    end
  end

  describe '#batch_connected?' do
    include_context 'choria multi-target'

    it 'returns true when all targets respond to ping' do
      r1 = make_rpc_result(sender: target)
      r2 = make_rpc_result(sender: target2)
      allow(mock_rpc_client).to receive(:ping).and_return([r1, r2])

      expect(transport.batch_connected?([target, target2])).to be true
    end

    it 'returns false when some targets do not respond' do
      r1 = make_rpc_result(sender: target)
      allow(mock_rpc_client).to receive(:ping).and_return([r1])

      expect(transport.batch_connected?([target, target2])).to be false
    end

    it 'returns false on error' do
      allow(mock_rpc_client).to receive(:ping).and_raise(StandardError, 'NATS timeout')
      expect(transport.batch_connected?([target, target2])).to be false
    end

    it 're-raises Bolt::Error instead of returning false' do
      allow(mock_rpc_client).to receive(:ping).and_raise(
        Bolt::Error.new('Config problem', 'bolt/choria-config-failed')
      )
      expect { transport.batch_connected?([target, target2]) }.to raise_error(
        Bolt::Error, 'Config problem'
      )
    end

    it 'ignores responses from unexpected senders' do
      r1 = make_rpc_result(sender: target)
      r2 = make_rpc_result(sender: target2)
      rogue = make_rpc_result(sender: 'rogue.example.com')
      allow(mock_rpc_client).to receive(:ping).and_return([r1, r2, rogue])

      expect(transport.batch_connected?([target, target2])).to be true
    end

    it 'returns false when expected target is missing despite extra senders' do
      r1 = make_rpc_result(sender: target)
      rogue = make_rpc_result(sender: 'rogue.example.com')
      allow(mock_rpc_client).to receive(:ping).and_return([r1, rogue])

      expect(transport.batch_connected?([target, target2])).to be false
    end

    it 'does not disconnect the shared NATS connection' do
      allow(mock_rpc_client).to receive(:ping).and_return([])
      expect(mock_rpc_client).not_to receive(:disconnect)
      transport.batch_connected?([target])
    end
  end

  describe '#upload' do
    it 'raises an unsupported operation error' do
      expect { transport.upload(target, '/src', '/dst') }.to raise_error(
        Bolt::Error, /does not yet support upload/
      )
    end
  end

  describe '#download' do
    it 'raises an unsupported operation error' do
      expect { transport.download(target, '/src', '/dst') }.to raise_error(
        Bolt::Error, /does not yet support download/
      )
    end
  end

  describe '#batches' do
    include_context 'choria multi-target'

    it 'groups all targets into one batch when they share the same collective' do
      batches = transport.batches([target, target2])
      expect(batches.length).to eq(1)
      expect(batches.first).to contain_exactly(target, target2)
    end

    it 'groups targets into separate batches by collective' do
      inventory.set_config(target, %w[choria collective], 'production')
      inventory.set_config(target2, %w[choria collective], 'staging')

      batches = transport.batches([target, target2])
      expect(batches.length).to eq(2)
      collectives = batches.map { |batch| batch.first.options['collective'] }.sort
      expect(collectives).to eq(%w[production staging])
    end

    it 'uses default collective for targets without explicit collective' do
      inventory.set_config(target, %w[choria collective], 'production')

      batches = transport.batches([target, target2])
      expect(batches.length).to eq(2)
      collectives = batches.map { |batch| batch.first.options['collective'] }
      expect(collectives).to contain_exactly(nil, 'production')
    end
  end

  describe '#batch_task' do
    include_context 'choria task file stubs'

    describe 'single target' do
      context 'default agent routing' do
        it 'defaults to bolt_tasks when bolt_tasks agent is present' do
          stub_agents(target, %w[rpcutil bolt_tasks shell])

          expect(transport).to receive(:run_task_via_bolt_tasks).and_return(
            [Bolt::Result.for_task(target, '{"result":"ok"}', '', 0, task_name, [])]
          )
          expect(transport).not_to receive(:run_task_via_shell)

          transport.batch_task([target], task, {})
        end

        it 'returns error when bolt_tasks not available' do
          stub_agents(target, %w[rpcutil shell])

          expect(transport).not_to receive(:run_task_via_bolt_tasks)
          expect(transport).not_to receive(:run_task_via_shell)

          result = transport.batch_task([target], task, {}).first
          expect(result.ok?).to be false
          expect(result.error_hash['msg']).to match(/bolt_tasks.*not available/)
        end

        it 'returns error when neither agent is available' do
          stub_agents(target, %w[rpcutil])

          result = transport.batch_task([target], task, {}).first
          expect(result.ok?).to be false
          expect(result.error_hash['msg']).to match(/bolt_tasks.*not available/)
        end
      end

      context 'with forced task-agent' do
        it 'uses only bolt_tasks when forced' do
          stub_agents(target, %w[rpcutil bolt_tasks shell])
          inventory.set_config(target, %w[choria task-agent], 'bolt_tasks')

          expect(transport).to receive(:run_task_via_bolt_tasks).and_return(
            [Bolt::Result.for_task(target, '{}', '', 0, task_name, [])]
          )
          expect(transport).not_to receive(:run_task_via_shell)

          transport.batch_task([target], task, {})
        end

        it 'uses only shell when forced' do
          stub_agents(target, %w[rpcutil bolt_tasks shell])
          inventory.set_config(target, %w[choria task-agent], 'shell')

          expect(transport).not_to receive(:run_task_via_bolt_tasks)
          expect(transport).to receive(:run_task_via_shell).and_return(
            [Bolt::Result.for_task(target, '{}', '', 0, task_name, [])]
          )

          transport.batch_task([target], task, {})
        end

        it 'returns error when forced agent is not available on target' do
          stub_agents(target, %w[rpcutil bolt_tasks])
          inventory.set_config(target, %w[choria task-agent], 'shell')

          result = transport.batch_task([target], task, {}).first
          expect(result.ok?).to be false
          expect(result.error_hash['msg']).to match(/shell.*not available/)
        end

        it 'raises for invalid forced agent value' do
          stub_agents(target, %w[rpcutil bolt_tasks shell invalid_agent])
          inventory.set_config(target, %w[choria task-agent], 'invalid_agent')

          expect {
            transport.batch_task([target], task, {})
          }.to raise_error(Bolt::ValidationError, /task-agent must be/)
        end
      end
    end

    describe 'multi-target' do
      include_context 'choria multi-target'

      it 'downloads and runs task on multiple targets via bolt_tasks' do
        stub_agents([target, target2], %w[rpcutil bolt_tasks])

        allow(mock_rpc_client).to receive_messages(
          download: [make_download_result(target), make_download_result(target2)],
          run_no_wait: [make_task_run_result(target), make_task_run_result(target2)],
          task_status: [make_task_status_result(target), make_task_status_result(target2)]
        )

        expect(transport).to receive(:run_task_via_bolt_tasks).and_call_original
        expect(transport).not_to receive(:run_task_via_shell)

        events = []
        callback = proc { |event| events << event }

        results = transport.batch_task([target, target2], task, {}, {}, [], &callback)
        expect(results.length).to eq(2)
        results.each { |result| expect(result.value).to eq('result' => 'ok') }

        started_targets = events.select { |event| event[:type] == :node_start }.map { |event| event[:target] }
        finished_targets = events.select { |event| event[:type] == :node_result }.map { |event| event[:result].target }
        expect(started_targets).to contain_exactly(target, target2)
        expect(finished_targets).to contain_exactly(target, target2)
      end

      it 'handles partial failure: one target has no agents' do
        # Only node1 responds to discovery and node2 is unreachable
        stub_agents(target, %w[rpcutil bolt_tasks])

        allow(mock_rpc_client).to receive_messages(
          download: [make_download_result(target)],
          run_no_wait: [make_task_run_result(target)],
          task_status: [make_task_status_result(target)]
        )

        results = transport.batch_task([target, target2], task, {})
        expect(results.length).to eq(2)

        ok_results = results.select(&:ok?)
        error_results = results.reject(&:ok?)
        expect(ok_results.length).to eq(1)
        expect(ok_results.first.target).to eq(target)
        expect(error_results.length).to eq(1)
        expect(error_results.first.target).to eq(target2)
        expect(error_results.first.error_hash['msg']).to match(/No agent information.*did not respond to discovery/)
      end

      it 'uses shell agent for all targets when task-agent is shell' do
        inventory.set_config(target, %w[choria task-agent], 'shell')
        inventory.set_config(target2, %w[choria task-agent], 'shell')
        stub_agents([target, target2], %w[rpcutil shell])

        allow(mock_rpc_client).to receive_messages(
          run: [make_shell_run_result(target), make_shell_run_result(target2)],
          start: [make_shell_start_result(target, handle: 'h1'), make_shell_start_result(target2, handle: 'h2')],
          list: [make_shell_list_result(target, 'h1'), make_shell_list_result(target2, 'h2')],
          statuses: [
            make_shell_statuses_result(target, 'h1', stdout: '{"result":"ok"}'),
            make_shell_statuses_result(target2, 'h2', stdout: '{"result":"ok"}')
          ]
        )

        expect(transport).to receive(:run_task_via_shell).and_call_original
        expect(transport).not_to receive(:run_task_via_bolt_tasks)

        events = []
        callback = proc { |event| events << event }
        results = transport.batch_task([target, target2], task, {}, {}, [], &callback)

        expect(results.length).to eq(2)
        results.each { |result| expect(result.value).to eq('result' => 'ok') }

        started_targets = events.select { |event| event[:type] == :node_start }.map { |event| event[:target] }
        finished_targets = events.select { |event| event[:type] == :node_result }.map { |event| event[:result].target }
        expect(started_targets).to contain_exactly(target, target2)
        expect(finished_targets).to contain_exactly(target, target2)
      end
    end
  end

  describe '#batch_task_with' do
    include_context 'choria multi-target'
    include_context 'choria task file stubs'

    it 'runs task with per-target arguments, batching discovery' do
      stub_agents([target, target2], %w[rpcutil bolt_tasks])

      # batch_task_with runs each target sequentially, so each call
      # returns the next target's result.
      allow(mock_rpc_client).to receive(:download)
        .and_return([make_download_result(target)], [make_download_result(target2)])
      allow(mock_rpc_client).to receive(:run_no_wait)
        .and_return([make_task_run_result(target)], [make_task_run_result(target2)])
      allow(mock_rpc_client).to receive(:task_status)
        .and_return([make_task_status_result(target)], [make_task_status_result(target2)])

      target_mapping = {
        target => { 'param' => 'value1' },
        target2 => { 'param' => 'value2' }
      }

      events = []
      callback = proc { |event| events << event }

      results = transport.batch_task_with([target, target2], task, target_mapping, {}, [], &callback)
      expect(results.length).to eq(2)
      results.each { |result| expect(result.value).to eq('result' => 'ok') }

      started_targets = events.select { |event| event[:type] == :node_start }.map { |event| event[:target] }
      finished_targets = events.select { |event| event[:type] == :node_result }.map { |event| event[:result].target }
      expect(started_targets).to contain_exactly(target, target2)
      expect(finished_targets).to contain_exactly(target, target2)
    end
  end
end
