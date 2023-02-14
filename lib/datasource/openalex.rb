# frozen_string_literal: true

require 'httpx'
require 'erb'

module Datasource
  class OpenAlex

    CSL_CUSTOM_FIELDS = [
      TIMES_CITED = "openalex-cited-by-count",
      AUTHORS_AFFILIATIONS = 'openalex-authors-affiliations',
      AUTHORS_INSTITUTIONS = 'openalex-institutions',
      AUTHORS_AFFILIATION_LITERAL = 'openalex-raw-affiliation-string'
    ]

    @email ||= ENV['API_EMAIL']
    @batch_size = 100
    @base_url = 'https://openalex.org/'
    @base_api_url = 'https://api.openalex.org/'
    @entity_types = %w[work author institution venue]
    class << self
      attr_accessor :email, :batch_size

      def headers
        raise 'No email address configured' unless email

        {
          'Accept' => 'application/json',
          'User-Agent' => "requests mailto:#{@email}"
        }
      end

      def raise_api_error(url, response)
        raise "#{url} returned 404 page not found" if response.status == 404

        begin
          json_response = response.json
          error = json_response['error']
          message = json_response['message']
        rescue StandardError
          error = 'Unknown Error'
          message = response.body.to_s
        end
        raise "Call to #{url} failed.\nError:#{response.status_code} #{error}\nMessage: #{message}"
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
        $logger.debug "Requesting #{url}"
        response = HTTPX.with(headers:).get(url)
        raise_api_error(url, response) if response.status != 200
        response.json
      end

      def get_multiple_entities(entity_type, entity_filter)
        raise "#{entity_type} is not a valid entity type" unless @entity_types.include? entity_type

        page = 1
        results = []
        filter = ERB::Util.url_encode(entity_filter)
        loop do
          url = "#{@base_api_url}/#{entity_type}s?filter=#{filter}&per-page=#{batch_size}&page=#{page}"
          $logger.debug "Requesting #{url}"
          response = HTTPX.with(headers:).get(url)
          raise_api_error(url, response) if response.status != 200

          data = response.json
          results.append(data['results'])
          break if results.length >= data['meta']['count']

          page += 1
          time.sleep(1)
        end
        # add "api_url" property for debugging
        results.map do |item|
          if item['id']
            entity_id = get_short_id(item['id'])
            item['api_url'] = "#{@base_api_url}/#{entity_type}s/#{entity_id}"
          end
        end
      end

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
            AUTHORS_INSTITUTIONS: author['institutions'],
            AUTHORS_AFFILIATION_LITERAL: author['raw_affiliation_string']
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

      def parse_reference(referenced_works)
        referenced_works.map do |openalex_id|
          entity_to_csl get_single_entity('work', openalex_id), include_references: false
        end
      end

      def parse_abstract(_abstract_inverted_index)
        'not implemented'
      end

      # Given an API entity response, return CSL-JSON data
      # @param [Hash] entity
      def entity_to_csl(entity, include_references: true, include_abstract: false)
        e = entity
        item = {
          "custom": {
            "openalex-id": get_short_id(e['id']),
            "openalex-cited-by-count": e['cited_by_count']
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
        item['reference'] = parse_reference(e['referenced_works']) if include_references
        item['abstract'] = parse_abstract(e['abstract_inverted_index']) if include_abstract
        item
      end

      # Given an array of DOIs, return their metadata in CSL-JSON format
      # @param [Array] dois
      # @return Array
      def items_by_doi(dois)
        dois.map do |doi|
          entity = get_single_entity 'work', "doi:#{doi}"
          entity_to_csl entity, include_references: true
        end
      end
    end
  end
end
