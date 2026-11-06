# frozen_string_literal: true

require 'bolt/completion/generator'
require 'bolt/completion/bash'
require 'bolt/completion/hints'
require 'bolt/completion/model'
require 'bolt/completion/zsh'
require 'open3'
require 'shellwords'
require 'tempfile'
require 'tmpdir'

describe 'completion generator' do
  let(:model) { Bolt::Completion::Model.build }

  describe 'common' do
    it 'lists the available shells' do
      expect(Bolt::Completion::Generator.shells).to eq(%w[bash zsh])
      expect(Bolt::Completion::Generator.shells).to eq(Bolt::Completion::SHELLS)
      expect(Bolt::CLI::COMMANDS['completion']).to eq(Bolt::Completion::SHELLS)
    end

    it 'shares renderer plumbing through a common base' do
      expect(Bolt::Completion::Bash).to be < Bolt::Completion::Base
      expect(Bolt::Completion::Zsh).to be < Bolt::Completion::Base
    end

    it 'errors for an unknown shell' do
      expect {
        Bolt::Completion::Generator.render('fish')
      }.to raise_error(Bolt::CLIError, /Unknown shell 'fish'/)
    end
  end

  describe 'model' do
    it 'builds an invocation for every command and action' do
      Bolt::CLI::COMMANDS.each do |subcommand, actions|
        command = model.commands.find { |candidate| candidate.name == subcommand }
        expect(command).not_to be_nil
        expected = actions.empty? ? [nil] : actions
        expect(command.invocations.map(&:action)).to eq(expected)
        command.invocations.each do |invocation|
          expect(invocation.options).not_to be_empty
        end
      end
    end

    it 'only has hints for real invocations and options' do
      keys = model.commands.flat_map { |command| command.invocations.map(&:key) }
      hints = Bolt::Completion::Hints
      expect(hints::POSITIONALS.keys - keys).to be_empty
      expect(hints::OPTION_TYPES.keys - model.options.map(&:name)).to be_empty
      expect(hints::STATIC_VALUES.keys - model.options.map(&:name)).to be_empty
    end

    it 'exposes the global options from the parser' do
      expect(model.global_options.map(&:name))
        .to eq(Bolt::BoltOptionParser::OPTIONS[:global])
    end
  end

  describe 'bash' do
    let(:script) { Bolt::Completion::Generator.render('bash') }
    let(:bash) { Bolt::Completion::Bash.new(model) }

    it 'parses as bash syntax' do
      skip 'bash is unavailable' unless system('bash --version > /dev/null 2>&1')

      Tempfile.create('bolt-completion') do |file|
        file.write(script)
        file.flush
        expect(system('bash', '-n', file.path, out: File::NULL, err: File::NULL)).to be(true)
      end
    end

    it 'completes every subcommand name' do
      line = script.lines.find { |line| line.start_with?('    next="') }
      words = line[/\A\s*next="(.*)"\s*\z/, 1]
      expect(words).to include(Bolt::CLI::COMMANDS.keys.join(' '))
    end

    it 'recognizes every subcommand when scanning the command line' do
      line = script.lines.find { |line| line.include?('local subactions=') }
      words = line[/subactions="(.*)"/, 1].split
      expect(words).to eq(Bolt::CLI::COMMANDS.keys)
    end

    it 'has a case for every command and action' do
      model.commands.each do |command|
        expect(script).to include("      #{command.name})")
        command.invocations.filter_map(&:action).each do |action|
          expect(script).to include("          #{action})")
        end
      end
    end

    it 'only allows target completion where the options include --targets' do
      helper = script[/^_bolt_targets_allowed\(\) \{.*?^\}/m]
      expect(helper).to include('apply) return 0')
      expect(helper).to include('plan:run) return 0')
      expect(helper).not_to include('guide')
    end

    it 'detects value-taking options from the parser' do
      line = script.lines.find { |line| line.include?('== *" $1 "') }
      words = line[/\[\[ "(.*) " ==/, 1].split
      expect(words).to include('-t', '--log-level', '--project')
      expect(words).not_to include('--noop', '--clear-cache')
    end

    it 'completes the transport enum values' do
      expect(script).to match(
        /elif \[ "\$prev" == "--transport" \]; then\s*\n\s*next="choria docker jail local lxd podman remote ssh winrm"/
      )
    end

    it 'uses the generic positional and entity helpers' do
      expect(script).to include('_bolt_positional()')
      expect(script).to include("_bolt_positional $_bolt_actix \"$next\" 'entity|plan|plans|plan|'")
      expect(script).to include("_bolt_positional $_bolt_actix \"$next\" 'entity|task|tasks|task|'")
      expect(script).not_to include('COMP_CWORD -eq 3')
    end

    it 'completes files for positional arguments' do
      skip 'bash is unavailable' unless system('bash --version > /dev/null 2>&1')

      Dir.mktmpdir do |dir|
        manifest = File.join(dir, 'manifest.pp')
        File.write(manifest, '')
        result = complete(script, ['bolt', 'apply', File.join(dir, 'man')], 2)
        expect(result).to include(manifest)
      end
    end

    it 'does not file-complete the lookup key' do
      skip 'bash is unavailable' unless system('bash --version > /dev/null 2>&1')

      Dir.mktmpdir do |dir|
        key_file = File.join(dir, 'somekey')
        File.write(key_file, '')
        result = complete(script, ['bolt', 'lookup', File.join(dir, 'some')], 2)
        expect(result).not_to include(key_file)
      end
    end

    it 'completes source files for file upload' do
      skip 'bash is unavailable' unless system('bash --version > /dev/null 2>&1')

      Dir.mktmpdir do |dir|
        source = File.join(dir, 'source.txt')
        File.write(source, '')
        result = complete(script, ['bolt', 'file', 'upload', File.join(dir, 'sou')], 3)
        expect(result).to include(source)
      end
    end

    it 'completes a script file when options precede it' do
      skip 'bash is unavailable' unless system('bash --version > /dev/null 2>&1')

      Dir.mktmpdir do |dir|
        script_file = File.join(dir, 'myscript.sh')
        File.write(script_file, '')
        words = ['bolt', 'script', 'run', '--project', dir, File.join(dir, 'mysc')]
        result = complete(script, words, 5)
        expect(result).to include(script_file)
      end
    end
  end

  describe 'zsh' do
    let(:script) { Bolt::Completion::Generator.render('zsh') }

    it 'parses as zsh syntax' do
      skip 'zsh is unavailable' unless system('zsh --version > /dev/null 2>&1')

      Tempfile.create('bolt-completion') do |file|
        file.write(script)
        file.flush
        expect(system('zsh', '-n', file.path, out: File::NULL, err: File::NULL)).to be(true)
      end
    end

    it 'starts with the compdef line' do
      expect(script.lines.first).to eq("#compdef bolt\n")
    end

    it 'declares the global option array' do
      expect(script).to match(/^\s*local -a opts_globals=/)
      expect(script).not_to match(/^\s*local -a opts_(?!globals)/)
      expect(script).not_to include('opts_action')
    end

    it 'describes the subcommands' do
      expect(script).to match(/_describe -t subcommands 'subcommand' _bolt_subcommands/)
    end

    it 'renders option entries with their descriptions' do
      expect(script).to match(/--clear-cache\[Clear plugin, plan, and task caches before executing\.\]'/)
    end

    it 'lists the guide topics' do
      expect(script).to match(/^\s*'debugging:/)
    end

    it 'dispatches and defines every command and action' do
      model.commands.each do |command|
        expect(script).to match(/^ +#{Regexp.escape(command.name)}\s*\) _bolt_#{Regexp.escape(command.name)} ;;/)
        command.invocations.each do |invocation|
          expect(script).to include("#{invocation.function_name} () {")
        end
      end
    end

    it 'uses generic entity helpers' do
      expect(script).to include('_bolt_entity_names ()')
      expect(script).to include('_bolt_entity_params ()')
      expect(script).not_to include('_bolt_plan_names')
      expect(script).not_to include('_bolt_task_params')
    end
  end

  describe 'shared headers' do
    let(:bash) { Bolt::Completion::Generator.render('bash') }
    let(:zsh) { Bolt::Completion::Generator.render('zsh') }

    it 'uses the same header in both shells' do
      ['OpenBolt shell completion',
       'generated by `bolt completion <shell>`',
       'BOLT_COMPLETION_TARGETS',
       'BOLT_COMPLETION_RUBY',
       'install it as `_bolt`'].each do |line|
        expect(bash).to include(line)
        expect(zsh).to include(line)
      end
    end

    it 'removes editor modelines' do
      [bash, zsh].each do |script|
        expect(script).not_to include('vim:')
        expect(script).not_to include('Local Variables')
      end
    end
  end

  describe 'shell parity' do
    let(:bash) { Bolt::Completion::Bash.new(model) }
    let(:zsh) { Bolt::Completion::Zsh.new(model) }
    let(:global) { model.global_options.map(&:name) }

    it 'offers the same options and positionals for every invocation' do
      model.commands.flat_map(&:invocations).each do |invocation|
        bash_tokens = bash.send(:bash_tokens, invocation).split
        zsh_entries = zsh.send(:zsh_arguments_for, invocation).join("\n")
        bash_case = bash.send(:bash_invocation_case, invocation, '$_bolt_actix', 0).join("\n")

        invocation.options.each do |option|
          expect(zsh_entries).to include("--#{option.name}")
          expect(bash_tokens).to include("--#{option.name}") unless global.include?(option.name)
        end

        invocation.positionals.each do |positional|
          expect(bash_case).to include("|#{positional.label}|")
          expect(zsh_entries).to include(positional.label)
        end
      end
    end
  end

  def complete(script, words, cword)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'completion.bash')
      File.write(path, script)
      command = [
        "source #{Shellwords.escape(path)}",
        "COMP_WORDS=(#{words.map { |word| Shellwords.escape(word) }.join(' ')})",
        "COMP_CWORD=#{cword}",
        '_bolt_complete',
        'printf "%s\\n" "${COMPREPLY[@]}"'
      ].join('; ')
      stdout, stderr, status = Open3.capture3('bash', '-c', command)
      raise "completion failed: #{stderr}" unless status.success?

      stdout.split("\n")
    end
  end
end
