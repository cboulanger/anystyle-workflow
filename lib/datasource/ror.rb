# frozen_string_literal: true

require './lib/datasource/datasource'

require 'httpx'
require 'erb'

# https://api.ror.org/organizations?affiliation=univ%20glasgow

module Datasource
  class Ror < ::Datasource::Datasource

    HTTPX::Plugins.load_plugin(:follow_redirects)
    HTTPX::Plugins.load_plugin(:retries)

    @base_api_url = 'https://api.ror.org/organizations?'
    @headers = {
      'Accept' => 'application/json'
    }
    @http = HTTPX.plugin(:follow_redirects)
                 .plugin(:retries, retry_after: 2, max_retries: 10)
                 .with(timeout: { operation_timeout: 10 })
                 .with(headers: @headers)

    class << self
      # @return [String]
      def id
        'ror'
      end

      # @return [String]
      def label
        'Data from api.ror.org'
      end

      # @return [Boolean]
      def enabled?
        false
      end

      # @return [Boolean]
      def provides_metadata?
        false
      end

      # The type of identifiers that can be used to import data
      # @return [Array<String>]
      def id_types
        [::Datasource::ROR_ID]
      end

      # @return [Boolean]
      def provides_citation_data?
        false
      end

      # @return [Boolean]
      def provides_affiliation_data?
        true
      end


      # @return [Array<Format::CSL::Affiliation>]
      # @param [Format::CSL::Affiliation] affiliation
      def lookup(affiliation)
        raise 'Argument must be Format::CSL::Affiliation' unless affiliation.is_a? Format::CSL::Affiliation

        affiliation_string = affiliation.to_s
        return if affiliation_string.empty?

        url = "#{@base_api_url}affiliation=#{ERB::Util.url_encode(affiliation_string)}"
        cache = Cache.new(url, prefix: "#{id}-")
        if (data = cache.load).nil?
          puts " - #{id}: requesting #{url}" if @verbose
          response = @http.get(url)
          raise response.error if response.status >= 400

          data = response.json
          cache.save(data)
          return nil if (data['number_of_results']).zero?
        elsif verbose
          puts " - #{id}: cached data exists" if @verbose
        end
        data['items'].map do |a|
          d = a['organization']
          d['x_affiliation_api_url'] = url
          Affiliation.new d
        end
      end

    end

    class Affiliation < Format::CSL::Affiliation
      def initialize(data, accessor_map: nil)
        self.ror= data['id']
        self.institution = data['name']
        self.country= data.dig('country', 'country_name')
        self.country_code = data.dig('country', 'country_code')
        self.x_affiliation_source = "ror"
        self.address = JSON.dump data['addresses']
      end
    end
  end
end
