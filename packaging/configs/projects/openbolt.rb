# frozen_string_literal: true

project "openbolt" do |proj|
  proj.license "See components"
  proj.vendor "Vox Pupuli <openvox@voxpupuli.org>"
  proj.homepage "https://voxpupuli.org"
  proj.identifier "org.voxpupuli"

  # openbolt inherits most build settings from puppetlabs/puppet-runtime:
  # - Modifications to global settings like flags and target directories should be made in puppet-runtime.
  # - Settings included in this file should apply only to local components in this repository.
  runtime_details = JSON.parse(File.read('configs/components/puppet-runtime.json'))

  settings[:puppet_runtime_version] = runtime_details['version']
  settings[:puppet_runtime_location] = runtime_details['location']
  settings[:puppet_runtime_basename] = "openbolt-runtime-#{runtime_details['version']}.#{platform.name}"

  settings_uri = File.join(runtime_details['location'], "#{proj.settings[:puppet_runtime_basename]}.settings.yaml")
  metadata_uri = File.join(runtime_details['location'], "#{proj.settings[:puppet_runtime_basename]}.json")
  sha1sum_uri = "#{settings_uri}.sha1"
  proj.inherit_yaml_settings(settings_uri, sha1sum_uri, metadata_uri: metadata_uri)

  proj.description 'Tool for executing commands, tasks, and plans on remote systems'
  proj.version_from_git

  if platform.is_windows?
    # WiX config
    proj.setting(:company_name, "Vox Pupuli")
    proj.setting(:pl_company_name, "Puppet Labs")
    proj.setting(:company_id, "VoxPupuli")
    proj.setting(:pl_company_id, "PuppetLabs")
    proj.setting(:product_id, "OpenBolt")
    proj.setting(:pl_product_id, "Bolt")
    proj.setting(:shortcut_name, "OpenBolt")
    proj.setting(:upgrade_code, "5F2FFC54-3620-429C-B90E-D16E0348A1E7")
    proj.setting(:product_name, "OpenBolt")
    proj.setting(:base_dir, "ProgramFiles64Folder")
    proj.setting(:links,
                 {
                   HelpLink: "https://voxpupuli.slack.com",
                   CommunityLink: "https://voxpupuli.org/",
                   ForgeLink: "http://forge.puppet.com",
                   NextStepLink: "https://puppet.com/docs/bolt/",
                   ManualLink: "https://puppet.com/docs/bolt/",
                 })
    proj.setting(:LicenseRTF, "wix/license/LICENSE.rtf")
    proj.setting(:install_root, File.join("C:", proj.base_dir, proj.pl_company_id, proj.product_id))
    proj.setting(:link_bindir, File.join(proj.install_root, "bin"))

    File.join(proj.datadir.sub(%r{^.*:/}, ''), 'PowerShell', 'Modules')
    # proj.extra_file_to_sign File.join(module_directory, 'PuppetBolt', 'PuppetBolt.psm1')
    # proj.extra_file_to_sign File.join(module_directory, 'PuppetBolt', 'PuppetBolt.psd1')
  else
    proj.setting(:link_bindir, "/opt/puppetlabs/bin")
    proj.setting(:main_bin, "/usr/local/bin")
  end

  proj.component "openbolt-runtime"
  proj.component "openbolt"
  proj.component "openbolt-create-ruby-tarballs"

  proj.component "gem-prune"

  # These come from puppet-runtime's settings output
  proj.directory proj.prefix
  proj.directory proj.bindir
  proj.directory proj.libdir
  proj.directory proj.includedir
  proj.directory proj.datadir
  proj.directory proj.mandir
  proj.directory proj.ruby_dir_base
  proj.directory proj.ruby_dir_base_version
  proj.directory proj.rubygems_dir
  proj.directory proj.rubygems_ssl_dir

  proj.directory proj.link_bindir

  # rubocop:disable Style/RedundantStringEscape, Style/FormatStringToken
  if platform.is_fedora?
    proj.package_override("# Disable check-rpaths since /opt/* is not a valid path\n%global __brp_check_rpaths \%{nil}")
    proj.package_override("# Disable the removal of la files, they are still required\n%global __brp_remove_la_files \%{nil}")
  end
  # rubocop:enable Style/RedundantStringEscape, Style/FormatStringToken

  if platform.name =~ /^el-(8)-.*/
    # Disable build-id generation since it's currently generating conflicts
    # with system libgcc and libstdc++
    proj.package_override("# Disable build-id generation to avoid conflicts\n%global _build_id_links none")
  end
end
