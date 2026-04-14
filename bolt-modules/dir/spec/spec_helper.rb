# frozen_string_literal: true

require 'puppet_pal'
require 'rspec-puppet'

# Ensure tasks are enabled when rspec-puppet sets up an environment
# so we get task loaders.
Puppet[:tasks] = true

# Lightweight replacement for puppetlabs_spec_helper's Fixtures module:
# fixtures('modules', 'test') resolves to spec/fixtures/modules/test.
module SpecFixtures
  FIXTURES_ROOT = File.expand_path('fixtures', __dir__).freeze

  def fixtures(*parts)
    File.join(FIXTURES_ROOT, *parts)
  end
end

RSpec.configure do |c|
  repo_root = File.expand_path('../../..', __dir__)
  c.module_path = [
    File.expand_path("fixtures/modules", __dir__),
    File.join(repo_root, 'bolt-modules'),
    File.join(repo_root, 'modules')
  ].join(File::PATH_SEPARATOR)
end
