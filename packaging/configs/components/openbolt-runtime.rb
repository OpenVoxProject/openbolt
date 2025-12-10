# frozen_string_literal: true

component 'openbolt-runtime' do |pkg, settings, platform|
  # The JSON name intentionally differs from the component, because automation to update
  # the puppet-runtime ref relies on the puppet-runtime name.
  unless settings[:puppet_runtime_version] && settings[:puppet_runtime_location] && settings[:puppet_runtime_basename]
    raise "Expected to find :puppet_runtime_version, :puppet_runtime_location, and :puppet_runtime_basename settings. " \
      "Please set these in your project file before including puppet-runtime as a component."
  end

  pkg.version settings[:puppet_runtime_version]

  tarball_name = "#{settings[:puppet_runtime_basename]}.tar.gz"
  pkg.url File.join(settings[:puppet_runtime_location], tarball_name)
  pkg.sha1sum File.join(settings[:puppet_runtime_location], "#{tarball_name}.sha1")

  pkg.install_only true

  install_command = if platform.is_windows?
                      # We need to make sure we're setting permissions correctly for the executables
                      # in the ruby bindir since preserving permissions in archives in windows is
                      # ... weird, and we need to be able to use cygwin environment variable use
                      # so cmd.exe was not working as expected.
                      [
                        "gunzip -c #{tarball_name} | tar -k -C /cygdrive/c/ -xf -",
                        "chmod 755 #{settings[:ruby_bindir].sub('C:', '/cygdrive/c')}/*"
                      ]
                    elsif platform.is_macos?
                      # We can't untar into '/' because of SIP on macOS; Just copy the contents
                      # of these directories instead:
                      [
                        "tar -xzf #{tarball_name}",
                        'rsync -ka opt/ /opt/'
                      ]
                    else
                      ["gunzip -c #{tarball_name} | #{platform.tar} -k -C / -xf -"]
                    end

  pkg.install do
    install_command
  end
end
