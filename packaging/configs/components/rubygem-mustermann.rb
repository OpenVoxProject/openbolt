component "rubygem-mustermann" do |pkg, settings, platform|
  pkg.version "1.0.2"
  pkg.md5sum "cf338e43770b024a954c8754d66881d7"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
