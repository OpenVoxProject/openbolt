component "bolt" do |pkg, settings, platform|
  pkg.load_from_json('configs/components/bolt.json')

  # We need ruby to install r10k
  pkg.build_requires "ruby"

  # We need to run r10k before building the gem, but we don't want to
  # include it in the package, so we install with the system ruby.
  # Except on EL 6, where the system ruby is too old to install r10k.
  if (platform.is_el? && platform.os_version == '6') || platform.is_windows?
    pkg.build do
      [ "#{settings[:host_gem]} install r10k --no-ri --no-rdoc --no-format-executable",
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

  if platform.is_windows?
    # PowerShell Module
    pkg.add_source("file://resources/files/windows/PuppetBolt/PuppetBolt.psd1", sum: "f21e2bcfcb64da273e561e6066dce949")
    pkg.add_source("file://resources/files/windows/PuppetBolt/PuppetBolt.psm1", sum: "1ed17a54fd4df1032ea8d96c047ac623")

    pkg.directory "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt"
    pkg.install_file "../PuppetBolt.psd1", "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt/PuppetBolt.psd1"
    pkg.install_file "../PuppetBolt.psm1", "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt/PuppetBolt.psm1"
  else
    pkg.add_source("file://resources/files/posix/bolt_env_wrapper", sum: "644f069f275f44af277b20a2d0d279c6")
    bolt_exe = File.join(settings[:link_bindir], 'bolt')
    pkg.install_file "../bolt_env_wrapper", bolt_exe, mode: "0755"

    if platform.is_macos?
      pkg.add_source 'file://resources/files/paths.d/50-bolt', sum: '4abf75aebbbfbbefc4fe0173c57ed0b2'
      pkg.install_file('../50-bolt', '/etc/paths.d/50-bolt')
    else
      pkg.link bolt_exe, File.join(settings[:main_bin], 'bolt')
    end
  end
end
