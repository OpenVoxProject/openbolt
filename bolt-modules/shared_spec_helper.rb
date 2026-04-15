# frozen_string_literal: true

# Shared spec helper for each bundled Bolt module under bolt-modules/ and
# modules/, plus bolt_spec_spec/. Each module's spec/spec_helper.rb loads
# this file and calls configure_rspec_for_this_module!.

require 'rspec-puppet'
require 'puppet_pal'

BOLT_REPO_ROOT = File.expand_path('..', __dir__)

# Lightweight replacement for puppetlabs_spec_helper's Fixtures#fixtures:
# returns the path to spec/fixtures/<parts> under the current module.
# Callers assume tests run with cwd at the module root (which ci:modules
# arranges).
def fixtures(*parts)
  File.join('spec', 'fixtures', *parts)
end

# Configure rspec-puppet to resolve Puppet modules by pointing at the real
# bolt-modules/ and modules/ directories directly (no symlinking into
# spec/fixtures/modules). Each module's own spec/fixtures/modules is also
# on the path for test-specific fixture modules.
#
# with_bolt_pal - set to true for modules whose specs require Bolt::PAL
#                 to be loaded before puppet functions are evaluated.
def configure_rspec_for_this_module!(with_bolt_pal: false, extra_module_paths: [])
  Puppet[:tasks] = true

  if with_bolt_pal
    require 'bolt/pal'
    Bolt::PAL.load_puppet
  end

  caller_spec_dir = File.dirname(caller_locations(1, 1).first.path)

  RSpec.configure do |c|
    c.module_path = ([
      File.join(caller_spec_dir, 'fixtures', 'modules'),
      File.join(BOLT_REPO_ROOT, 'bolt-modules'),
      File.join(BOLT_REPO_ROOT, 'modules')
    ] + extra_module_paths).join(File::PATH_SEPARATOR)

    # voxpupuli-test turns these on by default. Bolt's module specs were not
    # written against strict variables, and they rely on the real Facter to
    # resolve facts at plan-evaluation time.
    c.strict_variables = false
    c.facter_implementation = :facter if c.respond_to?(:facter_implementation=)
  end
end
