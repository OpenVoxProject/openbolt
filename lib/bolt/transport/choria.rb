# frozen_string_literal: true

require 'base64'
require 'concurrent/map'
require 'digest/sha2'
require 'json'
require 'securerandom'
require 'shellwords'
require_relative '../../bolt/transport/base'

module Bolt
  module Transport
    # Choria transport for OpenBolt. Communicates with nodes via Choria's NATS
    # pub/sub messaging infrastructure using the choria-mcorpc-support gem as
    # the client library. Extends Transport::Base directly (not Simple) because
    # Choria's pub/sub model doesn't fit the persistent connection/shell
    # abstraction that Simple assumes.
    #
    # Available capabilities depend on which agents are installed on the
    # target node:
    #
    #   bolt_tasks agent only: Only run_task works, via the bolt_tasks agent
    #     which downloads task files from an OpenVox/Puppet Server and executes
    #     them via task_wrapper. All other operations fail with an actionable
    #     error directing the user to install the shell agent.
    #
    #   shell agent installed (>= 1.2.1): run_command, run_script, and
    #     run_task work. run_task uses the bolt_tasks agent by default.
    #     To run local tasks via the shell agent, set task-agent to 'shell'
    #     in project config or specify --choria-task-agent shell.
    #
    #   Upload, download, and plans are not yet supported.
    class Choria < Base
      def initialize
        super
        @config_mutex = Mutex.new
        @config_error = nil
        @client_configured = false
        # Serializes RPC calls across batch threads. See the comment on
        # rpc_request in helpers.rb for why this is necessary.
        @rpc_mutex = Mutex.new
        # Multiple batch threads write to this map concurrently when we
        # have more than one collective.
        @agent_cache = Concurrent::Map.new
        @default_collective = nil
      end

      # Advertise both shell and powershell so tasks with either requirement
      # can be selected. The per-target selection happens in
      # select_implementation below, which picks the right feature set based
      # on the target's detected OS.
      def provided_features
        %w[shell powershell]
      end

      # Override to select task implementation based on the target's OS.
      # Other transports rely on inventory features to pick the right
      # implementation, but Choria discovers the OS at runtime via the
      # os.family fact. We pass only the detected platform's feature so
      # task.select_implementation picks the correct .ps1 or .sh file.
      #
      # @param target [Bolt::Target] Target whose OS determines the implementation
      # @param task [Bolt::Task] Task with platform-specific implementations
      # @return [Hash] Selected implementation hash with 'path', 'name', 'input_method', 'files' keys
      def select_implementation(target, task)
        features = windows_target?(target) ? ['powershell'] : ['shell']
        impl = task.select_implementation(target, features)
        impl['input_method'] ||= default_input_method(impl['path'])
        impl
      end

      # Group targets by collective so each batch uses a single RPC client
      # scope. MCollective RPC calls are published to a collective-specific
      # NATS subject, so targets in different collectives must be in separate
      # batches. Most deployments have one collective, yielding one batch.
      # Bolt runs each batch in its own thread and @rpc_mutex serializes
      # the RPC calls across threads to prevent response misrouting.
      #
      # @param targets [Array<Bolt::Target>] All targets for this operation
      # @return [Array<Array<Bolt::Target>>] Targets grouped by collective
      def batches(targets)
        # Populates @default_collective from the Choria config so targets
        # without an explicit collective are grouped correctly.
        configure_client(targets.first)
        targets.group_by { |target| collective_for(target) }.values
      end

      # Override batch_task to handle multiple targets in one thread using the RPC.
      # Implementation grouping (mixed-platform support) is handled internally
      # by run_task_via_bolt_tasks and run_task_via_shell.
      #
      # @param targets [Array<Bolt::Target>] Targets in a single collective batch
      # @param task [Bolt::Task] Task to execute
      # @param arguments [Hash] Task parameter names to values
      # @param options [Hash] Execution options (unused currently, passed through from Base)
      # @param position [Array] Positional info for result tracking
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>] Results for all targets (successes and failures)
      def batch_task(targets, task, arguments, _options = {}, position = [], &callback)
        chosen_agent = targets.first.options['task-agent'] || 'bolt_tasks'
        result_opts = { action: 'task', name: task.name, position: position }

        # The results var here is the error results for incapable targets, to which we'll add in
        # the successful results from the capable targets as we go.
        capable, results = prepare_targets(targets, chosen_agent, result_opts, &callback)

        logger.debug { "Task #{task.name} routing: agent: #{chosen_agent}, #{capable.size} capable / #{targets.size - capable.size} incapable" }

        unless capable.empty?
          capable.each { |target| callback&.call(type: :node_start, target: target) }
          arguments = unwrap_sensitive_args(arguments)

          results += case chosen_agent
                     when 'bolt_tasks'
                       run_task_via_bolt_tasks(capable, task, arguments, result_opts, &callback)
                     when 'shell'
                       run_task_via_shell(capable, task, arguments, result_opts, &callback)
                     else
                       raise Bolt::Error.new(
                         "Unsupported task-agent '#{chosen_agent}'",
                         'bolt/choria-unsupported-agent'
                       )
                     end
        end

        results
      end

      # Override batch_task_with for per-target arguments. Only called
      # from the run_task_with Puppet plan function (no CLI or Ruby API
      # path uses this). Discovery is batched upfront, but execution is
      # sequential per-target because MCollective RPC calls send the
      # same arguments to all targets. A future optimization could batch
      # the download/infra-setup/polling steps while keeping only the
      # start step per-target.
      #
      # THIS IS NOT YET READY FOR PRODUCTION. The API is stable, but we don't
      # yet have full plan support and this runs the task sequentially across
      # targets, which is very inefficient. It had to be implemented now, though,
      # in order to prevent the assert_batch_size_one from the Base interface
      # from blowing things up.
      #
      # @param targets [Array<Bolt::Target>] Targets in a single collective batch
      # @param task [Bolt::Task] Task to execute
      # @param target_mapping [Hash{Bolt::Target => Hash}] Per-target argument hashes
      # @param options [Hash] Execution options (passed through from Base)
      # @param position [Array] Positional info for result tracking
      # @param callback [Proc] Called with :node_start and :node_result events
      # @return [Array<Bolt::Result>] Results for all targets
      def batch_task_with(targets, task, target_mapping, options = {}, position = [], &callback)
        # Pre-warm the agent cache so individual batch_task calls are cache hits
        configure_client(targets.first)
        discover_agents(targets)

        results = []
        targets.each do |target|
          results += batch_task([target], task, target_mapping[target], options, position, &callback)
        end
        results
      end

      # Override batch_connected? to check all targets in one RPC call. Only
      # used for wait_until_available in plans.
      #
      # @param targets [Array<Bolt::Target>] Targets to check connectivity for
      # @return [Boolean] True if all targets responded to ping
      def batch_connected?(targets)
        logger.debug { "Checking connectivity for #{target_count(targets)}" }
        first_target = targets.first
        configure_client(first_target)

        response = rpc_request('rpcutil', targets, 'rpcutil.ping') do |client|
          client.ping
        end
        response[:responded].length == targets.length
      rescue StandardError => e
        raise if e.is_a?(Bolt::Error)

        logger.warn { "Batch connectivity check failed: #{e.class}: #{e.message}" }
        false
      end

      def upload(_target, _source, _destination, _options = {}, _position = [])
        raise Bolt::Error.new(
          'The Choria transport does not yet support upload.',
          'bolt/choria-unsupported-operation'
        )
      end

      def download(_target, _source, _destination, _options = {}, _position = [])
        raise Bolt::Error.new(
          'The Choria transport does not yet support download.',
          'bolt/choria-unsupported-operation'
        )
      end

      # Returns the Choria node identity for a target. Uses the transport
      # 'host' config if set, falling back to target.host (which Bolt
      # derives from the URI or target name).
      def choria_identity(target)
        target.options['host'] || target.host
      end

      # Returns the collective for a target, used by batches() to group
      # targets. Falls back to the default collective from the loaded config.
      def collective_for(target)
        target.options['collective'] || @default_collective
      end
    end
  end
end

require_relative 'choria/agent_discovery'
require_relative 'choria/bolt_tasks'
require_relative 'choria/client'
require_relative 'choria/command_builders'
require_relative 'choria/helpers'
require_relative 'choria/shell'
