require './lib/export/exporter'

module Export
  class CSL_JSON < Exporter

    # @param [String] outfile path to output file
    # @param [Boolean] compact If true, remove all empty tags. Default is true, pass false if an app complains about
    #   missing fields
    # @param [String] encoding
    # @param [Boolean] add_ref_source
    def initialize(outfile, compact: true, encoding: 'utf-8')
      super
      @outfile = outfile
      @compact = compact
      @encoding = encoding
    end

    def name
      'CSL-JSON exporter'
    end

    def start
      @data = []
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      item_hash = item.to_h
      if @compact
        item_hash.delete_if do |_k, v|
          case v
          when Array
            v.empty?
          when String
            v.strip.empty?
          else
            v.nil?
          end
        end
      end
      @data.append item_hash
    end

    def finish
      File.write(@outfile, JSON.pretty_generate(@data), encoding: @encoding)
    end
  end
end