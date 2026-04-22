# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'
require 'tempfile'

describe Bolt::Transport::Choria do
  include_context 'choria transport'

  describe '#configure_client' do
    it 'loads config on first call' do
      mc_config = MCollective::Config.instance
      expect(mc_config).to receive(:loadconfig).with(@choria_config_file.path).and_call_original
      transport.configure_client(target)
    end

    it 'only loads config once across multiple calls' do
      mc_config = MCollective::Config.instance
      expect(mc_config).to receive(:loadconfig).once.and_call_original

      transport.configure_client(target)
      transport.configure_client(target)
    end

    it 'uses an explicit config-file when provided and readable' do
      custom_config = write_choria_config(main_collective: 'custom')
      inventory.set_config(target, %w[choria config-file], custom_config.path)

      mc_config = MCollective::Config.instance
      expect(mc_config).to receive(:loadconfig).with(custom_config.path).and_call_original
      transport.configure_client(target)
    end

    it 'raises when an explicit config file is not readable' do
      inventory.set_config(target, %w[choria config-file], '/nonexistent/client.conf')
      allow(File).to receive(:readable?).with('/nonexistent/client.conf').and_return(false)

      expect { transport.configure_client(target) }.to raise_error(
        Bolt::Error, /Choria config file not found or not readable/
      )
    end

    it 'falls back to the next auto-detected config path when the first is not readable' do
      inventory.set_config(target, %w[choria config-file], nil)
      # Stub File.readable? at the I/O boundary to control which
      # auto-detected paths appear readable.
      auto_paths = MCollective::Util.config_paths_for_user
      allow(File).to receive(:readable?).and_call_original
      auto_paths.each { |path| allow(File).to receive(:readable?).with(path).and_return(false) }
      # Make the second path "readable" and point loadconfig at our temp file.
      second_path = auto_paths[1]
      allow(File).to receive(:readable?).with(second_path).and_return(true)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(second_path).and_return(true)
      allow(File).to receive(:readlines).and_call_original
      allow(File).to receive(:readlines).with(second_path).and_return(
        File.readlines(@choria_config_file.path)
      )

      mc_config = MCollective::Config.instance
      expect(mc_config).to receive(:loadconfig).with(second_path).and_call_original
      transport.configure_client(target)
    end

    it 'raises when no auto-detected config file is readable' do
      inventory.set_config(target, %w[choria config-file], nil)
      allow(File).to receive(:readable?).and_call_original
      MCollective::Util.config_paths_for_user.each do |path|
        allow(File).to receive(:readable?).with(path).and_return(false)
      end

      expect { transport.configure_client(target) }.to raise_error(
        Bolt::Error, /Could not find a readable Choria client config file/
      )
    end

    it 'applies NATS server overrides to pluginconf' do
      inventory.set_config(target, %w[choria nats-servers], %w[broker1:4222 broker2:4222])

      transport.configure_client(target)

      mc_config = MCollective::Config.instance
      expect(mc_config.pluginconf['choria.middleware_hosts']).to eq('broker1:4222,broker2:4222')
    end

    it 'applies TLS overrides to pluginconf' do
      ca = Tempfile.new('ca.pem')
      cert = Tempfile.new('cert.pem')
      key = Tempfile.new('key.pem')
      begin
        inventory.set_config(target, %w[choria ssl-ca], ca.path)
        inventory.set_config(target, %w[choria ssl-cert], cert.path)
        inventory.set_config(target, %w[choria ssl-key], key.path)

        transport.configure_client(target)

        mc_config = MCollective::Config.instance
        expect(mc_config.pluginconf['security.provider']).to eq('file')
        expect(mc_config.pluginconf['security.file.ca']).to eq(ca.path)
        expect(mc_config.pluginconf['security.file.certificate']).to eq(cert.path)
        expect(mc_config.pluginconf['security.file.key']).to eq(key.path)
      ensure
        [ca, cert, key].each(&:close!)
      end
    end

    it 'raises when SSL file is not readable' do
      inventory.set_config(target, %w[choria ssl-ca], '/nonexistent/ca.pem')
      inventory.set_config(target, %w[choria ssl-cert], '/nonexistent/cert.pem')
      inventory.set_config(target, %w[choria ssl-key], '/nonexistent/key.pem')
      expect { transport.configure_client(target) }.to raise_error(
        Bolt::Error, /ssl-ca.*not readable/
      )
    end

    it 'remembers loadconfig failure and re-raises on subsequent calls' do
      mc_config = MCollective::Config.instance
      allow(mc_config).to receive(:loadconfig).and_raise(RuntimeError, 'NATS connection refused')

      expect { transport.configure_client(target) }.to raise_error(
        Bolt::Error, /Choria client configuration failed.*NATS connection refused/
      )

      # Second call should re-raise the same error without calling loadconfig again
      expect(mc_config).not_to receive(:loadconfig)
      expect { transport.configure_client(target) }.to raise_error(
        Bolt::Error, /Choria client configuration failed.*NATS connection refused/
      )
    end
  end

  describe '#create_rpc_client' do
    it 'discovers with all target identities' do
      transport.configure_client(target)
      expect(mock_rpc_client).to receive(:discover).with(nodes: %w[node1.example.com node2.example.com])
      transport.create_rpc_client('rpcutil', [target, target2], 10)
    end

    it 'uses choria host config as identity when set' do
      inventory.set_config(target, %w[choria host], 'node1.fqdn.example.com')
      expect(mock_rpc_client).to receive(:discover).with(nodes: ['node1.fqdn.example.com'])
      transport.create_rpc_client('shell', [target], 60)
    end

    it 'disables progress output' do
      expect(mock_rpc_client).to receive(:progress=).with(false)
      transport.create_rpc_client('shell', [target], 60)
    end

    it 'sets collective from the first target' do
      transport.configure_client(target)
      inventory.set_config(target, %w[choria collective], 'production')
      expect(MCollective::RPC::Client).to receive(:new) do |_agent, opts|
        expect(opts[:options][:collective]).to eq('production')
        mock_rpc_client
      end
      transport.create_rpc_client('rpcutil', [target, target2], 10)
    end

    it 'leaves collective as nil when not configured (falls back to main_collective)' do
      expect(MCollective::RPC::Client).to receive(:new) do |_agent, opts|
        expect(opts[:options][:collective]).to be_nil
        mock_rpc_client
      end
      transport.create_rpc_client('shell', [target], 60)
    end

    it 'passes nats-connection-timeout to RPC client options' do
      transport.configure_client(target)
      inventory.set_config(target, %w[choria nats-connection-timeout], 45)

      expect(MCollective::RPC::Client).to receive(:new) do |_agent, opts|
        expect(opts[:options][:connection_timeout]).to eq(45)
        mock_rpc_client
      end

      transport.create_rpc_client('shell', [target], 10)
    end

    it 'passes rpc-timeout as the RPC call timeout' do
      transport.configure_client(target)
      inventory.set_config(target, %w[choria rpc-timeout], 120)

      allow(mock_rpc_client).to receive(:ping).and_return([make_rpc_result(sender: target)])

      expect(MCollective::RPC::Client).to receive(:new) do |_agent, opts|
        expect(opts[:options][:timeout]).to eq(120)
        mock_rpc_client
      end

      transport.rpc_request('rpcutil', [target], 'test') { |client| client.ping }
    end

    describe 'default_collective' do
      it 'uses default_collective when target has no explicit collective' do
        production_config = write_choria_config(main_collective: 'production')
        inventory.set_config(target, %w[choria config-file], production_config.path)

        transport.configure_client(target)

        expect(MCollective::RPC::Client).to receive(:new) do |_agent, opts|
          expect(opts[:options][:collective]).to eq('production')
          mock_rpc_client
        end
        transport.create_rpc_client('rpcutil', [target], 10)
      end
    end
  end

  describe '#rpc_request' do
    before(:each) do
      transport.configure_client(target)
    end

    it 'routes statuscode 0 to :responded' do
      result = make_rpc_result(sender: target, statuscode: 0, data: { value: 'ok' })
      allow(mock_rpc_client).to receive(:ping).and_return([result])

      response = transport.rpc_request('rpcutil', [target], 'test') { |client| client.ping }
      expect(response[:responded]).to have_key(target)
      expect(response[:responded][target]).to eq(value: 'ok')
      expect(response[:errors]).to be_empty
      expect(response[:rpc_failed]).to be false
      expect(response[:rpc_statuscodes][target]).to eq(0)
    end

    it 'routes statuscode 1 to :responded and preserves data' do
      result = make_rpc_result(
        sender: target, statuscode: 1,
        statusmsg: 'Task failed with exit code 1',
        data: { exitcode: 1, stdout: '{"_error":{"msg":"failed"}}' }
      )
      allow(mock_rpc_client).to receive(:ping).and_return([result])

      response = transport.rpc_request('rpcutil', [target], 'test') { |client| client.ping }
      expect(response[:responded]).to have_key(target)
      expect(response[:responded][target][:exitcode]).to eq(1)
      expect(response[:errors]).to be_empty
      expect(response[:rpc_statuscodes][target]).to eq(1)
    end

    it 'routes statuscode 2+ to :errors' do
      result = make_rpc_result(sender: target, statuscode: 3, statusmsg: 'Missing data')
      allow(mock_rpc_client).to receive(:ping).and_return([result])

      response = transport.rpc_request('rpcutil', [target], 'test') { |client| client.ping }
      expect(response[:responded]).to be_empty
      expect(response[:errors]).to have_key(target)
      expect(response[:errors][target][:error]).to match(/Missing data.*code 3/)
      expect(response[:rpc_statuscodes][target]).to eq(3)
    end

    it 'reports no-response targets as errors' do
      allow(mock_rpc_client).to receive(:ping).and_return([])

      response = transport.rpc_request('rpcutil', [target], 'test') { |client| client.ping }
      expect(response[:responded]).to be_empty
      expect(response[:errors]).to have_key(target)
      expect(response[:errors][target][:error]).to match(/No response/)
    end

    it 'returns rpc_failed: true when the RPC call raises a StandardError' do
      allow(mock_rpc_client).to receive(:ping).and_raise(StandardError, 'NATS timeout')

      response = transport.rpc_request('rpcutil', [target], 'test') { |client| client.ping }
      expect(response[:rpc_failed]).to be true
      expect(response[:responded]).to be_empty
      expect(response[:errors]).to have_key(target)
      expect(response[:errors][target][:error]).to match(/NATS timeout/)
    end

    it 're-raises Bolt::Error instead of returning rpc_failed' do
      allow(mock_rpc_client).to receive(:ping).and_raise(
        Bolt::Error.new('Config problem', 'bolt/choria-config-failed')
      )

      expect {
        transport.rpc_request('rpcutil', [target], 'test') { |client| client.ping }
      }.to raise_error(Bolt::Error, 'Config problem')
    end

    it 'handles mixed statuscodes across targets' do
      ok_result = make_rpc_result(sender: target, statuscode: 0, data: { value: 'ok' })
      err_result = make_rpc_result(sender: target2, statuscode: 4, statusmsg: 'Authorization denied')
      allow(mock_rpc_client).to receive(:ping).and_return([ok_result, err_result])

      response = transport.rpc_request('rpcutil', [target, target2], 'test') { |client| client.ping }
      expect(response[:responded]).to have_key(target)
      expect(response[:errors]).to have_key(target2)
      expect(response[:rpc_statuscodes][target]).to eq(0)
      expect(response[:rpc_statuscodes][target2]).to eq(4)
    end
  end

  describe '#index_results_by_sender' do
    it 'indexes results by sender for expected targets' do
      results = [
        { sender: 'node1.example.com', data: { exitcode: 0, stdout: 'ok1' } },
        { sender: 'node2.example.com', data: { exitcode: 0, stdout: 'ok2' } }
      ]

      indexed = transport.index_results_by_sender(results, [target, target2], 'test')

      expect(indexed.keys).to contain_exactly('node1.example.com', 'node2.example.com')
      expect(indexed['node1.example.com'][:data][:stdout]).to eq('ok1')
      expect(indexed['node2.example.com'][:data][:stdout]).to eq('ok2')
    end

    it 'discards responses from unexpected senders' do
      results = [
        { sender: 'node1.example.com', data: { exitcode: 0 } },
        { sender: 'evil.example.com', data: { exitcode: 0 } }
      ]

      indexed = transport.index_results_by_sender(results, [target, target2], 'test')

      expect(indexed.keys).to contain_exactly('node1.example.com')
      expect(indexed).not_to have_key('evil.example.com')
    end

    it 'discards responses with nil sender' do
      results = [
        { sender: 'node1.example.com', data: { exitcode: 0 } },
        { sender: nil, data: { exitcode: 0 } }
      ]

      indexed = transport.index_results_by_sender(results, [target, target2], 'test')

      expect(indexed.keys).to contain_exactly('node1.example.com')
    end

    it 'keeps first response and ignores duplicate with same data' do
      results = [
        { sender: 'node1.example.com', data: { exitcode: 0 } },
        { sender: 'node1.example.com', data: { exitcode: 0 } }
      ]

      indexed = transport.index_results_by_sender(results, [target], 'test')

      expect(indexed.size).to eq(1)
      expect(indexed['node1.example.com'][:data][:exitcode]).to eq(0)
    end

    it 'keeps first response and ignores duplicate with different data' do
      results = [
        { sender: 'node1.example.com', data: { exitcode: 0 } },
        { sender: 'node1.example.com', data: { exitcode: 1, stderr: 'dup' } }
      ]

      indexed = transport.index_results_by_sender(results, [target], 'test')

      expect(indexed.size).to eq(1)
      expect(indexed['node1.example.com'][:data][:exitcode]).to eq(0)
    end

    it 'returns empty hash for empty results' do
      indexed = transport.index_results_by_sender([], [target], 'test')

      expect(indexed).to be_empty
    end

    it 'returns empty hash when no results match expected targets' do
      results = [
        { sender: 'rogue1.example.com', data: { exitcode: 0 } },
        { sender: 'rogue2.example.com', data: { exitcode: 0 } }
      ]

      indexed = transport.index_results_by_sender(results, [target], 'test')

      expect(indexed).to be_empty
    end

    it 'logs warnings for unexpected and nil senders' do
      logger = transport.logger
      expect(logger).to receive(:warn).twice

      results = [
        { sender: nil, data: { exitcode: 0 } },
        { sender: 'evil.example.com', data: { exitcode: 0 } }
      ]

      transport.index_results_by_sender(results, [target], 'test')
    end

    it 'logs debug for identical duplicate and warn for different-data duplicate' do
      logger = transport.logger
      expect(logger).to receive(:debug)
      expect(logger).to receive(:warn)

      results = [
        { sender: 'node1.example.com', data: { exitcode: 0 } },
        { sender: 'node1.example.com', data: { exitcode: 0 } },
        { sender: 'node1.example.com', data: { exitcode: 1 } }
      ]

      transport.index_results_by_sender(results, [target], 'test')
    end
  end
end
