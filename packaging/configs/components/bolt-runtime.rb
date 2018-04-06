component 'bolt-runtime' do |pkg, settings, platform|
  runtime_details = JSON.parse(File.read('configs/components/bolt-runtime.json'))
  runtime_tag = runtime_details['ref'][/refs\/tags\/(.*)/, 1]
  raise "Unable to determine a tag for bolt-runtime (given #{runtime_details['ref']})" unless runtime_tag
  pkg.version runtime_tag

  tarball_name = "bolt-runtime-#{pkg.get_version}.#{platform.name}.tar.gz"

  pkg.sha1sum "http://builds.puppetlabs.lan/puppet-runtime/#{pkg.get_version}/artifacts/#{tarball_name}.sha1"
  pkg.url "http://builds.puppetlabs.lan/puppet-runtime/#{pkg.get_version}/artifacts/#{tarball_name}"

  pkg.install_only true

  if platform.is_windows?
    # We need to make sure we're setting permissions correctly for the executables
    # in the ruby bindir since preserving permissions in archives in windows is
    # ... weird, and we need to be able to use cygwin environment variable use
    # so cmd.exe was not working as expected.
    install_command = [
      "gunzip -c #{tarball_name} | tar -k -C /cygdrive/c/ -xf -",
      "chmod 755 #{settings[:ruby_bindir].sub(/C:/, '/cygdrive/c')}/*"
    ]
  elsif platform.is_macos?
    # We can't untar into '/' because of SIP on macOS; Just copy the contents
    # of these directories instead:
    install_command = [
      "tar -xzf #{tarball_name}",
      "for d in opt var private; do rsync -ka \"$${d}/\" \"/$${d}/\"; done"
    ]
  else
    install_command = ["gunzip -c #{tarball_name} | #{platform.tar} -k -C / -xf -"]
  end

  pkg.install do
    install_command
  end
end
