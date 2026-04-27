# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      # Number of consecutive RPC poll failures before giving up and marking
      # all remaining targets as failed. Used by both polling loops
      # (poll_task_status and wait_for_shell_results).
      RPC_FAILURE_RETRIES = 3

      # One-time setup of the local MCollective client connection to the
      # NATS broker. MCollective::Config.loadconfig must only be called
      # once since it loads plugins via PluginManager.loadclass, and a
      # second call raises "Plugin already loaded".
      #
      # The @client_configured flag is checked twice: once before taking
      # the mutex (fast path to avoid lock overhead on every call after
      # setup) and once inside (handles the race where two batch threads
      # both see false simultaneously and try to configure concurrently).
      #
      # This function is idempotent, so it should be called before any
      # operation that needs the client connection to ensure it is configured
      # correctly.
      #
      # @param target [Bolt::Target] Any target in the batch (used to read transport options)
      def configure_client(target)
        return if @client_configured

        @config_mutex.synchronize do
          return if @client_configured
          # If a previous attempt failed after partially initializing
          # MCollective (e.g., plugins loaded but NATS connector failed),
          # retrying loadconfig would hit "Plugin already loaded" errors.
          # Re-raise the original error so the caller gets a clear message.
          raise @config_error if @config_error

          # We do the require here because this is a pretty meaty library, and
          # no need to load it when OpenBolt starts up if the user isn't using
          # the Choria transport.
          require 'mcollective'

          opts = target.options
          config = MCollective::Config.instance

          unless config.configured
            config_file = opts['config-file'] || MCollective::Util.config_file_for_user

            unless File.readable?(config_file)
              msg = if opts['config-file']
                      "Choria config file not found or not readable: #{config_file}"
                    else
                      "Could not find a readable Choria client config file. " \
                      "Searched: #{MCollective::Util.config_paths_for_user.join(', ')}. " \
                      "Set the 'config-file' option in the Choria transport configuration."
                    end
              raise Bolt::Error.new(msg, 'bolt/choria-config-not-found')
            end

            begin
              config.loadconfig(config_file)
            rescue StandardError => e
              @config_error = Bolt::Error.new(
                "Choria client configuration failed: #{e.class}: #{e.message}",
                'bolt/choria-config-failed'
              )
              raise @config_error
            end
            logger.debug { "Loaded Choria client config from #{config_file}" }
          end

          if opts['mcollective-certname']
            ENV['MCOLLECTIVE_CERTNAME'] = opts['mcollective-certname']
            logger.debug { "MCOLLECTIVE_CERTNAME set to #{opts['mcollective-certname']}" }
          end

          if opts['brokers']
            brokers = Array(opts['brokers']).map { |broker| broker.include?(':') ? broker : "#{broker}:4222" }
            config.pluginconf['choria.middleware_hosts'] = brokers.join(',')
            logger.debug { "Choria brokers overridden: #{brokers.join(', ')}" }
          end

          if opts['ssl-ca'] && opts['ssl-cert'] && opts['ssl-key']
            unreadable = %w[ssl-ca ssl-cert ssl-key].find { |key| !File.readable?(opts[key]) }
            if unreadable
              raise Bolt::Error.new(
                "File for #{unreadable} is not readable: #{opts[unreadable]}",
                'bolt/choria-config-failed'
              )
            end

            config.pluginconf['security.provider'] = 'file'
            config.pluginconf['security.file.ca'] = opts['ssl-ca']
            config.pluginconf['security.file.certificate'] = opts['ssl-cert']
            config.pluginconf['security.file.key'] = opts['ssl-key']
            logger.debug { "Using file-based TLS security provider with given SSL override(s)" }
          end

          @default_collective = config.main_collective
          @client_configured = true
        end
      end

      # Create an MCollective::RPC::Client for one or more targets.
      # Accepts a single target or an array. Uses MCollective's direct
      # addressing mode (client.discover(nodes:)) to skip broadcast
      # discovery and send requests directly to the specified nodes.
      #
      # Note that when the client is created, if the shell agent isn't already
      # installed on the OpenBolt controller node, then the shell DDL that we
      # bundle with OpenBolt at lib/mcollective/agent/shell.ddl
      # automatically gets loaded since it's on the $LOAD_PATH and in the
      # right place for MCollective's plugin loading. The bolt_tasks
      # DDL is already included in the choria-mcorpc-support gem.
      #
      # @param agent_name [String] MCollective agent name (e.g. 'shell', 'bolt_tasks')
      # @param targets [Bolt::Target, Array<Bolt::Target>] One or more targets to address
      # @param timeout [Numeric] RPC call timeout in seconds
      # @return [MCollective::RPC::Client] Configured client with direct addressing enabled
      def create_rpc_client(agent_name, targets, timeout)
        targets = Array(targets)
        options = MCollective::Util.default_options
        options[:timeout] = timeout
        options[:verbose] = false
        options[:connection_timeout] = targets.first.options['broker-timeout']

        collective = collective_for(targets.first)
        options[:collective] = collective if collective

        client = MCollective::RPC::Client.new(agent_name, options: options)
        client.progress = false

        identities = targets.map { |target| choria_identity(target) }.uniq
        client.discover(nodes: identities)

        client
      end

      # Make a batched RPC call and split results into responded and errors.
      # Yields the RPC client so the caller specifies which action to invoke.
      #
      # Results are split based on MCollective RPC statuscodes:
      # - statuscode 0: action completed successfully (:responded)
      # - statuscode 1 (RPCAborted): action completed but reported a
      #   problem (:responded). The data is preserved rather than
      #   discarded because some agents (notably bolt_tasks) use
      #   statuscode 1 for application-level failures where the
      #   response data is still valid and meaningful (e.g., a task
      #   that ran but exited non-zero). Callers must handle this
      #   case and not assume :responded means success.
      # - statuscode 2-5: RPC infrastructure error (:errors)
      # - no response: target didn't reply (:errors)
      # - exception: total RPC failure (rpc_failed: true)
      #
      # Serialized by @rpc_mutex because MCollective's NATS connector is a
      # singleton with a shared receive queue. Concurrent RPC calls cause
      # reply channel collisions, cross-thread message confusion, and subscription
      # conflicts. See choria-transport-dev.md for the full explanation.
      #
      # @param agent [String] MCollective agent name (e.g. 'shell', 'bolt_tasks', 'rpcutil')
      # @param targets [Bolt::Target, Array<Bolt::Target>] One or more targets to address
      # @param context [String] Human-readable label for logging (e.g. 'shell.start')
      # @yield [MCollective::RPC::Client] The configured RPC client to invoke an action on
      # @return [Hash] with keys:
      #   - :responded [Hash] Targets where the action completed (statuscode 0-1),
      #     mapped to their response data
      #   - :errors [Hash] Targets with RPC errors or no response, mapped to error output hashes
      #   - :rpc_failed [Boolean] True when the entire RPC call failed
      #   - :rpc_statuscodes [Hash] Per-target MCollective RPC statuscodes.
      #     Includes all targets that responded (both :responded and :errors).
      #     Not populated when rpc_failed is true (no individual responses).
      def rpc_request(agent, targets, context)
        targets = Array(targets)
        rpc_results = @rpc_mutex.synchronize do
          rpc_timeout = targets.first.options['rpc-timeout']
          client = create_rpc_client(agent, targets, rpc_timeout)
          yield(client)
        end
        by_sender = index_results_by_sender(rpc_results, targets, context)

        responded = {}
        errors = {}
        rpc_statuscodes = {}
        targets.each do |target|
          rpc_result = by_sender[choria_identity(target)]
          if rpc_result.nil?
            errors[target] = error_output(
              "No response from #{target.safe_name} for #{context}",
              'bolt/choria-no-response'
            )
          elsif rpc_result[:statuscode] > 1
            rpc_statuscodes[target] = rpc_result[:statuscode]
            errors[target] = error_output(
              "#{context} on #{target.safe_name} returned RPC error: " \
              "#{rpc_result[:statusmsg]} (code #{rpc_result[:statuscode]})",
              'bolt/choria-rpc-error'
            )
          else
            rpc_statuscodes[target] = rpc_result[:statuscode]
            if rpc_result[:statuscode] == 1
              logger.warn { "#{context} on #{target.safe_name} had RPC status code #{rpc_result[:statuscode]}: #{rpc_result[:statusmsg]}" }
            end
            responded[target] = rpc_result[:data]
          end
        end
        { responded: responded, errors: errors, rpc_failed: false, rpc_statuscodes: rpc_statuscodes }
      rescue StandardError => e
        raise if e.is_a?(Bolt::Error)

        logger.warn { "#{context} RPC call failed: #{e.class}: #{e.message}" }
        errors = targets.each_with_object({}) do |target, errs|
          errs[target] = error_output("#{context} failed on #{target.safe_name}: #{e.message}",
                                      'bolt/choria-rpc-failed')
        end
        { responded: {}, errors: errors, rpc_failed: true, rpc_statuscodes: {} }
      end

      # Configure the client, discover agents, partition targets by agent
      # availability, and emit errors for incapable targets.
      #
      # @param targets [Array<Bolt::Target>] Targets to prepare
      # @param agent_name [String] Required agent name (e.g. 'shell', 'bolt_tasks')
      # @param result_opts [Hash] Options passed through to emit_results (:action, :name, :position)
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array] Two-element array:
      #   - [Array<Bolt::Target>] Targets that have the required agent
      #   - [Array<Bolt::Result>] Error results for targets that lack the agent
      def prepare_targets(targets, agent_name, result_opts, &callback)
        configure_client(targets.first)
        discover_agents(targets)

        capable, incapable = targets.partition { |target| has_agent?(target, agent_name) }

        agent_errors = incapable.each_with_object({}) do |target, errors|
          msg = if @agent_cache[choria_identity(target)].nil?
                  "No agent information available for #{target.safe_name} (node did not respond to discovery)"
                else
                  "The '#{agent_name}' agent is not available on #{target.safe_name}."
                end
          errors[target] = error_output(msg, 'bolt/choria-agent-not-available')
        end
        incapable_results = emit_results(agent_errors, fire_node_start: true, **result_opts, &callback)

        [capable, incapable_results]
      end

      # Index RPC results by sender, keeping only the first response per
      # sender and only from the set of expected identities. Logs and discards
      # responses from unexpected senders and duplicates.
      #
      # @param results [Array<Hash>] Raw MCollective RPC result hashes with :sender keys
      # @param targets [Array<Bolt::Target>] Expected targets (used to build the allowed sender set)
      # @param context [String] Human-readable label for log messages
      # @return [Hash{String => Hash}] Sender identity to first valid RPC result hash
      def index_results_by_sender(results, targets, context)
        expected = targets.to_set { |target| choria_identity(target) }
        by_sender = {}
        results.each do |result|
          sender = result[:sender]
          unless sender
            logger.warn { "Discarding #{context} response with nil sender" }
            next
          end
          unless expected.include?(sender)
            logger.warn { "Discarding #{context} response from unexpected sender '#{sender}'" }
            next
          end
          if by_sender.key?(sender)
            if result[:data] == by_sender[sender][:data]
              logger.debug { "Ignoring duplicate #{context} response from #{sender}" }
            else
              logger.warn { "Ignoring duplicate #{context} response from #{sender} with different data" }
            end
            next
          end
          by_sender[sender] = result
        end
        by_sender
      end
    end
  end
end
