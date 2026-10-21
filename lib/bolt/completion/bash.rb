# frozen_string_literal: true

require_relative 'base'
require_relative 'hints'

module Bolt
  module Completion
    # Renders the bash completion script from a Model. All shell syntax lives
    # in the template or in the clearly marked helpers below.
    class Bash < Base
      def bash_subcommand_words
        @model.commands.map(&:name).join(' ')
      end

      def bash_guide_names
        @model.guide_topics.map(&:first).join(' ')
      end

      def bash_file_opts
        @model.options.select { |option| %i[file directory].include?(option.type) }
                      .flat_map { |option| token_list(option) }
                      .join(' ')
      end

      def bash_value_opts
        @model.options.select(&:takes_arg)
              .flat_map { |option| token_list(option) }
              .uniq.join(' ')
      end

      def bash_global_opts
        @model.global_options.flat_map { |option| token_list(option) }
                             .uniq.join(' ')
      end

      def bash_enum_cases
        @model.options.filter_map do |option|
          values = option.values
          next if values.nil? || values.empty?

          ["  elif [ \"$prev\" == \"--#{option.name}\" ]; then",
           "    next=\"#{values.join(' ')}\""].join("\n")
        end.join("\n")
      end

      def bash_targeting_cases
        @model.commands.flat_map do |command|
          command.invocations.filter_map do |invocation|
            next unless invocation.options.any? { |option| option.name == 'targets' }

            key = invocation.action ? invocation.key : invocation.subcommand
            "    #{key}) return 0 ;;"
          end
        end.join("\n")
      end

      def bash_list_cases
        Hints::LISTS.map do |kind, spec|
          "    #{kind}) cmd=(#{spec[:command]}) jsonkey=#{spec[:json_key]} ;;"
        end.join("\n")
      end

      def bash_pair_lists
        Hints::LISTS.select { |_, spec| spec[:pairs] }.keys.join('|')
      end

      def bash_param_cases
        Hints::PARAMS.map do |kind, spec|
          path = spec[:json_path]
          jqexpr = ".#{path} // {} | (if type == \"object\" then keys[] else empty end)"
          indexes = path.split('.').map { |key| "['#{key}']" }.join
          rubysnip = "begin; ps = JSON.parse(STDIN.read)#{indexes}; " \
                     "ps.is_a?(Hash) and ps.each_key { |k| puts k }; rescue; end"
          "    #{kind})\n      jqexpr='#{jqexpr}'\n      rubysnip=\"#{rubysnip}\" ;;"
        end.join("\n")
      end

      # The per-subcommand case body of the bash script. Positional slots are
      # described by the shared Hints model and handled by _bolt_positional.
      def bash_case
        block = ['    case $subcommand in']
        @model.commands.each do |command|
          block << "      #{command.name})"
          if command.invocations.first.action.nil?
            block.concat(bash_invocation_case(command.invocations.first, '$_bolt_subix', 8))
          else
            block << '        case $action in'
            command.invocations.each do |invocation|
              block << "          #{invocation.action})"
              block.concat(bash_invocation_case(invocation, '$_bolt_actix', 12))
              block << '          ;;'
            end
            actions = command.invocations.map(&:action).join(' ')
            block << "          *) next=\"#{actions}\";;"
            block << '        esac'
          end
          block << '        ;;'
        end
        block << '    esac'
        block.join("\n")
      end

      private

      def template_name
        'bash'
      end

      def bash_invocation_case(invocation, start, indent)
        padding = ' ' * indent
        lines = ["#{padding}next=\"#{bash_tokens(invocation)}\""]
        return lines if invocation.positionals.empty?

        specs = invocation.positionals.map { |positional| positional_spec(positional) }
        lines << "#{padding}_bolt_positional #{start} \"$next\" " \
                 "#{specs.map { |spec| "'#{spec}'" }.join(' ')} || return 0"
        lines
      end

      # Semantic positional -> type|label|list|params|flags. Kept free of
      # shell syntax so the runtime helper can dispatch on the type.
      def positional_spec(positional)
        flags = +''
        flags << 'o' if positional.optional
        flags << 'm' if positional.multiple
        [positional.type, positional.label, positional.list,
         positional.params, flags].join('|')
      end

      # Option tokens (short and long spellings, --no- variants included)
      # for one invocation. Global options are added once to the option list
      # as a whole.
      def bash_tokens(invocation)
        global = @model.global_options.map(&:name)
        invocation.options.reject { |option| global.include?(option.name) }
                          .flat_map { |option| token_list(option) }
                          .uniq.join(' ')
      end

      def token_list(option)
        tokens = []
        tokens << "-#{option.short}" if option.short
        tokens << "--#{option.name}"
        tokens << "--no-#{option.name}" if option.negatable
        tokens
      end
    end
  end
end
