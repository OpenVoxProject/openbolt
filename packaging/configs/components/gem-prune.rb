component 'gem-prune' do |pkg, settings, platform|
  pkg.build_requires 'bolt-runtime'

  pkg.add_source('file://resources/rubygems-prune')

  pkg.build do
    puppet_cachedir = File.join(settings[:privatedir], 'puppet', 'ruby')
    ruby_cachedir = File.join(settings[:cachedir], 'ruby')

    gem_bins = {
      settings[:ruby_api] => settings[:host_gem],
    }

    settings[:additional_rubies]&.each do |rubyver, local_settings|
      gem_bins[local_settings[:ruby_api]] = local_settings[:host_gem]
    end

    bolt_ruby_versions = ['2.7.6']

    bolt_ruby_versions.map do |rubyapi|
      gem_paths = [
        File.join(puppet_cachedir, rubyapi),
        File.join(ruby_cachedir, rubyapi),
      ]

      # This code is evaluated on the host where vanagon is
      # running, so we can't depend on the PATH_SEPARATOR constant
      # being correct for the target platform.
      if platform.is_windows?
        path_sep = ";"
      else
        path_sep = File::PATH_SEPARATOR
      end

      "GEM_PATH=\"#{gem_paths.join(path_sep)}\" RUBYOPT=\"-Irubygems-prune\" #{gem_bins[rubyapi]} prune" if gem_bins[rubyapi]
    end
  end
end
