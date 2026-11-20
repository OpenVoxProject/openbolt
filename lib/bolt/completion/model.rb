# frozen_string_literal: true

require 'yaml'

require_relative '../bolt_option_parser'
require_relative '../cli'
require_relative 'hints'

module Bolt
  module Completion
    # The normalized description of the CLI that the shell renderers consume.
    # This class knows about the CLI and the parser, but contains no shell
    # syntax.
    class Model
      Option = Data.define(:name, :short, :takes_arg, :arg_label, :values,
                           :description, :negatable, :type, :value_label,
                           :value_description)
      Positional = Data.define(:label, :description, :type, :list, :params,
                               :optional, :multiple)
      Invocation = Data.define(:subcommand, :action, :description, :options,
                               :positionals) do
        def key
          action ? "#{subcommand}:#{action}" : "#{subcommand}:"
        end

        def function_name
          action ? "_bolt_#{subcommand}_#{action.tr('-', '_')}" : "_bolt_#{subcommand}"
        end
      end
      Command = Data.define(:name, :description, :invocations)

      attr_reader :commands, :guide_topics, :options

      def self.build
        new.tap(&:build)
      end

      def initialize
        @commands = []
        @guide_topics = []
        @options = []
      end

      def build
        parser = BoltOptionParser.new({})
        options_by_name = {}

        @commands = Bolt::CLI::COMMANDS.map do |subcommand, actions|
          invocations = (actions.empty? ? [nil] : actions).map do |action|
            parsed_options = switches_for(subcommand, action).map do |option|
              options_by_name[option.name] ||= option
            end
            Invocation.new(
              subcommand,
              action,
              description_from(parser.get_help_text(subcommand, action)[:banner]),
              parsed_options,
              positionals_for(subcommand, action)
            )
          end

          Command.new(
            subcommand,
            description_from(parser.get_help_text(subcommand, nil)[:banner]),
            invocations
          )
        end

        @options = options_by_name.values
        @guide_topics = load_guide_topics
        self
      end

      def option(name)
        options.find { |option| option.name == name } or
          raise Bolt::CLIError, "Unrecognized option '#{name}'."
      end

      def global_options
        BoltOptionParser::OPTIONS[:global].map { |name| option(name) }
      end

      private

      # Mirrors BoltOptionParser#update for the given subcommand and action:
      # the switch list bolt parses arguments against.
      def switches_for(subcommand, action)
        parser = BoltOptionParser.new(subcommand: subcommand, action: action)
        parser.update
        parser.top.list
              .select { |option| option.respond_to?(:switch_name) }
              .map { |option| option_from(option) }
      end

      def option_from(option)
        name = option.switch_name
        long_def = option.long.first.to_s
        type = Hints::OPTION_TYPES[name] || {}
        arg_label = option.arg.to_s.strip.downcase
        values = candidate_values(option, name)

        Option.new(
          name,
          option.short[0]&.delete_prefix('-'),
          !option.arg.nil?,
          arg_label,
          values,
          option.desc.join(' ').gsub(/\s+/, ' ').strip,
          long_def.include?('[no-]'),
          type[:type] || :value,
          type[:label] || arg_label,
          type[:description] || type[:label]
        )
      end

      def candidate_values(option, name)
        if option.pattern.is_a?(Hash)
          option.pattern.keys.map(&:to_s).sort
        else
          Hints::STATIC_VALUES[name]
        end
      end

      def positionals_for(subcommand, action)
        key = action ? "#{subcommand}:#{action}" : "#{subcommand}:"
        Array(Hints::POSITIONALS[key]).map do |hint|
          Positional.new(
            hint[:label],
            hint[:description] || hint[:label],
            hint[:type],
            hint[:list],
            hint[:params],
            hint.fetch(:optional, false),
            hint.fetch(:multiple, false)
          )
        end
      end

      def load_guide_topics
        dir = File.expand_path(File.join(__dir__, '..', '..', '..', 'guides'))
        Dir.children(dir).sort
           .select { |file| file.end_with?('.yaml') }
           .map do |file|
          info = YAML.safe_load_file(File.join(dir, file))
          [info['topic'], first_sentence(info['guide'].to_s)]
        rescue StandardError
          [file.delete_suffix('.yaml'), '']
        end
      end

      # The subcommand or action help banner's description section.
      def description_from(banner)
        match = banner.to_s.match(/Description\s*(.*?)(\n\s*\n|\z)/m)
        first_sentence(strip_ansi(match ? match[1] : ''))
      end

      # Everything up to the first sentence-ending period.
      def first_sentence(text)
        plain = strip_ansi(text).gsub(/\s+/, ' ').strip
        plain[/\A.*?\./] || plain[0, 80]
      end

      def strip_ansi(text)
        text.to_s.gsub(/\e\[[\d;]*m/, '')
      end
    end
  end
end
