# frozen_string_literal: true

require 'httpx'
require 'erb'

module Datasource
  class OpenAlex

    CSL_CUSTOM_FIELDS = [
      TIMES_CITED = 'openalex-cited-by-count',
      AUTHORS_AFFILIATIONS = 'openalex-authors-affiliations',
      AUTHORS_INSTITUTIONS = 'openalex-institutions',
      AUTHORS_AFFILIATION_LITERAL = 'openalex-raw-affiliation-string'
    ].freeze

    @email ||= ENV['API_EMAIL']
    @batch_size = 100
    @base_url = 'http://openalex.org'
    @base_api_url = 'http://api.openalex.org'
    @entity_types = %w[work author institution venue]

    class << self

      HTTPX::Plugins.load_plugin(:follow_redirects)
      HTTPX::Plugins.load_plugin(:retries)

      attr_accessor :email, :batch_size
      attr_accessor :verbose

      def headers
        raise 'No email address configured' unless email

        {
          'Accept' => 'application/json',
          'User-Agent' => "requests mailto:#{@email}"
        }
      end

      def raise_api_error(url, response)
        raise "#{url} returned 404 page not found" if response.status == 404
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
        if entity_id.start_with?(@base_url)
          entity_id[(@base_url.length)..]
        else
          entity_id
        end
      end

      # @param [String] entity_type
      # @param [String] entity_id
      def get_single_entity(entity_type, entity_id)
        raise "#{entity_type} is not a valid entity type" unless @entity_types.include? entity_type
        entity_id = get_short_id(entity_id)
        url = "#{@base_api_url}/#{entity_type}s/#{entity_id}"
        if (entity = Cache.load(url)).nil?
          puts " - Requesting #{url}" if verbose
          http = HTTPX.plugin(:follow_redirects, follow_insecure_redirects: true)
                      .plugin(:retries, retry_after: 2, max_retries: 10)
                      .with(timeout: { operation_timeout: 10 })
                      .with(headers:)
          response = http.get(url)
          raise_api_error(url, response) if response.error || response.status >= 400
          entity = response.json
          Cache.save(url, entity)
        else
          puts " - Using cached data for #{url}" if verbose
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
          if (data = Cache.load(url)).nil?
            puts " - Requesting #{url}" if verbose
            HTTPX::Plugins.load_plugin(:follow_redirects)
            http = HTTPX.plugin(:follow_redirects)
            response = http.with(headers:).get(url, follow_insecure_redirects: true)
            raise_api_error(url, response) if response.error || response.status >= 400
            data = response.json
            Cache.save(url, data)
          else
            puts " - Used cached data for #{url}" if verbose
          end
          results.append(data['results'])
          break if results.length >= data['meta']['count']

          page += 1
        end
        # add "api_url" property for debugging
        results.map do |item|
          if item['id']
            entity_id = get_short_id(item['id'])
            item['api_url'] = "#{@base_api_url}/#{entity_type}s/#{entity_id}"
          end
        end
      end

      # Given an array of DOIs, return their metadata in CSL-JSON format
      # @param [Array] dois
      # @return [CSL::Item]
      def import_items_by_doi(dois, include_references: false, include_abstract: false)
        dois.map do |doi|
          data = get_single_entity('work', "doi:#{doi}")
          data.delete('referenced_works') unless include_references
          data.delete('abstract_inverted_index') unless include_abstract
          Item.new(data)
        end
      end

      class Creator < Format::CSL::Creator

        def author=(author)
          self.literal = author['display_name']
          self.x_orcid = author['orcid']
          self.x_author_id = author['id']
          self.x_author_api_url = author['id'].gsub('https://', 'https://api.')
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
        def display_name=(name)
          self.literal = name
        end

        def id=(id)
          self.x_affiliation_id = id
          self.x_affiliation_api_url = id.gsub('https://', 'https://api.')
        end

        # ignore type attr
        def type= _; end
      end

      class Item < Format::CSL::Item

        # to do map any field that might be usable
        IGNORE_FIELDS = %w[ids primary_location open_access cited_by_count biblio is_retracted is_paratext concepts
                        mesh locations best_oa_location alternate_host_venues related_works ngrams_url counts_by_year
                        updated_date created_date].freeze

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
          return if inv_index.nil?

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
          puts ' - Retrieving references...' if OpenAlex.verbose
          self.x_references = work_ids.map do |id|
            oa_item = OpenAlex.get_single_entity('work', id)
            # no recursive download of references, no abstracts
            oa_item.delete('referenced_works')
            oa_item.delete('abstract')
            Item.new(oa_item)
          end
        end

        # Ignored properties
        def display_name=(_)
          ;
        end

        def publication_year=(_)
          ;
        end

        private

        def creator_factory(data)
          Creator.new(data)
        end
      end

      # ######################################################################
      # deprecated methods
      # ######################################################################

      # Given a "publication-date" entry, return a CSL date value
      def parse_date(date)
        {
          "date-parts": date.split('-')
        }
      end

      # Given a OpenAlex/CrossRef item type, return its CSL equivalent
      # incomplete!
      def parse_type(type)
        case type
        when 'journal-article'
          'article-journal'
        when 'book-section'
          'chapter'
        else
          type
        end
      end

      # Given an openalex "authorships" object, return the CSL-JSON
      # "author" field data
      def parse_author(authorships)
        authorships.map do |author|
          {
            "literal": author['author']['display_name'],
            "orcid": author['author']['orcid'],
            "#{AUTHORS_INSTITUTIONS}": author['institutions'],
            "#{AUTHORS_AFFILIATION_LITERAL}": author['raw_affiliation_string'],
            "openalex-author-id": author['author']['id']
          }
        end
      end

      def parse_page(entity)
        e = entity
        first_page = e['biblio']['first_page']
        last_page = e['biblio']['last_page']
        return nil unless first_page && last_page

        "#{first_page}-#{last_page}"
      end

      def parse_reference(entity)
        rw = entity['referenced_works']
        puts ' - Retrieving references...' if verbose
        rw.map do |openalex_id|
          entity_to_csl(get_single_entity('work', openalex_id))
        end
      end

      def parse_abstract(entity)
        ii = entity['abstract_inverted_index']
        return if ii.nil?

        text = []
        ii.each { |word, list| list.each { |i| text[i] = word } }
        text.join(' ')
      end

      # Given an API entity response, return CSL-JSON data
      # @param [Hash] entity
      def entity_to_csl(entity, include_references: false, include_abstract: false)
        e = entity
        item = {
          "custom": {
            "openalex-id": get_short_id(e['id']),
            "openalex-cited-by-count": e['cited_by_count'],
            "openalex-counts-by-year": e['counts_by_year']
          },
          "DOI": e['doi'],
          "title": e['title'],
          "issued": [parse_date(e['publication_date'])],
          "container-title": e['host_venue']['display_name'],
          "type": parse_type(e['type']),
          "author": parse_author(e['authorships']),
          "volume": e['biblio']['volume'],
          "issue": e['biblio']['issue'],
          "page": parse_page(e)
        }
        item['reference'] = parse_reference(e) if include_references
        item['abstract'] = parse_abstract(e) if include_abstract
        item.delete_if { |_k, v| v.nil? }
        item
      end

    end

  end
end
