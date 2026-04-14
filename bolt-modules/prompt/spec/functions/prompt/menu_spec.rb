# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'

describe 'prompt::menu' do
  let(:executor)      { Bolt::Executor.new }
  let(:tasks_enabled) { true }

  before(:each) do
    Puppet[:tasks] = tasks_enabled
    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'displays a menu from an array of options' do
    prompt = <<~PROMPT.chomp
      (1) apple
      (2) banana
      (3) carrot
      Select a fruit
    PROMPT

    expect(executor).to receive(:prompt).with(prompt, {}).and_return('1')

    is_expected.to run
      .with_params('Select a fruit', %w[apple banana carrot])
      .and_return('apple')
  end

  it 'displays a menu from a hash of options' do
    prompt = <<~PROMPT.chomp
      (a) apple
      (b) banana
      (c) carrot
      Select a fruit
    PROMPT

    expect(executor).to receive(:prompt).with(prompt, {}).and_return('a')

    is_expected.to run
      .with_params('Select a fruit', { 'a' => 'apple', 'b' => 'banana', 'c' => 'carrot' })
      .and_return('apple')
  end

  it 'aligns values' do
    prompt = <<~PROMPT.chomp
      (a)      apple
      (b)      banana
      (carrot) carrot
      Select a fruit
    PROMPT

    expect(executor).to receive(:prompt).with(prompt, {}).and_return('a')

    is_expected.to run
      .with_params('Select a fruit', { 'a' => 'apple', 'b' => 'banana', 'carrot' => 'carrot' })
      .and_return('apple')
  end

  it 'returns a default value if no input is provided' do
    expect($stdin).to receive(:tty?).and_return(true)
    expect($stdin).to receive(:gets).and_return('')
    expect($stderr).to receive(:print)

    is_expected.to run
      .with_params('Select a fruit', %w[apple banana carrot], 'default' => 'apple')
      .and_return('apple')
  end

  it 'errors if default value is not a valid option' do
    is_expected.to run
      .with_params('Select a fruit', %w[apple banana carrot], 'default' => 'durian')
      .and_raise_error(/Default value 'durian' is not one of the provided menu options/)
  end

  it 'reports the call to analytics' do
    expect(executor).to receive(:report_function_call).with('prompt::menu')
    expect(executor).to receive(:prompt).with("(1) apple\nSelect a fruit", {}).and_return('1')
    is_expected.to run.with_params('Select a fruit', ['apple'])
  end

  context 'without tasks enabled' do
    let(:tasks_enabled) { false }

    it 'fails and reports that prompt is not available' do
      is_expected.to run.with_params('Select a fruit', %w[apple banana carrot])
                        .and_raise_error(/Plan language function 'prompt::menu' cannot be used/)
    end
  end
end
