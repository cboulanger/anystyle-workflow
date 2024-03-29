# frozen_string_literal: true
require 'httpx'
require 'erb'

module Datasource
  class Openlibrary

    class << self
      @base_url = 'https://openlibrary.org'

      # @return [String]
      def id
        'openlibrary'
      end

      # @return [String]
      def name
        'Data from openlibrary.org - not implemented yet'
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
        [Format::CSL::BOOK, Format::CSL::CHAPTER]
      end

      # The type of identifiers that can be used to import data
      # @return [Array<String>]
      def id_types
        [::Datasource::ISBN]
      end

      def languages
        ['de','en']
      end

      # @return [Boolean]
      def provides_citation_data?
        false
      end

      # @return [Boolean]
      def provides_affiliation_data?
        true
      end

      def query(name, title, date)
        raise 'must be reimplemented'
        # name = Datasource.author_name_family(name)
        # title_keywords = Datasource.title_keywords(title)
        # lookup_string = "q=author:\"#{name}\" title:\"#{title_keywords}\" publish_year:#{date}"
        # url = @base_url + '/search.json?' + ERB::Util.url_encode(lookup_string)
        # $logger.debug "Searching openlibrary.org: #{url}..."
        # HTTPX.get(url).json
      end

      def exists(name, title, date)
        data = query(name, title, date)
        data['numFound'].positive?
      end

      def lookup(name, title, date)
        raise NotImplementedError
        # data = query(name, title, date)
        # if data['numFound'].zero?
        #   $logger.debug 'No items found'
        #   return []
        # end
        # # return all found items
        # candidates = data['docs'].map do |item|
        #   creators = item['author_name'].map do |author|
        #     {
        #       'literal' => author
        #     }
        #   end
        #   isbn = (item['isbn'].select { |i| i.start_with? '978' }.join(' ') if item['isbn'].is_a? Array)
        #   edition = item['edition_count']
        #   publisher = item['publisher'].last
        #   {
        #     'author' => creators,
        #     'title' => item['title'],
        #     'type' => item['type'].reject { |t| t == 'BibliographicResource' }.first.downcase,
        #     'edition' => edition,
        #     'ISBN' => isbn,
        #     'issued' => item['publish_date'].last,
        #     'publisher' => item['publisher'].last,
        #     'location' => pub['location']
        #   }
        # end
        # candidates.select! do |c|
        #   c['title']
        #     .downcase
        #     .scan(/[[:alnum:]]+/)
        #     .reject { |w| w.length < title_word_min_length}
        #     .first(title_words_max_number)
        #     .difference(title_keywords)
        #     .length
        #     .zero? &&
        #     c['issued'].include?(date)
        # end
      end

      def get_by_isbn(isbn)
        url = @base_url + "/isbn/#{isbn}.json"
        $logger.debug "Searching openlibrary.org: #{url}..."
        HTTPX.get(url).json
      end
    end

  end
end