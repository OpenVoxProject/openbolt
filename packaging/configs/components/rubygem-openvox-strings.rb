#####
# Component release information:
#   https://rubygems.org/gems/openvox-strings
#   https://github.com/voxpupuli/openvox-strings/releases
#   https://github.com/voxpupuli/openvox-strings/blob/main/CHANGELOG.md
#####
component 'rubygem-openvox-strings' do |pkg, _settings, _platform|
  ### Maintained by update_gems automation ###
  pkg.version '7.0.0'
  pkg.sha256sum '721346006242976650f92553adfffcef076cad84ee63e93d64044e602333db00'
  pkg.build_requires 'rubygem-openvox'
  pkg.build_requires 'rubygem-rgen'
  pkg.build_requires 'rubygem-yard'
  pkg.build_requires 'rubygem-fiddle'
  pkg.build_requires 'rubygem-locale'
  ### End automated maintenance section ###

  instance_eval File.read('configs/components/_base-rubygem.rb')
end
