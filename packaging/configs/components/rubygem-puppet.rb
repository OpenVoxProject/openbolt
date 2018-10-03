component "rubygem-puppet" do |pkg, settings, platform|
  pkg.version "6.0.1"
  pkg.md5sum "271b04a34964e4db6f029ffd910fe04d"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
