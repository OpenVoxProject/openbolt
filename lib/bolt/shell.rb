# frozen_string_literal: true

module Bolt
  class Shell
    attr_reader :target, :conn, :logger

    def initialize(target, conn)
      @target = target
      @conn = conn
      @logger = Bolt::Logger.logger(@target.safe_name)

      stream_logger if Bolt::Logger.stream
    end

    # Resolves whether output should be streamed for a given call, falling back
    # to the global stream setting when the call does not specify a value.
    def stream_enabled?(options)
      options.key?(:stream) ? options[:stream] : Bolt::Logger.stream
    end

    private def stream_logger
      @stream_logger ||= begin
        Bolt::Logger.warn_once("stream_experimental",
                               "The 'stream' option is experimental, and might " \
                               "include breaking changes between minor versions.")
        logger = Bolt::Logger.logger(:stream)
        # Don't send stream messages to the parent logger
        logger.additive = false

        # Log stream messages without any other data or color
        pattern = Logging.layouts.pattern(pattern: '%m\n')
        logger.appenders = Logging.appenders.stdout(
          'console',
          layout: pattern
        )
        logger
      end
    end

    protected def log_stream(to_print, stream_name, stream)
      return if !stream || to_print.chomp.empty?

      formatted = to_print.lines.map do |msg|
        "[#{@target.safe_name}] #{stream_name}: #{msg.chomp}"
      end.join("\n")
      stream_logger.warn(formatted)
    end

    def run_command(*_args)
      raise NotImplementedError, "run_command() must be implemented by the shell class"
    end

    def upload(*_args)
      raise NotImplementedError, "upload() must be implemented by the shell class"
    end

    def run_script(*_args)
      raise NotImplementedError, "run_script() must be implemented by the shell class"
    end

    def run_task(*_args)
      raise NotImplementedError, "run_task() must be implemented by the shell class"
    end

    def provided_features
      []
    end

    def default_input_method(_executable)
      'both'
    end

    # The above methods are the API that must be implemented by a Shell. Below
    # are helper methods.

    def select_implementation(target, task)
      impl = task.select_implementation(target, provided_features)
      impl['input_method'] ||= default_input_method(impl['path'])
      impl
    end

    def select_interpreter(executable, interpreters)
      interpreters[Pathname(executable).extname] if interpreters
    end

    # Transform a parameter map to an environment variable map, with parameter names prefixed
    # with 'PT_' and values transformed to JSON unless they're strings.
    def envify_params(params)
      params.each_with_object({}) do |(k, v), h|
        v = v.to_json unless v.is_a?(String)
        h["PT_#{k}"] = v
      end
    end

    # Unwraps any Sensitive data in an arguments Hash, so the plain-text is passed
    # to the Task/Script.
    #
    # This works on deeply nested data structures composed of Hashes, Arrays, and
    # and plain-old data types (int, string, etc).
    def unwrap_sensitive_args(arguments)
      # Skip this if Puppet isn't loaded
      return arguments unless defined?(Puppet::Pops::Types::PSensitiveType::Sensitive)

      case arguments
      when Array
        # iterate over the array, unwrapping all elements
        arguments.map { |x| unwrap_sensitive_args(x) }
      when Hash
        # iterate over the arguments hash and unwrap all keys and values
        arguments.each_with_object({}) { |(k, v), h|
          h[unwrap_sensitive_args(k)] = unwrap_sensitive_args(v)
        }
      when Puppet::Pops::Types::PSensitiveType::Sensitive
        # this value is Sensitive, unwrap it
        unwrap_sensitive_args(arguments.unwrap)
      else
        # unknown data type, just return it
        arguments
      end
    end
  end
end

require_relative 'shell/bash'
require_relative 'shell/powershell'
