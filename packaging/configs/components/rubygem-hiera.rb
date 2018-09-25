component "rubygem-hiera" do |pkg, settings, platform|
  pkg.version "3.4.5"
  pkg.md5sum "a248dbdd636a6a15cea5dd92b005af4c"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
