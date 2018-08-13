project "puppet-bolt" do |proj|
  # bolt inherits most build settings from puppetlabs/puppet-runtime:
  # - Modifications to global settings like flags and target directories should be made in puppet-runtime.
  # - Settings included in this file should apply only to local components in this repository.
  runtime_details = JSON.parse(File.read('configs/components/puppet-runtime.json'))

  settings[:puppet_runtime_version] = runtime_details['version']
  settings[:puppet_runtime_location] = runtime_details['location']
  settings[:puppet_runtime_basename] = "bolt-runtime-#{runtime_details['version']}.#{platform.name}"

  settings_uri = File.join(runtime_details['location'], "#{proj.settings[:puppet_runtime_basename]}.settings.yaml")
  sha1sum_uri = "#{settings_uri}.sha1"
  proj.inherit_yaml_settings(settings_uri, sha1sum_uri)

  proj.description 'Stand alone task runner'
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
  proj.instance_eval File.read('configs/projects/bolt-shared.rb')
  proj.component "bolt"

  proj.directory proj.prefix
  proj.directory proj.link_bindir
end
