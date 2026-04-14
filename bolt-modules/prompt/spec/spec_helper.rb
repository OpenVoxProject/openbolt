# frozen_string_literal: true

require 'puppet_pal'
require 'bolt/pal'
require 'bolt/target'
require 'rspec-puppet'

# Ensure tasks are enabled when rspec-puppet sets up an environment
# so we get task loaders.
Puppet[:tasks] = true
Bolt::PAL.load_puppet

RSpec.configure do |c|
  repo_root = File.expand_path('../../..', __dir__)
  c.module_path = [
    File.expand_path("fixtures/modules", __dir__),
    File.join(repo_root, 'bolt-modules'),
    File.join(repo_root, 'modules')
  ].join(File::PATH_SEPARATOR)
end
