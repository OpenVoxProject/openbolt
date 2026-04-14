# frozen_string_literal: true

require 'spec_helper'
require 'bolt/analytics'
require 'bolt/executor'
require 'bolt/inventory'
require 'bolt/plugin'
require 'bolt/result'
require 'bolt/result_set'
require 'bolt/target'
require 'bolt/task'

describe 'apply_prep' do
  include SpecFixtures

  let(:applicator)    { double('Bolt::Applicator') }
  let(:config)        { Bolt::Config.default }
  let(:executor)      { Bolt::Executor.new }
  let(:plugins)       { Bolt::Plugin.new(config, nil) }
  let(:plugin_result) { {} }
  let(:task_hook)     { proc { |_opts, target, _fun| proc { Bolt::Result.new(target, value: plugin_result) } } }
  let(:inventory)     { Bolt::Inventory.create_version({}, config.transport, config.transports, plugins) }
  let(:tasks_enabled) { true }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    allow(executor).to receive(:noop).and_return(false)

    Puppet.push_context(bolt_executor: executor, bolt_inventory: inventory, apply_executor: applicator)
  end

  after(:each) do
    Puppet.pop_context
  end

  context 'with targets' do
    let(:hostnames)         { %w[a.b.com winrm://x.y.com remote://foo] }
    let(:targets)           { hostnames.map { |h| inventory.get_target(h) } }
    let(:unknown_targets)   { targets.reject { |target| target.protocol == 'remote' } }
    let(:fact)              { { 'osfamily' => 'none' } }
    let(:custom_facts_task) { Bolt::Task.new('custom_facts_task') }
    let(:version_task)      { Bolt::Task.new('openvox_bootstrap::check') }
    let(:install_task)      { Bolt::Task.new('openvox_bootstrap::install') }
    let(:service_task)      { Bolt::Task.new('service') }

    before(:each) do
      allow(applicator).to receive(:build_plugin_tarball).and_return(:tarball)
      allow(applicator).to receive(:custom_facts_task).and_return(custom_facts_task)
      inventory.get_targets(targets)
      targets.each { |t| inventory.set_feature(t, 'puppet-agent', false) }

      task1 = double('version_task')
      allow(task1).to receive(:task_hash).and_return('name' => 'openvox_bootstrap::check')
      allow(task1).to receive(:runnable_with?).and_return(true)
      allow_any_instance_of(Puppet::Pal::ScriptCompiler).to receive(:task_signature).with('openvox_bootstrap::check').and_return(task1)
      task2 = double('install_task')
      allow(task2).to receive(:task_hash).and_return('name' => 'openvox_bootstrap::install')
      allow(task2).to receive(:runnable_with?).and_return(true)
      allow_any_instance_of(Puppet::Pal::ScriptCompiler).to receive(:task_signature).with('openvox_bootstrap::install').and_return(task2)
      task3 = double('service_task')
      allow(task3).to receive(:task_hash).and_return('name' => 'service')
      allow(task3).to receive(:runnable_with?).and_return(true)
      allow_any_instance_of(Puppet::Pal::ScriptCompiler).to receive(:task_signature).with('service').and_return(task3)
    end

    it 'sets puppet-agent feature and gathers facts' do
      facts = Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: fact) })
      expect(executor).to receive(:run_task)
              .with(anything, custom_facts_task, hash_including('plugins'), {})
              .and_return(facts)

      expect(plugins).to receive(:get_hook)
             .twice
             .with("openvox_bootstrap", :puppet_library)
             .and_return(task_hook)

      is_expected.to run.with_params(hostnames.join(','))
      targets.each do |target|
        expect(inventory.features(target)).to include('puppet-agent') unless target.transport == 'remote'
        expect(inventory.facts(target)).to eq(fact)
      end
    end

    it 'escalates if provided _run_as' do
      facts = Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: fact) })
      expect(executor).to receive(:run_task)
              .with(anything, custom_facts_task, hash_including('plugins'), { '_run_as' => 'root' })
              .and_return(facts)

      expect(plugins).to receive(:get_hook)
             .twice
             .with("openvox_bootstrap", :puppet_library)
             .and_return(task_hook)

      is_expected.to run.with_params(hostnames, '_run_as' => 'root')
      targets.each do |target|
        expect(inventory.features(target)).to include('puppet-agent') unless target.transport == 'remote'
        expect(inventory.facts(target)).to eq(fact)
      end
    end

    it 'ignores unsupported metaparameters' do
      facts = Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: fact) })
      expect(executor).to receive(:run_task)
              .with(anything, custom_facts_task, hash_including('plugins'), {})
              .and_return(facts)

      expect(plugins).to receive(:get_hook)
             .twice
             .with("openvox_bootstrap", :puppet_library)
             .and_return(task_hook)

      is_expected.to run.with_params(hostnames, '_noop' => true)
      targets.each do |target|
        expect(inventory.features(target)).to include('puppet-agent') unless target.transport == 'remote'
        expect(inventory.facts(target)).to eq(fact)
      end
    end

    it 'fails if fact gathering fails' do
      results = Bolt::ResultSet.new(
        targets.map { |t| Bolt::Result.new(t, error: { 'msg' => 'could not gather facts' }) }
      )
      expect(executor).to receive(:run_task)
              .with(anything, custom_facts_task, hash_including('plugins'), {})
              .and_return(results)

      expect(plugins).to receive(:get_hook)
             .twice
             .with("openvox_bootstrap", :puppet_library)
             .and_return(task_hook)

      is_expected.to run.with_params(hostnames).and_raise_error(
        Bolt::RunFailure, "run_task 'custom_facts_task' failed on #{targets.count} targets"
      )
    end

    context 'with configured plugin' do
      let(:hostname) { 'agentless' }
      let(:data) {
        {
          'targets' => [{
            'name' => hostname,
            'plugin_hooks' => {
              'puppet_library' => {
                'plugin' => 'task',
                'task' => 'openvox_bootstrap::install'
              }
            }
          }]
        }
      }
      let(:inventory) { Bolt::Inventory.create_version(data, config.transport, config.transports, plugins) }
      let(:target)    { inventory.get_targets(hostname)[0] }

      it 'installs the agent if not present' do
        facts = Bolt::ResultSet.new([Bolt::Result.new(target, value: fact)])
        expect(executor).to receive(:run_task)
                .with([target], custom_facts_task, hash_including('plugins'), {})
                .and_return(facts)

        expect(plugins).to receive(:get_hook)
               .with("task", :puppet_library)
               .and_return(task_hook)

        is_expected.to run.with_params(hostname)
        expect(inventory.features(target)).to include('puppet-agent')
        expect(inventory.facts(target)).to eq(fact)
      end
    end

    context 'with default plugin inventory v2' do
      let(:hostname) { 'agentless' }
      let(:data) {
        {
          'targets' => [{ 'uri' => hostname }]
        }
      }

      let(:config)    { Bolt::Config.default }
      let(:pal)       { nil }
      let(:plugins)   { Bolt::Plugin.new(config, pal) }
      let(:inventory) { Bolt::Inventory.create_version(data, config.transport, config.transports, plugins) }
      let(:target)    { inventory.get_target(hostname) }
      let(:targets)   { inventory.get_targets(hostname) }

      it 'installs the agent if not present' do
        facts = Bolt::ResultSet.new([Bolt::Result.new(target, value: fact)])
        expect(executor).to receive(:run_task)
                .with([target], custom_facts_task, hash_including('plugins'), {})
                .and_return(facts)

        expect(plugins).to receive(:get_hook)
               .with('openvox_bootstrap', :puppet_library)
               .and_return(task_hook)

        is_expected.to run.with_params(hostname)
        expect(inventory.features(target)).to include('puppet-agent')
        expect(inventory.facts(target)).to eq(fact)
      end
    end
  end

  context 'with only remote targets' do
    let(:hostnames)         { %w[remote://foo remote://bar] }
    let(:targets)           { hostnames.map { |h| inventory.get_target(h) } }
    let(:fact)              { { 'osfamily' => 'none' } }
    let(:custom_facts_task) { Bolt::Task.new('custom_facts_task') }

    before(:each) do
      allow(applicator).to receive(:build_plugin_tarball).and_return(:tarball)
      allow(applicator).to receive(:custom_facts_task).and_return(custom_facts_task)
    end

    it 'sets feature and gathers facts' do
      facts = Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: fact) })
      expect(executor).to receive(:run_task)
              .with(targets, custom_facts_task, hash_including('plugins'), {})
              .and_return(facts)

      is_expected.to run.with_params(hostnames.join(','))
      targets.each do |target|
        expect(inventory.features(target)).to include('puppet-agent') unless target.transport == 'remote'
        expect(inventory.facts(target)).to eq(fact)
      end
    end
  end

  context 'with targets assigned the puppet-agent feature' do
    let(:hostnames)         { %w[foo bar] }
    let(:targets)           { hostnames.map { |h| inventory.get_target(h) } }
    let(:fact)              { { 'osfamily' => 'none' } }
    let(:custom_facts_task) { Bolt::Task.new('custom_facts_task') }

    before(:each) do
      allow(applicator).to receive(:build_plugin_tarball).and_return(:tarball)
      allow(applicator).to receive(:custom_facts_task).and_return(custom_facts_task)
      targets.each { |target| inventory.set_feature(target, 'puppet-agent') }
    end

    it 'sets feature and gathers facts' do
      facts = Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: fact) })
      expect(executor).to receive(:run_task)
              .with(targets, custom_facts_task, hash_including('plugins'), {})
              .and_return(facts)

      is_expected.to run.with_params(hostnames.join(','))
      targets.each do |target|
        expect(inventory.features(target)).to include('puppet-agent')
        expect(inventory.facts(target)).to eq(fact)
      end
    end
  end

  context 'with required_modules specified' do
    let(:hostnames)         { %w[foo bar] }
    let(:targets)           { hostnames.map { |h| inventory.get_target(h) } }
    let(:fact)              { { 'osfamily' => 'none' } }
    let(:custom_facts_task) { Bolt::Task.new('custom_facts_task') }

    before(:each) do
      allow(applicator).to receive(:build_plugin_tarball).and_return(:tarball)
      allow(applicator).to receive(:custom_facts_task).and_return(custom_facts_task)
      targets.each { |target| inventory.set_feature(target, 'puppet-agent') }
    end

    it 'only uses required plugins' do
      facts = Bolt::ResultSet.new(targets.map { |t| Bolt::Result.new(t, value: fact) })
      expect(executor).to receive(:run_task)
              .with(anything, custom_facts_task, hash_including('plugins'), {})
              .and_return(facts)

      allow(Puppet).to receive(:debug)
      expect(Puppet).to receive(:debug).with("Syncing only required modules: non-existing-module.")
      is_expected.to run.with_params(hostnames,
                                     '_required_modules' => ['non-existing-module'])
    end
  end

  context 'with _catch_errors specified' do
    let(:custom_facts_task) { Bolt::Task.new('custom_facts_task') }
    let(:host)              { 'target' }
    let(:targets)           { inventory.get_targets([host]) }
    let(:result)            { Bolt::Result.new(targets.first, value: task_result) }
    let(:resultset)         { Bolt::ResultSet.new([result]) }

    before(:each) do
      allow(applicator).to receive(:build_plugin_tarball).and_return(:tarball)
      allow(applicator).to receive(:custom_facts_task).and_return(custom_facts_task)

      expect(plugins).to receive(:get_hook)
             .with("openvox_bootstrap", :puppet_library)
             .and_return(task_hook)
    end

    context 'with failing hook' do
      let(:plugin_result) { { '_error' => { 'msg' => 'failure' } } }

      it 'continues executing' do
        is_expected.to run.with_params(host, '_catch_errors' => true)
      end
    end

    context 'with failing fact retrieval' do
      let(:plugin_result) { {} }
      let(:task_result)   { { '_error' => { 'msg' => 'failure' } } }

      it 'continues executing' do
        expect(executor).to receive(:run_task)
                .with(targets, custom_facts_task, hash_including('plugins'), { '_catch_errors' => true })
                .and_return(resultset)

        is_expected.to run.with_params(host, '_catch_errors' => true)
      end
    end
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that apply_prep is not available' do
      is_expected.to run.with_params('foo')
                        .and_raise_error(/Plan language function 'apply_prep' cannot be used/)
    end
  end
end
