# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # upload and download through the file_transfer agent. The transfer
      # itself, message sizing, temporary files, verification and directory
      # walks, is the client library the agent's Puppet module installs on the
      # controller, MCollective::Util::FileTransfer. This file maps targets,
      # options and results onto it. See the Phase 4 design in
      # developer-docs/choria/choria-transport-plan.md.
      FILE_TRANSFER_LIBRARY = 'mcollective/util/file_transfer'
      FILE_TRANSFER_LIBRARY_REQUIREMENT = Gem::Requirement.new('~> 1.0')
      FILE_TRANSFER_LIBRARY_ERROR_KIND = 'bolt/choria-file-transfer-library'
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
      FILE_TRANSFER_DEFAULT_ERROR_KIND = FILE_TRANSFER_ERROR_KINDS.fetch(:transfer_failed)

      # @see Transport::Base#batch_upload
      def batch_upload(targets, source, destination, _options = {}, position = [], &callback)
        result_opts = { action: 'upload', name: source, position: position }
        with_file_transfer(targets, result_opts, callback) do |client, capable|
          logger.debug { "Uploading #{source} to #{destination} on #{target_count(capable)}" }
          file_transfer_call(capable, result_opts, callback) do
            outcomes = client.upload(source, destination, identities_of(capable))
            file_transfer_results(capable, outcomes, result_opts, callback) do |target, outcome|
              Bolt::Result.for_upload(target, source, outcome.path)
            end
          end
        end
      end

      # @see Transport::Base#batch_download
      def batch_download(targets, source, destination, _options = {}, position = [], &callback)
        result_opts = { action: 'download', name: source, position: position }
        with_file_transfer(targets, result_opts, callback) do |client, capable|
          logger.debug { "Downloading #{source} from #{target_count(capable)} to #{destination}" }
          # Each target gets its own directory, while the library takes one
          # directory per identity, so targets behind one identity go in
          # separate rounds. With distinct identities that's one round.
          download_rounds(capable).flat_map do |round|
            destination_dirs = round.to_h { |target| [choria_identity(target), download_dir(destination, target)] }
            file_transfer_call(round, result_opts, callback) do
              outcomes = client.download(source, destination_dirs)
              file_transfer_results(round, outcomes, result_opts, callback) do |target, outcome|
                Bolt::Result.for_download(target, source, destination_dirs.fetch(choria_identity(target)), outcome.path)
              end
            end
          end
        end
      end

      # The targets in rounds of at most 1 target per identity, in target order.
      #
      # @param targets [Array<Bolt::Target>]
      # @return [Array<Array<Bolt::Target>>]
      def download_rounds(targets)
        rounds = []
        until targets.empty?
          round = targets.uniq { |target| choria_identity(target) }
          rounds << round
          targets -= round
        end
        rounds
      end

      # Sorts the targets by whether they have the agent, fires node_start
      # for the capable ones, and yields them with a library client. Returns
      # a result for every target, whether it lacked the agent, went through
      # the block, or could not be served because the library cannot be used
      # on this host.
      #
      # @param targets [Array<Bolt::Target>] The targets of one batch
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc, nil] Called with :node_start and :node_result events
      # @yield [MCollective::Util::FileTransfer::Client, Array<Bolt::Target>] The client and the capable targets
      # @return [Array<Bolt::Result>]
      def with_file_transfer(targets, result_opts, callback)
        capable, results = prepare_targets(targets, FILE_TRANSFER_AGENT, result_opts, &callback)
        return results if capable.empty?

        capable.each { |target| callback&.call(type: :node_start, target: target) }
        begin
          client = file_transfer_client(capable)
        rescue Bolt::Error => e
          failures = capable.to_h { |target| [target, error_output(e.message, e.kind)] }
          return results + emit_results(failures, **result_opts, &callback)
        end
        results + yield(client, capable)
      end

      # Runs one library call for the targets and answers its results. An
      # error the library raises for what the controller holds, such as a
      # source that cannot be read, is a result for each of those targets,
      # and only those, so a later round reports nothing twice.
      #
      # @param targets [Array<Bolt::Target>] The targets the call serves
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc, nil] Called with :node_result events
      # @return [Array<Bolt::Result>]
      def file_transfer_call(targets, result_opts, callback)
        yield
      rescue SystemCallError, ArgumentError => e
        logger.warn { "The file transfer raised #{e.class} on the controller: #{e.message}" }
        logger.debug { e.backtrace.join("\n") }
        message = "#{e.message} (#{e.class} on the controller)"
        failures = targets.to_h { |target| [target, error_output(message, FILE_TRANSFER_DEFAULT_ERROR_KIND)] }
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
        begin
          require FILE_TRANSFER_LIBRARY
        rescue LoadError => e
          raise Bolt::Error.new(
            'The file_transfer client library is not installed on this host. Apply the mcollective_agent_file_transfer ' \
            "module with client => true where OpenBolt runs, which installs it under the Choria libdir (#{e.class}: #{e.message}).",
            FILE_TRANSFER_LIBRARY_ERROR_KIND
          )
        end

        version = MCollective::Util::FileTransfer::VERSION
        return if FILE_TRANSFER_LIBRARY_REQUIREMENT.satisfied_by?(Gem::Version.new(version))

        raise Bolt::Error.new(
          "The file_transfer client library on this host is version #{version} and this transport needs " \
          "#{FILE_TRANSFER_LIBRARY_REQUIREMENT}. Update the mcollective_agent_file_transfer module where OpenBolt runs.",
          FILE_TRANSFER_LIBRARY_ERROR_KIND
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
                     kind = FILE_TRANSFER_ERROR_KINDS.fetch(outcome.error_kind, FILE_TRANSFER_DEFAULT_ERROR_KIND)
                     build_result(target, error_output(outcome.error_message, kind), **result_opts)
                   end
          callback&.call(type: :node_result, result: result)
          result
        end
      end
    end
  end
end
