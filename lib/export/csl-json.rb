require './lib/export/exporter'

module Export
  class CSL_JSON < Exporter

    # @return [String]
    def self.id
      'csl-json'
    end

    # @return [String]
    def self.name
      'CSL-JSON exporter'
    end

    # @return [String]
    def self.extension
      'json'
    end

    def start
      @data = []
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      @data.append item.to_h(compact: @compact)
    end

    def finish
      File.write(@target, JSON.pretty_generate(@data), encoding: @encoding)
    end
  end
end