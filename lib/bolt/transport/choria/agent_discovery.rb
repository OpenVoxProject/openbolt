# frozen_string_literal: true

module Bolt
  module Transport
    class Choria
      AGENT_MIN_VERSIONS = {
        'shell' => '1.2.1',
        'file_transfer' => '1.0.0'
      }.freeze

      # Discover agents and detect OS on targets via two batched RPC calls
      # (agent_inventory for agents+versions, get_fact for os.family).
      # Populates @agent_cache with { agents: [...], os: 'redhat' | 'windows' | ... }.
      #
      # @param targets [Array<Bolt::Target>] Targets to discover agents on
      # @return [Hash{Bolt::Target => Hash}] The error output of each uncached target that the
      #   agent_inventory call failed for, other than by not answering. Empty otherwise.
      def discover_agents(targets)
        uncached = targets.reject { |target| discovered?(target) }
        return {} if uncached.empty?

        logger.debug { "Discovering agents on #{target_count(uncached)}" }
        failures = discover_agent_list(uncached)
        discover_os_family(uncached)
        failures
      end

      def discovered?(target)
        @agent_cache.key?(choria_identity(target))
      end

      def has_agent?(target, agent_name)
        @agent_cache[choria_identity(target)]&.dig(:agents)&.include?(agent_name) || false
      end

      def windows_target?(target)
        @agent_cache[choria_identity(target)]&.dig(:os) == 'windows'
      end

      # Discover available agents on targets via rpcutil.agent_inventory
      # and populate @agent_cache with agent lists.
      #
      # @param targets [Array<Bolt::Target>] Targets to query for agent inventory
      # @return [Hash{Bolt::Target => Hash}] The error output of each target that answered with
      #   an RPC error, or of every target when the call failed as a whole, such as when the
      #   client could not connect. A target that did not answer is left out.
      def discover_agent_list(targets)
        response = rpc_request('rpcutil', targets, 'rpcutil.agent_inventory') do |client|
          client.agent_inventory
        end
        response[:errors].each { |target, output| logger.warn { "agent_inventory failed for #{target.safe_name}: #{output[:error]}" } }

        response[:responded].each do |target, data|
          sender = choria_identity(target)
          # A node can send data that isn't a hash, which would raise and stop
          # discovery for every target after it
          agents = filter_agents(sender, data[:agents]) if data.is_a?(Hash)
          unless agents
            logger.warn { "Unexpected agent_inventory response from #{sender}. This target will be treated as unreachable." }
            next
          end
          @agent_cache[sender] = { agents: agents }
          logger.debug { "Discovered agents on #{sender}: #{agents.join(', ')}" }
        end
        response[:errors].reject { |_target, output| output[:error_kind] == 'bolt/choria-no-response' }
      rescue StandardError => e
        raise if e.is_a?(Bolt::Error)

        logger.warn { "Agent discovery failed: #{e.class}: #{e.message}" }
        {}
      end

      # Detect the OS family on targets via rpcutil.get_fact and update
      # @agent_cache entries with the :os key.
      #
      # @param targets [Array<Bolt::Target>] Targets to detect OS on
      def discover_os_family(targets)
        # Only fetch OS for targets that responded to agent_inventory
        responded = targets.select { |target| discovered?(target) }
        return if responded.empty?

        response = rpc_request('rpcutil', responded, 'rpcutil.get_fact') do |client|
          client.get_fact(fact: 'os.family')
        end
        response[:errors].each { |target, output|
          logger.warn {
            "OS detection failed for #{target.safe_name}: #{output[:error]}. Defaulting to POSIX command syntax."
          }
        }

        response[:responded].each do |target, data|
          sender = choria_identity(target)
          unless data.is_a?(Hash)
            logger.warn { "Unexpected get_fact response from #{sender}. Defaulting to POSIX command syntax." }
            next
          end
          os_family = data[:value].to_s.downcase
          if os_family.empty?
            logger.warn { "os.family fact is empty on #{sender}. Defaulting to POSIX command syntax." }
            next
          end
          @agent_cache[sender][:os] = os_family
          logger.debug { "Detected OS on #{sender}: #{os_family}" }
        end
      rescue StandardError => e
        raise if e.is_a?(Bolt::Error)

        logger.warn { "OS detection failed: #{e.class}: #{e.message}. Defaulting to POSIX command syntax." }
      end

      # Filter out agents that don't meet minimum version requirements.
      #
      # @param sender [String] Choria node identity (for logging)
      # @param agent_list [Array<Hash>, nil] Agent entries from agent_inventory, each with
      #   :agent (name) and :version keys
      # @return [Array<String>, nil] Agent names that meet version requirements, or nil
      #   if agent_list is not an Array
      def filter_agents(sender, agent_list)
        return nil unless agent_list.is_a?(Array)

        agent_list.filter_map do |entry|
          name = entry['agent']
          next unless name

          version = entry['version']
          min_version = AGENT_MIN_VERSIONS[name]
          if min_version && !meets_min_version?(version, min_version)
            logger.warn {
              "The '#{name}' agent on #{sender} is version #{version || 'unknown'}, " \
              "but #{min_version} or later is required. It will be treated as unavailable."
            }
            next
          end

          name
        end
      end

      def meets_min_version?(version, min_version)
        return false unless version

        Gem::Version.new(version) >= Gem::Version.new(min_version)
      rescue ArgumentError => e
        logger.warn { "Could not parse version '#{version}': #{e.message}. Treating agent as unavailable." }
        false
      end
    end
  end
end
