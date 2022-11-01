# frozen_string_literal: true

module Matcher
  # Matcher that works on csl-json items
  class CslMatcher
    def self.lookup(item)
      unless (item.is_a? Hash) && item['title'] && (item['author'] || item['editor']) && item['issued'] && item['type']
        $logger.debug(item)
        raise 'Lookup requires a hash in csl-json format, having a title, author[], issued, and type property'
      end
      name = (item['author'] || item['editor'])[0]['family']
      title = item['title']
      date = item['issued']
      candidates = case item['type']
                   when 'book'
                     Matcher::Book.lookup(name, title, date)
                   when 'journal-article'
                     Matcher::Article.lookup(name, title, date)
                   else
                     []
                   end
      candidates.map! do |candidate|
        candidate.each do |key, value|
          candidate.delete(key) if value.nil? || ((value.is_a? Array) && value.length.zero?)
        end
      end
      candidates.sort_by!(&:size).last
    end
  end
end
