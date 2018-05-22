project "puppet-bolt" do |proj|
  # bolt inherits most build settings from puppetlabs/puppet-runtime:
  # - Modifications to global settings like flags and target directories should be made in puppet-runtime.
  # - Settings included in this file should apply only to local components in this repository.
  runtime_details = JSON.parse(File.read(File.join(File.dirname(__FILE__), '..', 'components/puppet-runtime.json')))
  runtime_tag = runtime_details['ref'][/refs\/tags\/(.*)/, 1]
  raise "Unable to determine a tag for bolt-runtime (given #{runtime_details['ref']})" unless runtime_tag
  proj.inherit_settings 'bolt-runtime', runtime_details['url'], runtime_tag

  proj.description 'Stand alone task runner'
  proj.license "See components"
  proj.vendor "Puppet, Inc.  <info@puppet.com>"
  proj.homepage "https://www.puppet.com"
  proj.identifier "com.puppetlabs"
  proj.version_from_git

  if platform.is_windows?
    # WiX config
    proj.setting(:company_name, "Puppet, Inc.")
    proj.setting(:pl_company_name, "Puppet Labs")
    proj.setting(:company_id, "PuppetLabs")
    proj.setting(:product_id, "Bolt")
    proj.setting(:shortcut_name, "Puppet Bolt")
    proj.setting(:upgrade_code, "5F2FFC54-3620-429C-B90E-D16E0348A1E7")

    proj.setting(:product_name, "Puppet Bolt")
    proj.setting(:base_dir, "ProgramFiles64Folder")

    proj.setting(:links, {
      :HelpLink => "http://puppet.com/services/customer-support",
      :CommunityLink => "https://puppet.com/community",
      :ForgeLink => "http://forge.puppet.com",
      :NextStepLink => "https://puppet.com/docs/bolt/",
      :ManualLink => "https://puppet.com/docs/bolt/",
    })

    proj.setting(:LicenseRTF, "wix/license/LICENSE.rtf")
  end

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
