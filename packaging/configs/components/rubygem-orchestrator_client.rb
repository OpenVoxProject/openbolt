component "rubygem-orchestrator_client" do |pkg, settings, platform|
  pkg.version "0.3.0"
  pkg.md5sum "e81d18cdf501e5995a1b963809cf37a3"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
