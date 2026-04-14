# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'
require 'bolt/error'

describe 'fail_plan' do
  include SpecFixtures

  let(:tasks_enabled) { true }
  let(:executor) { Bolt::Executor.new }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'raises an error from arguments' do
    is_expected.to run.with_params('oops').and_raise_error(Bolt::PlanFailure)
  end

  it 'raises an error from an Error object' do
    error = Puppet::DataTypes::Error.new('oops')
    is_expected.to run.with_params(error).and_raise_error(Bolt::PlanFailure)
  end

  it 'reports the call to analytics' do
    executor = Bolt::Executor.new
    expect(executor).to receive(:report_function_call).with('fail_plan')

    Puppet.override(bolt_executor: executor) do
      is_expected.to run.with_params('foo').and_raise_error(Bolt::PlanFailure)
    end
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that fail_plan is not available' do
      is_expected.to run.with_params('foo')
                        .and_raise_error(/Plan language function 'fail_plan' cannot be used/)
    end
  end
end
