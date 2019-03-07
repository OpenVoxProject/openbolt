component "rubygem-r10k" do |pkg, settings, platform|
  pkg.version "3.1.1"
  pkg.md5sum "767b7a4b90bcb25fabb6edc424364514"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
