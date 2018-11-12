component "rubygem-r10k" do |pkg, settings, platform|
  pkg.version "2.6.5"
  pkg.md5sum "cdafd1663ab651ef06c1d28c30827521"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
