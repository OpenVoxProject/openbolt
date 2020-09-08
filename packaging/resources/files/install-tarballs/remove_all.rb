require 'pathname'
require 'fileutils'

script_dir = __dir__
install_dir = File.expand_path(File.join(script_dir, '..', '..'))

def logmessage(message)
  puts message
end

def ruby_api_version(ruby_version)
  gem_ver = Gem::Version.new(ruby_version)
  gem_ver.segments[0..1].join('.') + '.0'
end

# Remove the ruby and puppet cache, but not the actual runtime for the ruby we're _actually_ using
# right now. We need that!
dirs_to_delete = ["lib/ruby/gems"]

dirs_to_delete.each { |dir| logmessage("'#{dir}' is scheduled for deletion") }
dirs_to_delete.each do |dir|
  absolute_dir = File.join(install_dir, dir)
  logmessage("Attempting to delete '#{absolute_dir}'...")
  FileUtils.rm_rf(absolute_dir)
end
