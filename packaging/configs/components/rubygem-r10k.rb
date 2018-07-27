component "rubygem-r10k" do |pkg, settings, platform|
  pkg.version "2.6.3"
  pkg.md5sum "183b878d6e7b71fdb0d043ddd940f3f6"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
