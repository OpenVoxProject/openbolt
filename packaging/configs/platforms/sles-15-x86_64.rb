platform "sles-15-x86_64" do |plat|
  plat.inherit_from_default
  packages = %w(git)
  plat.provision_with("zypper -n install -y #{packages.join(' ')}")
end
