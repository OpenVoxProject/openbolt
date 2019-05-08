project "pe-bolt-server" do |proj|
  proj.license "See components"
  proj.vendor "Puppet, Inc.  <info@puppet.com>"
  proj.homepage "https://www.puppet.com"
  proj.identifier "com.puppetlabs"

  # pe-bolt-server inherits most build settings from puppetlabs/puppet-runtime:
  # - Modifications to global settings like flags and target directories should be made in puppet-runtime.
  # - Settings included in this file should apply only to local components in this repository.
  proj.description 'Service to expose bolt transports'
  runtime_details = JSON.parse(File.read('configs/components/puppet-runtime.json'))

  proj.setting(:puppet_runtime_version, runtime_details['version'])
  proj.setting(:puppet_runtime_location, runtime_details['location'])
  proj.setting(:puppet_runtime_basename, "pe-bolt-server-runtime-2019.1.x-#{runtime_details['version']}.#{platform.name}")

  settings_uri = File.join(runtime_details['location'], "#{proj.settings[:puppet_runtime_basename]}.settings.yaml")
  sha1sum_uri = "#{settings_uri}.sha1"
  proj.inherit_yaml_settings(settings_uri, sha1sum_uri)

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

  proj.setting(:pe_bolt_user, "pe-bolt-server")
  proj.setting(:homedir, "/opt/puppetlabs/server/data/bolt-server")
  proj.setting(:gem_build, "/opt/puppetlabs/puppet/bin/gem build")

  proj.user(proj.pe_bolt_user,
            group: proj.pe_bolt_user,
            shell: '/sbin/nologin',
            homedir: "#{proj.homedir}",
            is_system: true)

  proj.component 'bolt-runtime'

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

  if platform.name =~ /^el-(8)-.*/
    # Disable build-id generation since it's currently generating conflicts
    # with system libgcc and libstdc++
    proj.package_override("# Disable build-id generation to avoid conflicts\n%global _build_id_links none")
  end
end
