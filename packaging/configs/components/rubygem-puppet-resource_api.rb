component "rubygem-puppet-resource_api" do |pkg, settings, platform|
  pkg.version "1.6.2"
  pkg.md5sum "ba038d56be25c55affa2bda964acce34"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
