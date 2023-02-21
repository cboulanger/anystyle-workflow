# frozen_string_literal: true

require 'serrano'
require 'namae'
require 'digest'

module Datasource
  class Crossref

    CSL_CUSTOM_FIELDS = [
      TIMES_CITED = 'crossref-is-referenced-by-count',
      TIMES_CITED_ORIG = 'is-referenced-by-count',
      NUMBER_REFERENCES = 'references-count',
      AUTHOR_AFFILIATIONS = 'crossref-author-affiliations',
      AUTHORS_AFFILIATIONS = 'crossref-authors-affiliations'
    ].freeze

    include Format::CSL

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

      # ######################################################################
      # new style
      # ######################################################################

      def import_items_by_doi(dois, include_references: true, include_abstract: true)
        raise "dois must be Array" unless dois.is_a? Array
        puts " - Querying crossref with DOI #{dois.join(', ')}" if verbose

        items = Cache.load(dois)
        if items.nil?
          response = Serrano.content_negotiation(ids: dois, format: 'citeproc-json')
          if response.nil?
            puts ' - No result' if verbose
            return []
          end
          items = JSON.parse(response)
          unless items.is_a? Array
            items = [items]
          end
          items.map! do |item|
            item.delete('reference') unless include_references
            item.delete('abstract') unless include_abstract
          end
          Cache.save(dois, items)
        elsif verbose
          puts " - Using cache for DOI #{dois.join(', ')}" if verbose
        end

        items.map do |item|
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
