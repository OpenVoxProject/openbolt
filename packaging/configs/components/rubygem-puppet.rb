component "rubygem-puppet" do |pkg, settings, platform|
  pkg.version "6.0.4"
  pkg.md5sum "2f0060f3b4cf4042a75581922a8e1bfe"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
