# frozen_string_literal: true

require 'rspec-puppet'

$LOAD_PATH.unshift File.join(__dir__, '..', '..', 'lib')

RSpec.configure do |c|
  repo_root = File.expand_path('../..', __dir__)
  c.module_path = [
    File.join(repo_root, 'bolt-modules'),
    File.join(repo_root, 'modules'),
    repo_root
  ].join(File::PATH_SEPARATOR)
end
