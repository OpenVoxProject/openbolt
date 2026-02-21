# frozen_string_literal: true

source ENV['GEM_SOURCE'] || 'https://rubygems.org'

def location_for(place, fake_version = nil)
  if place.is_a?(String) && place =~ /^((?:git[:@]|https:)[^#]*)#(.*)/
    [fake_version, { git: Regexp.last_match(1), branch: Regexp.last_match(2), require: false }].compact
  elsif place.is_a?(String) && place =~ %r{^file://(.*)}
    ['>= 0', { path: File.expand_path(Regexp.last_match(1)), require: false }]
  else
    [place, { require: false }]
  end
end

# Disable analytics when running in development
ENV['BOLT_DISABLE_ANALYTICS'] = 'true'

# Disable warning that Bolt may be installed as a gem
ENV['BOLT_GEM'] = 'true'

gemspec

# Need to update the openssl gem on MacOS to avoid SSL errors. Doesn't hurt to have the newest
# for all platforms.
# https://www.rubyonmac.dev/certificate-verify-failed-unable-to-get-certificate-crl-openssl-ssl-sslerror
# openssl 4 raises some errors that need to be investigated
gem 'openssl', '~> 3' unless `uname -o`.chomp == 'Cygwin'

# Optional paint gem for rainbow outputter
gem "paint", "~> 2.2"

group(:test) do
  gem "beaker-hostgenerator"
  gem "mocha", '>= 1.4.0', '< 3'
  gem "rack-test", '>= 1', '< 3'
  gem 'rspec-github', require: false
end

group(:release, optional: true) do
  gem 'faraday-retry', '~> 2.1', require: false
  gem 'github_changelog_generator', '~> 1.16.4', require: false
end

group(:packaging) do
  gem 'json'
  gem 'packaging', '~> 0.105'
  gem 'rake'
  gem 'vanagon', *location_for(ENV['VANAGON_LOCATION'] || 'https://github.com/openvoxproject/vanagon#main')
end

local_gemfile = File.join(__dir__, 'Gemfile.local')
if File.exist? local_gemfile
  eval_gemfile local_gemfile
end

# https://github.com/OpenVoxProject/openvox/issues/90
gem 'syslog', '~> 0.3' if RUBY_VERSION >= '3.4'

gem 'puppet_metadata', '>= 5.3', '< 7'

# test puppet_forge branch until it's released
gem 'puppet_forge', github: 'puppetlabs/forge-ruby', branch: 'main'
