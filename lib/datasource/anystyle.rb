require './lib/datasource/datasource'

module Datasource
  class Anystyle < ::Datasource::Datasource
    class << self

      # @return [String]
      def id
        'anystyle'
      end

      # @return [String]
      def label
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

      # The type of identifiers that can be used to import data
      # @return [Array<String>]
      def id_types
        [::Datasource::FILE_NAME, ::Datasource::DOI]
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
      # @param [Array<String>] ids An array of identifiers
      # @param [String,nil] prefix Optional prefix for filesystem-based lookups (usually the dataset name)
      def import_items(ids, include_references: false, include_abstract: false, prefix: '')
        ids.map do |id|
          file_path = File.join(::Workflow::Path.csl,
                                "#{prefix}#{Workflow::Utils.to_filename(id)}.json")
          raise ::Datasource::NoDataError("Anystyle csl file does not exist: '#{file_path}'") unless File.exist? file_path

          item = Item.new({})
          item.x_references = JSON.load_file(file_path).map { |ref| Item.new(ref) }
          item
        end
      end
    end

    class Item < Format::CSL::Item
      def initialize(data)
        custom.reference_data_source = "anystyle"
        custom.metadata_id = data['id']
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