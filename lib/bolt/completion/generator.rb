# frozen_string_literal: true

require_relative '../completion'
require_relative 'bash'
require_relative 'model'
require_relative 'zsh'

module Bolt
  module Completion
    # Thin facade over the completion model and shell renderers.
    class Generator
      RENDERERS = {
        'bash' => Bash,
        'zsh' => Zsh
      }.freeze

      class << self
        def render(shell)
          renderer = RENDERERS[shell] or
            raise Bolt::CLIError,
                  "Unknown shell '#{shell}'; available shells: #{shells.join(', ')}."
          renderer.new(Model.build).render
        end

        def shells
          SHELLS
        end
      end
    end
  end
end
