component "rubygem-nori" do |pkg, settings, platform|
  pkg.version "2.6.0"
  pkg.md5sum "dc9c83026c10a3eb7093b9c8208c84f7"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
