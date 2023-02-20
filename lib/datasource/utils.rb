# frozen_string_literal: true

require 'namae'

module Datasource
  class Utils
    class << self

      def get_provider_by_name(datasource)
        case datasource
        when 'crossref'
          ::Datasource::Crossref
        when 'dimensions'
          ::Datasource::Dimensions
        when 'openalex'
          ::Datasource::OpenAlex
        when 'grobid'
          ::Datasource::Grobid
        when 'anystyle'
          ::Datasource::Anystyle
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
      def import_by_identifier(id, datasources: [], verbose:)
        all_items = []
        datasources.map do |ds|
          resolver = get_provider_by_name(ds)
          if id =~ /^10./ && resolver.respond_to?(:import_items_by_doi)
            resolver.verbose = verbose
            found_items = resolver.import_items_by_doi([id], include_references: true, include_abstract: true)
            all_items.append(found_items.first) if found_items.length.positive?
            puts " - Data imported." if verbose
          else
            puts " - Identifier '#{id}' cannot be resolved by #{ds}." if verbose
          end
        end
        all_items
      end


    end
  end
end
