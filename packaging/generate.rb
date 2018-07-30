#!/usr/bin/env ruby

require 'bundler'
require 'net/http'

lockfile = ARGV.first
if lockfile.nil?
  warn 'Usage: generate.rb /path/to/Gemfile.lock'
  exit 1
end

unless File.exist? lockfile
  warn "Lockfile #{lockfile} does not exist"
  exit 1
end

unless File.readable? lockfile
  warn "Lockfile #{lockfile} could not be read"
  exit 1
end

bundle = Bundler::LockfileParser.new(Bundler.read_file(lockfile))

http = Net::HTTP.start('artifactory.delivery.puppetlabs.net', use_ssl: true)

mirrors_needed = false

bundle.specs.each do |s|
  filename = "configs/components/rubygem-#{s.name}.rb"
  unless File.exist? filename
    puts "Skipping unmanaged gem #{s.name}"
    next
  end

  # Get MD5 of file, or warn if file is not mirrored
  resp = http.head("/artifactory/generic__buildsources/buildsources/#{s.name}-#{s.version}.gem")
  case resp
  when Net::HTTPSuccess
    sum = resp['X-Checksum-Md5']

    File.write filename, <<-CONTENT
component "rubygem-#{s.name}" do |pkg, settings, platform|
  pkg.version "#{s.version}"
  pkg.md5sum "#{sum}"
  instance_eval File.read('configs/components/_base-rubygem.rb')
end
CONTENT
  else
    mirrors_needed = true
    warn "Could not update #{s.name}, please mirror with: !mirrorsource https://rubygems.org/downloads/#{s.name}-#{s.version}.gem"
  end
end

warn "Some gems need mirroring, please run the provided commands in the 'release-new' HipChat room" if mirrors_needed

