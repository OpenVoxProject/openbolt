# frozen_string_literal: true

require 'erb'

module Bolt
  module Completion
    # Shared plumbing for the shell renderers. Subclasses provide their
    # template name and all shell-specific completion logic.
    class Base
      TEMPLATE_DIR = File.expand_path('templates', __dir__)

      attr_reader :model

      def initialize(model)
        @model = model
      end

      def render
        ERB.new(File.read(template_path), trim_mode: '-').result(binding)
      end

      def header
        ERB.new(File.read(File.join(TEMPLATE_DIR, 'header.erb')), trim_mode: '-').result(binding)
      end

      private

      def template_path
        File.join(TEMPLATE_DIR, "#{template_name}.erb")
      end

      def template_name
        raise NotImplementedError
      end

      def sanitize_desc(text)
        text.to_s.delete("[]'\"")
            .gsub(/\s+/, ' ')
            .strip
      end
    end
  end
end
