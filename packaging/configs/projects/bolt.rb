project "bolt" do |proj|
  platform = proj.get_platform

  proj.description 'Stand alone task runner'
  proj.version_from_git
  proj.license 'PL Commercial'
  proj.vendor "Puppet Labs <info@puppetlabs.com>"
  proj.homepage "https://www.puppetlabs.com"
  proj.target_repo ""
  proj.identifier "com.puppetlabs"

  proj.setting(:bindir, "/opt/puppetlabs/puppet/bin")
  proj.setting(:gem_path, "/opt/puppetlabs/puppet/lib/ruby/gems/2.4.0")
  proj.setting(:gem_install, "#{proj.bindir}/gem install --no-rdoc --no-ri --bindir=#{proj.bindir} --local --force ")
  proj.setting(:artifactory_url, "https://artifactory.delivery.puppetlabs.net/artifactory")
  proj.setting(:build_source, "#{proj.artifactory_url}/generic/buildsources")

  proj.component 'rubygem-addressable'
  proj.component 'rubygem-concurrent-ruby'
  proj.component 'rubygem-net-scp'
  proj.component 'rubygem-net-ssh'
  proj.component 'rubygem-orchestrator_client'
  proj.component 'rubygem-terminal-table'
  proj.component 'rubygem-unicode-display_width'
  proj.component 'rubygem-winrm'
  proj.component 'rubygem-gssapi'
  proj.component 'rubygem-ffi'
  proj.component 'rubygem-httpclient'
  proj.component 'rubygem-rubyntlm'
  proj.component 'rubygem-logging'
  proj.component 'rubygem-little-plugger'
  proj.component 'rubygem-multi_json'
  proj.component 'rubygem-nori'
  proj.component 'rubygem-gyoku'
  proj.component 'rubygem-builder'
  proj.component 'rubygem-erubis'
  proj.component 'rubygem-winrm-fs'
  proj.component 'rubygem-rubyzip'
  proj.component 'rubygem-CFPropertyList'
  proj.component 'rubygem-minitar'
  proj.component 'rubygem-win32-dir'
  proj.component 'rubygem-win32-process'
  proj.component 'rubygem-win32-security'
  proj.component 'rubygem-win32-service'
  proj.component 'bolt'

  proj.directory proj.bindir
  proj.directory proj.gem_path
end
