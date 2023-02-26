module Export
  class Exporter

    def self.by_id(id)
      case id
      when 'wos'
        WebOfScience
      when 'csl'
        CSL_JSON
      end
    end

    # @param [String] outfile path to output file
    # @param [Boolean] compact If true, remove all empty tags. Default is true, pass false if an app complains about
    #   missing fields
    # @param [String] encoding
    def initialize(outfile, compact: true, encoding: 'utf-8')
      @outfile = outfile
      @compact = compact
      @encoding = encoding
    end

    def name
      raise "Must be implemented by subclass"
    end

    def start; end

    # @param [Format::CSL::Item] item
    def add_item(item)
      raise "Must be implemented by subclass"
    end

    def finish; end
  end
end