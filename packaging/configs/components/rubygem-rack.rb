component "rubygem-rack" do |pkg, settings, platform|
  pkg.version "2.0.5"
  pkg.md5sum "92da3f9e4218d77689fddf003b51240d"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
