component "rubygem-net-scp" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "1.2.1"
  pkg.md5sum "abeec1cab9696e02069e74bd3eac8a1b"
  pkg.url "#{settings[:build_source]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.build_requires "puppet-agent"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end