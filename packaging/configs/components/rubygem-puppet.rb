component "rubygem-puppet" do |pkg, settings, platform|
  pkg.version "6.4.0"
  pkg.md5sum "b3f9716c9c8889f95c66b33bb7445f63"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
