component "rubygem-puppet-resource_api" do |pkg, settings, platform|
  pkg.version "1.8.1"
  pkg.md5sum "e6c189b1610180ce0fbd6be5073e77e7"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
