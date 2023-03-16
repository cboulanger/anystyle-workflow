# frozen_string_literal: true
# The Datasource module contains classes that allow to connect to external datasources
# or query locally stored export files from these sources.
module Datasource
  # @return [Datasource]
  def self.by_id(id)
    klass = ids.select { |k| k.id == id }.first
    raise "No datasource with id '#{id}' exists." if klass.nil?

    klass
  end

  # @return [Array<Datasource>]
  def self.ids
    constants
      .map { |c| const_get c }
      .select { |k| k < Datasource }
  end

  # @return [String]
  def self.list
    ids.map { |k| "#{k.id.ljust(20)}#{k.name}" }.sort.join("\n")
  end

  # Abstract Datasource class, datasource implementations must inherit from this
  class Datasource
    class << self
      # @return [String]
      def self.id
        raise 'Must be implemented by subclass'
      end

      # @return [String]
      def self.name
        raise 'Must be implemented by subclass'
      end

      attr_accessor :verbose

      # @return [Array<Format::CSL::Item>]
      def import_items(*)
        raise 'Method must be implemented by subclass'
      end
    end
  end

  # Given an id and a list of datasources, return an array of results from these sources
  # in CSL-JSON format
  # @deprecated
  # @return Array
  def import_by_identifier(id, verbose:, datasources: [])
    all_items = []
    datasources.map do |ds|
      resolver = by_id(ds)
      if id =~ /^10./ && resolver.respond_to?(:import_items)
        resolver.verbose = verbose
        doi = id.sub('_', '/')
        found_items = resolver.import_items([doi], include_references: true, include_abstract: true)
        all_items.append(found_items.first) if found_items.length.positive?
        puts ' - Data imported.' if verbose
      elsif verbose
        puts " - Identifier '#{id}' cannot be resolved by #{ds}."
      end
    end
    all_items
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
