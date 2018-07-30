component "rubygem-puppet_forge" do |pkg, settings, platform|
  pkg.version "2.2.9"
  pkg.md5sum "3d2c8936421e2101c846f98e3b3199b0"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
