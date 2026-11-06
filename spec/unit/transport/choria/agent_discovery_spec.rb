# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'

describe Bolt::Transport::Choria do
  include_context 'choria transport'

  describe '#discover_agents' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'discovers agents on multiple targets in one RPC call' do
      r1 = make_rpc_result(sender: target, data: {
                             agents: [{ 'agent' => 'rpcutil' }, { 'agent' => 'bolt_tasks' }]
                           })
      r2 = make_rpc_result(sender: target2, data: {
                             agents: [{ 'agent' => 'rpcutil' }, { 'agent' => 'shell', 'version' => '1.2.1' }]
                           })

      f1 = make_rpc_result(sender: target, data: { value: 'RedHat' })
      f2 = make_rpc_result(sender: target2, data: { value: 'RedHat' })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [r1, r2], get_fact: [f1, f2])

      transport.discover_agents([target, target2])
      expect(transport.has_agent?(target, 'bolt_tasks')).to be true
      expect(transport.has_agent?(target2, 'shell')).to be true
    end

    it 'excludes agents below the required minimum version' do
      result = make_rpc_result(sender: target, data: {
                                 agents: [{ 'agent' => 'rpcutil' },
                                          { 'agent' => 'shell', 'version' => '1.1.0' }]
                               })

      fact_result = make_rpc_result(sender: target, data: { value: 'RedHat' })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [result], get_fact: [fact_result])

      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'rpcutil')).to be true
      expect(transport.has_agent?(target, 'shell')).to be false
    end

    it 'excludes a file_transfer agent below 1.0.0 and keeps one at it' do
      result = make_rpc_result(sender: target, data: {
                                 agents: [{ 'agent' => 'file_transfer', 'version' => '0.9.0' }]
                               })
      result2 = make_rpc_result(sender: target2, data: {
                                  agents: [{ 'agent' => 'file_transfer', 'version' => '1.0.0' }]
                                })

      fact_results = [make_rpc_result(sender: target, data: { value: 'RedHat' }),
                      make_rpc_result(sender: target2, data: { value: 'RedHat' })]
      allow(mock_rpc_client).to receive_messages(agent_inventory: [result, result2], get_fact: fact_results)

      transport.discover_agents([target, target2])
      expect(transport.has_agent?(target, 'file_transfer')).to be false
      expect(transport.has_agent?(target2, 'file_transfer')).to be true
    end

    it 'excludes a file_transfer agent that reports no version' do
      result = make_rpc_result(sender: target, data: { agents: [{ 'agent' => 'file_transfer' }] })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [result],
                                                 get_fact: [make_rpc_result(sender: target, data: { value: 'RedHat' })])

      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'file_transfer')).to be false
    end

    it 'treats agents with unparseable version strings as unavailable' do
      result = make_rpc_result(sender: target, data: {
                                 agents: [{ 'agent' => 'rpcutil' },
                                          { 'agent' => 'shell', 'version' => 'not-a-version' }]
                               })

      fact_result = make_rpc_result(sender: target, data: { value: 'RedHat' })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [result], get_fact: [fact_result])

      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'shell')).to be false
    end

    it 'does not cache non-responding targets' do
      r1 = make_rpc_result(sender: target, data: {
                             agents: [{ 'agent' => 'rpcutil' }]
                           })

      fact_result = make_rpc_result(sender: target, data: { value: 'RedHat' })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [r1], get_fact: [fact_result])

      transport.discover_agents([target, target2])
      expect(transport.has_agent?(target, 'rpcutil')).to be true
      expect(transport.has_agent?(target2, 'rpcutil')).to be false
    end

    it 'uses cache for already-discovered targets' do
      stub_agents([target, target2], %w[rpcutil])

      transport.discover_agents([target, target2])

      expect(mock_rpc_client).not_to receive(:agent_inventory)
      transport.discover_agents([target, target2])
    end

    it 'discards responses from unexpected senders' do
      legit = make_rpc_result(sender: target, data: {
                                agents: [{ 'agent' => 'rpcutil', 'version' => '1.0.0' },
                                         { 'agent' => 'shell', 'version' => '1.2.1' }]
                              })
      rogue = make_rpc_result(sender: 'evil.example.com', data: {
                                agents: [{ 'agent' => 'rpcutil' }, { 'agent' => 'bolt_tasks' }]
                              })

      fact_result = make_rpc_result(sender: target, data: { value: 'RedHat' })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [legit, rogue], get_fact: [fact_result])

      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'shell')).to be true
    end

    it 'treats target as unreachable when agent_inventory returns non-Array agents' do
      result = make_rpc_result(sender: target, data: { agents: nil })
      allow(mock_rpc_client).to receive(:agent_inventory).and_return([result])

      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'rpcutil')).to be false
      expect(transport.has_agent?(target, 'shell')).to be false
    end

    it 'reports only that target when its agent_inventory data is not a hash' do
      malformed = make_rpc_result(sender: target, data: [])
      answered = make_rpc_result(sender: target2, data: { agents: [{ 'agent' => 'rpcutil' }] })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [malformed, answered],
                                                 get_fact: [make_rpc_result(sender: target2, data: { value: 'RedHat' })])

      failures = transport.discover_agents([target, target2])

      expect(failures.keys).to eq([target])
      expect(failures[target]).to include(
        error: 'rpcutil.agent_inventory on choria://node1.example.com returned no agent list',
        error_kind: 'bolt/choria-missing-data'
      )
      expect(transport.discovered?(target)).to be false
      expect(transport.has_agent?(target2, 'rpcutil')).to be true
    end

    it 'skips agent_inventory entries that are not hashes and keeps discovering the other targets' do
      odd = make_rpc_result(sender: target, data: { agents: [5, nil, 'shell_agent', { 'agent' => 'rpcutil' }] })
      answered = make_rpc_result(sender: target2, data: { agents: [{ 'agent' => 'rpcutil' }] })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [odd, answered],
                                                 get_fact: [make_rpc_result(sender: target, data: { value: 'RedHat' }),
                                                            make_rpc_result(sender: target2, data: { value: 'RedHat' })])

      transport.discover_agents([target, target2])

      expect(transport.has_agent?(target, 'rpcutil')).to be true
      expect(transport.has_agent?(target, 'agent')).to be false
      expect(transport.has_agent?(target2, 'rpcutil')).to be true
    end

    it 'treats target as unreachable when agents is a string instead of Array' do
      result = make_rpc_result(sender: target, data: { agents: 'corrupted' })
      allow(mock_rpc_client).to receive(:agent_inventory).and_return([result])

      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'rpcutil')).to be false
    end

    describe 'error handling' do
      it 'warns with the status message and leaves the target undiscovered when agent_inventory answers statuscode 1' do
        refused = make_rpc_result(sender: target, statuscode: 1,
                                  statusmsg: 'You are not authorized to call this agent or action', data: {})
        allow(mock_rpc_client).to receive(:agent_inventory).and_return([refused])
        warnings = []
        allow(transport.logger).to receive(:warn) { |*args, &block| warnings << (block ? block.call : args.first) }

        transport.discover_agents([target])

        expect(transport.discovered?(target)).to be false
        expect(warnings).to include(
          'agent_inventory failed for choria://node1.example.com: rpcutil.agent_inventory on ' \
          'choria://node1.example.com returned RPC error: You are not authorized to call this agent or action (code 1)'
        )
      end

      it 'leaves every target undiscovered when agent_inventory raises' do
        allow(mock_rpc_client).to receive(:agent_inventory).and_raise(StandardError, 'NATS timeout')

        transport.discover_agents([target, target2])
        expect(transport.has_agent?(target, 'rpcutil')).to be false
        expect(transport.has_agent?(target2, 'rpcutil')).to be false
      end

      it 're-raises Bolt::Error instead of swallowing it' do
        allow(mock_rpc_client).to receive(:agent_inventory).and_raise(
          Bolt::Error.new('Config problem', 'bolt/choria-config-failed')
        )
        expect { transport.discover_agents([target, target2]) }.to raise_error(
          Bolt::Error, /Config problem/
        )
      end

      it 'returns the reason for every target when the agent_inventory call fails as a whole' do
        allow(MCollective::RPC::Client).to receive(:new).and_raise(StandardError, 'The Choria client cannot be run as root')

        failures = transport.discover_agents([target, target2])

        expect(failures.keys).to contain_exactly(target, target2)
        expect(failures[target]).to include(
          error: 'rpcutil.agent_inventory failed on choria://node1.example.com: The Choria client cannot be run as root',
          error_kind: 'bolt/choria-rpc-failed'
        )
        expect(failures[target2]).to include(
          error: 'rpcutil.agent_inventory failed on choria://node2.example.com: The Choria client cannot be run as root',
          error_kind: 'bolt/choria-rpc-failed'
        )
      end

      it 'returns the RPC error of a target that answered agent_inventory with one' do
        refused = make_rpc_result(sender: target, statuscode: 1,
                                  statusmsg: 'You are not authorized to call this agent or action', data: {})
        answered = make_rpc_result(sender: target2, data: { agents: [{ 'agent' => 'rpcutil' }] })
        allow(mock_rpc_client).to receive_messages(agent_inventory: [refused, answered],
                                                   get_fact: [make_rpc_result(sender: target2, data: { value: 'RedHat' })])

        failures = transport.discover_agents([target, target2])

        expect(failures.keys).to eq([target])
        expect(failures[target]).to include(
          error: 'rpcutil.agent_inventory on choria://node1.example.com returned RPC error: ' \
                 'You are not authorized to call this agent or action (code 1)',
          error_kind: 'bolt/choria-rpc-error'
        )
      end

      it 'returns a no-response error for a target that does not answer' do
        stub_agents(target, %w[rpcutil])

        failures = transport.discover_agents([target, target2])

        expect(failures.keys).to eq([target2])
        expect(failures[target2]).to include(
          error: 'No response from choria://node2.example.com for rpcutil.agent_inventory',
          error_kind: 'bolt/choria-no-response'
        )
      end
    end
  end

  describe '#has_agent?' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'returns true when the agent is in the cache' do
      stub_agents(target, ['shell'])
      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'shell')).to be true
    end

    it 'returns false when the agent is not in the cache' do
      stub_agents(target, ['rpcutil'])
      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'shell')).to be false
    end

    it 'returns false when the target was not discovered' do
      expect(transport.has_agent?(target, 'shell')).to be false
    end
  end

  describe '#windows_target?' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'returns true when os.family is windows' do
      stub_agents(target, %w[rpcutil shell], os_family: 'windows')
      transport.discover_agents([target])
      expect(transport.windows_target?(target)).to be true
    end

    it 'returns false when os.family is RedHat' do
      stub_agents(target, %w[rpcutil shell], os_family: 'RedHat')
      transport.discover_agents([target])
      expect(transport.windows_target?(target)).to be false
    end

    it 'returns false when os.family is nil' do
      stub_agents(target, %w[rpcutil shell], os_family: nil)
      transport.discover_agents([target])
      expect(transport.windows_target?(target)).to be false
    end
  end

  describe '#discover_os_family' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'detects non-Windows OS family' do
      stub_agents(target, %w[rpcutil shell], os_family: 'RedHat')
      transport.discover_agents([target])

      expect(transport.windows_target?(target)).to be false
    end

    it 'detects Windows OS family' do
      stub_agents(target, %w[rpcutil shell], os_family: 'windows')
      transport.discover_agents([target])

      expect(transport.windows_target?(target)).to be true
    end

    it 'detects the OS family of the other targets when one get_fact reply has data that is not a hash' do
      inventory = [make_rpc_result(sender: target, data: { agents: [{ 'agent' => 'rpcutil' }] }),
                   make_rpc_result(sender: target2, data: { agents: [{ 'agent' => 'rpcutil' }] })]
      facts = [make_rpc_result(sender: target, data: []), make_rpc_result(sender: target2, data: { value: 'windows' })]
      allow(mock_rpc_client).to receive_messages(agent_inventory: inventory, get_fact: facts)

      transport.discover_agents([target, target2])

      expect(transport.windows_target?(target)).to be false
      expect(transport.windows_target?(target2)).to be true
    end

    it 'defaults to POSIX when OS detection fails' do
      result = make_rpc_result(sender: target, data: {
                                 agents: [{ 'agent' => 'rpcutil', 'version' => '1.0.0' },
                                          { 'agent' => 'shell', 'version' => '1.2.1' }]
                               })
      allow(mock_rpc_client).to receive(:agent_inventory).and_return([result])

      allow(mock_rpc_client).to receive(:get_fact).and_raise(StandardError, 'NATS timeout')

      transport.discover_agents([target])

      expect(transport.windows_target?(target)).to be false
    end

    it 'defaults to POSIX when os.family fact is an empty string' do
      result = make_rpc_result(sender: target, data: {
                                 agents: [{ 'agent' => 'rpcutil', 'version' => '1.0.0' },
                                          { 'agent' => 'shell', 'version' => '1.2.1' }]
                               })

      fact_result = make_rpc_result(sender: target, data: { value: '' })
      allow(mock_rpc_client).to receive_messages(agent_inventory: [result], get_fact: [fact_result])

      transport.discover_agents([target])

      expect(transport.windows_target?(target)).to be false
    end

    it 're-raises Bolt::Error from OS detection instead of swallowing it' do
      result = make_rpc_result(sender: target, data: {
                                 agents: [{ 'agent' => 'rpcutil', 'version' => '1.0.0' },
                                          { 'agent' => 'shell', 'version' => '1.2.1' }]
                               })
      allow(mock_rpc_client).to receive(:agent_inventory).and_return([result])

      allow(mock_rpc_client).to receive(:get_fact).and_raise(
        Bolt::Error.new('Config problem', 'bolt/choria-config-failed')
      )

      expect { transport.discover_agents([target]) }.to raise_error(
        Bolt::Error, /Config problem/
      )
    end
  end
end
