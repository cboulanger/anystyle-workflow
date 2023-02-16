# frozen_string_literal: true

require 'serrano'
require 'namae'

module Datasource
  class Crossref


    CSL_CUSTOM_FIELDS = [
      TIMES_CITED = "crossref-is-referenced-by-count",
      TIMES_CITED_ORIG = "is-referenced-by-count",
      AUTHORS_AFFILIATIONS = 'crossref-authors-affiliations'
    ]

    class << self

      attr_accessor :verbose

      def query(name, title, date)
        name = Datasource::Utils.author_name_family(name)
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
        $logger.debug("Querying crossref with DOIs #{dois.join(', ')}")
        response = Serrano.content_negotiation(ids: dois, format: 'citeproc-json')
        if response.nil?
          $logger.debug "No result"
          return []
        end
        result = JSON.parse(response)
        $logger.debug("Response:#{JSON.dump(result)}")
        items = if result.is_a? Array
                  result
                else
                  [result]
                end
        items.map do |item|
          %w[ license indexed reference-count content-domain created source is-referenced-by-count prefix member
              original-title link deposited score resource subtitle short-title subject relation
              journal-issue alternative-id container-title-short published published-print].each { |key| item.delete(key) }
          item['custom'] = {} if item['custom'].nil?
          item['custom']['crossref-references-count'] = item['references-count']
          item.delete('references-count')
          item
        end
      end

      # fixes some crossref specific problems
      def fix_crossref_item(item)
        # remove xml tags from crossref abstract field
        item['abstract'].gsub!(/<[^<]+?>/, '') if item['abstract'].is_a? String
        # parse crossref's 'reference[]/unstructured' fields into author, date and title information
        references = item['reference'] || []
        if references.length.positive?
          references.map! do |ref|
            if ref['unstructured'].nil? || ref['DOI'].nil?
              ref
            else
              m = ref['unstructured'].match(/^(?<author>.+) \((?<year>\d{4})\) (?<title>[^.]+)\./)
              return ref if m.nil?

              {
                'author' => Namae.parse(m[:author]).map(&:to_h),
                'issued' => [{ 'date-parts' => [m[:year]] }],
                'title' => m[:title],
                'DOI' => ref['DOI']
              }
            end
          end
        end
        item
      end
    end
  end
end

Serrano.configuration do |config|
  config.mailto = ENV['API_EMAIL']
end
