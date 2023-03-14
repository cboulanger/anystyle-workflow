# frozen_string_literal: true

module Workflow
  # Feedback/Logging:
  # - should be based on events
  # - should support different channels/meters
  # - should use pluggable adapters
  class Feedback

    # adapters: list of adapters, each respond to events (debug, log, info ..., close etc. )
    # optional parent: if the parent is closed, this should close, too, inherits adapters from parent
    # level: e.g., for indentation purposes
    def initialize(_adapters: nil, _parent: nil, _level: 0) end

    # debug information, realtime, ephemeral
    # audience: developer
    # visibility: UI/stdout
    # storage: may be logged, usually just in memory
    def debug; end

    # logging information for later viewing / analysis
    # audience: developer
    # visibility: usually not shown in UI/stdout
    # storage: log file
    def log; end

    # informational message
    # audience: user
    # visibility: UI/stdout
    def info; end

    def progress; end

    # visible in UI/stdout, mayb be logged
    def warning; end

    def error; end


    # here: create a default Feedback class and forward its methods to the eigenclass

    # The abstract Adapter class from which all adapter have to be subclasses of
    class Adapter
      def initialize(*) end

      def on_debug(_message) end

      # ...
    end

  end

end
