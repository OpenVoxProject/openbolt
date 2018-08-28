component "rubygem-mustermann" do |pkg, settings, platform|
  pkg.version "1.0.3"
  pkg.md5sum "ca68625e69446a98e2f4fd410321d9f8"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
