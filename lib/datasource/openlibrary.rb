# frozen_string_literal: true
require 'httpx'
require 'erb'

module Datasource
  class Openlibrary

    class << self
      @base_url = "https://openlibrary.org"
      def lookup(name, title, date)
        title_word_min_length = 4
        title_words_max_number = 5
        name = name.gsub(/[^\p{L}\s]/, '').split(' ').reject { |w| w.length < 3 }.join(' ')
        title_keywords = title.downcase.scan(/[[:alnum:]]+/).reject { |w| w.length < title_word_min_length }.first(title_words_max_number)
        lookup_string = "q=author:\"#{name}\" title:\"#{title_keywords}\" publish_year:#{date}"
        $logger.debug "Searching openlibrary.org for #{lookup_string}..."
        url = @base_url + "/search.json?" + ERB::Util.url_encode(lookup_string)
        data = HTTPX.get(url).json
        if (data['numFound']).zero?
          $logger.debug 'No items found'
          return []
        end
        #$logger.debug JSON.pretty_generate(data)
        # return all found items
        candidates = data['docs'].map do |item|
          creators = item['author_name'].map do |author|
            {
              'literal' => author
            }
          end
          isbn = (item['isbn'].select { |i| i.start_with? '978' }.join(' ') if item['isbn'].is_a? Array)
          edition = item['edition_count']
          publisher = item['publisher'].last
          {
            'author' => creators,
            'title' => item['title'],
            'type' => item['type'].reject { |t| t == 'BibliographicResource' }.first.downcase,
            'edition' => edition,
            'ISBN' => isbn,
            'issued' => item['publish_date'].last,
            'publisher' => item['publisher'].last,
            'location' => pub['location']
          }
        end
        candidates.select! do |c|
          c['title']
            .downcase
            .scan(/[[:alnum:]]+/)
            .reject { |w| w.length < title_word_min_length}
            .first(title_words_max_number)
            .difference(title_keywords)
            .length
            .zero? &&
            c['issued'].include?(date)
        end
      end

      def get_by_isbn(isbn)
        url = @base_url + "/isbn/#{isbn}.json"
        data = HTTPX.get(url).json
      end
    end

  end
end