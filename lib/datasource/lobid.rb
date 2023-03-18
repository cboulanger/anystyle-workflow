# frozen_string_literal: true

require './lib/datasource/datasource'

require 'httpx'
require 'erb'

module Datasource
  class Lobid < ::Datasource::Datasource

    HTTPX::Plugins.load_plugin(:follow_redirects)
    HTTPX::Plugins.load_plugin(:retries)
    HTTPX::Plugins.load_plugin(:rate_limiter)

    @batch_size = 100
    @base_url = 'https://lobid.org'
    @base_api_url = 'https://lobid.org/resources/search?'
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
        'lobid'
      end

      # @return [String]
      def name
        'Data from lobid.org'
      end

      # @return [Boolean]
      def enabled?
        true
      end

      # @return [Boolean]
      def provides_metadata?
        true
      end

      # @return [Array<String>]
      def metadata_types
        [Format::CSL::BOOK, Format::CSL::CHAPTER]
      end

      # @return [Boolean]
      def provides_citation_data?
        false
      end

      # @return [Boolean]
      def provides_affiliation_data?
        true
      end

      # @param [::Format::CSL::Item] item
      # @return [::Format::CSL::Item | nil]
      def lookup(item)
        author, year, title = item.creator_year_title(downcase: true)
        # query = %W[contribution.agent.label:#{author}
        #            publication.startDate:#{year}
        #            title:#{title.scan(/\p{L}+/).join(' ')}].join(' AND ')

        query = "#{author} #{year} #{title}".scan(/\p{Alnum}+/).join(' ')

        url = "#{@base_api_url}q=#{ERB::Util.url_encode(query)}"
        cache = Cache.new(url, prefix: 'lobid-')
        if (data = cache.load).nil?
          puts "     - lobid: requesting #{url}" if @verbose
          response = @http.get(url)
          raise response.error if response.status >= 400

          data = response.json
          cache.save(data)
          return nil if (data['totalItems']).zero?
        elsif verbose
          puts '     - lobid: cached data exists' if @verbose
        end
        data['member'].map { |r| Item.new(r) }.first
      end

    end

    class Creator < Format::CSL::Creator
      def initialize(data)
        data.merge! Namae.parse(data['label']).first.to_h
        super
      end

      def dateofbirth=(date)
        self.x_date_birth = date
      end

      def id=(id)
        self.x_author_id = id
      end

      # ignore the following attributes
      def dateofbirthanddeath=(*) end
      def label=(*); end
      def type=(*) end
      def gndidentifier=(*) end
      def type(*) end
      def dateofdeath=(*) end
      def altlabel=(*) end
      def source=(*) end
    end

    class Item < Format::CSL::Item
      def initialize(data)
        custom.metadata_source = 'lobid'
        custom.metadata_id = data['id']
        custom.same_as = (custom.same_as || []) + data['sameAs'].map { |s| s['id'] } if data['sameAs']
        fields = %w[type contribution publication isbn language edition title]
        data.each_key { |key| data.delete(key) unless fields.include? key }
        super
      end

      def type=(type)
        super Format::CSL::BOOK
      end

      def publication=(p)
        return unless (p = p.first)

        self.publisher = Array(p['publishedBy']).map { |i| i.sub(/Imprint:/, '') }.join(' ')
        self.issued = p['startDate'] || 0
        self.publisher_place = p['location']
      end

      def contribution=(contribution)
        contribution.each do |c|
          case c['role']['id']
          when 'http://id.loc.gov/vocabulary/relators/aut'
            author << Creator.new(c['agent'])
          when 'http://id.loc.gov/vocabulary/relators/edt'
            editor << Creator.new(c['agent'])
          else
            # pass
          end
        end
      end


      def edition=(ed)
        super ed.first
      end

    end
  end
end
