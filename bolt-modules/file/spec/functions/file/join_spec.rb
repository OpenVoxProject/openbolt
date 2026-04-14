# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'

describe 'file::join' do
  let(:executor) { Bolt::Executor.new }

  before(:each) do
    Puppet[:tasks] = true
    Puppet.push_context(bolt_executor: executor)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'joins file paths' do
    is_expected.to run.with_params('foo', 'bar', 'bak').and_return('foo/bar/bak')
  end

  it 'reports function call to analytics' do
    expect(executor).to receive(:report_function_call).with('file::join')
    is_expected.to run.with_params('foo', 'bar', 'bak')
  end
end
