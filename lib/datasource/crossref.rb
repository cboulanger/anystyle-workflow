# frozen_string_literal: true

require 'serrano'

module Datasource
  class Crossref
    def lookup(name, title, date)
      name = name.gsub(/[^\p{L}\s]/, '').split(' ').reject { |w| w.length < 3 }.join(' ')
      title_keywords = title.scan(/[[:alnum:]]+/).sort_by(&:length).last(2).join(' ')
      args = {
        query_author: name,
        query_bibliographic: "#{title_keywords} #{date}",
        select: 'author, title, issued, DOI'
      }
      $logger.debug("Querying crossref with #{JSON.pretty_generate(args)}")
      response = Serrano.works(**args)
      $logger.debug("Response:#{JSON.pretty_generate(response)}")
      self.items_by_doi(response['message'].map { |item| item['DOI'] })
    end

    def self.items_by_doi(dois)
      $logger.debug("Querying crossref with DOIs #{JSON.pretty_generate(dois)}")
      response = Serrano.content_negotiation(ids: dois, format: 'citeproc-json')
      $logger.debug("Response:#{JSON.pretty_generate(response)}")
      response['message']
    end
  end
end

Serrano.configuration do |config|
  config.mailto = ENV['CROSSREF_EMAIL']
end
