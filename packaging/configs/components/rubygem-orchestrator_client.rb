component "rubygem-orchestrator_client" do |pkg, settings, platform|
  gemname = pkg.get_name.gsub('rubygem-', '')
  pkg.version "0.3.0"
  pkg.md5sum "e81d18cdf501e5995a1b963809cf37a3"
  pkg.url "https://rubygems.org/downloads/#{gemname}-#{pkg.get_version}.gem"
  pkg.mirror "#{settings[:buildsources_url]}/#{gemname}-#{pkg.get_version}.gem"

  pkg.install do
    "#{settings[:gem_install]} #{gemname}-#{pkg.get_version}.gem"
  end
end
