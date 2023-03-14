module Export
  class Exporter

    def self.by_id(id)
      case id
      when 'wos'
        WebOfScience
      when 'csl'
        CSL_JSON
      when 'cypher'
        Cypher
      when 'neo4j'
        Neo4j
      when 'citnetexplorer'
        CitnetExplorer
      else
        raise "Unknown exporter '#{id}'"
      end
    end

    # @param [String] outfile path to output file
    # @param [Boolean] compact If true, remove all empty tags. Default is true, pass false if an app complains about
    #   missing fields
    # @param [String] encoding
    # @param [Boolean] pretty If true, format output to be more human-readable
    def initialize(outfile = nil,
                   compact: true,
                   encoding: 'utf-8',
                   pretty: false,
                   verbose: false)
      @outfile = outfile
      @compact = compact
      @encoding = encoding
      @pretty = pretty
      @verbose = verbose
    end

    def name
      raise 'Must be implemented by subclass'
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
        items.map(&:to_h)
             .jq(jq)
             .map { |data| ::Format::CSL::Item.new(data) }
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
      raise "No postprocessing method implemented"
    end
  end
end