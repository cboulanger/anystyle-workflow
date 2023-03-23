# frozen_string_literal: true

require './lib/datasource/datasource'
require 'httpx'
require 'erb'

module Datasource
  class Harvard < ::Datasource::Datasource
    HTTPX::Plugins.load_plugin(:follow_redirects)
    HTTPX::Plugins.load_plugin(:retries)

    @base_api_url = 'https://api.lib.harvard.edu/v2/items.json?'
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
        'harvard'
      end

      # @return [String]
      def label
        'Data from api.lib.harvard.edu/v2'
      end

      # @return [Boolean]
      def enabled?
        false
      end

      # @return [Boolean]
      def provides_metadata?
        true
      end

      # @return [Array<String>]
      def metadata_types
        [Format::CSL::BOOK]
      end

      # @return [Array<String>]
      def languages
        ['en']
      end

      # @return [Boolean]
      def provides_citation_data?
        false
      end

      # @return [Boolean]
      def provides_affiliation_data?
        false
      end

      # @param [::Format::CSL::Item] item
      # @return [Datasource::Harvard::Item | nil]
      def lookup(item)
        author, year, title = item.creator_year_title(downcase: true)
        query = "#{author} #{year} #{title}".scan(/\p{Alnum}+/).join(' ')
        url = "#{@base_api_url}q=#{ERB::Util.url_encode(query)}"
        cache = Cache.new(url, prefix: "#{id}-")
        if (data = cache.load).nil?
          puts "     - #{id}: requesting #{url}" if @verbose
          response = @http.get(url)
          raise response.error if response.status >= 400

          data = response.json
          cache.save(data)
          return nil if data.dig('pagination', 'numFound').zero?
        elsif verbose
          puts "     - #{id}: cached data exists" if @verbose
        end
        data.dig('items', 'mods')&.map { |r| Item.new(r) }.first
      end
    end

    class Creator < Format::CSL::Creator
      def initialize(data)
        Workflow::Utils.debug_message JSON.dump(data)
        name_part = data['namePart']
        name_literal = case name_part
                       when String
                         name_part
                       when Array
                         name_part.reduce() { |s, i| i.is_a?(String) ? i : s }
                       end
        data = Namae.parse(name_literal).first.to_h
        super
      end
    end

    # example: https://api.lib.harvard.edu/v2/items.json?q=boulanger%20cultural%20lives
    class Item < Format::CSL::Item
      def initialize(data)
        custom.metadata_source = 'harvard'
        fields = %w[titleInfo name originInfo tableOfContents identifier]
        data.each_key { |key| data.delete(key) unless fields.include? key }
        super
      end

      def type
        Format::CSL::BOOK
      end

      def titleinfo=(t)
        self.title = t.values.join(' ')
      end

      def name=(name_arr)
        Workflow::Utils.debug_message JSON.dump(name_arr)
        name_arr = [name_arr] unless name_arr.is_a? Array
        self.author = Array(name_arr).map { |n| Creator.new n }
      end

      def origininfo=(o)
        Workflow::Utils.debug_message JSON.dump o
        self.publisher_place = o['place'].reduce('') do |p, i|
          (i.is_a?(Array) ? i : [i])
            .reduce('') { |p2, i2| i2.dig('placeTerm', '#text') || p }
        end
        self.publisher = o['publisher']
        self.issued = o['dateIssued']
      end

      def language=(lang)
        super lang['languageTerm'].reduce([]) { |a, i| a << i['#text'] if i['@type'] == 'text' }
      end

      def tableofcontents=(toc)
        self.note = toc
      end

      def identifier=(ident)
        self.isbn = ident.reduce([]) { |a, i| a << i['#text'].gsub(/[^\d-]/, '') if i['@type'] == 'isbn' }
        custom.same_as = ident.reduce([]) { |a, i| a << "#{i['@type']}:#{i['#text']}" unless i['@type'] == 'isbn' }
      end

      private

      def extract_text(node, **attributes)
        case node
        when String, Integer
          node
        when Array
          node.each do |i|
            v = extract_text(i, **attributes)
            return v unless v.nil?
          end
        when Hash
          if attribute.nil? && i.is_a?(String)
            i
          elsif !attributes.empty?
            attributes.each do |k, v|
              return i["#text"] if i["@#{k}"] == v
            end
          end
        end
      end
    end
  end
end
