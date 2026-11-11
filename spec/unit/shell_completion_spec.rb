# frozen_string_literal: true

require 'spec_helper'
require 'bolt/cli'
require 'json'
require 'open3'
require 'tmpdir'

describe Bolt::ShellCompletion do
  # Completion runs in a scratch directory that is also HOME, so cache files
  # in the real project and home directories do not leak in.
  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:transports) { Bolt::TRANSPORTS.keys.map(&:to_s) }
  let(:plan_names) { %w[aggregate::count mymodule::deploy] }

  def write_cache(path, names)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, names.to_h { |name| [name, {}] }.to_json)
  end

  # Runs code in shell with the completion script as $0 and args as the
  # positional parameters, and returns the lines it prints
  def run_completion(shell, code, *args)
    script = File.join(@dir, "completion.#{shell}")
    File.write(script, described_class.script(shell))
    output, status = Open3.capture2e({ 'HOME' => @dir }, shell, '-c', code, script, *args, chdir: @dir)
    raise "#{shell} completion failed: #{output}" unless status.success?

    output.lines(chomp: true)
  end

  describe 'bash', unless: Bolt::Util.windows? do
    # Returns what bash offers for the last of the words
    def complete(*words)
      run_completion('bash', <<~'BASH', *words)
        source "$0"
        COMP_WORDS=("$@")
        COMP_CWORD=$(($# - 1))
        _bolt
        [[ ${#COMPREPLY[@]} -eq 0 ]] || printf '%s\n' "${COMPREPLY[@]}"
      BASH
    end

    it 'registers the completion with file names as the fallback' do
      expect(run_completion('bash', 'source "$0"; complete -p bolt')).to eq(['complete -o default -F _bolt bolt'])
    end

    it 'completes subcommands' do
      expect(complete('bolt', '')).to match_array(Bolt::CLI::COMMANDS.keys)
    end

    it 'completes actions' do
      expect(complete('bolt', 'plan', '')).to match_array(%w[convert new run show])
    end

    it 'completes the options of the action' do
      expect(complete('bolt', 'plan', 'run', '--p')).to include('--params', '--password', '--private-key', '--project')
      expect(complete('bolt', 'plan', 'run', '--p')).not_to include('--pp')
      expect(complete('bolt', 'plan', 'new', '--p')).to include('--pp')
      expect(complete('bolt', 'plan', 'new', '--p')).not_to include('--params')
    end

    it 'completes global options before a subcommand' do
      expect(complete('bolt', '-')).to match_array(%w[-h --help --version --log-level --clear-cache])
    end

    it 'completes both forms of negatable options' do
      expect(complete('bolt', 'command', 'run', '--no-c')).to include('--no-cleanup', '--no-color')
    end

    it 'skips options and their values when it looks for the subcommand' do
      expect(complete('bolt', '--project', 'plan', 'task', '')).to match_array(%w[run show])
    end

    it 'completes option values' do
      expect(complete('bolt', 'task', 'run', '--transport', '')).to match_array(transports)
      expect(complete('bolt', 'task', 'run', '--log-level', '')).to match_array(Bolt::Logger::LEVELS)
    end

    it 'offers nothing for free-form values and arguments, so bash completes file names' do
      expect(complete('bolt', 'apply', '--inventoryfile', '')).to be_empty
      expect(complete('bolt', 'apply', '')).to be_empty
    end

    it 'completes guide topics' do
      expect(complete('bolt', 'guide', '')).to include('targets', 'transports')
    end

    it 'completes plan names from the cache of the project in the current directory' do
      write_cache(File.join(@dir, '.plan_cache.json'), plan_names)
      expect(complete('bolt', 'plan', 'run', '')).to match_array(plan_names)
      expect(complete('bolt', 'plan', 'run', 'aggregate::count', '')).to be_empty
    end

    it 'completes task names from the cache of the default project' do
      write_cache(File.join(@dir, '.puppetlabs', 'bolt', '.task_cache.json'), %w[facts package])
      expect(complete('bolt', 'task', 'show', '')).to match_array(%w[facts package])
    end
  end

  describe 'zsh', unless: Bolt::Util.windows? do
    before(:each) do
      skip 'zsh is not installed' unless system('zsh', '-c', 'true', out: File::NULL, err: File::NULL)
    end

    # Returns what zsh offers for the last of the words. Described words come
    # as "word:description", and file name completion as <files>. Functions
    # that print their input replace the completion builtins.
    def complete(*words)
      run_completion('zsh', <<~'ZSH', *words)
        compdef() { : }
        _describe() { print -rl -- ${(P)${@[-1]}} }
        _files() { print -r -- '<files>' }
        compadd() {
          if [[ $1 == -a ]]; then
            (( ${#${(P)2}} )) || return 1
            print -rl -- ${(P)2}
          else
            print -rl -- ${@:2}
          fi
        }
        source "$0"
        words=("$@")
        CURRENT=$#words
        _bolt
      ZSH
    end

    it 'completes subcommands with descriptions' do
      expect(complete('bolt', '')).to include('plan:Convert, create, show, and run plans',
                                              'completion:Print a shell completion script')
      expect(complete('bolt', '').size).to eq(Bolt::CLI::COMMANDS.size)
    end

    it 'completes actions with descriptions' do
      expect(complete('bolt', 'plan', '')).to include('run:Run a plan on the specified targets')
      expect(complete('bolt', 'plan', '').size).to eq(4)
    end

    it 'completes the options of the action with descriptions' do
      options = complete('bolt', 'plan', 'run', '-')
      expect(options).to include("--targets:Identifies the targets of the command. For more information, " \
                                 "see 'bolt guide targets'.")
      expect(options).to include('--no-color:Whether to show output in color.')
      expect(options.grep(/\A--pp:/)).to be_empty
    end

    it 'skips options and their values when it looks for the subcommand' do
      expect(complete('bolt', '--project', 'plan', 'task', '').map { |entry| entry.split(':').first })
        .to match_array(%w[run show])
    end

    it 'completes option values' do
      expect(complete('bolt', 'task', 'run', '--transport', '')).to match_array(transports)
    end

    it 'completes file names for free-form values and arguments' do
      expect(complete('bolt', 'apply', '--inventoryfile', '')).to eq(['<files>'])
      expect(complete('bolt', 'apply', '')).to eq(['<files>'])
    end

    it 'completes guide topics' do
      expect(complete('bolt', 'guide', '')).to include('targets', 'transports')
    end

    it 'completes plan names from the cache of the project in the current directory' do
      write_cache(File.join(@dir, '.plan_cache.json'), plan_names)
      expect(complete('bolt', 'plan', 'run', '')).to match_array(plan_names)
      expect(complete('bolt', 'plan', 'run', 'aggregate::count', '')).to eq(['<files>'])
    end
  end

  describe 'bolt completion' do
    it 'prints the script for the shell' do
      expect {
        expect {
          Bolt::CLI.new(%w[completion bash]).parse
        }.to raise_error(Bolt::CLIExit)
      }.to output(/^complete -o default -F _bolt bolt$/).to_stdout
    end

    it 'errors without a known shell' do
      allow($stdout).to receive(:puts)
      expect { Bolt::CLI.new(%w[completion]).parse }.to raise_error(Bolt::CLIError, /one of bash, zsh/)
      expect { Bolt::CLI.new(%w[completion fish]).parse }.to raise_error(Bolt::CLIError, /one of bash, zsh/)
    end
  end
end
