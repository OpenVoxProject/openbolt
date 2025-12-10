require_relative '../../../lib/bolt/version'
component "openbolt" do |pkg, settings, platform|
  pkg.url 'file://../'
  pkg.version Bolt::VERSION
  pkg.build_requires 'openbolt-runtime'

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

    pkg.add_source("file://resources/files/windows/bolt.bat", sum: "60ead805dc78855d4a1a13230c141daa")
    pkg.install_file "../bolt.bat", "#{settings[:link_bindir]}/bolt.bat"

    # PowerShell Module
    pkg.directory "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt"
    pkg.install_file "pwsh_module/PuppetBolt/PuppetBolt.psm1", "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt/PuppetBolt.psm1"
    pkg.install_file "pwsh_module/PuppetBolt/PuppetBolt.psd1", "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt/PuppetBolt.psd1"

    # Add topic guides to the PowerShell Module
    pkg.directory "#{settings[:datadir]}/PowerShell/Modules/PuppetBolt/en-US"
    pkg.install { ["/usr/bin/cp pwsh_module/PuppetBolt/en-US/* #{settings[:datadir]}/PowerShell/Modules/PuppetBolt/en-US"] }
  else
    pkg.add_source("file://resources/files/posix/bolt_env_wrapper", sum: "644f069f275f44af277b20a2d0d279c6")
    bolt_exe = File.join(settings[:link_bindir], 'bolt')
    pkg.install_file "../bolt_env_wrapper", bolt_exe, mode: "0755"

    if File.directory?("/etc/bash_completion.d")
      pkg.install_file "resources/bolt_bash_completion.sh", "/etc/bash_completion.d/bolt.sh", mode: "0644"
    end

    if platform.is_macos?
      pkg.add_source 'file://resources/files/paths.d/50-bolt', sum: '4abf75aebbbfbbefc4fe0173c57ed0b2'
      pkg.install_file('../50-bolt', '/etc/paths.d/50-bolt')
    else
      pkg.link bolt_exe, File.join(settings[:main_bin], 'bolt')
    end
  end
end
