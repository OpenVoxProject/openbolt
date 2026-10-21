# frozen_string_literal: true

require 'bolt/completion/generator'
require 'tempfile'

describe 'completion generator' do
  describe 'common' do
    it 'lists the available shells' do
      expect(Bolt::Completion::Generator.shells).to eq(%w[bash zsh])
    end

    it 'errors for an unknown shell' do
      expect {
        Bolt::Completion::Generator.render('fish')
      }.to raise_error(Bolt::CLIError, /Unknown shell 'fish'/)
    end
  end

  describe 'bash' do
    let(:script) { Bolt::Completion::Generator.render('bash') }

    it 'parses as bash syntax' do
      skip 'bash is unavailable' unless system('bash --version > /dev/null 2>&1')

      Tempfile.create('bolt-completion') do |f|
        f.write(script)
        f.flush
        expect(system('bash', '-n', f.path, out: File::NULL, err: File::NULL)).to be(true)
      end
    end

    it 'completes every subcommand name' do
      line = script.lines.find { |l| l.start_with?('    next="') }
      words = line[/\A\s*next="(.*)"\s*\z/, 1]
      expect(words).to include(Bolt::CLI::COMMANDS.keys.join(' '))
    end

    it 'recognizes every subcommand when scanning the command line' do
      line = script.lines.find { |l| l.include?('local subactions=') }
      words = line[/subactions="(.*)"/, 1].split
      expect(words).to eq(Bolt::CLI::COMMANDS.keys)
    end

    it 'offers guide topics as positional arguments' do
      expect(script).to match(/^ {6}guide\)\n {8}next="[^"]*debugging/)
    end

    it 'offers file completion for the script argument' do
      expect(script).to match(
        /^ {6}script\)\n {8}case \$action in\n {10}run\)\n {12}if \[ \$COMP_CWORD -eq 3 \]/
      )
    end

    it 'only allows target completion where the options include --targets' do
      helper = script[/^_bolt_targets_allowed\(\) \{.*?^\}/m]
      expect(helper).to include('apply) return 0')
      expect(helper).to include('plan:run) return 0')
      expect(helper).not_to include('guide')
    end

    it 'detects value-taking options from the parser' do
      line = script.lines.find { |l| l.include?('== *" $1 "') }
      words = line[/\[\[ "(.*) " ==/, 1].split
      expect(words).to include('-t', '--log-level', '--project')
      expect(words).not_to include('--noop', '--clear-cache')
    end

    it 'completes the transport enum values' do
      expect(script).to match(
        /elif \[ "\$prev" == "--transport" \]; then\s*\n\s*next="choria docker jail local lxd podman remote ssh winrm"/
      )
    end

    it 'completes plan and task run entity slots via the dynamic helpers' do
      expect(script).to match(/_bolt_entity_slot plans plan "[^"]*"\s*\|\| return 0/)
      expect(script).to match(/_bolt_entity_slot tasks task "[^"]*"\s*\|\| return 0/)
    end
  end

  describe 'zsh' do
    let(:script) { Bolt::Completion::Generator.render('zsh') }

    it 'parses as zsh syntax' do
      skip 'zsh is unavailable' unless system('zsh --version > /dev/null 2>&1')

      Tempfile.create('bolt-completion') do |f|
        f.write(script)
        f.flush
        expect(system('zsh', '-n', f.path, out: File::NULL, err: File::NULL)).to be(true)
      end
    end

    it 'declares the option groups' do
      expect(script).to match(/^\s*local -a opts_globals=/)
    end

    it 'describes the subcommands' do
      expect(script).to match(/_describe -t subcommands 'subcommand' _bolt_subcommands/)
    end

    it 'renders option entries with their descriptions' do
      expect(script).to match(/^.*--clear-cache\[Clear plugin, plan, and task caches before executing\.\]'/)
    end

    it 'lists the guide topics' do
      expect(script).to match(/^\s*'debugging:/)
    end

    it 'dispatches every subcommand' do
      Bolt::CLI::COMMANDS.each_key do |sub|
        expect(script).to match(/^ +#{Regexp.escape(sub)}\s*\) _bolt_#{Regexp.escape(sub)} ;;/)
      end
    end
  end
end
