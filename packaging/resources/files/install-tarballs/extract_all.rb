# frozen_string_literal: true

# Idea from https://stackoverflow.com/questions/856891/unzip-zip-tar-tag-gz-files-with-ruby
# Altered using https://github.com/puppetlabs/puppet/blob/983154f7e29a2a50d416d889a6fed012b9b12399/lib/puppet/module_tool/tar/mini.rb
#
# WARNING - This extraction blindly assumes the tarballs are sane and correct. Unlike the `.../module_tool/tar/mini.rb` implementation, this
# script does not do any checks:
# - Symlinks within the tar will throw an error
# - We assume that all files in the tar have relative paths.
#   If there is an absolute path in the tarball it will 'escape' the intended extract directory
# - Avoids extra disk IO (e.g. expand_path) as the tarballs will have 30,000+ files inside

require 'fileutils'
require 'rubygems/package'
require 'zlib'

TAR_LONGLINK = '././@LongLink'

def logmessage(message)
  puts message if ENV['BOLT_DEBUG']
end

EXECUTABLE = 0o755
NOT_EXECUTABLE = 0o644
USER_EXECUTE = 0o100

def sanitized_mode(old_mode)
  old_mode.nobits?(USER_EXECUTE) ? NOT_EXECUTABLE : EXECUTABLE
end

def unpack(sourcefile, destdir, _)
  Gem::Package::TarReader.new(Zlib::GzipReader.open(sourcefile)) do |tar|
    dest = nil
    tar.each do |entry|
      if entry.full_name == TAR_LONGLINK
        dest = File.join destdir, entry.read.strip
        next
      end
      dest ||= File.join(destdir, entry.full_name)
      if entry.directory? || (entry.header.typeflag == '' && entry.full_name.end_with?('/'))
        # Due to the size of the tarballs, logging consumes a ton of time. Just ignore it for now
        # logmessage("dir #{dest}")
        File.delete dest if File.file? dest
        # set_dir_mode! from mini.rb will always set this to EXECUTABLE so just use that - ref
        FileUtils.mkdir_p dest, mode: EXECUTABLE, verbose: false
      elsif entry.file? || (entry.header.typeflag == '' && !entry.full_name.end_with?('/'))
        # Due to the size of the tarballs, logging consumes a ton of time. Just ignore it for now
        # logmessage "file #{dest}"
        FileUtils.rm_rf dest if File.directory? dest
        File.open dest, "wb" do |f|
          f.print entry.read
        end
        FileUtils.chmod sanitized_mode(entry.header.mode), dest, verbose: false
      # There should be NO symlinks on our tarballs so just ignore them
      # elsif entry.header.typeflag == '2' #Symlink!
      #   File.symlink entry.header.linkname, dest
      else
        logmessage("Unkown tar entry: #{entry.full_name} type: #{entry.header.typeflag}.")
      end
      dest = nil
    end
  end
end

script_dir = __dir__
dest_dir = File.expand_path(File.join(script_dir, '..', '..'))

Dir.glob(File.join(script_dir, '*.tgz')) do |targz_filename|
  logmessage("Extracting #{targz_filename} to #{dest_dir} ...")
  unpack(targz_filename, dest_dir, nil)
end
