# frozen_string_literal: true

require 'spec_helper'
require 'puppet_pal'
require 'bolt/executor'
require 'bolt/plan_future'

describe 'wait' do
  let(:name)      { "Pluralize" }
  let(:future)    { Bolt::PlanFuture.new('foo', name, plan_id: 1234) }
  let(:executor)  { Bolt::Executor.new }
  let(:result)    { ['return'] }
  let(:timeout)   { 2 }
  let(:options)   { { '_catch_errors' => true } }
  let(:sym_opts)  { { catch_errors: true } }

  before(:each) do
    Puppet[:tasks] = true
    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'reports the function call to analytics' do
    expect(executor).to receive(:report_function_call).with('wait')
    expect(executor).to receive(:wait).with([future]).and_return(result)

    is_expected.to(run
      .with_params(future))
  end

  context 'with no futures' do
    it "passes 'nil' to the executor" do
      expect(executor).to receive(:wait).with(nil).and_return(result)

      is_expected.to(run
        .and_return(result))
    end

    it 'accepts just a timeout' do
      expect(executor).to receive(:wait)
        .with(nil, timeout: 2).and_return(result)

      is_expected.to(run
        .with_params(2)
        .and_return(result))
    end

    it 'accepts just options' do
      expect(executor).to receive(:wait)
        .with(nil, catch_errors: true).and_return(result)

      is_expected.to(run
        .with_params('_catch_errors' => true)
        .and_return(result))
    end

    it 'accepts a timeout and options' do
      expect(executor).to receive(:wait)
        .with(nil, timeout: 2, catch_errors: true).and_return(result)

      is_expected.to(run
        .with_params(2, '_catch_errors' => true)
        .and_return(result))
    end
  end

  it 'turns a single object into an array' do
    expect(executor).to receive(:wait).with([future]).and_return(result)

    is_expected.to(run
      .with_params(future)
      .and_return(result))
  end

  it 'runs with a timeout specified' do
    expect(executor).to receive(:wait)
      .with([future], { timeout: timeout }).and_return(result)

    is_expected.to(run
      .with_params(future, timeout)
      .and_return(result))
  end

  it 'runs with only options specified' do
    expect(executor).to receive(:wait)
      .with([future], sym_opts).and_return(result)

    is_expected.to(run
      .with_params(future, options)
      .and_return(result))
  end

  it 'runs with timeout and options specified' do
    expect(executor).to receive(:wait)
      .with([future], sym_opts.merge({ timeout: timeout })).and_return(result)

    is_expected.to(run
      .with_params(future, timeout, options)
      .and_return(result))
  end

  it 'filters out invalid options' do
    expect(executor).to receive(:wait).with([future]).and_return(result)
    expect(Bolt::Logger).to receive(:warn)
      .with('plan_function_options', anything)

    is_expected.to(run
      .with_params(future, { 'timeout' => 2 })
      .and_return(result))
  end
end
