require './lib/export/exporter'

module Export
  class Cypher < Exporter

    def name
      'Cypher exporter'
    end

    def start
      @data = []
      # To do: create constraints
      # CREATE CONSTRAINT source_id IF NOT EXISTS ON (s:Source) ASSERT s.pk_sources IS UNIQUE;
      # CALL db.awaitIndexes();
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      @data.append Format::Cypher.new(item, pretty:@pretty).serialize
    end

    def finish
      File.write(@outfile, @data.join("\n"), encoding: @encoding)
    end
  end
end