# frozen_string_literal: true

require 'csv'

module Datasource
  class Dimensions
    class << self
      def parse_authors(authors)
        authors.split(';').map do |author|
          author_parts = author.split(',')
          {
            'family': author_parts[0].strip,
            'given': author_parts[1].strip
          }
        end
      end

      def csv_to_csljson(csv_path, **options)
        options[:headers] = true
        metadata_cache = {}
        CSV.foreach(csv_path, **options) do |row|
          doi = row['DOI']
          csl_item = {
            'custom': {
              'dimensions-id': row['Publication ID'],
              'dimensions-authors-affiliation': row['Authors Affiliations - Name of Research organization'],
              'dimensions-times-cited': row['Times cited'],
              'dimensions-cited-references': row['Cited references']
            },
            'DOI': doi,
            'title': row['Title'],
            'abstract': row['Abstract'],
            'container-title': row['Source title/Anthology title'],
            'issued': {
              'date-parts': [[row['PubYear']]]
            },
            'volume': row['Volume'],
            'issue': row['Issue'],
            'page': row['Pagination'],
            'author': parse_authors(row['Authors'])
          }
          metadata_cache[doi] = csl_item
        end
        metadata_cache
      end
    end
  end
end
