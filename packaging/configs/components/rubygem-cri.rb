component "rubygem-cri" do |pkg, settings, platform|
  pkg.version "2.15.3"
  pkg.md5sum "1e972707fc6eafdcb9f2a5928d0d488b"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
