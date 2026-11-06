# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/files'
require 'bolt_spec/integration'

describe "When plans run other plans" do
  include BoltSpec::Files
  include BoltSpec::Integration

  after(:each) { Puppet.settings.send(:clear_everything_for_tests) }

  let(:config_flags) {
    ['--project', fixtures_path('configs', 'empty'),
     '--modulepath', fixtures_path('nested_plans')]
  }

  it 'runs plans nested 50 levels deep with the default Fiber stack sizes' do
    result = run_cli_json(%w[plan run nested::depth levels=50] + config_flags)
    expect(result).to eq('bottom')
  end

  it 'runs plans nested 50 levels deep when targets are passed positionally' do
    result = run_cli_json(%w[plan run nested::depth_targets targets=localhost levels=50] + config_flags)
    expect(result).to eq('bottom')
  end

  it 'returns the value of next() in a nested plan parameter default to the caller' do
    result = run_cli_json(%w[plan run nested::next_caller] + config_flags)
    expect(result).to eq('caller got 7')
  end
end
