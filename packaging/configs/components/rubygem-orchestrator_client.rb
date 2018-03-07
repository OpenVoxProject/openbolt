component "rubygem-orchestrator_client" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "0.2.3"
  pkg.md5sum "b172c1997eccc466ea76a15ee6d3292d"
  pkg.url "#{settings[:build_source]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.build_requires "puppet-agent"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end
