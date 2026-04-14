# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require_relative '../../bolt-modules/shared_spec_helper'

# bolt_spec_spec lives directly under the repo root, so we need the repo root
# on the modulepath for the bolt_spec_spec module itself to be discoverable.
configure_rspec_for_this_module!(extra_module_paths: [BOLT_REPO_ROOT])
