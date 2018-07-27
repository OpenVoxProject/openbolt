component "rubygem-logging" do |pkg, settings, platform|
  pkg.version "2.2.2"
  pkg.md5sum "13c12082ef0b69a639ed7ca318e7f514"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
