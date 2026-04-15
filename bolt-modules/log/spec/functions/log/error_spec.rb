# frozen_string_literal: true

require 'spec_helper'

describe 'log::error' do
  let(:executor)      { double('executor', report_function_call: nil, publish_event: nil) }
  let(:tasks_enabled) { true }

  before(:each) do
    Puppet[:tasks] = tasks_enabled

    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'sends a log event to the executor' do
    expect(executor).to receive(:publish_event).with(
      type:    :log,
      level:   :error,
      message: 'This is an error message'
    )

    is_expected.to run.with_params('This is an error message')
  end

  it 'reports function call to analytics' do
    expect(executor).to receive(:report_function_call).with('log::error')
    is_expected.to run.with_params('This is an error message')
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that log::error is not available' do
      is_expected.to run.with_params('This is an error message')
                        .and_raise_error(/Plan language function 'log::error' cannot be used/)
    end
  end
end
