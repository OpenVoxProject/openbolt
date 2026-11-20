# frozen_string_literal: true

require_relative '../cli'
require_relative 'base'
require_relative 'hints'

module Bolt
  module Completion
    # Renders the zsh completion script from a Model.
    class Zsh < Base
      TARGETING = Bolt::CLI::TARGETING_OPTIONS.map(&:to_s).freeze

      def zsh_global_options
        @model.global_options.flat_map { |option| zsh_entry(option) }
                             .map { |entry| "    #{entry}" }.join("\n")
      end

      def zsh_subcommands
        @model.commands.map do |command|
          "    '#{command.name}:#{sanitize_desc(command.description)}'"
        end.join("\n")
      end

      def zsh_topics
        @model.guide_topics.map do |topic, description|
          "    '#{topic}:#{sanitize_desc(description)}'"
        end.join("\n")
      end

      def zsh_dispatch
        @model.commands.map do |command|
          "    #{command.name.ljust(9)}) _bolt_#{command.name} ;;"
        end.join("\n") + "\n    help)      _bolt_help ;;"
      end

      def zsh_functions
        @model.commands.flat_map do |command|
          if command.invocations.first.action.nil?
            [zsh_action_fn(command.invocations.first)]
          else
            [zsh_chooser(command),
             command.invocations.map { |invocation| zsh_action_fn(invocation) }]
          end
        end.join("\n\n") << "\n"
      end

      def zsh_help_cases
        @model.commands.map do |command|
          actions = command.invocations.filter_map(&:action)
          fn = if actions.empty?
                 '_nothing'
               else
                 "_bolt_help_action '#{actions.join(' ')}'"
               end
          "    #{command.name.ljust(9)}) #{fn} ;;"
        end.join("\n")
      end

      def zsh_list_cases
        Hints::LISTS.map do |kind, spec|
          "    #{kind}) appcmd=( #{spec[:command]} ) jsonkey=#{spec[:json_key]} ;;"
        end.join("\n")
      end

      def zsh_pair_lists
        Hints::LISTS.select { |_, spec| spec[:pairs] }.keys.join('|')
      end

      def zsh_param_cases
        Hints::PARAMS.map do |kind, spec|
          path = spec[:json_path]
          jqexpr = ".#{path} // {} | (if type == \"object\" then keys[] else empty end)"
          indexes = path.split('.').map { |key| "[\"#{key}\"]" }.join
          rubysnip = "begin; ps = JSON.parse(STDIN.read)#{indexes}; " \
                     "ps.is_a?(Hash) and ps.each_key { |k| puts k }; rescue; end"
          "    #{kind})\n      jqexpr='#{jqexpr}'\n      rubysnip='#{rubysnip}' ;;"
        end.join("\n")
      end

      private

      def template_name
        'zsh'
      end

      def zsh_arguments_for(invocation)
        entries = invocation.options.flat_map { |option| zsh_entry(option) }
        invocation.positionals.each do |positional|
          entries << single_quote(zsh_positional(positional))
          next unless positional.type == :entity && positional.params

          entries << single_quote(
            "*::#{positional.params} parameter: _bolt_entity_params #{positional.params}"
          )
        end
        entries
      end

      def zsh_positional(positional)
        prefix = if positional.multiple
                   '*::'
                 elsif positional.optional
                   '::'
                 else
                   ':'
                 end
        action = case positional.type
                 when :file then '_files'
                 when :directory then '_files -/'
                 when :topic then '_describe "guide" topics'
                 when :entity then "_bolt_entity_names #{positional.list}"
                 else "_message \"#{positional.description}\""
                 end
        "#{prefix}#{positional.label}: #{action}"
      end

      def zsh_action_fn(invocation)
        entries = zsh_arguments_for(invocation)
        joined = entries.join(" \\\n      ")
        <<~ZSH
          #{invocation.function_name} () {
            _arguments \\
                #{joined}
          }
        ZSH
      end

      def zsh_chooser(command)
        actions = command.invocations.map do |invocation|
          "    '#{invocation.action}:#{sanitize_desc(invocation.description)}'"
        end.join("\n")
        cases = command.invocations.map do |invocation|
          "        #{invocation.action}) #{invocation.function_name} ;;"
        end.join("\n")
        <<~ZSH
          _bolt_#{command.name} () {
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

      def zsh_entry(option)
        return zsh_no_pair_entry(option) if option.negatable

        exclusion = zsh_exclusion(option)
        spelling = zsh_spelling(option)
        body = "[#{sanitize_desc(option.description)}]#{zsh_value(option)}"
        text = +''
        text << "'#{exclusion}'" unless exclusion.empty?
        if spelling.start_with?('{')
          text << spelling << single_quote(body)
        else
          text << single_quote(spelling + body)
        end
        text
      end

      def zsh_no_pair_entry(option)
        name = option.name
        short = option.short ? "-#{option.short}" : nil
        negated = [short, "--#{name}"].compact.join(' ')
        positive_body = "[#{sanitize_desc(option.description)}]"
        negative_body = "[Disables --#{name}.]"
        spelling = zsh_spelling(option)
        positive = if spelling.start_with?('{')
                     "'(--no-#{name})'#{spelling}#{single_quote(positive_body)}"
                   else
                     single_quote("(--no-#{name})#{spelling}#{positive_body}")
                   end
        negative = single_quote("(#{negated})--no-#{name}#{negative_body}")
        [positive, negative]
      end

      def zsh_exclusion(option)
        if option.name == 'help'
          '(- : *)'
        elsif TARGETING.include?(option.name)
          tokens = (TARGETING - [option.name]).flat_map do |name|
            other = @model.option(name)
            [other.short && "-#{other.short}", "--#{name}"]
          end.compact
          "(#{tokens.join(' ')})"
        elsif option.short
          "(-#{option.short} --#{option.name})"
        else
          ''
        end
      end

      def zsh_spelling(option)
        eq = option.takes_arg ? '=' : ''
        if option.short
          "{-#{option.short}#{eq},--#{option.name}#{eq}}"
        else
          "--#{option.name}#{eq}"
        end
      end

      def zsh_value(option)
        return '' unless option.takes_arg

        if option.values
          ":#{option.arg_label}:(#{option.values.join(' ')})"
        else
          label = option.value_label
          case option.type
          when :file then ":#{label}: _files"
          when :directory then ":#{label}: _files -/"
          when :targets then ":#{label}: _bolt_target_list"
          when :command then ":#{label}: _path_commands"
          when :integer
            ":#{label}: _guard \"[0-9]#\" #{option.value_description || 'number'}"
          when :message
            ":#{label}: _message \"#{sanitize_desc(option.value_description)}\""
          else
            ":#{label}:"
          end
        end
      end

      def single_quote(text)
        "'#{text}'"
      end
    end
  end
end
