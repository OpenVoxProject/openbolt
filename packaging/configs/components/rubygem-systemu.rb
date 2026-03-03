#####
# Component release information:
#   https://rubygems.org/gems/systemu
#####
component 'rubygem-systemu' do |pkg, _settings, _platform|
  ### Maintained by update_gems automation ###
  pkg.version '2.6.5'
  pkg.sha256sum '01f7d014b1453b28e5781e15c4d7d63fc9221c29b174b7aae5253207a75ab33e'
  ### End automated maintenance section ###

  instance_eval File.read('configs/components/_base-rubygem.rb')
end
