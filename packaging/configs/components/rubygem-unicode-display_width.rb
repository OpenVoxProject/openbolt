component "rubygem-unicode-display_width" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "1.3.0"
  pkg.md5sum "5c4f87f8ca57d2df52c3c9c2d4e874bb"
  pkg.url "https://rubygems.org/downloads/#{gemname}-#{pkg.get_version}.gem"
  pkg.mirror "#{settings[:buildsources_url]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end