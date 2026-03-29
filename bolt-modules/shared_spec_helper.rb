# frozen_string_literal: true

require 'voxpupuli/test/spec_helper'

def fixtures(*subdirs)
  File.join('spec', 'fixtures', *subdirs)
end

def make_module_symlink(module_name = File.basename(Dir.pwd))
  target = File.join('spec', 'fixtures', 'modules', module_name)
  RSpec::Puppet::Setup.safe_make_link('.', target, false)
end

def configure_rspec_for_this_module!(module_name = File.basename(Dir.pwd), with_bolt_pal: false)
  # Ensure tasks are enabled when rspec-puppet sets up an environment so we get task loaders.
  Puppet[:tasks] = true
  
  if with_bolt_pal
    require 'bolt/pal'
    Bolt::PAL.load_puppet
  end

  RSpec.configure do |c|
    c.mock_with :mocha
    # Create the module symlink before the suite
    c.before(:all) do
      target = File.join('spec', 'fixtures', 'modules', module_name)
      RSpec::Puppet::Setup.safe_make_link('.', target, false)
    end
    # Delete the module symlink after the suite
    c.after(:all) do
      RSpec::Puppet::Setup.safe_teardown_links(module_name)
    end
  end
end
