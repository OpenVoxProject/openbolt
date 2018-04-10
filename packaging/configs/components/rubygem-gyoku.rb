component "rubygem-gyoku" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "1.3.1"
  pkg.md5sum "7af7a2b4fac7bf7ec15eff1026b1495d"
  pkg.url "https://rubygems.org/downloads/#{gemname}-#{pkg.get_version}.gem"
  pkg.mirror "#{settings[:buildsources_url]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end