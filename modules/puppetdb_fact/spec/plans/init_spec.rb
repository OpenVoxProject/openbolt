# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/plans'
require 'bolt/target'

describe 'puppetdb_fact' do
  include BoltSpec::Plans

  let(:facts) {
    {
      'foo' => { 'fqdn' => 'foo', 'osfamily' => 'RedHat' },
      'bar' => { 'fqdn' => 'bar', 'osfamily' => 'windows' },
      'baz' => { 'fqdn' => 'baz', 'osfamily' => 'Darwin' }
    }
  }

  it 'returns facts from PuppetDB' do
    expect(puppetdb_client).to receive(:facts_for_node).with(facts.keys, nil).and_return(facts)
    result = run_plan('puppetdb_fact', 'targets' => facts.keys)
    expect(result).to eq(Bolt::PlanResult.new(facts, 'success'))
  end

  it 'adds facts to Targets' do
    expect(puppetdb_client).to receive(:facts_for_node).with(facts.keys, nil).and_return(facts)
    run_plan('puppetdb_fact', 'targets' => facts.keys)
    facts.each do |k, v|
      expect(inventory.facts(Bolt::Target.new(k))).to eq(v)
    end
  end

  it 'returns an empty hash for an empty list' do
    expect(puppetdb_client).to receive(:facts_for_node).with([], nil).and_return({})
    result = run_plan('puppetdb_fact', 'targets' => [])
    expect(result).to eq(Bolt::PlanResult.new({}, 'success'))
  end
end
