require './lib/datasource/datasource'

require 'httpx'
require 'erb'

module Datasource
  class OpenAlex < ::Datasource::Datasource

    HTTPX::Plugins.load_plugin(:follow_redirects)
    HTTPX::Plugins.load_plugin(:retries)
    HTTPX::Plugins.load_plugin(:rate_limiter)

    @email ||= ENV['API_EMAIL'] || raise('Email is required for OpenAlex')
    @batch_size = 100
    @base_url = 'https://openalex.org'
    @base_url2 = 'http://openalex.org'
    @base_api_url = 'https://api.openalex.org'
    @base_api_url2 = 'http://api.openalex.org'
    @entity_types = %w[work author institution venue]
    @headers = {
      'Accept' => 'application/json',
      'User-Agent' => "ruby/HTTPX mailto:#{@email}"
    }
    @http = HTTPX.plugin(:follow_redirects)
                 .plugin(:retries, retry_after: 5, max_retries: 3)
                 .plugin(:rate_limiter)
                 .with(timeout: { operation_timeout: 600 })
                 .with(headers: @headers)

    class << self

      # @return [String]
      def id
        'openalex'
      end

      # @return [String]
      def label
        'Data from api.openalex.org'
      end

      # @return [Boolean]
      def enabled?
        true
      end

      # @return [Boolean]
      def provides_metadata?
        false #
      end

      # @return [Array<String>]
      def metadata_types
        [Format::CSL::ARTICLE_JOURNAL, Format::CSL::CHAPTER, Format::CSL::BOOK]
      end

      # The type of identifiers that can be used to import data
      # @return [Array<String>]
      def id_types
        [::Datasource::DOI]
      end

      # @return [Boolean]
      def provides_citation_data?
        true
      end

      # @return [Boolean]
      def provides_affiliation_data?
        true
      end

      attr_accessor :email, :batch_size
      attr_accessor :verbose

      def raise_api_error(url, response)
        # raise "#{url} returned 404 page not found" if response.status == 404
        if response.error
          error = 'Connection error'
          message = response.error.to_s
        else
          begin
            json_response = response.json
            error = json_response['error']
            message = json_response['message']
          rescue StandardError
            error = 'Unknown Error'
            message = response.to_s
          end
        end
        raise "Call to #{url} failed.\n#{error}: #{message}"
      end

      def get_short_id(entity_id)
        if entity_id.start_with? @base_url
          entity_id[(@base_url.length + 1)..]
        elsif entity_id.start_with? @base_url2
          entity_id[(@base_url2.length + 1)..]
        else
          entity_id
        end
      end

      # @param [String] entity_type
      # @param [String] entity_id
      def get_single_entity(entity_type, entity_id)
        raise "#{entity_type} is not a valid entity type" unless @entity_types.include? entity_type

        # this whole convoluted stuff below is to rename previous caches, the names of which were based on the
        # whole url, it will go away once they are all converted
        entity_id_long = entity_id
        entity_id = get_short_id(entity_id)
        url = "#{@base_api_url}/#{entity_type}s/#{entity_id}"
        url2 = "#{@base_api_url2}/#{entity_type}s/#{entity_id_long}"
        cache2 = Cache.new(url2, prefix: 'openalex-')
        cache3 = Cache.new("openalex-#{entity_id.gsub(/[^\p{Alnum}]/,"_")}", use_literal: true)
        data1 = Cache.load(url2)
        data2 = cache2.load
        data3 = cache3.load
        if (entity = data2 || data1 || data3).nil?
          puts " - Requesting #{url}" if verbose
          tries = 3
          entity = loop do
            response = @http.get(url)
            unless response.error || response.status >= 400
              break response.json
            end
            unless response.error.to_s.include?('timed out') && tries > 0
              raise_api_error(url, response)
            end
            puts response.error.to_s.colorize(:red)
            tries -= 1
          end
          cache3.save(entity)
        else
          puts " - Using cached data for #{url}" if verbose
          if data1 || data2
            cache3.save(entity)
            Cache.delete(url) if data1
            cache2.delete if data2
          end
        end
        entity
      end

      def get_multiple_entities(entity_type, entity_filter)
        raise "#{entity_type} is not a valid entity type" unless @entity_types.include? entity_type

        page = 1
        results = []
        filter = ERB::Util.url_encode(entity_filter)
        loop do
          url = "#{@base_api_url}/#{entity_type}s?filter=#{filter}&per-page=#{batch_size}&page=#{page}"
          url2 = "#{@base_api_url2}/#{entity_type}s?filter=#{filter}&per-page=#{batch_size}&page=#{page}"
          cache = Cache.new(url, prefix: 'openalex-')
          cache2 = Cache.new(url2, prefix: 'openalex-')
          data2 = cache2.load
          if (data = cache.load || data2).nil?
            puts " - Requesting #{url}" if verbose
            response = @http.get(url)
            raise_api_error(url, response) if response.error || response.status >= 400
            data = response.json
            cache.save(data)
            cache2.delete if data2
          else
            puts " - Used cached data for #{url}" if verbose
          end
          results += data['results']
          break if results.length >= data['meta']['count']

          page += 1
        end
        results
      end

      def items_by_filter(filter)
        get_multiple_entities('work', filter)
          .map { |data| Item.new data }
      end

      # Given an array of DOIs, return their metadata in CSL-JSON format
      # @param [Array] dois
      # @return [Array<Item>]
      def import_items(dois, include_references: false, include_abstract: false, prefix: '')
        dois.map do |doi|
          data = get_single_entity('work', "doi:#{doi}")
          data.delete('referenced_works') unless include_references
          data.delete('abstract_inverted_index') unless include_abstract
          Item.new(data)
        end
      end

    end

    class Creator < Format::CSL::Creator

      def author=(author)
        self.literal = author['display_name']
        self.x_orcid = author['orcid']
        self.x_author_id = author['id']
        self.x_author_api_url = author['id']&.gsub('https://', 'https://api.')
      end

      def author_position=(p)
        self.sequence = p
      end

      def raw_affiliation_string=(s)
        self.x_raw_affiliation_string = s
      end

      def institutions=(institutions)
        self.x_affiliations = institutions
      end

      private

      def affiliation_factory(data)
        Affiliation.new(data)
      end

    end

    class Affiliation < Format::CSL::Affiliation

      def initialize(data, accessor_map: nil)
        super
        self.x_affiliation_source = 'openalex'
      end

      def display_name=(name)
        self.literal = name
      end

      def id=(id)
        self.x_affiliation_id = id
        self.x_affiliation_api_url = id&.gsub('https://', 'https://api.')
      end

      # ignore type attr
      def type= _; end
    end

    class Item < Format::CSL::Item

      # to do map any field that might be usable
      IGNORE_FIELDS = %w[ids primary_location open_access cited_by_count biblio is_retracted is_paratext concepts
                        mesh locations best_oa_location alternate_host_venues related_works ngrams_url counts_by_year
                        updated_date created_date summary_stats].freeze

      def initialize(data)
        custom.metadata_source = 'openalex'

        IGNORE_FIELDS.each { |key| data.delete(key) }
        super data
      end

      def id=(id)
        custom.metadata_id = id
        custom.metadata_api_url = id.sub('https://', 'https://api.')
      end

      def publication_date=(date)
        self.issued = ({ "date-parts": [date.split('-')] })
      end

      def biblio=(biblio)
        self.volume = biblio['volume']
        self.issue = biblio['issue']
        first_page = biblio['first_page']
        last_page = biblio['last_page']
        self.page = "#{first_page}-#{last_page}"
      end

      def authorships=(authorships)
        self.author = authorships
      end

      def type=(type)
        super(case type
              when 'journal-article'
                'article-journal'
              when 'book-section'
                'chapter'
              else
                type
              end)
      end

      def host_venue=(venue)
        self.custom.container_id = venue['id']
        self.issn = venue['issn']
        self.container_title = venue['display_name']
      end

      def abstract_inverted_index=(inv_index)
        return if inv_index.to_s.empty?

        text = []
        inv_index.each { |word, list| list.each { |i| text[i] = word } }
        self.abstract = text.join(' ')
      end

      def cited_by_count=(count)
        custom.times_cited = count
      end

      def cited_by_api_url=(url)
        custom.cited_by_api_url = url
      end

      def referenced_works=(work_ids)
        puts " - Retrieving #{work_ids.length} references for #{self.to_s}" if OpenAlex.verbose
        self.x_references = work_ids.map do |id|
          oa_item = OpenAlex.get_single_entity('work', id)
          # no recursive download of references
          oa_item.delete('referenced_works')
          Item.new(oa_item)
        end
      end

      # Ignored properties
      def display_name=(_) end

      def publication_year=(_) end

      private

      def creator_factory(data)
        Creator.new(data)
      end
    end
  end
end
