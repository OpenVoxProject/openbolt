# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/inventory'

describe 'facts' do
  let(:executor) { Bolt::Executor.new }
  let(:inventory) { Bolt::Inventory.empty }
  let(:hostname) { 'example' }
  let(:target) { inventory.get_target(hostname) }

  before(:each) do
    Puppet[:tasks] = true
    Puppet.push_context(bolt_executor: executor, bolt_inventory: inventory)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'should return an empty hash if no facts are set' do
    is_expected.to run.with_params(target).and_return({})
  end

  it 'reports the call to analytics' do
    expect(executor).to receive(:report_function_call).with('facts')
    is_expected.to run.with_params(target)
  end
end
