component "rubygem-docker-api" do |pkg, settings, platform|
  pkg.version "1.34.2"
  pkg.md5sum "3403caf5b1f7d61db0e1c3a1144257ef"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
