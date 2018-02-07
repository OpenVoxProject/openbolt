component "bolt" do |pkg, settings, platform|
  pkg.load_from_json('configs/components/bolt.json')

  pkg.build_requires "puppet-agent"
  pkg.requires "puppet-agent"

  pkg.build do
    ["/opt/puppetlabs/puppet/bin/gem build bolt.gemspec"]
  end

  pkg.install do
    ["#{settings[:gem_install]} bolt-*.gem"]
  end
end
