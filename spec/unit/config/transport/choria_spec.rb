# frozen_string_literal: true

require 'spec_helper'
require 'bolt/config/transport/choria'
require 'shared_examples/transport_config'

describe Bolt::Config::Transport::Choria do
  let(:transport) { Bolt::Config::Transport::Choria }
  let(:data) { { 'host' => 'node1.example.com' } }
  let(:merge_data) { { 'tmpdir' => '/var/tmp' } }

  include_examples 'transport config'
  include_examples 'filters options'

  context 'using plugins' do
    let(:plugin_data)   { { 'host' => { '_plugin' => 'foo' } } }
    let(:resolved_data) { { 'host' => 'foo' } }

    include_examples 'plugins'
  end

  context 'validating' do
    include_examples 'interpreters'

    %w[choria-agent config-file collective host puppet-environment ssl-ca ssl-cert ssl-key tmpdir].each do |opt|
      it "#{opt} rejects non-string value" do
        data[opt] = 100
        expect { transport.new(data) }.to raise_error(Bolt::ValidationError)
      end
    end

    %w[command-timeout nats-connection-timeout rpc-timeout task-timeout].each do |opt|
      it "#{opt} rejects non-integer value" do
        data[opt] = 'not_an_integer'
        expect { transport.new(data) }.to raise_error(Bolt::ValidationError)
      end
    end

    it 'nats-servers accepts a string' do
      data['nats-servers'] = 'nats://broker:4222'
      expect { transport.new(data) }.not_to raise_error
    end

    it 'nats-servers accepts an array' do
      data['nats-servers'] = ['nats://broker1:4222', 'nats://broker2:4222']
      expect { transport.new(data) }.not_to raise_error
    end

    it 'nats-servers errors with wrong type' do
      data['nats-servers'] = 12345
      expect { transport.new(data) }.to raise_error(Bolt::ValidationError)
    end

    it 'cleanup errors with wrong type' do
      data['cleanup'] = 'true'
      expect { transport.new(data) }.to raise_error(Bolt::ValidationError)
    end

    it 'choria-agent rejects invalid values' do
      data['choria-agent'] = 'not-an-agent'
      expect { transport.new(data) }.to raise_error(Bolt::ValidationError, /choria-agent must be one of/)
    end

    %w[bolt_tasks shell].each do |agent|
      it "choria-agent accepts '#{agent}'" do
        data['choria-agent'] = agent
        expect { transport.new(data) }.not_to raise_error
      end
    end

    it 'rejects partial SSL overrides (only ssl-ca)' do
      data['ssl-ca'] = '/path/to/ca.pem'
      expect { transport.new(data) }.to raise_error(Bolt::ValidationError, /ssl-cert, ssl-key/)
    end

    it 'rejects partial SSL overrides (missing ssl-key)' do
      data['ssl-ca'] = '/path/to/ca.pem'
      data['ssl-cert'] = '/path/to/cert.pem'
      expect { transport.new(data) }.to raise_error(Bolt::ValidationError, /ssl-key/)
    end

    it 'accepts complete SSL overrides' do
      data['ssl-ca'] = '/path/to/ca.pem'
      data['ssl-cert'] = '/path/to/cert.pem'
      data['ssl-key'] = '/path/to/key.pem'
      expect { transport.new(data) }.not_to raise_error
    end

    it 'tmpdir rejects relative paths' do
      data['tmpdir'] = 'relative/path'
      expect { transport.new(data) }.to raise_error(Bolt::ValidationError, /absolute path/)
    end

    it 'tmpdir accepts absolute paths' do
      data['tmpdir'] = '/var/tmp/bolt'
      expect { transport.new(data) }.not_to raise_error
    end

    it 'tmpdir accepts Windows absolute paths with C: drive' do
      data['tmpdir'] = 'C:\temp'
      expect { transport.new(data) }.not_to raise_error
    end

    it 'tmpdir rejects relative backslash paths' do
      data['tmpdir'] = 'relative\path'
      expect { transport.new(data) }.to raise_error(Bolt::ValidationError, /absolute path/)
    end
  end
end
