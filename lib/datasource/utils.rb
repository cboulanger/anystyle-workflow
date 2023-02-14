# frozen_string_literal: true

require 'namae'

module Datasource
  class Utils
    class << self

      def get_resolver(datasource)
        case datasource
        when 'crossref'
          ::Datasource::Crossref
        when 'dimensions'
          ::Datasource::Dimensions
        when 'openalex'
          ::Datasource::OpenAlex
        else
          raise "Unknown datasource #{datasource}"
        end
      end

      def get_vendor_data
        vendor_info = JSON.load_file(File.join(::Workflow::Path.metadata, 'vendors.json'))
        vendor_cache = {}
        vendor_info.each do |vendor, data|
          vendor_cache[vendor] ||= {}
          data['files'].each do |file|
            vendor_cache[vendor].merge! JSON.load_file(file['path'])
          end
        end
        vendor_cache
      end

      # Given an id and a list of datasources, return an array of results from these sources
      # in CSL-JSON format
      # @return Array
      def fetch_metadata_by_identifier(id, datasources: [])
        raise 'No identifier given' if id.nil? || id.empty?
        raise 'No datasources given' if datasources.empty?

        all_items = []
        datasources.map do |ds|
          resolver = get_resolver(ds)
          if id =~ /^10./ && resolver.respond_to?(:items_by_doi)
            found_items = resolver.items_by_doi([id])
            all_items.append(found_items.first) unless found_items.empty?
          else
            $logger.debug "Identifier '#{id}' cannot be resolved by #{ds}."
          end
        end
        all_items
      end

    end
  end
end
