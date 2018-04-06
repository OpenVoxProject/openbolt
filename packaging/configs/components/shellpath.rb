component "shellpath" do |pkg, settings, platform|
  pkg.version "2018-04-06"
  pkg.add_source "file://resources/files/bolt-bin.sh", sum: "f5987a68adf3844ca15ba53813ad6f63"
  pkg.add_source "file://resources/files/bolt-bin.csh", sum: "62b360a7d15b486377ef6c7c6d05e881"
  pkg.install_file("./bolt-bin.sh", "/etc/profile.d/bolt-bin.sh")
  pkg.install_file("./bolt-bin.csh", "/etc/profile.d/bolt-bin.csh")
end
