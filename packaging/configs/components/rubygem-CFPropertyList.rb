component "rubygem-CFPropertyList" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "2.3.6"
  pkg.md5sum "ae4086185992f293ffab1641b83286a5"
  pkg.url "#{settings[:build_source]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.build_requires "puppet-agent"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end