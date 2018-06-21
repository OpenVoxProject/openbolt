component "rubygem-net-ssh-krb" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "0.4.0"
  pkg.md5sum "a19209530717d3b1254aebb2ab230635"
  pkg.url "https://rubygems.org/downloads/#{gemname}-#{pkg.get_version}.gem"
  pkg.mirror "#{settings[:buildsources_url]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end

