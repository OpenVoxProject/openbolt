# frozen_string_literal: true

require 'open3'
require 'rake'

RED = "\033[31m"
GREEN = "\033[32m"
RESET = "\033[0m"

def run_command(cmd, silent: true, print_command: false, report_status: false)
  puts "#{GREEN}Running #{cmd}#{RESET}" if print_command
  output = ''
  Open3.popen2e(cmd) do |_stdin, stdout_stderr, thread|
    stdout_stderr.each do |line|
      puts line unless silent
      output += line
    end
    exitcode = thread.value.exitstatus
    unless exitcode.zero?
      err = "#{RED}Command failed! Command: #{cmd}, Exit code: #{exitcode}"
      # Print details if we were running silent
      err += "\nOutput:\n#{output}" if silent
      err += RESET
      abort err
    end
    puts "#{GREEN}Command finished with status #{exitcode}#{RESET}" if report_status
  end
  output.chomp
end

begin
  require 'github_changelog_generator/task'
  require_relative 'lib/bolt/version'

  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.header = <<~HEADER.chomp
      # Changelog

      All notable changes to this project will be documented in this file.
    HEADER
    config.user = 'openvoxproject'
    config.project = 'openbolt'
    config.exclude_labels = %w[dependencies duplicate question invalid wontfix wont-fix modulesync skip-changelog]
    config.future_release = Bolt::VERSION
    # we limit the changelog to all new openvox releases, to skip perforce onces
    # otherwise the changelog generate takes a lot amount of time
    config.since_tag = '4.0.0'
  end
rescue LoadError
  task :changelog do
    abort('Run `bundle install --with release` to install the `github_changelog_generator` gem.')
  end
end

desc 'Prepare for a release'
task 'release:prepare' => [:changelog]

desc "Check for new versions of bundled modules"
task :update_modules do
  sh "scripts/update_modules.rb"
end

begin
  require 'voxpupuli/rubocop/rake'
rescue LoadError
  # the voxpupuli-rubocop gem is optional
end
