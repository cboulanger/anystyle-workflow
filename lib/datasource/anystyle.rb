module Datasource
  class Anystyle < Datasource
    class << self
      # @return [Array<Item>]
      def import_items(ids, include_references: false, include_abstract: false)
        ids.map do |id|
          # use crossref item for metadata
          Crossref.verbose = self.verbose
          doi = id.sub('_', '/')
          data = Crossref.import_items([doi], include_references: false).first.to_h
          item = Item.new(data)
          file_path = File.join(::Workflow::Path.csl, "#{id.sub('/', '_')}.json")
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

      def legal_ref=(ref)
        self.references = ref
      end
    end
  end
end