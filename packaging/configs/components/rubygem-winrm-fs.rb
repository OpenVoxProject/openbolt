component "rubygem-winrm-fs" do |pkg, settings, platform|
  pkg.version "1.3.1"
  pkg.md5sum "706b7e0e917a1f0b18473785eb534194"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
