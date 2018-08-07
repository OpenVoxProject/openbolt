component "rubygem-winrm-fs" do |pkg, settings, platform|
  pkg.version "1.2.1"
  pkg.md5sum "40dd5e3ab75756b152ee14c4ece409c1"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
