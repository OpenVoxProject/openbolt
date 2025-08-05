# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/config'
require 'bolt_spec/pal'
require 'bolt/pal'

describe 'Target DataType' do
  include BoltSpec::Config
  include BoltSpec::PAL

  before(:all) { Bolt::PAL.load_puppet }
  after(:each) { Puppet.settings.send(:clear_everything_for_tests) }

  let(:pal)             { make_pal }
  let(:inventory)       { make_inventory }
  let(:default_config)  { make_config.transports['ssh'].to_h }
  let(:target_code)     { "$target = Target('ssh://user1:pass1@example.com:33')\n" }

  def target(attr)
    code = target_code + attr
    peval(code, pal, nil, inventory)
  end

  it 'should expose uri' do
    expect(target('$target.uri')).to eq('ssh://user1:pass1@example.com:33')
  end

  it 'should expose name' do
    expect(target('$target.name')).to eq('ssh://user1:pass1@example.com:33')
  end

  it 'should expose host' do
    expect(target('$target.host')).to eq('example.com')
  end

  it 'should expose protocol' do
    expect(target('$target.protocol')).to eq('ssh')
  end

  it 'should expose port' do
    expect(target('$target.port')).to eq(33)
  end

  it 'should expose user' do
    expect(target('$target.user')).to eq('user1')
  end

  it 'should expose password' do
    expect(target('$target.password')).to eq('pass1')
  end

  it 'should expose transport' do
    expect(target('$target.transport')).to eq('ssh')
  end

  it 'should expose transport_config' do
    expect(target('$target.transport_config')).to eq(default_config)
  end
end
