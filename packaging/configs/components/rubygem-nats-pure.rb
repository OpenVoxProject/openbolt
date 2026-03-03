#####
# Component release information:
#   https://rubygems.org/gems/nats-pure
#   https://github.com/nats-io/nats-pure.rb/blob/main/CHANGELOG.md
#####
component 'rubygem-nats-pure' do |pkg, _settings, _platform|
  # WARNING Update ahead
  # You shall not update beyond 0.6.0, because that is what bundler determined
  # https://github.com/OpenVoxProject/puppet-runtime/issues/128#issuecomment-3989498214
  ### Maintained by update_gems automation ###
  pkg.version '0.6.2'
  pkg.sha256sum '4c8b24466ae4a364ac5e5f066d5045b6825632993a3d39ddd91718c2bc86c1f5'
  ### End automated maintenance section ###

  instance_eval File.read('configs/components/_base-rubygem.rb')
end
