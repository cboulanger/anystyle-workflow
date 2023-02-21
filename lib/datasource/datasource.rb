# frozen_string_literal: true
module Datasource

  extend self

  # @return [Datasource]
  # @param [String] datasource
  def get_provider_by_name(datasource)
    case datasource
    when 'crossref'
      Crossref
    when 'dimensions'
      Dimensions
    when 'openalex'
      OpenAlex
    when 'grobid'
      Grobid
    when 'anystyle'
      Anystyle
    when 'wos'
      Wos
    else
      raise "Unknown datasource #{datasource}"
    end
  end

  def get_vendor_data(vendors = [])
    vendor_info = JSON.load_file(File.join(::Workflow::Path.metadata, 'vendors.json'))
    vendor_cache = {}
    vendor_info.each do |vendor, data|
      next if vendors.length.positive? && !vendors.include?(vendor)
      vendor_cache[vendor] ||= {}
      data['files'].each do |file|
        vendor_cache[vendor].merge! JSON.load_file(file['path'])
      end
    end
    vendor_cache
  end

  class Datasource
    class << self
      attr_accessor :verbose

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

      # @return [Array<Format::CSL::Item>]
      def import_items_by_doi(*)
        raise 'Method must be implemented by subclass'
      end
    end
  end
end