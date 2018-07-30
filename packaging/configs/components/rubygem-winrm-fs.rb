component "rubygem-winrm-fs" do |pkg, settings, platform|
  pkg.version "1.2.0"
  pkg.md5sum "623202e7df96e1bc13b82c7cda1a42fb"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
