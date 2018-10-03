component "rubygem-facter" do |pkg, settings, platform|
  pkg.version "2.5.1"
  pkg.md5sum "5da7598481d6eb779a3fe770f73e24ee"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
