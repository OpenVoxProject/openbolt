component "rubygem-puppet" do |pkg, settings, platform|
  pkg.version "6.0.2"
  pkg.md5sum "894459f2f68cac1956c93ee0c98f4c34"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
