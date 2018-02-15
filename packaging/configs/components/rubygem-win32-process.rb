component "rubygem-win32-process" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "0.7.5"
  pkg.md5sum "d7ff67c7934b0d6ab93030d2cc2fc4f0"
  pkg.url "#{settings[:build_source]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.build_requires "puppet-agent"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end