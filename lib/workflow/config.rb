# frozen_string_literal: true

module Workflow
  class Config
    class << self

      def progress_defaults
        {
          format: "%t %b\u{15E7}%i %p%% %c/%C %a %e",
          progress_mark: ' ',
          remainder_mark: "\u{FF65}"
        }
      end

    end
  end
end


