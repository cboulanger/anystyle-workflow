# frozen_string_literal: true

require 'csv'

module Datasource
  class Dimensions
    class << self
      @cache = nil

      def parse_authors(authors)
        return [] if authors.nil?

        authors.split(';').map do |author|
          author_parts = author.split(',')
          {
            'family': author_parts[0]&.strip,
            'given': author_parts[1]&.strip
          }
        end
      end

      def parse_cited_references(cited_refs)
        return [] if cited_refs.nil?

        columns = %w[author author_id journal year vol issue page DOI id]
        rows = cited_refs
                 .split(/(?:;\[)/)
                 .map { |row| row.split('|')[0...-1].map { |v| v.gsub(/[\[\]]/,'') } }

        rows.map do |row|
          columns.each_with_index.map { |k, i| [k.to_s, row[i]] }.to_h
        end
      end

      def init_cache
        @cache = {}
        csv_files = Dir.glob('data/0-metadata/Dimensions-*.csv').map(&:untaint)
        csv_files.each do |csv_path|
          options = {}
          options[:headers] = true
          CSV.foreach(csv_path, **options) do |row|
            doi = row['DOI']
            csl_item = {
              'DOI': doi,
              'abstract': row['Abstract'],
              'author': parse_authors(row['Authors']),
              'container-title': row['Source title/Anthology title'],
              'custom': {
                'dimensions-authors-affiliation': row['Authors Affiliations - Name of Research organization'],
                'dimensions-id': row['Publication ID'],
                'dimensions-times-cited': row['Times cited']
              },
              'issue': row['Issue'],
              'issued': {
                'date-parts': [[row['PubYear']]]
              },
              'page': row['Pagination'],
              'reference': parse_cited_references(row['Cited references']),
              'title': row['Title'],
              'volume': row['Volume']
            }
            @cache[doi] = csl_item
          end
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
