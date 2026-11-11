# frozen_string_literal: true

module Bolt
  # Builds the scripts that `bolt completion <shell>` prints. The commands,
  # actions, options and their descriptions come from the CLI and its option
  # parser, so the scripts follow CLI changes on their own. The completion
  # logic for each shell is in shell_completion/.
  module ShellCompletion
    class << self
      # Returns the completion script for shell, 'bash' or 'zsh'.
      def script(shell)
        parser = BoltOptionParser.new({})
        commands = Bolt::CLI::COMMANDS
        guide_topics = Dir.children(File.expand_path('../../guides', __dir__))
                          .grep(/\.ya?ml\z/)
                          .map { |file| File.basename(file, '.*') }
                          .sort

        # The options of each command, keyed by "<subcommand>" or "<subcommand> <action>"
        command_options = commands.each_with_object({}) do |(subcommand, actions), options|
          (actions.empty? ? [nil] : actions).each do |action|
            key = [subcommand, action].compact.join(' ')
            options[key] = spellings(parser, parser.get_help_text(subcommand, action)[:flags]).join(' ')
          end
        end

        lines = []
        lines << '#compdef bolt' if shell == 'zsh'
        lines << "# OpenBolt #{Bolt::VERSION} #{shell} completion, printed by `bolt completion #{shell}`."
        lines << "_bolt_commands=#{quote(commands.keys.join(' '))}"
        lines << "_bolt_globals=#{quote(spellings(parser, parser.get_help_text(nil)[:flags]).join(' '))}"
        lines << "_bolt_guides=#{quote(guide_topics.join(' '))}"
        lines << assoc(shell, '_bolt_actions', commands.reject { |_, actions| actions.empty? }.transform_values { |actions| actions.join(' ') })
        lines << assoc(shell, '_bolt_options', command_options)
        lines << assoc(shell, '_bolt_values', option_values(parser))
        lines << assoc(shell, '_bolt_descriptions', zsh_descriptions(parser)) if shell == 'zsh'
        lines << File.read(File.join(__dir__, 'shell_completion', "bolt.#{shell}"))
        lines.join("\n")
      end

      private

      # The values offered after each option that takes one. An empty list
      # makes the shells complete file names instead.
      def option_values(parser)
        known = {
          'format' => Bolt::Config::Options::OPTIONS['format'][:enum],
          'log-level' => Bolt::Logger::LEVELS,
          'rerun' => %w[all failure success]
        }
        switches(parser).select(&:arg).each_with_object({}) do |switch, values|
          list = switch.pattern.is_a?(Hash) ? switch.pattern.keys : known.fetch(switch.switch_name, [])
          (switch.short + switch.long).each { |spelling| values[spelling] = list.join(' ') }
        end
      end

      # Descriptions for zsh, keyed by option spelling, subcommand, or
      # "<subcommand> <action>", taken from the option and help texts
      def zsh_descriptions(parser)
        descriptions = {}
        switches(parser).each do |switch|
          spellings(parser, [switch.switch_name]).each { |spelling| descriptions[spelling] = switch.desc.join(' ') }
        end
        Bolt::CLI::COMMANDS.each do |subcommand, actions|
          descriptions[subcommand] = listed_description(parser.get_help_text(nil)[:banner], subcommand)
          actions.each do |action|
            descriptions["#{subcommand} #{action}"] = listed_description(parser.get_help_text(subcommand)[:banner], action)
          end
        end
        descriptions
      end

      # The description next to name in the subcommand or action list of a help text
      def listed_description(banner, name)
        banner[/^ +#{Regexp.escape(name)} {2,}(\S.*)$/, 1].to_s
      end

      def switches(parser)
        parser.top.list.grep(OptionParser::Switch)
      end

      # Returns the short, long and --no- spellings of the named options
      def spellings(parser, names)
        names.flat_map do |name|
          switch = parser.top.long.fetch(name)
          switch.short + switch.long.flat_map do |long|
            long.include?('[no-]') ? [long.sub('[no-]', ''), long.sub('[no-]', 'no-')] : long
          end
        end
      end

      def assoc(shell, name, hash)
        if shell == 'bash'
          entries = hash.map { |key, value| "  [#{quote(key)}]=#{quote(value)}" }
          "declare -gA #{name}=(\n#{entries.join("\n")}\n)"
        else
          entries = hash.map { |key, value| "  #{quote(key)} #{quote(value)}" }
          "typeset -gA #{name}\n#{name}=(\n#{entries.join("\n")}\n)"
        end
      end

      def quote(text)
        "'#{text.gsub("'") { "'\\''" }}'"
      end
    end
  end
end
