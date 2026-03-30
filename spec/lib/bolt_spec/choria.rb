# frozen_string_literal: true

require 'bolt/inventory'
require 'bolt/transport/choria'
require 'mcollective'
require 'tempfile'

module BoltSpec
  # Shared helper methods for Choria transport specs.
  module Choria
    # Write a minimal Choria config file to a Tempfile. Returns the Tempfile
    # object (call .path to get the path).
    #
    # Default config suppresses log output. Pass overrides as key-value pairs
    # matching Choria config file syntax.
    #
    #   write_choria_config(main_collective: 'production')
    def write_choria_config(**overrides)
      defaults = { logger_type: 'console', loglevel: 'error' }
      config = defaults.merge(overrides)

      file = Tempfile.new(['choria-test', '.conf'])
      config.each { |key, value| file.puts("#{key} = #{value}") }
      file.flush
      file
    end

    # Build a real MCollective::RPC::Result matching the format the
    # RPC client returns. The Result class delegates [] to an internal
    # hash, so code accessing result[:sender], result[:data], etc. works.
    def make_rpc_result(sender:, statuscode: 0, statusmsg: 'OK', data: {})
      identity = sender.is_a?(Bolt::Target) ? transport.choria_identity(sender) : sender
      MCollective::RPC::Result.new('test', 'test',
                                   sender: identity, statuscode: statuscode, statusmsg: statusmsg, data: data)
    end

    # Stub agent discovery for one or more targets. Accumulates across
    # calls so different targets can have different agent lists. Calling
    # again for the same target replaces that target's entry. Instance
    # variables are cleared between `it` blocks.
    #
    # Accepts Bolt::Target objects or host strings, single or as an array.
    # Agents can be strings (version defaults to '1.2.1') or [name, version]
    # pairs for version-specific scenarios.
    #
    #   stub_agents(target, %w[rpcutil shell])
    #   stub_agents(target2, %w[rpcutil bolt_tasks])
    #   stub_agents([target, target2], %w[rpcutil bolt_tasks])
    #   stub_agents(target, [['shell', '1.1.0']], os_family: 'windows')
    def stub_agents(targets, agents, os_family: 'RedHat')
      targets = [targets].flatten

      agent_data = agents.map do |agent|
        name, version = agent.is_a?(Array) ? agent : [agent, '1.2.1']
        { 'agent' => name, 'name' => name, 'version' => version }
      end

      @stub_inventory_results ||= []
      @stub_fact_results ||= []

      # Replace existing entries for these targets (supports re-stubbing)
      new_senders = targets.map { |target| transport.choria_identity(target) }
      @stub_inventory_results.reject! { |result| new_senders.include?(result[:sender]) }
      @stub_fact_results.reject! { |result| new_senders.include?(result[:sender]) }

      targets.each do |target|
        @stub_inventory_results << make_rpc_result(sender: target, data: { agents: agent_data })
        @stub_fact_results << make_rpc_result(sender: target, data: { value: os_family })
      end

      allow(mock_rpc_client).to receive_messages(agent_inventory: @stub_inventory_results, get_fact: @stub_fact_results)
    end

    # --- bolt_tasks result builders ---

    def make_download_result(sender, downloads: 1)
      make_rpc_result(sender: sender, data: { downloads: downloads })
    end

    def make_task_run_result(sender, task_id: 'test-task-id')
      make_rpc_result(sender: sender, data: { task_id: task_id })
    end

    def make_task_status_result(sender, stdout: '{"result":"ok"}', stderr: '', exitcode: 0, completed: true)
      make_rpc_result(sender: sender, data: {
                        completed: completed, exitcode: exitcode, stdout: stdout, stderr: stderr
                      })
    end

    # --- shell agent result builders ---

    def make_shell_run_result(sender, stdout: '', stderr: '', exitcode: 0)
      make_rpc_result(sender: sender, data: { stdout: stdout, stderr: stderr, exitcode: exitcode })
    end

    def make_shell_start_result(sender, handle: 'test-handle-uuid')
      make_rpc_result(sender: sender, data: { handle: handle })
    end

    def make_shell_list_result(sender, handle, status: 'stopped')
      make_rpc_result(sender: sender, data: {
                        jobs: { handle => { 'id' => handle, 'status' => status } }
                      })
    end

    def make_shell_statuses_result(sender, handle, stdout: '', stderr: '', exitcode: 0, status: 'stopped')
      make_rpc_result(sender: sender, data: {
                        statuses: { handle => { 'status' => status, 'stdout' => stdout, 'stderr' => stderr, 'exitcode' => exitcode } }
                      })
    end

    # --- Shell agent stub helpers ---
    # Accept a hash of { target => options }.
    #
    #   stub_shell_start(target => { handle: 'h1' })
    #   stub_shell_start(target => { handle: 'h1' }, target2 => { handle: 'h2' })
    #
    # For single-target convenience with defaults, pass keyword args:
    #   stub_shell_start(stdout: 'ok')
    #   stub_shell_start  # uses target with all defaults

    def stub_shell_run(targets = nil, **kwargs)
      results = normalize_shell_targets(targets, kwargs).map do |sender, opts|
        make_shell_run_result(sender, stdout: '', stderr: '', exitcode: 0, **opts)
      end
      allow(mock_rpc_client).to receive(:run).and_return(results)
    end

    def stub_shell_start(targets = nil, **kwargs)
      results = normalize_shell_targets(targets, kwargs).map do |sender, opts|
        make_shell_start_result(sender, handle: 'test-handle-uuid', **opts)
      end
      allow(mock_rpc_client).to receive(:start).and_return(results)
    end

    def stub_shell_list(targets = nil, **kwargs)
      results = normalize_shell_targets(targets, kwargs).map do |sender, opts|
        handle = opts.delete(:handle) || 'test-handle-uuid'
        make_shell_list_result(sender, handle, status: 'stopped', **opts)
      end
      allow(mock_rpc_client).to receive(:list).and_return(results)
    end

    def stub_shell_status(targets = nil, **kwargs)
      results = normalize_shell_targets(targets, kwargs).map do |sender, opts|
        handle = opts.delete(:handle) || 'test-handle-uuid'
        make_shell_statuses_result(sender, handle,
                                   stdout: '', stderr: '', exitcode: 0, status: 'stopped', **opts)
      end
      allow(mock_rpc_client).to receive(:statuses).and_return(results)
    end

    def stub_shell_kill
      allow(mock_rpc_client).to receive(:kill)
    end

    private

    # Normalize arguments into a hash of { target => options }.
    # If a target-keyed hash is given, use it directly.
    # If only keyword args are given, wrap as { target => kwargs }.
    def normalize_shell_targets(targets, kwargs)
      if targets.is_a?(Hash)
        targets
      else
        { target => kwargs }
      end
    end
  end
end

# Base setup for any Choria transport spec. Provides transport, inventory,
# targets, and the mock RPC client. Resets MCollective singleton state
# between tests so each test starts with a clean config.
RSpec.shared_context 'choria transport' do
  include BoltSpec::Choria

  let(:transport) { Bolt::Transport::Choria.new }
  let(:inventory) { Bolt::Inventory.empty }
  let(:target) { inventory.get_target('choria://node1.example.com') }
  let(:target2) { inventory.get_target('choria://node2.example.com') }

  # Use a plain double rather than instance_double because the real
  # MCollective::RPC::Client dispatches agent actions via method_missing,
  # so methods like :agent_inventory, :ping, :run, etc. are not actually
  # defined on the class and instance_double would reject them.
  let(:mock_rpc_client) do
    mock_options = { filter: { 'identity' => [] } }
    double('MCollective::RPC::Client').tap do |client|
      allow(client).to receive(:identity_filter)
      allow(client).to receive(:discover) { |**flags| mock_options[:filter]['identity'] = flags[:nodes] || [] }
      allow(client).to receive(:progress=)
      allow(client).to receive(:options).and_return(mock_options)
    end
  end

  before(:each) do
    # Reset MCollective singleton state so each test starts clean.
    @choria_config_file = write_choria_config
    mc_config = MCollective::Config.instance
    mc_config.set_config_defaults(@choria_config_file.path)
    mc_config.instance_variable_set(:@configured, false)
    MCollective::PluginManager.clear

    # Point targets at the temp config so configure_client uses it
    # instead of auto-detecting from the filesystem.
    inventory.set_config(target, 'transport', 'choria')
    inventory.set_config(target, %w[choria config-file], @choria_config_file.path)
    inventory.set_config(target2, 'transport', 'choria')
    inventory.set_config(target2, %w[choria config-file], @choria_config_file.path)

    # Stub the RPC client constructor. This is the only MCollective
    # stub we need -- it prevents the real client from connecting to
    # NATS via TCP during construction.
    allow(MCollective::RPC::Client).to receive(:new).and_return(mock_rpc_client)

    # Stub sleep so polling loops don't actually wait.
    allow(transport).to receive(:sleep)

    # Default OS detection stub. Tests that need a different OS family
    # (e.g. Windows) can override via stub_agents with os_family: param.
    allow(mock_rpc_client).to receive(:get_fact).and_return([
                                                              make_rpc_result(sender: target, data: { value: 'RedHat' }),
                                                              make_rpc_result(sender: target2, data: { value: 'RedHat' })
                                                            ])
  end

  after(:each) do
    @choria_config_file&.close!
  end
end

# Configures the client for multi-target tests.
RSpec.shared_context 'choria multi-target' do
  before(:each) do
    transport.configure_client(target)
  end
end

# Task object and metadata for task execution tests.
RSpec.shared_context 'choria task' do
  let(:task_name) { 'mymod::mytask' }
  let(:task_executable) { '/path/to/mymod/tasks/mytask.sh' }
  let(:task_content) { "#!/bin/bash\necho '{\"result\": \"ok\"}'" }
  let(:task) do
    Bolt::Task.new(
      task_name,
      { 'input_method' => 'both' },
      [{ 'name' => 'mytask.sh', 'path' => task_executable }]
    )
  end

  # Task with only a Linux (shell) implementation.
  let(:linux_only_task) do
    Bolt::Task.new(
      'mymod::linuxtask',
      {
        'input_method' => 'both',
        'implementations' => [
          { 'name' => 'linuxtask.sh', 'requirements' => ['shell'] }
        ]
      },
      [{ 'name' => 'linuxtask.sh', 'path' => '/path/to/linuxtask.sh' }]
    )
  end

  # Task with only a Windows (PowerShell) implementation.
  let(:windows_only_task) do
    Bolt::Task.new(
      'mymod::wintask',
      {
        'input_method' => 'both',
        'implementations' => [
          { 'name' => 'wintask.ps1', 'requirements' => ['powershell'] }
        ]
      },
      [{ 'name' => 'wintask.ps1', 'path' => '/path/to/wintask.ps1' }]
    )
  end

  # Task with implementations for both platforms.
  let(:cross_platform_task) do
    Bolt::Task.new(
      'mymod::crosstask',
      {
        'input_method' => 'both',
        'implementations' => [
          { 'name' => 'crosstask.ps1', 'requirements' => ['powershell'] },
          { 'name' => 'crosstask.sh', 'requirements' => ['shell'] }
        ]
      },
      [
        { 'name' => 'crosstask.ps1', 'path' => '/path/to/crosstask.ps1' },
        { 'name' => 'crosstask.sh', 'path' => '/path/to/crosstask.sh' }
      ]
    )
  end
end

# File system stubs for task executables. Stubs SHA256, File.size,
# File.binread, File.basename, and SecureRandom.uuid so both
# bolt_tasks (download manifest) and shell (file upload) paths work.
RSpec.shared_context 'choria task file stubs' do
  before(:each) do
    mock_digest = instance_double(Digest::SHA256, hexdigest: Digest::SHA256.hexdigest(task_content))
    allow(Digest::SHA256).to receive(:file).and_call_original
    allow(Digest::SHA256).to receive(:file).with(task_executable).and_return(mock_digest)
    allow(File).to receive(:size).and_call_original
    allow(File).to receive(:size).with(task_executable).and_return(task_content.bytesize)
    allow(File).to receive(:binread).and_call_original
    allow(File).to receive(:binread).with(task_executable).and_return(task_content)
    allow(File).to receive(:basename).and_call_original
    allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
  end
end

# File system stubs for script execution tests. Expects script_path and
# script_content to be defined via let in the including context.
RSpec.shared_context 'choria script file stubs' do
  before(:each) do
    allow(File).to receive(:binread).and_call_original
    allow(File).to receive(:binread).with(script_path).and_return(script_content)
    allow(File).to receive(:basename).and_call_original
    allow(File).to receive(:basename).with(script_path).and_return(File.basename(script_path))
    allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
  end
end
