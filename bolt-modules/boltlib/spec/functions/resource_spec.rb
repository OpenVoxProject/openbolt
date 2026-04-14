# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/inventory'

describe 'resource' do
  let(:executor) { Bolt::Executor.new }
  let(:inventory) { Bolt::Inventory.empty }
  let(:hostname) { 'example' }
  let(:target) { inventory.get_target(hostname) }
  let(:hash) { { 'target' => target, 'type' => 'Package', 'title' => 'openssl' } }
  let(:resource) { Bolt::ResourceInstance.new(hash) }

  before(:each) do
    Puppet[:tasks] = true
    Puppet.push_context(bolt_executor: executor, bolt_inventory: inventory)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'should return nil if the resource is not found' do
    is_expected.to run.with_params(target, 'Foo', 'bar').and_return(nil)
  end

  it 'should return the resource if it is found' do
    target.set_resource(resource)
    is_expected.to run.with_params(*hash.values)
                      .and_return(resource)
  end

  it 'reports the call to analytics' do
    expect(executor).to receive(:report_function_call).with('resource')
    is_expected.to run.with_params(target, 'Foo', 'bar')
  end
end
