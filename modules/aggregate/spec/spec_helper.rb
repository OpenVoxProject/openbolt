# frozen_string_literal: true

require 'puppet_pal'
require 'rspec-puppet'
require 'bolt_spec/plans'

# Ensure tasks are enabled when rspec-puppet sets up an environment
# so we get task loaders.
Puppet[:tasks] = true

RSpec.configure do |c|
  repo_root = File.expand_path('../../..', __dir__)
  c.module_path = [
    File.expand_path('fixtures/modules', __dir__),
    File.join(repo_root, 'bolt-modules'),
    File.join(repo_root, 'modules')
  ].join(File::PATH_SEPARATOR)
end

# BoltSpec::BoltContext#modulepath wraps RSpec.configuration.module_path in
# a single-element array, which leaves colon-separated paths joined and
# unsplittable by Bolt's module loader. Override it so Bolt sees each
# directory as a distinct entry.
module BoltSpec
  module BoltContext
    def modulepath
      RSpec.configuration.module_path.split(File::PATH_SEPARATOR)
    end
  end
end
