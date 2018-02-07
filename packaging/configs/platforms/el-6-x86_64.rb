platform "el-6-x86_64" do |plat|
  plat.servicedir "/etc/rc.d/init.d"
  plat.defaultdir "/etc/sysconfig"
  plat.servicetype "sysv"
  plat.add_build_repository "http://pl-build-tools.delivery.puppetlabs.net/yum/pl-build-tools-release-#{plat.get_os_name}-#{plat.get_os_version}.noarch.rpm"
  plat.add_build_repository "http://yum.puppetlabs.com/puppet5-nightly/puppet5-nightly-release-#{plat.get_os_name}-#{plat.get_os_version}.noarch.rpm"
  plat.provision_with "rpm --import http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs"
  plat.provision_with "yum install --assumeyes autoconf automake createrepo rsync gcc make rpmdevtools rpm-libs yum-utilsi autogen"
  plat.install_build_dependencies_with "yum install --assumeyes"
  plat.vmpooler_template "centos-6-x86_64"
end
