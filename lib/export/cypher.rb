# frozen_string_literal: true

require './lib/export/exporter'

module Export
  class Cypher < Exporter

    # @return [String]
    def self.id
      'cypher'
    end

    # @return [String]
    def self.name
      'Cypher exporter'
    end



    def start
      @data = ::Format::Cypher.header
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      @data.append Format::Cypher.new(item, pretty: @pretty).serialize
    end

    def finish
      File.write(@target, @data.join("\n"), encoding: @encoding)
    end
  end
end
