component "rubygem-hocon" do |pkg, settings, platform|
  pkg.version "1.2.5"
  pkg.md5sum "e7821d3a731ab617320ccfa4f67f886b"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
