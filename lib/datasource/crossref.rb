# frozen_string_literal: true

require 'serrano'

module Datasource
  class Crossref

    class << self
      def query(name, title, date)
        name = Datasource::Utils.author_lastname(name)
        title_keywords = Datasource::Utils.title_keywords(title)
        args = {
          query_author: name,
          query_bibliographic: "#{title_keywords} #{date}",
          select: 'author, title, issued, DOI'
        }
        $logger.debug("Querying crossref with #{JSON.pretty_generate(args)}")
        response = Serrano.works(**args)
        $logger.debug("Response:#{JSON.pretty_generate(response)}")
      end

      def exists(name, title, date)
        data = query(name, title, date)
        true
      end

      def lookup(name, title, date)
        data = query(name, title, date)
        items_by_doi(data['message'].map { |item| item['DOI'] })
      end

      def items_by_doi(dois)
        $logger.debug("Querying crossref with DOIs #{dois.join(", ")}")
        result = JSON.parse(Serrano.content_negotiation(ids: dois, format: 'citeproc-json'))
        $logger.debug("Response:#{JSON.dump(result)}")
        items = if result.is_a? Array
                result
              else
                [result]
              end
        items.map do |item|
          %w[ license indexed reference-count content-domain created source is-referenced-by-count prefix member
              original-title link deposited score resource subtitle short-title references-count subject relation
              journal-issue alternative-id container-title-short published ISSN published-print
          ].each { |key| item.delete(key) }

          item
        end
      end
    end
  end
end

Serrano.configuration do |config|
  config.mailto = ENV['CROSSREF_EMAIL']
end
