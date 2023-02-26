require './lib/export/exporter'

module Export
  class CSL_JSON < Exporter

    def name
      'CSL-JSON exporter'
    end

    def start
      @data = []
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      @data.append item.to_h(compact: @compact)
    end

    def finish
      File.write(@outfile, JSON.pretty_generate(@data), encoding: @encoding)
    end
  end
end