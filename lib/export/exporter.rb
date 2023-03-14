# frozen_string_literal: true

module Export
  class Exporter
    def self.by_id(id)
      klass = exporters.select { |k| k.id == id }.first
      raise "No exporter with id '#{id}' exists." if klass.nil?

      klass
    end

    # @return [Array<Exporter>]
    def self.exporters
      Export.constants
            .map { |c| Export.const_get c}
            .select { |k| k < Exporter  }
    end

    # @return [String]
    def self.list
      exporters.map { |k| "#{k.id.ljust(20)}#{k.name}" }.sort.join("\n")
    end

    # @return [String]
    def self.id
      raise 'Must be implemented by subclass'
    end

    # @return [String]
    def self.name
      raise 'Must be implemented by subclass'
    end

    # @return [String]
    def self.extension
      id
    end

    # @param [String] target path to output file
    # @param [Boolean] compact If true, remove all empty tags. Default is true, pass false if an app complains about
    #   missing fields
    # @param [String] encoding
    # @param [Boolean] pretty If true, format output to be more human-readable
    def initialize(target: nil,
                   compact: true,
                   encoding: 'utf-8',
                   pretty: false,
                   verbose: false)
      @target = target
      @compact = compact
      @encoding = encoding
      @pretty = pretty
      @verbose = verbose
    end

    # @param [Object] items
    # @param [Workflow::Dataset::Instruction] instruction
    def preprocess(items, instruction)
      # apply jq filter to items
      case instruction.type
      when 'jq'
        require 'jq/extend'
        # shortcuts
        jq = "map(#{instruction.command})[]"
               .gsub(/\.year/, '.issued."date-parts"[0][0]')
        # apply filter
        items.map(&:to_h).jq(jq).map { |data| ::Format::CSL::Item.new(data) }
      else
        raise "Unknown instruction type #{instruction.type}"
      end
    end

    def start; end

    # @param [Format::CSL::Item] item
    def add_item(*)
      raise 'Must be implemented by subclass'
    end

    def finish; end

    # needs to be explicitly called by finish if postprocessing is supported
    def postprocess(*)
      raise 'No postprocessing method implemented'
    end
  end
end
