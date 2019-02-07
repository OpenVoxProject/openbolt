platform "fedora-29-x86_64" do |plat|
  plat.servicedir "/usr/lib/systemd/system"
  plat.defaultdir "/etc/sysconfig"
  plat.servicetype "systemd"

  plat.vmpooler_template "fedora-29-x86_64"
  plat.dist "fc29"

  packages = %w[
    autoconf automake bzip2-devel gcc gcc-c++
    make cmake pkgconfig readline-devel
    rpm-libs rpmdevtools rsync swig zlib-devel git
  ]
  plat.provision_with("/usr/bin/dnf install -y --best --allowerasing #{packages.join(' ')}")

  plat.install_build_dependencies_with "/usr/bin/dnf install -y --best --allowerasing"
end
