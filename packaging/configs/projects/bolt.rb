project "bolt" do |proj|
  platform = proj.get_platform

  proj.description 'Stand alone task runner'
  proj.version '0.17.0'
  proj.license 'PL Commercial'
  proj.vendor "Puppet Labs <info@puppetlabs.com>"
  proj.homepage "https://www.puppetlabs.com"
  proj.target_repo "PC1"
  proj.identifier "com.puppetlabs"

  #proj.setting(:sysconfdir, "/etc/puppetlabs")
  #proj.setting(:prefix, "/opt/puppetlabs/client-tools")
  #proj.setting(:prefix, "/opt/puppetlabs/bolt")
  #proj.setting(:main_bin, "/opt/puppetlabs/bin")
  proj.setting(:bindir, "/opt/puppetlabs/puppet/bin")

  #proj.setting(:client_bin, File.join(proj.prefix, "bin"))
  #proj.setting(:client_configdir, proj.sysconfdir)
  #proj.setting(:libdir, File.join(proj.prefix, "lib"))
  #proj.setting(:includedir, File.join(proj.prefix, "include"))
  #proj.setting(:datadir, File.join(proj.prefix, "share"))
  #proj.setting(:mandir, File.join(proj.datadir, "man"))

  #proj.setting(:cflags, "-I#{proj.includedir}")
  #proj.setting(:ldflags, "-L#{proj.libdir} -Wl,-rpath=#{proj.libdir}")
  #proj.setting(:paths, [ proj.client_bin ]) unless platform.is_windows?
  proj.setting(:puppet_agent_prefix, "/opt/puppetlabs/puppet") unless platform.is_windows?

  proj.setting(:agent_bindir, File.join(proj.puppet_agent_prefix, "bin"))
  proj.setting(:agent_libdir, File.join(proj.puppet_agent_prefix, "lib"))
  proj.setting(:agent_includedir, File.join(proj.puppet_agent_prefix, "include"))
  proj.setting(:gem_path, "/opt/puppetlabs/puppet/lib/ruby/gems/2.1.0/gems/")
  proj.setting(:gem_install, "/opt/puppetlabs/puppet/bin/gem install --no-rdoc --no-ri --bindir=/opt/puppetlabs/puppet/bin --local --force ")
  proj.setting(:gem_source, "http://rubygems.delivery.puppetlabs.net/")
  proj.setting(:artifactory_url, "https://artifactory.delivery.puppetlabs.net/artifactory")
  proj.setting(:build_source, "#{proj.artifactory_url}/generic/buildsources")
  #proj.setting(:openssl_prefix, proj.puppet_agent_prefix)
  #proj.setting(:cflags, "#{proj.cflags} -I#{proj.agent_includedir}")
  #proj.setting(:ldflags, "#{proj.ldflags} -L#{proj.agent_libdir} -Wl,-rpath=#{proj.agent_libdir}")
  #proj.paths << proj.agent_bindir
  #proj.paths << "/opt/pl-build-tools/bin"

  #proj.conflicts 'pe-client-tools'

  proj.component 'bolt'
  proj.component 'rubygem-addressable'

  #proj.directory proj.prefix
  proj.directory proj.puppet_agent_prefix unless platform.is_windows?
  proj.directory "/opt/puppetlabs/bin"
  proj.directory "/opt/puppetlabs/puppet/bin"
  proj.directory "/opt/puppetlabs/puppet/lib/ruby/gems"
  #proj.directory proj.main_bin
  #proj.directory proj.client_bin
  #proj.directory proj.client_configdir
end
