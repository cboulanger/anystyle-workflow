# frozen_string_literal: true

module Format
  # This module hold information and methods that work with the CSL standard and
  # non-standard vendor extension or those defined by this app
  module CSL

    CSL_FIELDS = [
      FIELD_CUSTOM = 'custom'
    ].freeze

    CUSTOM_FIELDS = [
      CUSTOM_VALIDATED_BY = 'validated-by',
      CUSTOM_GENERATED_KEYWORDS = 'x-generated-keywords'
    ].freeze

    class Object

      # Initialize an object with values
      def initialize(data, accesor_map = {})
        @_accessor_map = accesor_map || {}
        @_key_map = {}
        @_accessor_map.each { |k, v| @_key_map[v] = k }
        data.each do |k, v|
          method_name = "#{accessor_name(k)}=".to_sym
          if respond_to? method_name
            public_send(method_name, v)
          else
            STDERR.puts "#{self.class.name}: Ignoring unsupported attribute '#{k}'"
          end
        end
      end

      def to_h
        hash = {}
        instance_variables.each do |var|
          attr_name = var.to_s.delete('@')
          next if attr_name.start_with? '_'

          key = key_name(attr_name)
          value = instance_variable_get(var)

          hash[key] = case value
                      when Array
                        value = value.map { |i| i.is_a?(CSL::Object) ? i.to_hash : i }
                      when CSL::Object
                        value.to_h
                      else
                        value
                      end
        end
        hash
      end

      alias_method :to_hash, :to_h

      def to_json opts = nil
        JSON.pretty_generate to_hash, opts
      end

      def self.from_hash(properties)
        new(properties)
      end

      private

      def accessor_name(key)
        @_key_map[key.to_s] || key.to_s.downcase.gsub('-', '_').to_sym
      end

      def key_name(attribute)
        @_accessor_map[attribute.to_sym] || attribute.to_s.gsub('_', '-')
      end
    end

    # A CSL-JSON date field such as issued, accessed ...
    class Date < Object

      ACCESSOR_MAP = {
        "date_parts": 'date-parts'
      }.freeze

      attr_accessor :raw, :season, :circa, :literal
      attr_reader :date_parts

      def initialize(data)
        super data, ACCESSOR_MAP
      end

      def date_parts=(date_parts)
        unless date_parts.is_a?(Array) && date_parts.length.positive? && date_parts.select { |i| !i.is_a? Array }.empty?
          raise 'Invalid date-parts format'
        end
        @date_parts = date_parts
      end

      def to_s
        @raw || @date_parts.first.join('-')
      end

    end

    # A name/creator field such as author, editor, translator...
    class Creator < Object

      ACCESSOR_MAP = {
        'dropping_particle': 'dropping-particle',
        'non_dropping_particle': 'non-dropping-particle'
      }.freeze

      # csl standard
      attr_accessor :family, :given, :literal, :suffix, :dropping_particle, :non_dropping_particle, :sequence, :particle

      # extensions
      attr_accessor :x_orcid, :x_author_id, :x_author_api_url, :x_raw_affiliation_string
      attr_reader :x_affiliations

      def initialize(properties)
        super properties, ACCESSOR_MAP
      end

      def x_affiliations=(affiliations)
        unless affiliations.is_a?(Array)
          raise 'Value must be an array'
        end
        @x_affiliations = affiliations.map do |affiliation|
          case affiliation
          when Affiliation
            affiliation
          when Hash
            affiliation_factory(affiliation)
          else
            raise 'Invalid affiliation item'
          end
        end
      end

      private

      def affiliation_factory(data)
        Affiliation.new(data)
      end

    end

    # Non-standard! Field names are a mix of OpenAlex and GROBID-TEI
    # 'literal': the non-segmented name
    # "department": "Department of Applied Economics",
    # "center": "ESRC Centre for Business Research",
    # "institution": "University of Cambridge",
    # "address": "Sidgwick Avenue",
    # "post_code": "CB3 9DE",
    # "settlement": "Cambridge",
    # "country": "England",
    # "country_code": "GB"
    #
    class Affiliation < Object

      attr_accessor :literal, :center, :institution, :department, :address, :country,
                    :country_code, :ror, :x_affiliation_api_url, :x_affiliation_id

      def initialize(properties)
        super properties
      end
    end

    # Custom
    class Custom < Object

      # allowed entrys in the 'custom' object
      attr_accessor :times_cited, :validated_by, :metadata_source, :metadata_id, :metadata_api_url,
                    :cited_by_api_url, :container_id

    end

    # A CSL-JSON item. Extensions to the standard schema are prefixed with "x_"
    # @see https://citeproc-js.readthedocs.io/en/latest/csl-json/markup.html
    # @see https://github.com/citation-style-language/schema/blob/master/schemas/input/csl-data.json
    class Item < Object

      ACCESSOR_MAP = {
        'doi': 'DOI',
        'isbn': 'ISBN',
        'issn': 'ISSN',
        'url': 'URL',
        'citation_key': 'citation-key',
        'journal_abbreviation': 'journalAbbreviation',
        'publisher_place': 'publisher-place'
      }.freeze

      # actively supported fields

      # mandatory
      attr_accessor :type, :id, :title

      # to do : check type

      # creator fields
      attr_reader :author, :editor

      def initialize(data)
        super(data, ACCESSOR_MAP)
      end

      def author=(authors)
        unless authors.is_a?(Array)
          raise 'author data must be an array'
        end
        @author = authors.map do |creator|
          case creator
          when CSL::Creator
            creator
          when Hash
            creator_factory(creator)
          end
        end
      end

      def editor=(editors)
        unless editors.is_a?(Array)
          raise 'Value must be an array'
        end
        @editor = editors.map do |creator|
          case creator
          when CSL::Creator
            creator
          when Hash
            creator_factory(creator)
          end
        end
      end

      # date fields
      attr_reader :issued

      def issued=(date_obj)
        @issued = case date_obj
                  when Date
                    date
                  when Hash
                    Date.new(date_obj)
                  when String
                    if (m = date_obj.match(/^(\d{4})-(\d\d)-(\d\d)$/))
                      date_parts = [m[1..3].map { |i| Integer(i) }]
                      Date.new({ "date-parts": date_parts })
                    elsif (m = date_obj.match(/^(\d{4})$/))
                      date_parts = [[Integer(m[1])]]
                      Date.new({ "date-parts": date_parts })
                    else
                      Date.new({ "raw": date_obj })
                    end

                  when Integer
                    # assume it's a year
                    Date.new({
                               "date-parts": [[date_obj]]
                             })
                  else
                    raise 'Invalid date'
                  end
      end

      # custom

      def custom=(hash)
        raise 'custom must be a hash' unless hash.is_a?(Hash)

        @custom = Custom.new(hash)
      end

      def custom
        if @custom.nil?
          @custom = Custom.new({})
        end
        @custom
      end

      # references
      def x_references=(references)
        unless references.is_a?(Array) && references.select { |r| !r.is_a?(Item) }.empty?
          raise 'References must be an array of Item instances'
        end
        @x_references = references
      end

      def x_references
        @x_references || []
      end

      # other metadata
      attr_accessor :authority, :citation_number, :doi, :isbn, :issn, :url, :abstract, :categories, :citation_key,
                    :edition, :issue, :journal_abbreviation, :keyword, :language, :locator, :note,
                    :page, :publisher, :publisher_place, :references, :volume

      # currently not actively supported, although data can be stored

      # roles
      attr_accessor :chair, :collection_editor, :compiler, :composer, :container_author, :contributor, :curator, :director,
                    :editorial_director, :executive_producer, :guest, :host, :illustrator, :interviewer, :narrator,
                    :organizer, :original_author, :performer, :producer, :recipient, :reviewed_author, :script_writer,
                    :series_creator, :translator

      # date fields
      attr_accessor :accessed, :available_date, :event_date, :original_date, :submitted

      # other metadata
      attr_accessor :pmcid, :pmid, :annote, :archive, :archive_collection, :archive_location, :archive_place,
                    :call_number, :chapter_number, :citation_label, :collection_number,
                    :collection_title, :container_title, :container_title_short, :dimensions, :division,
                    :event, :event_place, :event_title, :first_reference_note_number, :genre, :jurisdiction,
                    :medium, :number, :number_of_pages, :number_of_volumes, :original_publisher,
                    :original_publisher_place, :original_title, :page_first, :part, :part_title, :printing,
                    :reviewed_genre, :reviewed_title, :scale, :section, :short_title, :source, :status, :supplement,
                    :title_short, :version, :volume_title, :volume_title_short, :year_suffix

      private

      def creator_factory(data)
        CSL::Creator.new(data)
      end
    end

    ##############
    # Utils
    ##############

    # @return [Array]
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
    # @param [Hash] item
    # @param [Boolean] downcase
    def get_csl_author_year_title(item, downcase: false)
      author = get_csl_creator_names(item)&.first&.first
      year = get_csl_year(item)
      title = item['title']
      if downcase
        [author&.downcase, year, title&.downcase]
      else
        [author, year, title]
      end
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
        elsif (dp = date['date-parts'])
          if dp.is_a?(Array) && dp.length.positive?
            if dp.first.is_a?(Array)
              # work around malformed data
              dp = dp.first
            end
            dp.join('-')
          else
            'Invalid date'
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
      csl_item['author'] || csl_item['editor'] || []
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
            [literal.capitalize, '']
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
