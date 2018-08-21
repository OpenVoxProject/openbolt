component "pe-bolt-server" do |pkg, settings, platform|
  pkg.environment "GEM_HOME", settings[:gem_home]
  pkg.environment "PATH", "#{settings[:bindir]}:$$PATH"
  pkg.load_from_json('configs/components/pe-bolt-server.json')
  pkg.build_requires 'puppet-agent'

  pkg.build do
    ["#{settings[:gem_build]} bolt.gemspec"]
  end

  pkg.install do
    ["#{settings[:gem_install]} bolt-*.gem"]
  end

  pkg.install_file('config.ru', "#{settings[:prefix]}/config.ru")

  case platform.servicetype
  when "systemd"
    pkg.install_service "ext/systemd/pe-bolt-server.service"
    pkg.install_file('ext/tmpfiles/pe-bolt-server.conf', "/usr/lib/tmpfiles.d/pe-bolt-server.conf")
  when "sysv"
    if platform.is_rpm?
      pkg.install_service "ext/redhat/pe-bolt-server.init", "ext/redhat/pe-bolt-server.sysconfig"
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
