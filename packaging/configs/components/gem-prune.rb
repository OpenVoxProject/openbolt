# frozen_string_literal: true

component 'gem-prune' do |pkg, settings, _platform|
  pkg.build_requires 'openbolt-runtime'

  pkg.add_source('file://resources/rubygems-prune')

  pkg.build do
    "GEM_PATH=\"#{settings[:gem_home]}\" RUBYOPT=\"-Irubygems-prune\" #{settings[:host_gem]} prune"
  end
end
