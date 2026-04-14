# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'

describe 'catch_errors' do
  let(:executor) { Bolt::Executor.new }
  let(:tasks_enabled) { true }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'reports the call to analytics' do
    expect(executor).to receive(:report_function_call).with('catch_errors')
    is_expected.to(run
      .with_lambda { 'abcd' })
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that catch_errors is not available' do
      is_expected.to run
        .with_lambda { puts 'hi' }
        .and_raise_error(/Plan language function 'catch_errors' cannot be used/)
    end
  end
end
