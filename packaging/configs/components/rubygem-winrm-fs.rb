component "rubygem-winrm-fs" do |pkg, settings, platform|
  pkg.version "1.3.0"
  pkg.md5sum "190670971b9644938f462fe50b28ba96"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
