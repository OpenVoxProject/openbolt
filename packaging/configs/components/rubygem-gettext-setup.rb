component "rubygem-gettext-setup" do |pkg, settings, platform|
  pkg.version "0.30"
  pkg.md5sum "b7de0e7af0f56ddc55c88435ee95fd47"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
