# frozen_string_literal: true

require 'serrano'
require 'namae'
require 'digest'

module Datasource
  class Crossref < Datasource

    CSL_CUSTOM_FIELDS = [
      TIMES_CITED = 'crossref-is-referenced-by-count',
      TIMES_CITED_ORIG = 'is-referenced-by-count',
      NUMBER_REFERENCES = 'references-count',
      AUTHOR_AFFILIATIONS = 'crossref-author-affiliations',
      AUTHORS_AFFILIATIONS = 'crossref-authors-affiliations'
    ].freeze

    class << self

      def query(name, title, date)
        raise 'must be reimplemented'
        # name = Format::CSL.author_name_family(name)
        # title_keywords = Format::CSL.title_keywords(title)
        # args = {
        #   query_author: name,
        #   query_bibliographic: "#{title_keywords} #{date}",
        #   select: 'author, title, issued, DOI'
        # }
        # puts "Querying crossref with #{JSON.pretty_generate(args)}" if verbose
        response = Serrano.works(**args)
        #puts"Response:#{JSON.pretty_generate(response)}" if verbose
        # response
      end

      def exists(name, title, date)
        data = query(name, title, date)
        raise "not implemented"
      end

      def lookup(name, title, date)
        data = query(name, title, date)
        import_items(data['message'].map { |item| item['DOI'] })
      end

      # @return [Array<Item>]
      def import_items(dois, include_references: true, include_abstract: true)
        raise 'dois must be Array' unless dois.is_a? Array

        items = Cache.load(dois)
        if items.nil?
          puts " - CrossRef: Requesting data for #{dois.join(', ')}" if verbose
          response = Serrano.content_negotiation(ids: dois, format: 'citeproc-json')
          if response.nil?
            puts ' - No result' if verbose
            return []
          end
          items = JSON.parse(response)
          unless items.is_a? Array
            items = [items]
          end
          Cache.save(dois, items)
        elsif verbose
          puts " - CrossRef: Using cache for DOI #{dois.join(', ')}" if verbose
        end
        items.map do |item|
          item.delete('reference') unless include_references
          item.delete('abstract') unless include_abstract
          Item.new(item)
        end
      end
    end

    class Creator < Format::CSL::Creator
      def affiliation=(affiliation)
        self.x_affiliations = affiliation.map { |a| Format::CSL::Affiliation.new({ 'literal': a }) }
      end
    end

    class Item < Format::CSL::Item

      # to do map any field that might be usable
      IGNORE_FIELDS = %w[license indexed reference-count content-domain created source
                         is-referenced-by-count references-count prefix member original-title link deposited
                         score resource subtitle short-title subject relation
                         journal-issue alternative-id container-title-short published published-print].freeze

      def initialize(data)
        self.custom.metadata_source = 'crossref'
        IGNORE_FIELDS.each { |key| data.delete(key) }
        super data
      end

      def creator_factory(data)
        Creator.new(data)
      end

      def abstract=(abstract)
        @abstract = abstract.gsub!(/<[^<]+?>/, '')
      end

      def is_referenced_by_count=(count)
        self.custom.times_cited = count
      end

      def reference=(references)
        regex = /^(?<author>.+) \((?<year>\d{4})\) (?<title>[^.]+)\./
        self.x_references = references.map do |ref|
          case ref
          when Item
            ref
          when Hash
            item = if ref['unstructured']
                     if (m = ref['unstructured'].match(regex))
                       {
                         'author' => Namae.parse(m[:author]).map(&:to_h),
                         'issued' => { 'date-parts' => [m[:year]] },
                         'title' => m[:title],
                         'DOI' => ref['DOI']
                       }
                     else
                       {
                         'title' => ref['unstructured']
                       }
                     end
                   end
            item['DOI'] = ref['DOI'] if ref['DOI']
            Item.new(item)
          else
            raise "Invalid reference item"
          end
        end
      end
    end
  end
end

Serrano.configuration do |config|
  config.mailto = ENV['API_EMAIL']
end
