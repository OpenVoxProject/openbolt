component "rubygem-gyoku" do |pkg, settings, platform|
  pkg.version "1.3.1"
  pkg.md5sum "7af7a2b4fac7bf7ec15eff1026b1495d"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
