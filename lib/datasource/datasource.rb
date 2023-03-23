# frozen_string_literal: true
# The Datasource module contains classes that allow to connect to external datasources
# or query locally stored export files from these sources.
module Datasource

  class << self
    def by_id(id)
      klass = providers.select { |k| k.id == id }.first
      raise "No datasource with id '#{id}' exists." if klass.nil?

      klass
    end

    # @return [Array<Datasource>]
    def providers
      constants
        .map { |c| const_get c }
        .select { |p| p < Datasource && p.enabled? }
        .sort { |a, b| a.id <=> b.id }
    end

    # @return [String]
    def list
      providers.map { |p| "#{p.id.ljust(20)}#{p.label}" }.sort.join("\n")
    end

    # @return [Array<Datasource>]
    def metadata_providers
      providers.select(&:provides_metadata?)
    end

    # @return [Array<Datasource>]
    def citation_data_providers
      providers.select(&:provides_citation_data?)
    end

    # @return [Array<Datasource>]
    def affiliation_data_providers
      providers.select(&:provides_affiliation_data?)
    end

  end

  # @return [Datasource]

  # Abstract Datasource class, datasource implementations must inherit from this
  class Datasource
    class << self
      # @return [String]
      def id
        raise 'Must be implemented by subclass'
      end

      # @return [String]
      def label
        raise 'Must be implemented by subclass'
      end

      # @return [Boolean]
      def enabled?
        raise 'Must be implemented by subclass'
      end

      # @return [Boolean]
      def provides_metadata?
        raise 'Must be implemented by subclass'
      end

      # @return [Array<String>]
      def metadata_types
        raise 'Must be implemented by subclass'
      end

      # @return [Array<String>]
      def languages
        []
      end

      # @return [Boolean]
      def provides_citation_data?
        raise 'Must be implemented by subclass'
      end

      # @return [Boolean]
      def provides_affiliation_data?
        raise 'Must be implemented by subclass'
      end

      attr_accessor :verbose

      Options = Struct.new(:include_references, :include_abstract)

      # Import an item from the datasource, identified by a persistent identifier, which can be anything
      # (ISBN, DOI, or other ) as long as the datasource knows how to handle it
      # @param [String] _id
      # @param [Options] _options
      # @return [Array<Format::CSL::Item>]
      def import(_id, _options = nil)
        raise 'Method must be implemented by subclass'
      end

      # Searches for items that are similar to the given item or
      # match the given string.
      # @param [Format::CSL::Item, String] _item_or_string
      # @return [Array<Format::CSL::Item>, Format::CSL::Item]
      def lookup(_item_or_string)
        raise 'Method must be implemented by subclass'
      end

      # @return [Array<Format::CSL::Item>]
      # @deprecated
      def import_items(item_ids, include_references: false, include_abstract: false)
        raise 'Method must be implemented by subclass'
      end
    end
  end

  # @deprecated
  def self.get_vendor_data(vendors = [])
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
end
