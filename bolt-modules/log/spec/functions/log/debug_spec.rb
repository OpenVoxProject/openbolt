# frozen_string_literal: true

require 'spec_helper'

describe 'log::debug' do
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
      level:   :debug,
      message: 'This is a debug message'
    )

    is_expected.to run.with_params('This is a debug message')
  end

  it 'reports function call to analytics' do
    expect(executor).to receive(:report_function_call).with('log::debug')
    is_expected.to run.with_params('This is a debug message')
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that log::debug is not available' do
      is_expected.to run.with_params('This is a debug message')
                        .and_raise_error(/Plan language function 'log::debug' cannot be used/)
    end
  end
end
