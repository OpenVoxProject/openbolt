component "rubygem-rack" do |pkg, settings, platform|
  pkg.version "2.0.6"
  pkg.md5sum "69cc82a54b431f0f947b38cf25030905"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
