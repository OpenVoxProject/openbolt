component "rubygem-winrm" do |pkg, settings, platform|
  pkg.version "2.3.0"
  pkg.md5sum "884f5a5d2cd8e49e5eca8f79694bcfd3"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
