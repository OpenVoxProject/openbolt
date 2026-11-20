# frozen_string_literal: true

module Bolt
  module Completion
    # The shells supported by `bolt completion <shell>`. The renderer registry
    # in Generator must provide exactly these shells.
    SHELLS = %w[bash zsh].freeze
  end
end
