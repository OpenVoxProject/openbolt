component "bolt" do |pkg, settings, platform|
  pkg.load_from_json('configs/components/bolt.json')

  # Install the bolt runtime for access to rubygem-r10k:
  pkg.build_requires 'bolt-runtime'

  # We need to run r10k before building the gem.
  pkg.build do
    ["#{settings[:ruby_bindir]}/r10k puppetfile install --verbose" ]
  end

  pkg.build do
    ["#{settings[:host_gem]} build bolt.gemspec"]
  end

  pkg.install do
    ["#{settings[:gem_install]} bolt-*.gem"]
  end

  if platform.is_windows?
    pkg.install { ["#{settings[:ruby_bindir]}/rake.bat pwsh:generate_module"] }

    # PowerShell Module
    pkg.directory "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt"
    pkg.install_file "pwsh_module/PuppetBolt.psm1", "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt/PuppetBolt.psm1"
    pkg.install_file "pwsh_module/PuppetBolt.psd1", "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt/PuppetBolt.psd1"
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
