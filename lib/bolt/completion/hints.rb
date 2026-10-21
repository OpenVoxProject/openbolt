# frozen_string_literal: true

require_relative '../logger'

module Bolt
  module Completion
    # Completion knowledge that cannot be derived from the CLI parser.
    #
    # Everything in this file is semantic, not shell syntax: renderers map the
    # types onto bash and zsh completion functions.
    module Hints
      def self.positional(type, label, description: nil, **options)
        {
          type: type,
          label: label,
          description: description
        }.merge(options)
      end

      def self.file(label, description: nil, **options)
        positional(:file, label, description: description, **options)
      end

      def self.directory(label, description: nil, **options)
        positional(:directory, label, description: description, **options)
      end

      def self.value(label, description: nil, **options)
        positional(:message, label, description: description, **options)
      end

      def self.topic(label, description: nil, **options)
        positional(:topic, label, description: description, **options)
      end

      def self.entity(list, params: nil, optional: false, **options)
        positional(:entity, list.to_s.delete_suffix('s'), list: list.to_s,
                   params: params&.to_s, optional: optional, **options)
      end

      # Positional arguments of each `bolt <subcommand> [action]`.
      # Keys are "<subcommand>:<action>" ("<subcommand>:" for subcommands
      # without actions).
      POSITIONALS = {
        'apply:'         => [file('manifest file')],
        'guide:'         => [topic('topic')],
        'lookup:'        => [value('Hiera key', description: 'key to look up')],
        'command:run'    => [value('remote command', description: 'command to run')],
        'file:download'  => [value('remote source', description: 'remote file'),
                             directory('destination directory')],
        'file:upload'    => [file('source file or directory'),
                             value('remote destination', description: 'remote path')],
        'module:add'     => [value('module', description: 'module name (e.g. puppetlabs-apt)')],
        'module:show'    => [value('module', description: 'module name', optional: true)],
        'plan:convert'   => [entity(:plans)],
        'plan:new'       => [value('plan name', description: 'plan name (mymodule::myplan)')],
        'plan:run'       => [entity(:plans, params: :plan)],
        'plan:show'      => [entity(:plans, optional: true)],
        'policy:apply'   => [value('policy', description: 'policy (comma separated list to apply several)')],
        'policy:new'     => [value('policy name', description: 'policy name')],
        'project:init'   => [value('project name', description: 'project name', optional: true)],
        'script:run'     => [file('script'),
                             value('script argument', description: 'script argument', multiple: true)],
        'secret:decrypt' => [value('ciphertext', description: 'ciphertext')],
        'secret:encrypt' => [value('plaintext', description: 'plaintext', optional: true)],
        'task:run'       => [entity(:tasks, params: :task)],
        'task:show'      => [entity(:tasks, optional: true)]
      }.freeze

      # How an option's value completes.
      OPTION_TYPES = {
        'targets'                    => { type: :targets, label: 'targets' },
        'query'                      => { type: :message, label: 'query', description: 'PuppetDB query' },
        'user'                       => { type: :value, label: 'user' },
        'password'                   => { type: :value, label: 'password' },
        'private-key'                => { type: :file, label: 'private key' },
        'run-as'                     => { type: :value, label: 'run as user' },
        'sudo-password'              => { type: :value, label: 'sudo password' },
        'sudo-executable'            => { type: :command, label: 'executable' },
        'concurrency'                => { type: :integer, label: 'count', description: 'number' },
        'compile-concurrency'        => { type: :integer, label: 'count', description: 'number' },
        'modulepath'                 => { type: :directory, label: 'modulepath' },
        'project'                    => { type: :directory, label: 'project' },
        'hiera-config'               => { type: :file, label: 'hiera config' },
        'inventoryfile'              => { type: :file, label: 'inventory file' },
        'puppetdb'                   => { type: :value, label: 'instance' },
        'connect-timeout'            => { type: :integer, label: 'seconds', description: 'seconds' },
        'ssh-command'                => { type: :command, label: 'command' },
        'copy-command'               => { type: :command, label: 'command' },
        'tmpdir'                     => { type: :directory, label: 'tmpdir' },
        'choria-config-file'         => { type: :file, label: 'config file' },
        'choria-mcollective-certname' => { type: :value, label: 'certname' },
        'choria-ssl-ca'              => { type: :file, label: 'ca file' },
        'choria-ssl-cert'            => { type: :file, label: 'cert file' },
        'choria-ssl-key'             => { type: :file, label: 'key file' },
        'choria-collective'          => { type: :value, label: 'collective' },
        'choria-puppet-environment'  => { type: :value, label: 'environment' },
        'choria-rpc-timeout'         => { type: :integer, label: 'seconds', description: 'seconds' },
        'choria-task-timeout'        => { type: :integer, label: 'seconds', description: 'seconds' },
        'choria-command-timeout'     => { type: :integer, label: 'seconds', description: 'seconds' },
        'choria-brokers'             => { type: :value, label: 'brokers' },
        'choria-broker-timeout'      => { type: :integer, label: 'seconds', description: 'seconds' },
        'params'                     => { type: :message, label: 'params', description: 'JSON parameters' },
        'execute'                    => { type: :value, label: 'manifest code' },
        'env-var'                    => { type: :message, label: 'environment variable', description: 'name=value' },
        'filter'                     => { type: :message, label: 'filter', description: 'substring filter' },
        'modules'                    => { type: :message, label: 'modules', description: 'comma separated module names' },
        'plugin'                     => { type: :message, label: 'plugin', description: 'plugin name' }
      }.freeze

      # Static candidate lists for options whose values optparse does not
      # restrict.
      STATIC_VALUES = {
        'rerun'     => %w[all failure success],
        'format'    => %w[human json rainbow],
        'log-level' => Bolt::Logger::LEVELS
      }.freeze

      # Dynamic list sources: the `bolt <command> show --format json` call and
      # the JSON key holding the names.
      LISTS = {
        plans:   { command: 'plan',      json_key: 'plans',   pairs: true },
        tasks:   { command: 'task',      json_key: 'tasks',   pairs: true },
        groups:  { command: 'group',     json_key: 'groups',  pairs: false },
        targets: { command: 'inventory', json_key: 'targets', pairs: false }
      }.freeze

      # Dynamic parameter sources: where `bolt <kind> show <name>` keeps the
      # parameter names in its JSON output.
      PARAMS = {
        plan: { json_path: 'parameters' },
        task: { json_path: 'metadata.parameters' }
      }.freeze
    end
  end
end
