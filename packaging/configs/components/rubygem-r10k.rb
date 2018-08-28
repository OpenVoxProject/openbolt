component "rubygem-r10k" do |pkg, settings, platform|
  pkg.version "2.6.4"
  pkg.md5sum "188ee31f443e6379c0ddec35b889ba1f"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
