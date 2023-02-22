# frozen_string_literal: true

require 'csv'
require 'namae'
require './lib/cache'

module Datasource

  class Dimensions < Datasource

    CSL_CUSTOM_FIELDS = [
      TIMES_CITED = 'dimensions-times-cited',
      AUTHORS_AFFILIATIONS = 'dimensions-authors-affiliation'
    ].freeze

    COLUMNS = [
      COL_AUTHORS_ORG = 'Authors Affiliations - Name of Research organization',
      COL_AUTHORS_COUNTRY = 'Authors Affiliations - Country of Research organization',
      COL_CONTAINER_TITLE = 'Source title/Anthology title'
    ].freeze

    class << self
      @cache = nil

      def parse_authors(authors)
        Namae.parse(authors).map(&:to_h).map { |h| h.slice(:family, :given) }
      end

      def parse_cited_references(cited_refs)
        return [] if cited_refs.nil?

        columns = %w[author author_id journal year vol issue page DOI id]
        rows = cited_refs
                 .split(/(?:;\[)/)
                 .map { |row| row.split('|')[0...-1].map { |v| v.gsub(/[\[\]]/, '') } }

        rows.map do |row|
          columns.each_with_index.map { |k, i| [k.to_s, row[i]] }.to_h
        end
      end

      # @param [Boolean] include_references
      # @param [Boolean] include_abstract
      def init_cache(include_references: false, include_abstract: true)
        cache = {}
        csv_files = Dir.glob('data/0-metadata/dimensions-*.csv')
        csv_files.each do |csv_path|
          puts " - Parsing #{csv_path}" if verbose
          options = {}
          options[:headers] = true
          CSV.foreach(csv_path, **options) do |row|
            doi = row['DOI']
            aff_orgs = Array(row[COL_AUTHORS_ORG]&.split(';')&.map(&:strip))
            aff_countrys = Array(row[COL_AUTHORS_COUNTRY]&.split(';')&.map(&:strip))
            authors = parse_authors(row['Authors']).map do |author|
              if aff_orgs.length.positive?
                author['x-affiliations'] = [
                  {
                    'literal': aff_orgs.shift,
                    'country': aff_countrys.shift
                  }
                ]
              end
              author
            end
            csl_item = {
              'DOI': doi,
              'abstract': row['Abstract'],
              'author': authors,
              'container-title': row[COL_CONTAINER_TITLE],
              'custom': {
                'x-metadata-id': row['Publication ID'],
                'x-times-cited': row['Times cited']
              },
              'issue': row['Issue'],
              'issued': {
                'date-parts': [row['PubYear']]
              },
              'page': row['Pagination'],
              'reference': parse_cited_references(row['Cited references']),
              'title': row['Title'],
              'volume': row['Volume']
            }
            cache[doi] = csl_item
          end
        end
        cache
      end

      # interface method
      # @return [Array<Item>]
      def import_items(dois, include_references: false, include_abstract: false, reset_cache: false)
        @cache ||= Cache.load('dimensions', use_literal: true)
        if @cache && !reset_cache
          puts " - Getting data for #{dois.join(',')} from cache..." if verbose
        else
          @cache = init_cache(include_references: false, include_abstract:)
          Cache.save('dimensions', @cache, use_literal: true)
        end
        dois.map { |doi| Item.new(@cache[doi]) }
      end
    end

    class Item < Format::CSL::Item
      def initialize(_row, data = {})
        custom.metadata_source = 'dimensions'
        super(data)
      end
    end
  end
end
