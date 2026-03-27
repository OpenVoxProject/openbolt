# frozen_string_literal: true

require_relative '../../../bolt/error'
require_relative '../../../bolt/config/transport/base'

module Bolt
  class Config
    module Transport
      class Choria < Base
        OPTIONS = %w[
          cleanup
          collective
          command-timeout
          config-file
          host
          interpreters
          nats-connection-timeout
          nats-servers
          puppet-environment
          rpc-timeout
          ssl-ca
          ssl-cert
          ssl-key
          task-agent
          task-timeout
          tmpdir
        ].sort.freeze

        DEFAULTS = {
          'cleanup' => true,
          'command-timeout' => 60,
          'nats-connection-timeout' => 30,
          'puppet-environment' => 'production',
          'rpc-timeout' => 30,
          'task-timeout' => 300,
          'tmpdir' => '/tmp'
        }.freeze

        VALID_AGENTS = %w[bolt_tasks shell].freeze

        private def validate
          super

          if @config['task-agent'] && !VALID_AGENTS.include?(@config['task-agent'])
            raise Bolt::ValidationError,
                  "task-agent must be one of #{VALID_AGENTS.join(', ')}, got '#{@config['task-agent']}'"
          end

          if @config['tmpdir'] && !absolute_path?(@config['tmpdir'])
            raise Bolt::ValidationError,
                  "Choria tmpdir must be an absolute path, got '#{@config['tmpdir']}'"
          end

          ssl_keys = %w[ssl-ca ssl-cert ssl-key]
          provided_ssl = ssl_keys.select { |k| @config[k] }
          if provided_ssl.any? && provided_ssl.length < ssl_keys.length
            missing = ssl_keys - provided_ssl
            raise Bolt::ValidationError,
                  "When overriding Choria SSL settings, all three options must be provided " \
                  "(ssl-ca, ssl-cert, ssl-key). Missing: #{missing.join(', ')}"
          end

          @config['interpreters'] = normalize_interpreters(@config['interpreters']) if @config['interpreters']
        end

        # Accept both POSIX absolute paths (/tmp) and Windows absolute paths (C:\temp).
        def absolute_path?(path)
          path.start_with?('/') || path.match?(Bolt::Transport::Choria::WINDOWS_PATH_REGEX)
        end
      end
    end
  end
end
