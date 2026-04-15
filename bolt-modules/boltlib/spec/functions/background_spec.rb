# frozen_string_literal: true

require 'spec_helper'
require 'puppet_pal'
require 'bolt/executor'
require 'bolt/plan_future'

describe 'background' do
  let(:name)      { "Pluralize" }
  let(:object)    { "noodle" }
  let(:future)    { Bolt::PlanFuture.new('foo', name, plan_id: 1234) }
  let(:executor)  { Bolt::Executor.new }

  before(:each) do
    expect(executor).to receive(:get_current_plan_id).and_return(1234)
    Puppet[:tasks] = true
    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'reports the function call to analytics' do
    expect(executor).to receive(:report_function_call).with('background')

    is_expected.to(run
      .with_params(name)
      .with_lambda { 'a' + 'b' })
  end

  it 'returns the PlanFuture the executor creates' do
    expect(executor).to receive(:create_future)
      .with(hash_including(scope: anything, name: name))
      .and_return(future)

    is_expected.to(run
      .with_params(name)
      .with_lambda { 'a' + 'b' }
      .and_return(future))
  end
end
