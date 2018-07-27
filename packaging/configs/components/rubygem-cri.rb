component "rubygem-cri" do |pkg, settings, platform|
  pkg.version "2.6.1"
  pkg.md5sum "657c231f411fc9b7f630dcb980517bce"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
