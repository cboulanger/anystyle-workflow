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

      # Given two hashes that would appear in the "references" section of CSL-JSON,
      # return true if they should be considered the same for the purpose of avoiding
      # duplicates
      # NOT USED
      def is_same_cited_ref?(r1, r2)
        keys = %w[DOI id key]
        keys.each do |key|
          next if r1[key].nil? || r2[key].nil?
          return true if r1[key] == r2[key]
        end
        # check author, title, year etc.
        false
      end

      # Given an array of CSL-JSON items, merge their properties, in particular the
      # 'references'
      # NOT USED
      def merge_metadata(items)
        merged_item = {}
        items.each do |item|
          item.each do |key, value|
            case key
            when 'references'
              # for now, just check doi & proprietary ids to avoid duplicates
              refs = merged_item['references']
              value.each do |r1|
                refs.append(r) unless refs.any? { |r2| is_same_cited_ref?(r1, r2) }
              end
            else
              # for now, just add missing values (does not check authors etc. )
              merged_item[key] = value if merged_item[key].nil?
            end
          end
        end
        merged_item
      end
    end
  end
end
