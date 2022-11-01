# frozen_string_literal: true

require 'httpx'
require 'erb'

module Datasource
  class Lobid
    @base_url = 'https://lobid.org/resources/search?q='

    def self.lookup(name, title, date)
      title_word_min_length = 4
      title_words_max_number = 5
      name = name.gsub(/[^\p{L}\s]/, '').split(' ').reject { |w| w.length < 3 }.join(' ')
      title_keywords = title.downcase.scan(/[[:alnum:]]+/).reject { |w| w.length < title_word_min_length }.first(title_words_max_number)
      lookup_string = [name, title_keywords.join(' '), date].join(' ')
      $logger.debug "Searching lobid.org for #{lookup_string}..."
      url = @base_url + ERB::Util.url_encode(lookup_string)
      response = HTTPX.get(url)
      data = response.json
      if (data['totalItems']).zero?
        $logger.debug 'No items found'
        return []
      end
      # $logger.debug JSON.pretty_generate(data)
      # return all found items
      candidates = data['member'].reject { |i| i['contribution'].nil? }.map do |item|
        creators = item['contribution'].map do |creator|
          {
            'literal' => creator['agent']['label'],
            # 'dateOfBirth' => creator['agent']['dateOfBirth'],
            # 'gnd_id' => creator['agent']['gndIdentifier'],
            'role' => creator['role']['id'] == 'http://id.loc.gov/vocabulary/relators/edt' ? 'editor' : 'author'
          }
        end
        pub = item['publication']&.first || {}
        isbn = (item['isbn'].select { |i| i.start_with? '978' }.join(' ') if item['isbn'].is_a? Array)
        edition = item['edition'].join(' ') if item['edition'].is_a? Array
        publisher =  if item['publishedBy'].is_a? Array
                       pub['publishedBy'].map { |i| i.sub(/Imprint:/,'') }.join(' ')
                     end
        {
          'author' => creators.select { |creator| creator['role'] == 'author' },
          'editor' => creators.select { |creator| creator['role'] == 'editor' },
          'title' => item['title'],
          'type' => item['type'].reject { |t| t == 'BibliographicResource' }.first.downcase,
          'edition' => edition,
          'ISBN' => isbn,
          'issued' => pub['startDate'],
          'publisher' => publisher,
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
  end
end
