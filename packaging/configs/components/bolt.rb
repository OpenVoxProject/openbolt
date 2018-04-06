component "bolt" do |pkg, settings, platform|
  pkg.load_from_json('configs/components/bolt.json')

  # We need ruby to install r10k
  pkg.build_requires "ruby"

  # We need to run r10k before building the gem, but we don't want to
  # include it in the package, so we install with the system ruby.
  # Except on EL 6, where the system ruby is too old to install r10k.
  if platform.is_el? && platform.os_version == '6'
    pkg.build do
      [ "#{settings[:bindir]}/gem install r10k --no-ri --no-rdoc --no-format-executable",
        "#{settings[:bindir]}/r10k puppetfile install --verbose" ]
    end
  else
    if platform.is_sles?
      r10k_bin = '/usr/bin/r10k'
    else
      r10k_bin = '/usr/local/bin/r10k'
    end
    pkg.build do
      [ "/usr/bin/gem install r10k --no-ri --no-rdoc --no-format-executable",
        "#{r10k_bin} puppetfile install --verbose" ]
    end
  end

  pkg.build do
    ["#{settings[:host_gem]} build bolt.gemspec"]
  end

  pkg.install do
    ["#{settings[:gem_install]} bolt-*.gem"]
  end

  pkg.link "#{settings[:bindir]}/bolt", "#{settings[:link_bindir]}/bolt"
end
