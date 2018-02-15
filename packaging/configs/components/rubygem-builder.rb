component "rubygem-builder" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "3.2.3"
  pkg.md5sum "24dbb8bc3a17ce24ff65c9af513f5245"
  pkg.url "#{settings[:build_source]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.build_requires "puppet-agent"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end