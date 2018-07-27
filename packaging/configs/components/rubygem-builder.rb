component "rubygem-builder" do |pkg, settings, platform|
  pkg.version "3.2.3"
  pkg.md5sum "24dbb8bc3a17ce24ff65c9af513f5245"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
