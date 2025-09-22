# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/conn'
require 'bolt_spec/env_var'
require 'bolt_spec/files'
require 'bolt_spec/integration'

describe 'lookup' do
  include BoltSpec::EnvVar
  include BoltSpec::Files
  include BoltSpec::Integration

  let(:project)      { fixtures_path('hiera') }
  let(:hiera_config) { File.join(project, 'hiera.yaml') }
  let(:plan)         { 'test::lookup' }

  after(:each) do
    Puppet.settings.send(:clear_everything_for_tests)
  end

  context 'plan function' do
    let(:cli_command) {
      %W[plan run #{plan} --project #{project} --hiera-config #{hiera_config}]
    }

    context 'with plan_hiera' do
      let(:hiera_config) { File.join(project, 'plan_hiera.yaml') }
      let(:plan)         { 'test::plan_lookup' }
      let(:uri)          { 'localhost' }

      it 'uses plan_hierarchy outside apply block, and hierarchy in apply block' do
        result = run_cli_json(cli_command + %W[-t #{uri} --log-level debug --trace --verbose])
        expect(result['outside_apply']).to eq('goes the weasel')
        expect(result['in_apply'].keys).to include('Notify[tarts]')
      end
    end

    context 'with invalid plan_hierarchy' do
      let(:hiera_config) { File.join(project, 'plan_hiera_facts.yaml') }
      let(:plan)         { 'test::plan_lookup' }
      let(:uri)          { 'localhost' }

      it 'errors with a missing key' do
        result = run_cli_json(cli_command + %W[-t #{uri}])
        expect(result).to include(
          'kind' => 'bolt/pal-error',
          'msg'  => "Function lookup() did not find a value for the name 'pop'"
        )
      end
    end
  end
end
