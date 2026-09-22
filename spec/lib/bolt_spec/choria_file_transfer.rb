# frozen_string_literal: true

module BoltSpec
  # A stand-in for the file_transfer client library that the agent's Puppet
  # module installs on a controller, MCollective::Util::FileTransfer, which
  # the transport requires at run time and the test suite does not have.
  # Specs stub the constant with this module and script what its clients
  # answer through the class-level settings below.
  module FakeFileTransfer
    VERSION = '1.0.0'

    class << self
      attr_accessor :clients, :upload_script, :download_script

      def reset
        @clients = []
        @upload_script = nil
        @download_script = nil
      end

      # Scripts what upload answers, with the source, destination and
      # identities. Without a script every identity succeeds at the destination.
      def on_upload(&block)
        @upload_script = block
      end

      # Scripts what download answers, with the source and the directory per
      # identity. Without a script every identity succeeds at the source's
      # basename under its directory.
      def on_download(&block)
        @download_script = block
      end
    end

    class Outcome
      attr_reader :identity, :path, :kind, :message

      def self.success(identity, path)
        new(identity, path: path)
      end

      def self.failure(identity, kind, message)
        new(identity, kind: kind, message: message)
      end

      def initialize(identity, path: nil, kind: nil, message: nil)
        @identity = identity
        @path = path
        @kind = kind
        @message = message
      end

      def success?
        @kind.nil?
      end
    end

    class Client
      attr_reader :arguments, :uploads, :downloads

      # The arguments the library's client takes at this version, so a
      # keyword it does not know is refused here as it would be there.
      def initialize(options, mutex: nil, logger: nil, rpc_timeout: 30, message_data_size: nil, upload_batch_size: nil)
        @arguments = { options: options, mutex: mutex, logger: logger, rpc_timeout: rpc_timeout, message_data_size: message_data_size,
                       upload_batch_size: upload_batch_size }
        @uploads = []
        @downloads = []
        FakeFileTransfer.clients << self
      end

      def upload(source, destination, identities)
        @uploads << [source, destination, identities.dup]
        hold_the_lock
        script = FakeFileTransfer.upload_script
        return script.call(source, destination, identities) if script

        identities.to_h { |identity| [identity, Outcome.success(identity, destination)] }
      end

      def download(source, destinations)
        @downloads << [source, destinations.dup]
        hold_the_lock
        script = FakeFileTransfer.download_script
        return script.call(source, destinations) if script

        destinations.to_h { |identity, directory| [identity, Outcome.success(identity, File.join(directory, File.basename(source)))] }
      end

      private

      # The real client takes the transport's lock for every call, so a
      # caller that already holds it stops there, which a Mutex reports as
      # a ThreadError.
      def hold_the_lock
        @arguments[:mutex].synchronize {}
      end
    end
  end
end

# Puts the stand-in where the transport requires the library, with the
# require itself answered as if the module's client files were installed.
RSpec.shared_context 'choria file transfer library' do
  before do
    BoltSpec::FakeFileTransfer.reset
    stub_const('MCollective::Util::FileTransfer', BoltSpec::FakeFileTransfer)
    allow(transport).to receive(:require).and_call_original
    allow(transport).to receive(:require).with(Bolt::Transport::Choria::FILE_TRANSFER_LIBRARY).and_return(true)
  end
end
