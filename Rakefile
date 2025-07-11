# frozen_string_literal: true

# rubocop:disable Lint/SuppressedException
begin
  # Needed for Vanagon component ship job. Jenkins automatically sets 'BUILD_ID'.
  # Packaging tasks should not be loaded unless running in Jenkins.
  if ENV['BUILD_ID']
    require 'packaging'
    Pkg::Util::RakeUtils.load_packaging_tasks
  end
rescue LoadError
end
# rubocop:enable Lint/SuppressedException

desc "Update Bolt's changelog for release"
task :changelog, [:version] do |_t, args|
  sh "scripts/generate_changelog.rb #{args[:version]}"
end

desc "Check for new versions of bundled modules"
task :update_modules do
  sh "scripts/update_modules.rb"
end

begin
  require 'voxpupuli/rubocop/rake'
rescue LoadError
  # the voxpupuli-rubocop gem is optional
end
