# frozen_string_literal: true

require './lib/datasource/datasource'

require 'serrano'
require 'namae'
require 'digest'
require 'httpx'
require 'erb'

module Datasource
  class Crossref < ::Datasource::Datasource
    TYPES_MAP = {
      'journal-article' => Format::CSL::ARTICLE_JOURNAL
    }.freeze

    HTTPX::Plugins.load_plugin(:follow_redirects)
    HTTPX::Plugins.load_plugin(:retries)
    HTTPX::Plugins.load_plugin(:rate_limiter)
    @headers = {
      'Accept' => 'application/json',
      'User-Agent' => "ruby/HTTPX mailto:#{@email}"
    }
    @http = HTTPX.plugin(:follow_redirects, follow_insecure_redirects: true)
                 .plugin(:retries, retry_after: 2, max_retries: 10)
                 .plugin(:rate_limiter)
                 .with(timeout: { operation_timeout: 120 })
                 .with(headers: @headers)

    Serrano.configuration do |config|
      config.mailto = ENV['API_EMAIL']
    end

    class << self
      # @param [::Format::CSL::Item] item
      # @return [::Format::CSL::Item | nil]
      def lookup(item)
        raise 'Argument must be Format::CSL::Item' unless item.is_a? ::Format::CSL::Item

        author, year, title = item.creator_year_title
        cit_str = "#{author} (#{year}) #{title}, #{item.container_title}".strip
        select = 'type,DOI,title,author,container-title,issued,page,volume,issue'
        # TO DO: use HTTPX semantics https://honeyryderchuck.gitlab.io/httpx/wiki/Make-Requests
        url = "http://api.crossref.org/works?query.bibliographic=#{ERB::Util.url_encode(cit_str)}&select=#{select}&rows=1"
        if (data = Cache.load(url, prefix: '_cr-bib-')).nil?
          puts "   - looking up '#{cit_str}'" if @verbose
          begin
            response = @http.get(url)
            raise response.error if response.error || response.status >= 400

            data = response.json.dig('message', 'items')&.first
            Cache.save(url, data, prefix: '_cr-bib-')
          rescue StandardError => e
            puts
            puts "Error:".colorize(:red)
            puts e.to_s
            puts
            data = nil
          end
        elsif @verbose
          puts "   - getting '#{cit_str}' from cache"
        end
        if data.to_s.empty?
          item = nil
          puts '   - no match was found' if @verbose
        else
          item = Item.new(data)
          item.custom.metadata_api_url = url
          puts "   - found https://doi.org/#{item.doi}" if @verbose
        end
        item
      end

      # @return [Array<Item>]
      def import_items(dois, include_references: true, include_abstract: true)
        raise 'dois must be Array' unless dois.is_a? Array

        items = Cache.load(dois)
        if items.nil?
          retries = 0
          wait_time = 1
          response = loop do
            dois_str = dois.join(', ')
            begin
              retries_str = (retries.positive? ? "(#{retries})" : '')
              puts " - CrossRef: Requesting data for #{dois_str} #{retries_str}" if verbose
              response = Serrano.content_negotiation(ids: dois, format: 'citeproc-json')
              sleep 0.5 # avoid hitting the rate limit
              break response
            rescue Net::ReadTimeout, Faraday::ConnectionFailed
              retries += 1
              raise 'Too many timeouts' if retries > 3

              warn " - CrossRef: Connection problem, retrying in #{wait_time} seconds...".colorize(:red)
              sleep wait_time
              wait_time *= 2
            end
          end

          if response.nil?
            puts ' - No result' if verbose
            return []
          end
          items = JSON.parse(response)
          items = [items] unless items.is_a? Array
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

    class Affiliation < Format::CSL::Affiliation
      def initialize(data, accessor_map: nil)
        super
        self.x_affiliation_source = 'crossref'
      end

      def name=(name)
        self.literal = name
      end
    end

    class Creator < Format::CSL::Creator
      def name=(name)
        self.literal = name
      end

      def orcid=(orcid)
        self.x_orcid = orcid
      end

      def authenticated_orcid=(orcid)
        self.x_orcid = orcid
      end

      def affiliation=(affiliation)
        self.x_affiliations = affiliation.map { |a| Affiliation.new({ 'literal': a }) }
      end
    end

    class Item < Format::CSL::Item
      ACCESSOR_MAP = {
        'page_first': 'first-page'
      }.freeze

      # to do map any field that might be usable
      IGNORE_FIELDS = %w[license indexed reference-count content-domain created source funder article-number notes
                         is-referenced-by-count isbn_type references-count prefix member original-title link deposited
                         score resource subtitle short-title subject relation published-online doi-asserted-by
                         journal-issue alternative-id container-title-short published published-print publisher_location].freeze

      def initialize(data, accessor_map: {})
        custom.metadata_source = 'crossref'
        IGNORE_FIELDS.each { |key| data.delete(key) }
        super(data, accessor_map: accessor_map.merge(ACCESSOR_MAP))
      end

      def type=(type)
        type = TYPES_MAP[type] || type
        super(type)
      end

      def author=(authors)
        if authors.is_a? String
          author_ = Creator.new(({ literal: authors }))
          author_.family, author_.given = author_.family_and_given
          authors = [author_]
        end
        super
      end

      def title=(title)
        title = title.join('. ') if title.is_a? Array
        super(title)
      end

      def year=(year)
        self.issued = year.to_i if issued.nil? && year.to_i.positive?
      end

      def article_title=(title)
        self.title = title
      end

      def abstract=(abstract)
        @abstract = abstract.gsub!(/<[^<]+?>/, '')
      end

      def is_referenced_by_count=(count)
        custom.times_cited = count
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
                   else
                     ref
                   end
            item['DOI'] = ref['DOI'] if ref['DOI']
            Item.new(item)
          else
            raise 'Invalid reference item'
          end
        end
      end

      def key=(key)
        self.citation_key = key
      end

      def journal_title=(title)
        self.container_title = title
      end

      def container_title=(title)
        title = (title.is_a?(Array) ? title.first : title).to_s
        title.gsub!('&amp;', '&')
        super(title)
      end

      protected

      def creator_factory(data)
        Creator.new(data)
      end
    end
  end
end
