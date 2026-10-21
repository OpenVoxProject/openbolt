# frozen_string_literal: true

require 'erb'
require 'yaml'

require_relative '../bolt_option_parser'
require_relative '../cli'

module Bolt
  module Completion
    # Renders the bolt shell completion scripts (see `bolt completion`).
    #
    # Every static table in the scripts is derived from the same sources the
    # CLI uses at runtime, so the completions cannot drift from bolt:
    #
    # * subcommands and actions: Bolt::CLI::COMMANDS
    # * the option set of each `bolt <subcommand> [action]`:
    #   BoltOptionParser#get_help_text, pruned exactly like
    #   BoltOptionParser#update does when bolt parses arguments
    # * option spellings (short forms, --no- pairs) and whether an option
    #   takes a value: the parser's own OptionParser switch objects
    # * candidate values for options that restrict them
    #   (--transport, --choria-task-agent): the parser's candidate lists
    # * guide topics: the yaml files in the guides directory
    #
    # The interactive machinery (live `bolt` calls, in-memory caching, word
    # scanning) is hand-written text in the ERB templates under
    # lib/bolt/completion/templates and is independent of the CLI surface.
    class Generator
      SHELLS = %w[bash zsh].freeze

      TEMPLATE_DIR = File.expand_path('templates', __dir__)

      # Options that exclude each other ('--targets', '--rerun', and '--query'
      # cannot be combined). The order defines the tokens of the generated
      # exclusion sets.
      TARGETING = Bolt::CLI::TARGETING_OPTIONS.map(&:to_s).freeze

      # Static candidate lists for options whose values optparse does not
      # restrict.
      FILTERS = %w[all failure success].freeze
      FORMATS = %w[human json rainbow].freeze

      # How each option's value completes in zsh (the text after the option
      # description). Options with candidate lists are rendered from their
      # candidate lists; anything unlisted completes as a free value.
      VALUE_SPEC = {
        'targets'     => ':targets: _bolt_target_list',
        'query'       => ':query: _message "PuppetDB query"',
        'user'        => ':user:',
        'password'    => ':password:',
        'private-key' => ':private key: _files',
        'run-as'      => ':run as user:',
        'sudo-password' => ':sudo password:',
        'sudo-executable' => ':executable: _path_commands',
        'concurrency' => ':count: _guard "[0-9]#" number',
        'compile-concurrency' => ':count: _guard "[0-9]#" number',
        'modulepath'  => ':modulepath: _files -/',
        'project'     => ':project: _files -/',
        'hiera-config' => ':hiera config: _files',
        'inventoryfile' => ':inventory file: _files',
        'puppetdb' => ':instance:',
        'connect-timeout' => ':seconds: _guard "[0-9]#" seconds',
        'ssh-command' => ':command: _path_commands',
        'copy-command' => ':command: _path_commands',
        'tmpdir' => ':tmpdir: _files -/',
        'choria-config-file' => ':config file: _files',
        'choria-mcollective-certname' => ':certname:',
        'choria-ssl-ca' => ':ca file: _files',
        'choria-ssl-cert' => ':cert file: _files',
        'choria-ssl-key' => ':key file: _files',
        'choria-collective' => ':collective:',
        'choria-puppet-environment' => ':environment:',
        'choria-rpc-timeout' => ':seconds: _guard "[0-9]#" seconds',
        'choria-task-timeout' => ':seconds: _guard "[0-9]#" seconds',
        'choria-command-timeout' => ':seconds: _guard "[0-9]#" seconds',
        'choria-brokers' => ':brokers:',
        'choria-broker-timeout' => ':seconds: _guard "[0-9]#" seconds',
        'params'      => ':params: _message "JSON parameters"',
        'execute'     => ':manifest code:',
        'env-var'     => ':environment variable: _message "name=value"',
        'filter'      => ':filter: _message "substring filter"',
        'modules'     => ':modules: _message "comma separated module names"',
        'plugin'      => ':plugin: _message "plugin name"'
      }.freeze

      # Options whose values complete as filesystem paths in bash (the
      # _files entries of VALUE_SPEC).
      FILE_VALUE_OPTS = VALUE_SPEC.select { |_, spec| spec.include?('_files') }.keys.freeze

      # The plural kind names of ENTITY_HOOKS mapping to their singular word.
      KIND_SINGULAR = { 'plans' => 'plan', 'tasks' => 'task' }.freeze

      # Positional arguments of each `bolt <subcommand> [action]`.
      # Keys are "<subcommand>:<action>" ("<subcommand>:" for subcommands
      # without actions). Coordinated with the dynamic helper hooks.
      POSITIONALS = {
        'apply:'         => [':manifest file: _files'],
        'guide:'         => [':topic: _describe "guide" topics'],
        'lookup:'        => [':Hiera key: _message "key to look up"'],
        'command:run'    => [':remote command: _message "command to run"'],
        'file:download'  => [':remote source: _message "remote file"',
                             ':destination directory: _files -/'],
        'file:upload'    => [':source file or directory: _files',
                             ':remote destination: _message "remote path"'],
        'module:add'     => [':module: _message "module name (e.g. puppetlabs-apt)"'],
        'module:show'    => ['::module: _message "module name"'],
        'plan:new'       => [':plan name: _message "plan name (mymodule::myplan)"'],
        'policy:apply'   => [':policy: _message "policy (comma separated list to apply several)"'],
        'policy:new'     => [':policy name: _message "policy name"'],
        'project:init'   => ['::project name: _message "project name"'],
        'script:run'     => [':script: _files',
                             '*::script argument: _message "script argument"'],
        'secret:decrypt' => [':ciphertext: _message "ciphertext"'],
        'secret:encrypt' => ['::plaintext: _message "plaintext"']
      }.freeze

      # Subcommand actions that complete entity names and (where allowed)
      # "name=" parameters via the dynamic helpers.
      ENTITY_HOOKS = {
        'plan:convert' => { names: 'plans' },
        'plan:run'     => { names: 'plans', params: true },
        'plan:show'    => { names: 'plans', optional: true },
        'task:run'     => { names: 'tasks', params: true },
        'task:show'    => { names: 'tasks', optional: true }
      }.freeze

      attr_reader :shell

      class << self
        # Renders the completion script for the given shell.
        def render(shell)
          new(shell).render
        end

        # The shells of the `bolt completion <shell>` subcommand.
        def shells
          SHELLS
        end

        private :new
      end

      def initialize(shell)
        unless SHELLS.include?(shell)
          raise Bolt::CLIError,
                "Unknown shell '#{shell}'; available shells: #{SHELLS.join(', ')}."
        end

        @shell = shell
        @switches = {}
        collect_switches
      end

      # Renders the script for @shell. The methods below are the interface
      # the templates call.
      def render
        template = File.join(TEMPLATE_DIR, "bolt-completion.#{shell}.erb")
        content = File.read(template)
        ERB.new(content, trim_mode: '-').result(binding)
      end

      # The command tree:
      # [{ name:, bare:, actions: [{ name:, bare:, key: }] }]
      def commands
        @commands ||= begin
          parser = BoltOptionParser.new({})
          Bolt::CLI::COMMANDS.map do |sub, actions|
            {
              name: sub,
              bare: description_from(parser.get_help_text(sub, nil)[:banner]),
              actions: actions.map do |action|
                { name: action,
                  bare: description_from(parser.get_help_text(sub, action)[:banner]),
                  key: "#{sub}:#{action}" }
              end
            }
          end
        end
      end

      # Guide topics from the guides directory: [[name, description], ...]
      def guide_topics
        @guide_topics ||= begin
          dir = File.expand_path(File.join(__dir__, '..', '..', '..', 'guides'))
          Dir.children(dir).sort
             .select { |f| f.end_with?('.yaml') }
             .map do |file|
            info = YAML.safe_load_file(File.join(dir, file))
            [info['topic'], first_sentence(info['guide'].to_s)]
          rescue StandardError
            [file.delete_suffix('.yaml'), '']
          end
        end
      end

      ####################################################################
      # zsh emission

      # The per-group option arrays declared at the top of the main zsh
      # function, rendered from the parser's own OPTIONS groups.
      def zsh_opt_groups
        @zsh_opt_groups ||= begin
          lines = ['  local -a opts_globals=(']
          BoltOptionParser::OPTIONS[:global].each do |name|
            Array(zsh_entry(switch(name))).each { |e| lines << "    #{e}" }
          end
          lines += ['  )', '']
          BoltOptionParser::OPTIONS.except(:global).each do |group, names|
            lines << "  local -a opts_#{group}=("
            names.each do |n|
              Array(zsh_entry(switch(n))).each { |e| lines << "    #{e}" }
            end
            lines += ['  )', '']
          end
          lines << '  # All "action" options: every non-global parser group'
          lines << '  local -a opts_action=('
          lines << ('    ' + BoltOptionParser::OPTIONS.keys
                                                         .reject { |g| g == :global }
                                                 .map { |g| "\"${opts_#{g}[@]}\"" }
                                                 .join(' '))
          lines << '  )'
          lines.join("\n")
        end
      end

      # The subcommand _describe list.
      def zsh_subcommands
        commands.map { |c| "    '#{c[:name]}:#{sanitize_desc(c[:bare])}'" }.join("\n")
      end

      # The guide topics _describe list.
      def zsh_topics
        guide_topics.map { |t, d| "    '#{t}:#{sanitize_desc(d)}'" }.join("\n")
      end

      # The main dispatcher case in the `bolt` completion function.
      def zsh_dispatch
        commands.map { |c| "    #{c[:name].ljust(9)}) _bolt_#{c[:name]} ;;" }
                .join("\n") + "\n    help)      _bolt_help ;;"
      end

      # All subcommand chooser and per-action completion functions.
      def zsh_functions
        commands.flat_map do |c|
          if c[:actions].empty?
            [zsh_action_fn(c[:name], nil)]
          else
            [zsh_chooser(c),
             c[:actions].map { |a| zsh_action_fn(c[:name], a[:name]) }]
          end
        end.join("\n\n") << "\n"
      end

      # The `bolt help` action cases.
      def zsh_help_cases
        commands.map do |c|
          fn = if c[:actions].empty?
                 '_nothing'
               else
                 "_bolt_help_action '#{c[:actions].map { |a| a[:name] }.join(' ')}'"
               end
          "    #{c[:name].ljust(9)}) #{fn} ;;"
        end.join("\n")
      end

      ####################################################################
      # bash emission

      # The top-level subcommand words.
      def bash_subcommand_words
        commands.map { |c| c[:name] }.join(' ')
      end

      # The per-group option token lists declared at the top of the bash
      # completion function, rendered from the parser's own OPTIONS groups.
      def bash_opts
        @bash_opts ||= begin
          # Parser group name -> local variable name in the bash script.
          names = { global_config_setters: 'context_opts' }
          group_local = ->(group) { names.fetch(group, "#{group}_opts") }
          lines = BoltOptionParser::OPTIONS.map do |group, option_names|
            toks = option_names.flat_map { |n| token_list(switch(n)) }.uniq.join(' ')
            "  local #{group_local.call(group)}=\"#{toks}\""
          end
          composed = (BoltOptionParser::OPTIONS.keys - [:global]).map do |g|
            "$#{group_local.call(g)}"
          end
          lines << "  local action_opts=\"#{composed.join(' ')}\""
          lines.join("\n")
        end
      end

      # Option tokens (short and long spellings, --no- variants included)
      # for one `bolt <subcommand> [action]` invocation, joined by spaces.
      # The global options are excluded: the completion function adds them
      # once to the option list as a whole.
      def bash_tokens(sub, action)
        global = BoltOptionParser::OPTIONS[:global]
        switches_for(sub, action).reject { |s| global.include?(s[:name]) }
                                 .flat_map { |s| token_list(s) }
                                 .uniq.join(' ')
      end

      # The "option value" elif branches for enumerable options, derived from
      # the candidate lists of the parser's options.
      def bash_enum_cases
        @switches.values.filter_map do |rec|
          values = rec[:values]
          next if values.nil? || values.empty?

          ["  elif [ \"$prev\" == \"--#{rec[:name]}\" ]; then",
           "    next=\"#{values.join(' ')}\""].join("\n")
        end.join("\n")
      end

      # The guide topics for the bash listing (names only).
      def bash_guide_names
        guide_topics.map { |t, _| t }.join(' ')
      end

      # The file-accepting option tokens for compgen-based file completion.
      def bash_file_opts
        FILE_VALUE_OPTS.flat_map { |n|
          [switch(n)[:short] && "-#{switch(n)[:short]}", "--#{n}"].compact
        }.join(' ')
      end

      # Option tokens that consume the following word, for the helpers that
      # scan the command line. Derived from the parser so that new options (or
      # options changing between flags and value-taking) stay in sync.
      def bash_value_opts
        @bash_value_opts ||= @switches.select { |_, rec| rec[:takes_arg] }
                                      .flat_map { |_, rec| token_list(rec) }
                                      .uniq.join(' ')
      end

      # The case arms of the _bolt_targets_allowed helper: every subcommand,
      # and subcommand action, whose options include a targeting option.
      def bash_targeting_cases
        bash_targeting_keys.map { |key| "    #{key}) return 0 ;;" }.join("\n")
      end

      # The whole per-subcommand case body of the bash script, tabs and
      # branches rendered from the command tree.
      def bash_case
        block = []
        block << "    case $subcommand in"
        commands.each do |c|
          sub = c[:name]
          block << "      #{sub})"
          if c[:actions].empty?
            tokens = bash_tokens(sub, nil)
            tokens = "#{bash_guide_names} #{tokens}" if sub == 'guide'
            block << "        next=\"#{tokens}\""
          else
            block << '        case $action in'
            c[:actions].each do |a|
              block << "          #{a[:name]})"
              hook = ENTITY_HOOKS[a[:key]]
              tokens = bash_tokens(sub, a[:name])
              if a[:key] == 'script:run'
                # The first argument after the action is the script path: a
                # file, not an option token — offer files at that position.
                block << '            if [ $COMP_CWORD -eq 3 ]; then'
                block << '              next=$(compgen -f -d "" -- "$cur")'
                block << '            else'
                block << "              next=\"#{tokens}\""
                block << '            fi'
              elsif hook
                block << ("            _bolt_entity_slot #{hook[:names]} #{KIND_SINGULAR[hook[:names]]} \"#{tokens}\"" +
                         (hook[:params] ? ' || return 0' : ' no-params'))
              else
                block << "            next=\"#{tokens}\""
              end
              block << '          ;;'
            end
            block << "          *) next=\"#{c[:actions].map { |a| a[:name] }.join(' ')}\";;"
            block << '        esac'
          end
          block << '        ;;'
        end
        block << '    esac'
        block.join("\n")
      end

      ####################################################################
      # internals

      private

      # Records of the options of an `bolt <subcommand> [action]`.
      def switches_for(sub, action)
        # Mirrors BoltOptionParser#update for the given subcommand and
        # action: the switch list bolt parses arguments against.
        parser = BoltOptionParser.new(subcommand: sub, action: action)
        parser.update
        parser.top.list
              .select { |o| o.respond_to?(:switch_name) }
              .map { |o| record_from(o) }
      end

      # The "<subcommand>" and "<subcommand>:<action>" keys whose options
      # include a targeting option.
      def bash_targeting_keys
        @bash_targeting_keys ||= commands.flat_map do |c|
          if c[:actions].empty?
            targeting?(c[:name], nil) ? [c[:name]] : []
          else
            c[:actions].select { |a| targeting?(c[:name], a[:name]) }
                       .map { |a| a[:key] }
          end
        end
      end

      def targeting?(sub, action)
        switches_for(sub, action).any? { |s| s[:name] == 'targets' }
      end

      def record_from(opt)
        long_def = opt.long.first.to_s
        {
          name: opt.switch_name,
          short: opt.short[0]&.delete_prefix('-'),
          takes_arg: !opt.arg.nil?,
          arg_label: opt.arg.to_s.strip.downcase,
          values: candidate_values(opt, opt.switch_name),
          desc: opt.desc.join(' ').gsub(/\s+/, ' ').strip,
          no_pair: long_def.include?('[no-]')
        }
      end

      def candidate_values(opt, name)
        if opt.pattern.is_a?(Hash)
          opt.pattern.keys.map(&:to_s).sort
        else
          case name
          when 'rerun' then FILTERS
          when 'format' then FORMATS
          when 'log-level' then Bolt::Logger::LEVELS
          end
        end
      end

      # The shell spellings of one switch: short, long, --no- variant.
      def token_list(rec)
        toks = []
        toks << "-#{rec[:short]}" if rec[:short]
        toks << "--#{rec[:name]}"
        toks << "--no-#{rec[:name]}" if rec[:no_pair]
        toks
      end

      def switch(name)
        @switches[name] or raise Bolt::CLIError, "Unrecognized option '#{name}'."
      end

      # Collects the union of all option records across every subcommand and
      # action, so the zsh script can render one spec per option.
      def collect_switches
        Bolt::CLI::COMMANDS.each do |sub, actions|
          pairs = actions.empty? ? [nil] : actions
          pairs.each do |action|
            switches_for(sub, action).each do |rec|
              @switches[rec[:name]] ||= rec
            end
          end
        end
      end

      # ---------------------------------------------------------------
      # zsh spec rendering

      # The zsh _arguments specs for one switch (two entries for a
      # --[no-] pair). Structure mirrors the hand-written script: the
      # exclusion set and the description bracket are single-quoted, a
      # braced short/long spelling is left unquoted for zsh brace
      # expansion, and the value spec is part of the quoted description.
      def zsh_entry(rec)
        return zsh_no_pair_entry(rec) if rec[:no_pair]

        excl = zsh_exclusion(rec)
        spelling = zsh_spelling(rec)
        body = "[#{sanitize_desc(rec[:desc])}]#{zsh_value(rec)}"
        text = +''
        text << "'#{excl}'" unless excl.empty?
        if spelling.start_with?('{')
          text << spelling << single_quote(body)
        else
          text << single_quote(spelling + body)
        end
        text
      end

      # Single-quotes a zsh string fragment, escaping as needed.
      def single_quote(text)
        # Option descriptions and value specs are sanitized beforehand, so
        # no single quotes remain to terminate the string early.
        "'#{text}'"
      end

      # The two specs for a --[no-] switch, as an array: the positive form
      # excluding the negative one and vice-versa.
      def zsh_no_pair_entry(rec)
        name = rec[:name]
        short = rec[:short] ? "-#{rec[:short]}" : nil
        neg_tokens = [short, "--#{name}"].compact.join(' ')
        pos_body = "[#{sanitize_desc(rec[:desc])}]"
        neg_body = "[Disables --#{name}.]"
        spelling = zsh_spelling(rec)
        pos = if spelling.start_with?('{')
                "'(--no-#{name})'#{spelling}#{single_quote(pos_body)}"
              else
                single_quote("(--no-#{name})#{spelling}#{pos_body}")
              end
        neg = single_quote("(#{neg_tokens})--no-#{name}#{neg_body}")
        [pos, neg]
      end

      # Exclusion set: the TARGETING siblings for targeting options, the
      # option's own short form for (-s --name) style pairs; --help
      # excludes everything else on the word, like the hand script.
      def zsh_exclusion(rec)
        if rec[:name] == 'help'
          '(- : *)'
        elsif TARGETING.include?(rec[:name])
          toks = (TARGETING - [rec[:name]])
                 .flat_map { |n|
            s = switch(n)
            [s[:short] && "-#{s[:short]}", "--#{n}"]
          }.compact
          "(#{toks.join(' ')})"
        elsif rec[:short]
          "(-#{rec[:short]} --#{rec[:name]})"
        else
          ''
        end
      end

      # {-t=,--targets=} style spelling when a short form exists.
      def zsh_spelling(rec)
        eq = rec[:takes_arg] ? '=' : ''
        if rec[:short]
          "{-#{rec[:short]}#{eq},--#{rec[:name]}#{eq}}"
        else
          "--#{rec[:name]}#{eq}"
        end
      end

      # The value completion spec (after the description bracket). Flags
      # get no value spec.
      def zsh_value(rec)
        return '' unless rec[:takes_arg]

        if rec[:values]
          ":#{rec[:arg_label]}:(#{rec[:values].join(' ')})"
        else
          VALUE_SPEC[rec[:name]] || ":#{rec[:arg_label]}:"
        end
      end

      # The _arguments body entries of one subcommand or action function.
      def zsh_arguments_for(sub, action)
        entries = switches_for(sub, action).flat_map { |s| zsh_entry(s) }
        key = action.nil? ? "#{sub}:" : "#{sub}:#{action}"
        POSITIONALS.fetch(key, []).each { |p| entries << single_quote(p) }
        hook = action && ENTITY_HOOKS["#{sub}:#{action}"]
        if hook
          kind = hook[:names]
          entity = KIND_SINGULAR[kind]
          prefix = hook[:optional] ? '::' : ':'
          entries << single_quote("#{prefix}#{entity}: _bolt_#{entity}_names")
          entries << single_quote("*::#{entity} parameter: _bolt_#{entity}_params") if hook[:params]
        end
        entries
      end

      # One completion function: _bolt_plan_run or (no actions) _bolt_apply.
      def zsh_action_fn(sub, action)
        entries = zsh_arguments_for(sub, action)
        fn = "_bolt_#{sub}#{"_#{action.tr('-', '_')}" if action}"
        joined = entries.join(" \\\n      ")
        <<~ZSH
          #{fn} () {
            _arguments \\
                #{joined}
          }
        ZSH
      end

      # The action-chooser function for a subcommand with actions.
      def zsh_chooser(command)
        subs = command[:actions]
        actions = subs.map { |a| "    '#{a[:name]}:#{sanitize_desc(a[:bare])}'" }.join("\n")
        cases = subs.map { |a| "        #{a[:name]}) _bolt_#{command[:name]}_#{a[:name].tr('-', '_')} ;;" }
                    .join("\n")
        <<~ZSH
          _bolt_#{command[:name]} () {
            integer ret=1
            local -a actions
            actions=(
            #{actions}
            )
            _arguments -C \\
              "${opts_globals[@]}" \\
              '*::: :->args' && ret=0
            if [[ -n $state ]]; then
              if (( CURRENT == 1 )); then
                _describe -t actions 'action' actions
              else
                compset -n 1
                case $line[1] in
            #{cases}
                  *)       _message "unknown action: $line[1]" ;;
                esac
              fi
            fi
            return ret
          }
        ZSH
      end

      # ------------------------------------------------------------------
      # text helpers

      # The subcommand or action help banner's description section.
      def description_from(banner)
        m = banner.to_s.match(/Description\s*(.*?)(\n\s*\n|\z)/m)
        first_sentence(strip_ansi(m ? m[1] : ''))
      end

      # Everything up to the first sentence-ending period.
      def first_sentence(text)
        plain = strip_ansi(text).gsub(/\s+/, ' ').strip
        plain[/\A.*?\./] || plain[0, 80]
      end

      # Strips the characters that cannot appear inside the single-quoted
      # sections of a zsh option spec.
      def sanitize_desc(text)
        text.to_s.delete("[]'\"")
            .gsub(/\s+/, ' ')
            .strip
      end

      def strip_ansi(text)
        text.to_s.gsub(/\e\[[\d;]*m/, '')
      end
    end
  end
end
