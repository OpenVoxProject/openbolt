pkg.environment "GEM_HOME", settings[:gem_home]
gemname = pkg.get_name.gsub('rubygem-', '')
pkg.url "https://rubygems.org/downloads/#{gemname}-#{pkg.get_version}.gem"
pkg.mirror "#{settings[:buildsources_url]}/#{gemname}-#{pkg.get_version}.gem"

pkg.install do
  "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
end
