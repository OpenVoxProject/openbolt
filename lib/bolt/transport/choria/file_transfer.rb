# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # Upload and download through the file_transfer agent. The transfers
      # themselves are done by the client library the agent's Puppet module
      # installs on the controller, MCollective::Util::FileTransfer. This file
      # maps targets, options and results onto it.

      # The library's outcome kinds as this transport's error kinds. A kind
      # a later library adds is reported as a transfer failure.
      FILE_TRANSFER_ERROR_KINDS = {
        no_response: 'bolt/choria-no-response',
        rpc_error: 'bolt/choria-rpc-error',
        rpc_failed: 'bolt/choria-rpc-failed',
        transfer_failed: 'bolt/choria-file-transfer-failed',
        payload_too_large: 'bolt/choria-payload-too-large',
        checksum_mismatch: 'bolt/choria-checksum-mismatch'
      }.freeze

      # Upload one file to the capable targets through the library.
      def batch_upload(targets, source, destination, _options = {}, position = [], &callback)
        result_opts = { action: 'upload', name: source, position: position }
        capable, results = prepare_targets(targets, 'file_transfer', result_opts, &callback)
        return results if capable.empty?

        logger.debug { "Uploading #{source} to #{destination} on #{target_count(capable)}" }
        results + transfer(capable, result_opts, callback) do |client|
          outcomes = client.upload(source, destination, identities_of(capable))
          file_transfer_results(capable, outcomes, result_opts, callback) do |target, outcome|
            Bolt::Result.for_upload(target, source, outcome.path)
          end
        end
      end

      # Download a path from each capable target into its own directory.
      def batch_download(targets, source, destination, _options = {}, position = [], &callback)
        directories = targets.to_h { |target| [target, download_dir(destination, target)] }
        download_into(directories, source, position, &callback)
      end

      # Download a path from each capable target into the directory given
      # for it.
      #
      # @param directories [Hash{Bolt::Target => String}] Each target and the local directory its download goes into
      # @param source [String] The path to download from each target
      # @param position [Array] Positional info for result tracking
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>]
      def download_into(directories, source, position, &callback)
        result_opts = { action: 'download', name: source, position: position }
        capable, results = prepare_targets(directories.keys, 'file_transfer', result_opts, &callback)
        return results if capable.empty?

        logger.debug { "Downloading #{source} from #{target_count(capable)}" }
        # The library takes one directory per identity, so targets behind one
        # identity share the last one's directory.
        destination_dirs = capable.to_h { |target| [choria_identity(target), directories.fetch(target)] }
        results + transfer(capable, result_opts, callback) do |client|
          outcomes = client.download(source, destination_dirs)
          file_transfer_results(capable, outcomes, result_opts, callback) do |target, outcome|
            Bolt::Result.for_download(target, source, destination_dirs.fetch(choria_identity(target)), outcome.path)
          end
        end
      end

      # Runs one transfer for the targets with a library client and returns a
      # result per target. A library that isn't installed on this host, or an
      # error raised for what the controller contains, such as a source that
      # can't be read, is a result for each of the targets.
      #
      # @param targets [Array<Bolt::Target>] The capable targets of one batch
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc, nil] Called with :node_result events
      # @yield [MCollective::Util::FileTransfer::Client] The client for the targets
      # @return [Array<Bolt::Result>]
      def transfer(targets, result_opts, callback)
        yield file_transfer_client(targets)
      rescue Bolt::Error => e
        failures = targets.to_h { |target| [target, error_output(e.message, e.kind)] }
        emit_results(failures, **result_opts, &callback)
      rescue SystemCallError, ArgumentError => e
        logger.warn { "The file transfer raised #{e.class} on the controller: #{e.message}" }
        logger.debug { e.backtrace.join("\n") }
        message = "#{e.message} (#{e.class} on the controller)"
        failures = targets.to_h { |target| [target, error_output(message, FILE_TRANSFER_ERROR_KINDS[:transfer_failed])] }
        emit_results(failures, **result_opts, &callback)
      end

      # A library client for the targets, with the batch's options. The
      # library builds its connection from the options this transport's own
      # clients get and the RPC mutex every other call in the process takes.
      # A timeout or size the batch does not set is left to the library's
      # default.
      def file_transfer_client(targets)
        load_file_transfer_library
        options = targets.first.options
        settings = { rpc_timeout: options['file-transfer-timeout'], message_data_size: options['message-data-size'],
                     upload_batch_size: options['upload-batch-size'] }
        MCollective::Util::FileTransfer::Client.new(client_options(targets), mutex: @rpc_mutex, logger: logger, **settings.compact)
      end

      # The library is a client file of the agent's Puppet module under the
      # libdir the Choria client config names, which loading that config in
      # configure_client put on the load path.
      def load_file_transfer_library
        require 'mcollective/util/file_transfer'
      rescue LoadError => e
        raise Bolt::Error.new(
          'The file_transfer client library is not installed on this host. Apply the mcollective_agent_file_transfer ' \
          "module with client => true where OpenBolt runs, which installs it under the Choria libdir (#{e.class}: #{e.message}).",
          'bolt/choria-file-transfer-library'
        )
      end

      # A result per target from the outcomes by identity, firing
      # node_result for each. The block builds the result of a success.
      def file_transfer_results(targets, outcomes, result_opts, callback)
        targets.map do |target|
          outcome = outcomes.fetch(choria_identity(target))
          result = if outcome.success?
                     yield(target, outcome)
                   else
                     kind = FILE_TRANSFER_ERROR_KINDS.fetch(outcome.error_kind, FILE_TRANSFER_ERROR_KINDS[:transfer_failed])
                     build_result(target, error_output(outcome.error_message, kind), **result_opts)
                   end
          callback&.call(type: :node_result, result: result)
          result
        end
      end
    end
  end
end
