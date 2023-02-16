# frozen_string_literal: true

require 'csv'
require 'namae'

module Datasource
  class Dimensions

    CSL_CUSTOM_FIELDS = [
      ID_FIELD = 'dimensions-id',
      TIMES_CITED = "dimensions-times-cited",
      AUTHORS_AFFILIATIONS = 'dimensions-authors-affiliation'
    ]

    class << self

      attr_accessor :verbose

      @cache = nil

      def parse_authors(authors)
        Namae.parse(authors).map(&:to_h).map {|h| h.slice(:family,:given)}
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

      def init_cache(save:false)
        @cache = {}
        csv_files = Dir.glob('data/0-metadata/dimensions-*.csv')
        csv_files.each do |csv_path|
          puts "Parsing #{csv_path}"
          options = {}
          options[:headers] = true
          CSV.foreach(csv_path, **options) do |row|
            doi = row['DOI']
            authors = parse_authors(row['Authors'])
            aff_org =  Array(row['Authors Affiliations - Name of Research organization']&.split(";")&.map(&:strip))
            aff_country = Array(row['Authors Affiliations - Country of Research organization']&.split(";")&.map(&:strip))
            affiliations = if aff_org.length.positive?
                             aff_org.map.with_index {|v,i| "#{v}, #{aff_country[i]}"}
                           else
                             nil
                           end
            csl_item = {
              'DOI': doi,
              'abstract': row['Abstract'],
              'author': authors,
              'container-title': row['Source title/Anthology title'],
              'custom': {
                AUTHORS_AFFILIATIONS: affiliations,
                ID_FIELD: row['Publication ID'],
                TIMES_CITED: row['Times cited']
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
            @cache[doi] = csl_item
          end
        end
        puts "Saving #{@cache.keys.length} entries"
        if save
          File.write( 'data/0-metadata/dimensions.json', JSON.pretty_generate(@cache))
        end
      end

      # interface method
      # @return Array
      def items_by_doi(dois)
        init_cache if @cache.nil?
        dois.map { |doi| @cache[doi] }
      end
    end
  end
end
