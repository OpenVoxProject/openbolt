component "rubygem-gssapi" do |pkg, settings, platform|
  pkg.version "1.2.0"
  pkg.md5sum "c0d2b5894fdc11a026b4d09bc33f8b42"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
