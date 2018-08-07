project "pe-bolt-server" do |proj|
  proj.description 'Service to expose bolt transports'
  proj.requires 'puppet-agent'
  # We can just have the same version as bolt, and use tags for specific packages
  proj.version_from_git

  proj.setting(:prefix, "/opt/puppetlabs/server/apps/bolt-server")
  proj.setting(:sysconfdir, "/etc/puppetlabs/bolt-server/conf.d")
  proj.setting(:logdir, "/var/log/puppetlabs/bolt-server")
  proj.setting(:bindir, "#{proj.prefix}/bin")
  proj.setting(:libdir, "#{proj.prefix}/lib")
  proj.setting(:gem_home, File.join(proj.libdir, 'ruby', 'gems', '2.4.0'))
  proj.setting(:gem_install, "/opt/puppetlabs/puppet/bin/gem install --no-rdoc --no-ri --local --bindir=#{proj.bindir}")
  proj.setting(:gem_build, "/opt/puppetlabs/puppet/bin/gem build")
  proj.setting(:artifactory_url, "https://artifactory.delivery.puppetlabs.net/artifactory")
  proj.setting(:buildsources_url, "#{proj.artifactory_url}/generic/buildsources")

  # R10k dependency
  proj.component 'rubygem-gettext-setup'
  # Bolt dependencies that aren't included in Puppet on our platforms yet
  proj.component 'rubygem-ffi'
  proj.component 'rubygem-minitar'

  proj.instance_eval File.read('configs/projects/bolt-shared.rb')

  # Webserver dependencies
  proj.component 'rubygem-rack'
  proj.component 'rubygem-tilt'
  proj.component 'rubygem-rack-protection'
  proj.component 'rubygem-mustermann'
  proj.component 'rubygem-sinatra'
  proj.component 'rubygem-puma'
  proj.component 'pe-bolt-server'

  proj.directory proj.prefix
  proj.directory proj.sysconfdir
  proj.directory proj.logdir
end
