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

    def start; end

    # @param [Format::CSL::Item] item
    def add_item(*)
      raise 'Must be implemented by subclass'
    end

    def finish; end
  end
end