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

    it 'treats target as unreachable when agents is a string instead of Array' do
      result = make_rpc_result(sender: target, data: { agents: 'corrupted' })
      allow(mock_rpc_client).to receive(:agent_inventory).and_return([result])

      transport.discover_agents([target])
      expect(transport.has_agent?(target, 'rpcutil')).to be false
    end

    describe 'error handling' do
      it 'returns nil for all targets when agent_inventory raises' do
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
