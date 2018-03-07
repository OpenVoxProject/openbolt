component "bolt" do |pkg, settings, platform|
  pkg.version '0.17.0'
  pkg.load_from_json('configs/components/bolt.json')

  # TODO can we set up internal gem mirror and install from there instead, 
  # or do like puppet agent and have each dependency have it's own build + install 
  pkg.build_requires "puppet-agent"
  pkg.requires "puppet-agent"

  pkg.build do
    ["gem build bolt.gemspec"]
  end

  pkg.install do
    ["#{settings[:gem_install]} bolt-#{pkg.get_version}.gem"]
  end

  pkg.link "#{settings[:bindir]}/bolt", "#{settings[:link_bindir]}/bolt"
end
