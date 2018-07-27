component "pe-bolt-server" do |pkg, settings, platform|
  pkg.environment "GEM_HOME", settings[:gem_home]
  pkg.load_from_json('configs/components/pe-bolt-server.json')
  pkg.build_requires 'puppet-agent'

  pkg.build do
    ["#{settings[:gem_build]} bolt.gemspec"]
  end

  pkg.install do
    ["#{settings[:gem_install]} bolt-*.gem"]
  end

  case platform.servicetype
  when "systemd"
    pkg.install_service "ext/systemd/pe-bolt-server.service"
  when "sysv"
    if platform.is_deb?
      pkg.install_service "ext/debian/pe-bolt-server.init", "ext/debian/pe-bolt-server.default"
      pkg.add_postinstall_action ["install"], ["systemctl daemon-reload && service pe-bolt-server start"]
    elsif platform.is_rpm?
      pkg.install_service "ext/redhat/pe-bolt-server.init", "ext/redhat/pe-bolt-server.sysconfig"
    else
      fail "This OS is not supported. See https://puppet.com/docs/pe/latest/supported_operating_systems.html#puppet-master-platforms for supported platforms"
    end
    else
      fail "need to know where to put service files"
    end
end
