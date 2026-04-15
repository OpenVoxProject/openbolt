# frozen_string_literal: true

require 'spec_helper'

describe 'puppetdb_query' do
  let(:pdb_client) { double('pdb_client') }

  before(:each) do
    Puppet[:tasks] = true
    Puppet.push_context(bolt_pdb_client: pdb_client)
  end

  after(:each) do
    Puppet.pop_context
  end

  context 'it calls puppetdb_facts' do
    let(:query)    { 'inventory {}' }
    let(:result)   { [1, 2, 3] }
    let(:instance) { 'instance' }

    it 'with list of targets' do
      expect(pdb_client).to receive(:make_query).with(query).and_return(result)

      is_expected.to run.with_params(query).and_return(result)
    end

    it 'with a named instance' do
      expect(pdb_client).to receive(:make_query).with(query, instance).and_return(result)

      is_expected.to run.with_params(query, instance).and_return(result)
    end
  end
end
