# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'

describe 'prompt' do
  let(:executor)      { Bolt::Executor.new }
  let(:prompt)        { 'prompt' }
  let(:response)      { 'response' }
  let(:tasks_enabled) { true }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'returns a String value' do
    expect(executor).to receive(:prompt).with(prompt, {}).and_return(response)
    is_expected.to run.with_params(prompt).and_return(response)
  end

  it 'returns a Sensitive value' do
    expect(executor).to receive(:prompt).with(prompt, { sensitive: true }).and_return(response)

    result = subject.execute(prompt, 'sensitive' => true)

    expect(result.class).to be(Puppet::Pops::Types::PSensitiveType::Sensitive)
    expect(result.unwrap).to eq(response)
  end

  it 'returns a default value if no input is provided' do
    expect($stdin).to receive(:tty?).and_return(true)
    expect($stdin).to receive(:gets).and_return('')
    expect($stderr).to receive(:print)

    is_expected.to run.with_params(prompt, 'default' => response).and_return(response)
  end

  it 'errors if default value is not a string' do
    is_expected.to run
      .with_params(prompt, 'default' => 1)
      .and_raise_error(/Option 'default' must be a string/)
  end

  it 'errors when passed invalid data types' do
    is_expected.to run.with_params(1)
                      .and_raise_error(ArgumentError,
                                       "'prompt' parameter 'prompt' expects a String value, got Integer")
  end

  it 'reports the call to analytics' do
    expect(executor).to receive(:report_function_call).with('prompt')
    expect(executor).to receive(:prompt).with(prompt, {}).and_return(response)
    is_expected.to run.with_params(prompt)
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that prompt is not available' do
      is_expected.to run.with_params(prompt)
                        .and_raise_error(/Plan language function 'prompt' cannot be used/)
    end
  end
end
