# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/choria'
require 'bolt_spec/choria_file_transfer'
require 'tmpdir'

describe Bolt::Transport::Choria do
  include_context 'choria transport'
  include_context 'choria multi-target'
  include_context 'choria file transfer library'

  let(:library) { BoltSpec::FakeFileTransfer }
  let(:source) { '/srv/app.tar' }
  let(:destination) { '/opt/app/app.tar' }
  let(:identities) { %w[node1.example.com node2.example.com] }

  before { stub_agents([target, target2], %w[rpcutil file_transfer]) }

  describe '#batch_upload' do
    it 'uploads through the library to the identities of the targets and answers a result per target' do
      results = transport.batch_upload([target, target2], source, destination)

      expect(library.clients.length).to eq(1)
      expect(library.clients.last.uploads).to eq([[source, destination, identities]])
      expect(results.map(&:target)).to eq([target, target2])
      expect(results.map(&:ok?)).to eq([true, true])
      expect(results.map(&:action).uniq).to eq(['upload'])
      expect(results.first.message).to include(destination)
    end

    it 'reports the path the library says the file landed at, not the destination it was given' do
      library.on_upload { |_source, _destination, names| names.to_h { |name| [name, library::Outcome.success(name, '/opt/app/app.tar')] } }

      results = transport.batch_upload([target], source, '/opt/app')

      expect(results.first.message).to include('/opt/app/app.tar')
    end

    it 'answers agent-not-available for every target and builds no client when none has the agent' do
      stub_agents([target, target2], %w[rpcutil shell])

      results = transport.batch_upload([target, target2], source, destination)

      expect(results.map { |result| result.error_hash['kind'] }).to eq(%w[bolt/choria-agent-not-available bolt/choria-agent-not-available])
      expect(library.clients).to be_empty
    end

    it 'builds the client with the batch options' do
      inventory.set_config(target, %w[choria message-data-size], 65_536)
      inventory.set_config(target, %w[choria upload-batch-size], 100)
      inventory.set_config(target, %w[choria file-transfer-timeout], 45)

      transport.batch_upload([target, target2], source, destination)

      arguments = library.clients.last.arguments
      expect(arguments).to include(rpc_timeout: 45, message_data_size: 65_536, upload_batch_size: 100)
      expect(arguments[:mutex]).to be_a(Mutex)
      expect(arguments[:logger]).to be_a(Bolt::Transport::Choria::FileTransferLogger)
    end

    it 'passes no sizes and no timeout without the options, so the library\'s own defaults apply' do
      inventory.set_config(target, %w[choria rpc-timeout], 45)

      transport.batch_upload([target], source, destination)

      expect(library.clients.last.arguments).to include(rpc_timeout: nil, message_data_size: nil, upload_batch_size: nil)
    end

    it 'fires node_start and node_result for every target' do
      events = []

      transport.batch_upload([target, target2], source, destination) { |event| events << event }

      expect(events.map { |event| event[:type] }).to eq(%i[node_start node_start node_result node_result])
      expect(events.last(2).map { |event| event[:result].target }).to eq([target, target2])
    end

    it 'reports a failed outcome with the library message under the transport error kind and keeps the rest' do
      library.on_upload do |_source, _destination, names|
        names.to_h do |name|
          outcome = if name == 'node2.example.com'
                      library::Outcome.failure(name, :checksum_mismatch, 'expected abc, got def')
                    else
                      library::Outcome.success(name, destination)
                    end
          [name, outcome]
        end
      end

      results = transport.batch_upload([target, target2], source, destination)

      failed = results.find { |result| result.target == target2 }
      expect(failed.ok?).to be(false)
      expect(failed.error_hash['kind']).to eq('bolt/choria-checksum-mismatch')
      expect(failed.error_hash['msg']).to eq('expected abc, got def')
      expect(results.find { |result| result.target == target }.ok?).to be(true)
    end

    # The error kind a user sees for each failure kind the library answers
    # at version 1.0.0.
    {
      no_response: 'bolt/choria-no-response',
      rpc_error: 'bolt/choria-rpc-error',
      rpc_failed: 'bolt/choria-rpc-failed',
      transfer_failed: 'bolt/choria-file-transfer-failed',
      payload_too_large: 'bolt/choria-payload-too-large',
      checksum_mismatch: 'bolt/choria-checksum-mismatch'
    }.each do |outcome_kind, error_kind|
      it "reports a #{outcome_kind} outcome as #{error_kind}" do
        library.on_upload do |_source, _destination, names|
          names.to_h { |name| [name, library::Outcome.failure(name, outcome_kind, 'not delivered')] }
        end

        results = transport.batch_upload([target], source, destination)

        expect(results.first.error_hash['kind']).to eq(error_kind)
      end
    end

    it 'reports an outcome kind a later library adds as a transfer failure' do
      library.on_upload { |_source, _destination, names| names.to_h { |name| [name, library::Outcome.failure(name, :quota_exceeded, 'over quota')] } }

      results = transport.batch_upload([target], source, destination)

      expect(results.first.error_hash['kind']).to eq('bolt/choria-file-transfer-failed')
      expect(results.first.error_hash['msg']).to eq('over quota')
    end

    it 'reports every target with the library message when it refuses the source before any call, after node_start' do
      library.on_upload { |_source, _destination, _names| raise ArgumentError, 'The source name "caf\xE9.bin" is not valid UTF-8' }
      events = []

      results = transport.batch_upload([target, target2], source, destination) { |event| events << event }

      expect(results.map { |result| result.error_hash['kind'] }.uniq).to eq(['bolt/choria-file-transfer-failed'])
      expect(results.map { |result| result.error_hash['msg'] }.uniq)
        .to eq(['The source name "caf\xE9.bin" is not valid UTF-8 (ArgumentError on the controller)'])
      expect(results.map(&:action).uniq).to eq(['upload'])
      expect(events.map { |event| event[:type] }).to eq(%i[node_start node_start node_result node_result])
    end

    it 'keeps the result of a target without the agent when the library raises for the rest' do
      stub_agents(target2, %w[rpcutil shell])
      library.on_upload { |source, _destination, _names| raise Errno::ENOENT, source }

      results = transport.batch_upload([target, target2], source, destination)

      expect(results.map { |result| [result.target, result.error_hash['kind']] })
        .to contain_exactly([target2, 'bolt/choria-agent-not-available'], [target, 'bolt/choria-file-transfer-failed'])
    end

    it 'fails fast for a target without the agent and sends the library only the rest' do
      stub_agents(target2, %w[rpcutil shell])

      results = transport.batch_upload([target, target2], source, destination)

      expect(results.find { |result| result.target == target2 }.error_hash['kind']).to eq('bolt/choria-agent-not-available')
      expect(library.clients.last.uploads).to eq([[source, destination, ['node1.example.com']]])
    end

    it 'gives two targets behind one identity that identity once and the same outcome' do
      twin = inventory.get_target('twin')
      inventory.set_config(twin, 'transport', 'choria')
      inventory.set_config(twin, %w[choria host], 'node1.example.com')
      library.on_upload { |_source, _destination, names| names.to_h { |name| [name, library::Outcome.failure(name, :no_response, 'silent')] } }

      results = transport.batch_upload([target, twin], source, destination)

      expect(library.clients.last.uploads).to eq([[source, destination, ['node1.example.com']]])
      expect(results.map(&:target)).to eq([target, twin])
      expect(results.map { |result| result.error_hash['kind'] }.uniq).to eq(['bolt/choria-no-response'])
    end

    context 'when the library is not installed on this host' do
      before do
        allow(transport).to receive(:require).with(Bolt::Transport::Choria::FILE_TRANSFER_LIBRARY).and_raise(LoadError, 'cannot load such file')
      end

      it 'reports every capable target with the module to install and creates no client' do
        events = []

        results = transport.batch_upload([target, target2], source, destination) { |event| events << event }

        expect(results.map { |result| result.error_hash['kind'] }.uniq).to eq(['bolt/choria-file-transfer-library'])
        expect(results.first.error_hash['msg']).to include('not installed', 'mcollective_agent_file_transfer', 'client => true')
        expect(library.clients).to be_empty
        expect(events.map { |event| event[:type] }).to eq(%i[node_start node_start node_result node_result])
      end
    end

    context 'when the library on this host is too old' do
      before { stub_const('BoltSpec::FakeFileTransfer::VERSION', '0.9.0') }

      it 'reports every capable target with both versions' do
        results = transport.batch_upload([target], source, destination)

        expect(results.first.error_hash['kind']).to eq('bolt/choria-file-transfer-library')
        expect(results.first.error_hash['msg']).to include('0.9.0', '~> 1.0')
        expect(library.clients).to be_empty
      end
    end

    context 'when the library on this host is a later minor version' do
      before { stub_const('BoltSpec::FakeFileTransfer::VERSION', '1.1.0') }

      it 'builds a client and uploads as usual' do
        results = transport.batch_upload([target], source, destination)

        expect(results.first).to be_ok
        expect(library.clients.length).to eq(1)
      end
    end

    context 'when the library on this host is a later major version' do
      before { stub_const('BoltSpec::FakeFileTransfer::VERSION', '2.0.0') }

      it 'reports every capable target and builds no client' do
        results = transport.batch_upload([target], source, destination)

        expect(results.first.error_hash['kind']).to eq('bolt/choria-file-transfer-library')
        expect(results.first.error_hash['msg']).to include('2.0.0')
        expect(library.clients).to be_empty
      end
    end
  end

  describe '#batch_download' do
    let(:workdir) { Dir.mktmpdir('bolt-choria-download') }

    after { FileUtils.remove_entry_secure(workdir) }

    # The per-target directory is the url-encoded safe name under the
    # destination, as Transport::Base names it for every transport.
    def directory_for(target)
      File.join(workdir, ERB::Util.url_encode(target.safe_name))
    end

    it 'downloads through the library into a directory per target under the destination' do
      results = transport.batch_download([target, target2], '/var/log/app.log', workdir)

      destination_dirs = { 'node1.example.com' => directory_for(target), 'node2.example.com' => directory_for(target2) }
      expect(library.clients.last.downloads).to eq([['/var/log/app.log', destination_dirs]])
      expect(directory_for(target)).to end_with('choria%3A%2F%2Fnode1.example.com')
      expect(results.map(&:ok?)).to eq([true, true])
      expect(results.map(&:action).uniq).to eq(['download'])
      expect(results.first.value['path']).to eq(File.join(directory_for(target), 'app.log'))
    end

    it 'reports a failed outcome under the transport error kind' do
      library.on_download do |_source, destination_dirs|
        destination_dirs.keys.to_h { |name| [name, library::Outcome.failure(name, :transfer_failed, "/var/log/app.log does not exist on #{name}")] }
      end

      results = transport.batch_download([target], '/var/log/app.log', workdir)

      expect(results.first.error_hash['kind']).to eq('bolt/choria-file-transfer-failed')
      expect(results.first.error_hash['msg']).to include('does not exist')
    end

    it 'fires node_start and node_result for every target' do
      events = []

      transport.batch_download([target, target2], '/var/log/app.log', workdir) { |event| events << event }

      expect(events.map { |event| event[:type] }).to eq(%i[node_start node_start node_result node_result])
    end

    it 'lets an error that is not about what the controller holds propagate instead of reporting it as a transfer failure' do
      library.on_download { |_source, _destination_dirs| raise 'the library hit a bug' }

      expect { transport.batch_download([target, target2], '/var/log/app.log', workdir) }.to raise_error(RuntimeError, 'the library hit a bug')
    end
  end

  describe 'the options and the mutex the library gets' do
    it 'are the options the transport gives its own clients and the RPC mutex every call takes' do
      inventory.set_config(target, %w[choria broker-timeout], 45)
      inventory.set_config(target, %w[choria collective], 'production')
      transport.batch_upload([target, target2], source, destination)
      arguments = library.clients.last.arguments

      expect(arguments[:options]).to include(verbose: false, connection_timeout: 45, collective: 'production')
      held = nil
      transport.rpc_request('rpcutil', [target], 'lock check') do |_client|
        held = arguments[:mutex].owned?
        []
      end
      expect(held).to be(true)
    end
  end

  describe Bolt::Transport::Choria::FileTransferLogger do
    let(:adapter) { described_class.new(transport.logger) }

    it 'passes debug and warn lines to the transport logger' do
      lines = []
      allow(transport.logger).to receive(:debug) { |&block| lines << [:debug, block.call] }
      allow(transport.logger).to receive(:warn) { |&block| lines << [:warn, block.call] }

      adapter.debug('Upload of /srv/app.tar to /opt/app on 2 nodes')
      adapter.warn('The temporary file .file_transfer-3f2a beside /opt/app/app.tar stays on node1: No response')

      expect(lines).to eq([[:debug, 'Upload of /srv/app.tar to /opt/app on 2 nodes'],
                           [:warn, 'The temporary file .file_transfer-3f2a beside /opt/app/app.tar stays on node1: No response']])
    end

    it 'passes warn_once to Bolt::Logger with the id' do
      message = "The file transfer client could not read the broker's message size limit and assumes 1048576 bytes"
      expect(Bolt::Logger).to receive(:warn_once).with('file_transfer_max_payload_unknown', message)

      adapter.warn_once('file_transfer_max_payload_unknown', message)
    end
  end
end
