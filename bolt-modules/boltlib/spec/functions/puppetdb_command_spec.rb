# frozen_string_literal: true

require 'spec_helper'
require 'bolt/executor'

describe 'puppetdb_command' do
  let(:executor)   { Bolt::Executor.new }
  let(:pdb_client) { double('pdb_client') }
  let(:tasks)      { true }

  let(:command)  { 'replace_facts' }
  let(:payload)  { {} }
  let(:version)  { 5 }
  let(:instance) { 'instance' }

  before(:each) do
    Puppet[:tasks] = tasks
    Puppet.push_context(bolt_executor: executor, bolt_pdb_client: pdb_client)
  end

  after(:each) do
    Puppet.pop_context
  end

  it 'calls Bolt::PuppetDB::Client.send_command' do
    expect(pdb_client).to receive(:send_command).with(command, version, payload, nil).and_return('uuid')
    is_expected.to run.with_params(command, version, payload)
  end

  it 'calls Bolt::PuppetDB::Client.send_command with a named instance' do
    expect(pdb_client).to receive(:send_command).with(command, version, payload, instance).and_return('uuid')
    is_expected.to run.with_params(command, version, payload, instance)
  end

  it 'errors if client does not implement :send_command' do
    is_expected.to run
      .with_params(command, version, payload)
      .and_raise_error(/PuppetDB client .* does not implement :send_command/)
  end

  it 'reports the call to analytics' do
    expect(pdb_client).to receive(:send_command).and_return('uuid')
    expect(executor).to receive(:report_function_call).with('puppetdb_command')
    is_expected.to run.with_params(command, version, payload)
  end

  context 'without tasks enabled' do
    let(:tasks) { false }

    it 'errors' do
      is_expected.to run
        .with_params(command, version, payload)
        .and_raise_error(/Plan language function 'puppetdb_command' cannot be used/)
    end
  end
end
