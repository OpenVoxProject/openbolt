component "rubygem-winrm-fs" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "1.2.0"
  pkg.md5sum "623202e7df96e1bc13b82c7cda1a42fb"
  pkg.url "https://rubygems.org/downloads/#{gemname}-#{pkg.get_version}.gem"
  pkg.mirror "#{settings[:buildsources_url]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end
