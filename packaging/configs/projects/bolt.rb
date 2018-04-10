project "bolt" do |proj|
  # bolt inherits most build settings from puppetlabs/puppet-runtime:
  # - Modifications to global settings like flags and target directories should be made in puppet-runtime.
  # - Settings included in this file should apply only to local components in this repository.
  runtime_details = JSON.parse(File.read(File.join(File.dirname(__FILE__), '..', 'components/bolt-runtime.json')))
  runtime_tag = runtime_details['ref'][/refs\/tags\/(.*)/, 1]
  raise "Unable to determine a tag for bolt-runtime (given #{runtime_details['ref']})" unless runtime_tag
  proj.inherit_settings 'bolt-runtime', 'git://github.com/puppetlabs/puppet-runtime', runtime_tag

  proj.description 'Stand alone task runner'
  proj.license "See components"
  proj.vendor "Puppet, Inc.  <info@puppet.com>"
  proj.homepage "https://www.puppet.com"
  proj.identifier "com.puppetlabs"
  proj.version_from_git

  proj.setting(:link_bindir, "/opt/puppetlabs/bin")
  proj.setting(:main_bin, "/usr/local/bin")

  proj.component "bolt-runtime"

  proj.component 'rubygem-addressable'
  proj.component 'rubygem-public_suffix'
  proj.component 'rubygem-concurrent-ruby'
  proj.component 'rubygem-net-scp'
  proj.component 'rubygem-orchestrator_client'
  proj.component 'rubygem-terminal-table'
  proj.component 'rubygem-unicode-display_width'
  proj.component 'rubygem-winrm'
  proj.component 'rubygem-gssapi'
  proj.component 'rubygem-httpclient'
  proj.component 'rubygem-rubyntlm'
  proj.component 'rubygem-logging'
  proj.component 'rubygem-little-plugger'
  proj.component 'rubygem-nori'
  proj.component 'rubygem-gyoku'
  proj.component 'rubygem-builder'
  proj.component 'rubygem-erubis'
  proj.component 'rubygem-winrm-fs'
  proj.component 'rubygem-rubyzip'
  proj.component 'rubygem-CFPropertyList'
  proj.component 'bolt'

  proj.directory proj.prefix
  proj.directory proj.link_bindir
end
