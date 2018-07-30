component "rubygem-winrm" do |pkg, settings, platform|
  pkg.version "2.2.3"
  pkg.md5sum "16c7a0b30e9d4410c2730d2f4d8a8d25"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
