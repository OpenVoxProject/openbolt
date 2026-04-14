# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/inventory'
require 'bolt/result'
require 'bolt/result_set'
require 'bolt/target'
require 'bolt/task'

describe 'get_resources' do
  include SpecFixtures

  let(:applicator) { double('Bolt::Applicator') }
  let(:executor) { Bolt::Executor.new }
  let(:inventory) { Bolt::Inventory.empty }
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
    let(:hostnames) { %w[a.b.com winrm://x.y.com remote://foo] }
    let(:targets) { hostnames.map { |h| inventory.get_target(h) } }
    let(:query_resources_task) { Bolt::Task.new('query_resources_task') }

    before(:each) do
      allow(applicator).to receive(:build_plugin_tarball).and_return(:tarball)
      allow(applicator).to receive(:query_resources_task).and_return(query_resources_task)
    end

    it 'queries a single resource' do
      results = Bolt::ResultSet.new(
        targets.map { |t| Bolt::Result.new(t, value: { 'some' => 'resources' }) }
      )
      expect(executor).to receive(:run_task).with(targets,
                                       query_resources_task,
                                       hash_including('resources' => ['file'])).and_return(results)

      is_expected.to run.with_params(hostnames, 'file').and_return(results)
    end

    it 'queries requested resources' do
      results = Bolt::ResultSet.new(
        targets.map { |t| Bolt::Result.new(t, value: { 'some' => 'resources' }) }
      )
      resources = ['User', 'File[/tmp]']
      expect(executor).to receive(:run_task).with(targets,
                                       query_resources_task,
                                       hash_including('resources' => resources)).and_return(results)

      is_expected.to run.with_params(hostnames, resources).and_return(results)
    end

    it 'fails if querying resources fails' do
      results = Bolt::ResultSet.new(
        targets.map { |t| Bolt::Result.new(t, error: { 'msg' => 'could not query resources' }) }
      )
      expect(executor).to receive(:run_task).with(targets, query_resources_task, hash_including('plugins')).and_return(results)

      is_expected.to run.with_params(hostnames, []).and_raise_error(
        Bolt::RunFailure, "run_task 'query_resources_task' failed on #{targets.count} targets"
      )
    end

    it 'errors if resource names are invalid' do
      is_expected.to run.with_params(hostnames, 'not a type').and_raise_error(
        Bolt::Error, "not a type is not a valid resource type or type instance name"
      )
    end

    it 'errors if resource names are invalid' do
      is_expected.to run.with_params(hostnames, 'not a type[hello there]').and_raise_error(
        Bolt::Error, "not a type[hello there] is not a valid resource type or type instance name"
      )
    end

    context 'without tasks enabled' do
      let(:tasks_enabled) { false }

      it 'fails and reports that get_resources is not available' do
        is_expected.to run.with_params(hostnames, 'file')
                          .and_raise_error(/Plan language function 'get_resources' cannot be used/)
      end
    end
  end
end
