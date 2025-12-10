component 'gem-prune' do |pkg, settings, platform|
  pkg.build_requires 'bolt-runtime'

  pkg.add_source('file://resources/rubygems-prune')

  pkg.build do
    "GEM_PATH=\"#{settings[:gem_home]}\" RUBYOPT=\"-Irubygems-prune\" #{settings[:host_gem]} prune"
  end
end
