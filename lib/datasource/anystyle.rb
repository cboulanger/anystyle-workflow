module Datasource
  class Anystyle < Datasource
    class << self
      # @return [Array<Item>]
      def import_items_by_doi(dois, include_references: false, include_abstract: false)
        dois.map do |doi|
          # use crossref item as base
          Crossref.verbose = self.verbose
          data = Crossref.import_items_by_doi([doi], include_references: false).first.to_h
          item = Item.new(data)
          file_path = File.join(::Workflow::Path.csl, "#{doi.sub('/', '_')}.json")
          next unless File.exist?(file_path)

          item.x_references = JSON.load_file(file_path).map { |ref| Item.new(ref) }
          item
        end
      end
    end

    class Item < Format::CSL::Item
      def initialize(data)
        custom.metadata_source = "crossref"
        custom.reference_data_source = "anystyle"
        data.delete('signal')
        data.delete('backref')
        super data
      end
    end
  end
end