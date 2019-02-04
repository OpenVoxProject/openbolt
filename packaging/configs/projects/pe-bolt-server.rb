project "pe-bolt-server" do |proj|
  proj.description 'Service to expose bolt transports'
  proj.requires 'puppet-agent'
  # We can just have the same version as bolt, and use tags for specific packages
  proj.version_from_git

  services = {"bolt-server" => "bolt", "plan-executor" => "plan"}

  services.each do |service, short|
    proj.setting("#{short}_sysconfdir".to_sym,
                 "/etc/puppetlabs/#{service}/conf.d")
    proj.setting("#{short}_logdir".to_sym,
                 "/var/log/puppetlabs/#{service}")
    proj.setting("#{short}_rundir".to_sym,
                 "/var/run/puppetlabs/#{service}")
  end

  proj.setting(:prefix, "/opt/puppetlabs/server/apps/bolt-server")
  proj.setting(:pe_bolt_user, "pe-bolt-server")
  proj.setting(:bindir, "#{proj.prefix}/bin")
  proj.setting(:libdir, "#{proj.prefix}/lib")
  proj.setting(:homedir, "/opt/puppetlabs/server/data/bolt-server")
  proj.setting(:gem_home, File.join(proj.libdir, 'ruby'))
  proj.setting(:gem_install, "/opt/puppetlabs/puppet/bin/gem install --no-rdoc --no-ri --local --bindir=#{proj.bindir}")
  proj.setting(:gem_build, "/opt/puppetlabs/puppet/bin/gem build")
  proj.setting(:artifactory_url, "https://artifactory.delivery.puppetlabs.net/artifactory")
  proj.setting(:buildsources_url, "#{proj.artifactory_url}/generic/buildsources")

  proj.user(proj.pe_bolt_user,
            group: proj.pe_bolt_user,
            shell: '/sbin/nologin',
            homedir: "#{proj.homedir}",
            is_system: true)

  # R10k dependency
  proj.component 'rubygem-gettext-setup'

  proj.instance_eval File.read('configs/projects/bolt-shared.rb')

  # Webserver dependencies
  proj.component 'rubygem-json-schema'
  proj.component 'rubygem-rack'
  proj.component 'rubygem-tilt'
  proj.component 'rubygem-rack-protection'
  proj.component 'rubygem-mustermann'
  proj.component 'rubygem-sinatra'
  proj.component 'rubygem-puma'
  proj.component 'rubygem-rails-auth'
  proj.component 'pe-bolt-services'

  proj.directory proj.prefix
  proj.directory proj.homedir

  services.each do |_, short|
    proj.directory proj.send("#{short}_sysconfdir")
    proj.directory proj.send("#{short}_logdir")
    proj.directory proj.send("#{short}_rundir")
  end
end
