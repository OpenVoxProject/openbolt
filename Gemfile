# frozen_string_literal: true

source ENV['GEM_SOURCE'] || 'https://rubygems.org'

# Disable analytics when running in development
ENV['BOLT_DISABLE_ANALYTICS'] = 'true'

# Disable warning that Bolt may be installed as a gem
ENV['BOLT_GEM'] = 'true'

gemspec

# Optional paint gem for rainbow outputter
gem "paint", "~> 2.2"

group(:test) do
  gem "beaker-hostgenerator"
  gem "mocha", '~> 1.4.0'
  gem "rack-test", '~> 1.0'
  gem 'rspec-github', require: false
end

group(:release, optional: true) do
  gem 'faraday-retry', '~> 2.1', require: false
  gem 'github_changelog_generator', '~> 1.16.4', require: false
end

group(:packaging) do
  gem 'packaging', '~> 0.105'
end

local_gemfile = File.join(__dir__, 'Gemfile.local')
if File.exist? local_gemfile
  eval_gemfile local_gemfile
end

# https://github.com/OpenVoxProject/puppet/issues/90
gem 'syslog', '~> 0.3' if RUBY_VERSION >= '3.4'
