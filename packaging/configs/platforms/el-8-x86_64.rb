peversion = IO.read('peversion').strip
platform "el-8-x86_64" do |plat|
  plat.servicedir "/usr/lib/systemd/system"
  plat.defaultdir "/etc/sysconfig"
  plat.servicetype "systemd"

  plat.provision_with "rpm --import http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs"
  plat.add_build_repository "http://enterprise.delivery.puppetlabs.net/#{peversion}/repos/#{plat.get_name}/#{plat.get_name}.repo"
  plat.provision_with "yum install --assumeyes autoconf automake rsync gcc createrepo make rpmdevtools rpm-libs yum-utils rpm-sign libtool git"
  plat.install_build_dependencies_with "yum install --assumeyes"
  plat.vmpooler_template "redhat-8-x86_64"
end
