# This file is a common basis for multiple rubygem components.
#
# It should not be included as a component itself; Instead, other components
# should load it with instance_eval after setting pkg.version. Parts of this
# shared configuration may be overridden afterward.

name = pkg.get_name.gsub('rubygem-', '')
raise 'Rubygem component files that instance_eval _base-rubygem must be named rubygem-<gem-name>.rb' unless name && !name.empty?

version = pkg.get_version
raise "You must set the `pkg.version` in your rubygem component before instance_eval'ing _base_rubygem.rb" unless version && !version.empty?

pkg.build_requires "runtime-#{settings[:runtime_project]}"
pkg.build_requires 'pl-ruby-patch' if platform.is_cross_compiled?

if platform.is_windows?
  pkg.environment 'PATH',
                  "$(shell cygpath -u #{settings[:gcc_bindir]}):$(shell cygpath -u #{settings[:ruby_bindir]}):$(shell cygpath -u #{settings[:bindir]}):/cygdrive/c/Windows/system32:/cygdrive/c/Windows:/cygdrive/c/Windows/System32/WindowsPowerShell/v1.0:$(PATH)"
end

# When cross-compiling, we can't use the rubygems we just built.
# Instead we use the host gem installation and override GEM_HOME. Yay?
pkg.environment 'GEM_HOME', settings[:gem_home]
pkg.environment 'GEM_PATH', settings[:gem_home]

# PA-25 in order to install gems in a cross-compiled environment we need to
# set RUBYLIB to include puppet and hiera, so that their gemspecs can resolve
# hiera/version and puppet/version requires. Without this the gem install
# will fail by blowing out the stack.
pkg.environment 'RUBYLIB', "#{settings[:ruby_vendordir]}:$(RUBYLIB)" if settings[:ruby_vendordir]

pkg.url("https://rubygems.org/downloads/#{name}-#{version}.gem")
pkg.mirror("#{settings[:buildsources_url]}/#{name}-#{version}.gem")

# If a gem needs more command line options to install set the :gem_install_options
# in its component file rubygem-<compoment>, before the instance_eval of this file.
gem_install_options = settings["#{pkg.get_name}_gem_install_options".to_sym]
# Set a default gem_uninstall
gem_uninstall = settings[:gem_uninstall] || "#{settings[:host_gem]} uninstall --all --ignore-dependencies"
pkg.install do
  steps = []
  # Attempting to uninstall a default gem this way will fail, so ignore failures
  steps << "#{gem_uninstall} --force --silent #{name} || true"
  steps << "#{settings[:gem_install]} #{name}-#{version}.gem #{gem_install_options || ''}"
  # If we are installing a newer version of a default gem, we need to remove the existing
  # specification file so that we don't get warnings. The corresponding gem directory is
  # usually empty and only there for compatibility reasons, so we remove that too to avoid confusion.
  steps << "rm -fv #{settings[:gem_home]}/specifications/default/#{name}-*.gemspec"
  steps << "rm -rfv #{settings[:gem_home]}/gems/#{name}-*[!#{version}]"
end
