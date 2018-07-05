project "pe-bolt-server" do |proj|
  proj.description 'Service to expose bolt transports'
  proj.requires 'puppet-agent'
  # We can just have the same version as bolt, and use tags for specific packages
  proj.version_from_git

  #proj.setting(:prefix, "/opt/puppetlabs/server/apps/bolt-server")
  proj.setting(:prefix, "/opt/puppetlabs/puppet")
  proj.setting(:sysconfdir, "/etc/puppetlabs/bolt-server")
  proj.setting(:logdir, "/var/log/puppetlabs/bolt-server")
  proj.setting(:bindir, "#{proj.prefix}/bin")
  proj.setting(:link_bindir, "/opt/puppetlabs/bin")
  proj.setting(:main_bin, "/usr/local/bin")
  proj.setting(:gem_install, "/opt/puppetlabs/puppet/bin/gem install --no-rdoc --no-ri --bindir=#{proj.bindir} --local --force ")
  proj.setting(:gem_build, "/opt/puppetlabs/puppet/bin/gem build")
  proj.setting(:artifactory_url, "https://artifactory.delivery.puppetlabs.net/artifactory")
  proj.setting(:buildsources_url, "#{proj.artifactory_url}/generic/buildsources")

  proj.instance_eval File.read('configs/projects/bolt-shared.rb')
  proj.component 'pe-bolt-server'

  proj.directory proj.prefix
  proj.directory proj.bindir
  proj.directory proj.link_bindir
  proj.directory proj.main_bin
  proj.directory proj.sysconfdir
  proj.directory proj.logdir
end
