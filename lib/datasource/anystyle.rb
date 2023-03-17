require './lib/datasource/datasource'

module Datasource
  class Anystyle < ::Datasource::Datasource
    class << self

      # @return [String]
      def id
        'anystyle'
      end

      # @return [String]
      def name
        'Reference data from AnyStyle-extracted CSL-JSON files'
      end

      # @return [Boolean]
      def enabled?
        true
      end

      # @return [Boolean]
      def provides_metadata?
        false
      end

      # @return [Boolean]
      def provides_citation_data?
        true
      end

      # @return [Boolean]
      def provides_affiliation_data?
        false
      end

      # @return [Array<Item>]
      def import_items(ids, include_references: false, include_abstract: false)
        ids.map do |id|
          # use crossref item for metadata
          Crossref.verbose = self.verbose
          data = Crossref.import_items([id], include_references: false).first.to_h
          item = Item.new(data)
          file_path = File.join(::Workflow::Path.csl, "#{Workflow::Utils.to_filename(id)}.json")
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
        data.delete('ignore')
        super
      end

      def legal_ref=(ref)
        self.references = ref
      end

    end
  end
end