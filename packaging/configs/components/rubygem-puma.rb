component "rubygem-puma" do |pkg, settings, platform|
  pkg.version "3.12.0"
  pkg.md5sum "edd31875638ae3ef22ba116a6977276b"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
