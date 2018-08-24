component "pe-bolt-server" do |pkg, settings, platform|
  pkg.environment "GEM_HOME", settings[:gem_home]
  pkg.environment "PATH", "#{settings[:bindir]}:$$PATH"
  pkg.load_from_json('configs/components/bolt.json')
  pkg.build_requires 'puppet-agent'

  pkg.build do
    ["#{settings[:gem_build]} bolt.gemspec"]
  end

  pkg.install do
    ["#{settings[:gem_install]} bolt-*.gem"]
  end

  pkg.install_file('puma_config.rb', "#{settings[:prefix]}/puma_config.rb")

  case platform.servicetype
  when "systemd"
    pkg.add_source("file://resources/systemd/pe-bolt-server.service", sum: "37bf640ee38c77ee8893badf9af6ad05")
    pkg.install_service "../pe-bolt-server.service"
  when "sysv"
    if platform.is_rpm?
      pkg.add_source("file://resources/redhat/pe-bolt-server.init", sum: "e59aafed20d3db5025f99f6345a3fd29")
      pkg.add_source("file://resources/redhat/pe-bolt-server.sysconfig", sum: "273ddf6ee45968f2f96a0a7adc3b4a59")
      pkg.install_service "../pe-bolt-server.init", "../pe-bolt-server.sysconfig"
    else
      fail "This OS is not supported. See https://puppet.com/docs/pe/latest/supported_operating_systems.html#puppet-master-platforms for supported platforms"
    end
  else
    fail "need to know where to put service files"
  end

  pkg.add_postinstall_action ["install", "upgrade"], [
    "/bin/chown -R #{settings[:pe_bolt_user]}:#{settings[:pe_bolt_user]} #{settings[:homedir]}",
    "/bin/chown -R #{settings[:pe_bolt_user]}:#{settings[:pe_bolt_user]} #{settings[:sysconfdir]}",
    "/bin/chown -R #{settings[:pe_bolt_user]}:#{settings[:pe_bolt_user]} #{settings[:logdir]}",
    "/bin/chown -R #{settings[:pe_bolt_user]}:#{settings[:pe_bolt_user]} #{settings[:rundir]}"
  ]
  pkg.add_postinstall_action ["install"], [
    "systemctl daemon-reload"
  ]
end
