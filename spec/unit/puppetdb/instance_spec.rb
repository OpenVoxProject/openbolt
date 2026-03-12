# frozen_string_literal: true

require 'spec_helper'
require 'bolt/puppetdb/instance'

describe Bolt::PuppetDB::Instance do
  let(:token) { 'token' }
  let(:config) do
    {
      'server_urls' => ["https://puppet.example.com:8081"],
      'cacert'      => '/etc/puppetlabs/puppet/ssl/certs/ca.pem',
      'token'       => '~/.puppetlabs/token'
    }
  end
  let(:instance) { described_class.new(config: config) }

  before(:each) do
    allow(File).to receive(:exist?).and_return(true)
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(File.expand_path('~/.puppetlabs/token')).and_return(token)
  end

  context "#headers" do
    it "includes Content-Type" do
      expect(instance.headers).to include('Content-Type' => 'application/json')
    end

    it "includes X-Authentication token" do
      expect(instance.headers).to include('X-Authentication' => token)
    end

    context "with custom headers" do
      let(:config) do
        {
          'server_urls' => ["https://puppet.example.com:8081"],
          'headers'     => { 'Authorization' => 'Bearer info' }
        }
      end

      it "includes custom headers" do
        expect(instance.headers).to include('Authorization' => 'Bearer info')
      end

      it "does not include X-Authentication if no token" do
        # config does not have 'token', so it falls back to DEFAULT_TOKEN.
        # We need to simulate no default token file.
        allow(File).to receive(:exist?).with(Bolt::PuppetDB::Config::DEFAULT_TOKEN).and_return(false)
        expect(instance.headers).not_to have_key('X-Authentication')
      end
    end

    context "with custom headers overlapping Content-Type" do
      let(:config) do
        {
          'server_urls' => ["https://puppet.example.com:8081"],
          'headers'     => { 'Content-Type' => 'application/x-yaml' }
        }
      end

      it "overrides default Content-Type" do
        expect(instance.headers).to include('Content-Type' => 'application/x-yaml')
      end
    end
  end
end
