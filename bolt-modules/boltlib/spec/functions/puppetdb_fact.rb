# frozen_string_literal: true

require 'spec_helper'

describe 'puppetdb_fact' do
  include SpecFixtures

  let(:pdb_client) { double('pdb_client') }

  before(:each) do
    Puppet[:tasks] = true
    Puppet.push_context(bolt_pdb_client: pdb_client)
  end

  after(:each) do
    Puppet.pop_context
  end

  context 'it calls puppetdb_facts' do
    let(:facts)    { { 'a.com' => {}, 'b.com' => {} } }
    let(:instance) { 'instance' }

    it 'with list of targets' do
      expect(pdb_client).to receive(:facts_for_node).with(facts.keys).and_return(facts)

      is_expected.to run.with_params(facts.keys).and_return(facts)
    end

    it 'with a named instance' do
      expect(pdb_client).to receive(:facts_for_node).with(facts.keys, instance).and_return(facts)

      is_expected.to run.with_params(facts.keys, instance).and_return(facts)
    end
  end
end
