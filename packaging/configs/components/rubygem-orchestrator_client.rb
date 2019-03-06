component "rubygem-orchestrator_client" do |pkg, settings, platform|
  pkg.version "0.4.2"
  pkg.md5sum "a2c95a3fe3ab736092dc857a44a296a5"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
