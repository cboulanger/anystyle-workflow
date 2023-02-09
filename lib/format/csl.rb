module Format
  module CSL
    def title_keywords(title, min_length = 4, max_number = 5)
      title.downcase
           .scan(/[[:alnum:]]+/)
           .reject { |w| w.length < min_length }
           .first(max_number)
    end

    # Given an array of csl-hashes, remove those items which lack author or title information
    def filter_items(items)
      items.reject do |item|
        author, year, title = get_csl_author_year_title(item)
        author.nil? || author.empty? || year.nil? || year.empty? || title.nil? || title.empty?
      end
    end

    # Given a csl-hash, return an array with author, year and title
    def get_csl_author_year_title(item)
      author = get_csl_creator_names(item)&.first&.first
      year = get_csl_year(item)
      title = item['title']
      [author, year, title]
    end

    # Given a csl hash, return the publication date
    # This contains workarounds for malformed entries
    def get_csl_date(item)
      date = item['issued']
      date = date.first if date.is_a? Array
      case date
      when Hash
        if date['raw']
          date['raw']
        elsif date['date-parts']
          dp = date['date-parts']
          if dp.is_a?(Array) && dp.length.positive?
            dp = dp.first if dp.first.is_a?(Array) # work around malformed data
            dp.join('-')
          else
            "Invalid date"
          end
        else
          raise 'Invalid date'
        end
      else
        date
      end
    end

    def get_csl_year(csl_item)
      get_csl_date(csl_item)&.scan(/\d{4}/)&.first
    end

    # Given a csl hash, return the author array, or in case of edited collection, the editor array
    # If none exists, returns an empty array
    # @return [Array]
    # @param [Hash] csl_item
    def get_csl_creator_list(csl_item)
      csl_item['author'] || csl_item['editor']
    end

    def get_csl_family_and_given(creator_item)
      c = creator_item
      case c
      when Hash
        literal = c['literal']
        if !literal.nil?
          case literal
          when /^\p{Lu}+ \p{Lu}{1,3}$/ # this handles WoS entries, shouldn't be here
            p = literal.split(' ')
            [p[0].capitalize, p[1]]
          when /^\p{Lu}\p{Ll}+ \p{Lu}{1,3}$/ # this handles WoS entries, shouldn't be here
            p = literal.split(' ')
            [p[0].capitalize, p[1]]
          when /^\p{Lu}+$/ # this handles WoS entries, shouldn't be here
            [literal.capitalize, ""]
          else
            # normal case
            [author_name_family(literal), author_name_given(literal)]
          end
        else
          [c['family'], c['given']]
        end
      when String
        # malformed, string-only creator item
        [author_name_family(c), author_name_given(c)]
      else
        # no information can be parsed
        ['INVALID', '']
      end
    end

    # Given a CSL item, return an array of arrays [[family, given], ...] with the family
    # names and the given names of the creators (author OR editor) entry.
    def get_csl_creator_names(csl_item)
      creator_list = get_csl_creator_list(csl_item)
      if creator_list.is_a?(Array) && creator_list.length.positive?
        creator_list.map { |creator_item| get_csl_family_and_given(creator_item) }
      else
        [['', '']]
      end
    end

    # given a author name as a string, return what is probably the last name
    def author_name_family(name)
      n = Namae.parse(name).first
      return if n.nil?

      [n.particle, n.family].reject(&:nil?).join(' ')
    end

    def author_name_given(name)
      Namae.parse(name).first&.given
    end

    def initialize_given_name(given_name)
      given_name.scan(/\p{L}+/)&.map { |n| n[0] }&.join('')
    end
  end
end