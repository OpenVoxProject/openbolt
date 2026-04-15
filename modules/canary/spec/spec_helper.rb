# frozen_string_literal: true

require_relative '../../../bolt-modules/shared_spec_helper'
require 'bolt_spec/plans'

configure_rspec_for_this_module!

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
