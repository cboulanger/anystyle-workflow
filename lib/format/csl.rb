# frozen_string_literal: true

module Format
  # This module hold information and methods that work with the CSL standard and
  # non-standard vendor extension or those defined by this app
  # Extensions to the standard schema are prefixed with "x_"
  # @see https://citeproc-js.readthedocs.io/en/latest/csl-json/markup.html
  # @see https://github.com/citation-style-language/schema/blob/master/schemas/input/csl-data.json
  module CSL
    CSL_TYPES = [
      ARTICLE_JOURNAL = 'article-journal'
    ].freeze

    class Object
      # Initialize an object with values
      def initialize(data, accessor_map: {})
        @_accessor_map = accessor_map
        @_key_map = @_accessor_map.invert
        data.each do |k, v|
          method_name = "#{accessor_name(k)}=".to_sym
          if respond_to? method_name
            public_send(method_name, v)
          else
            warn "#{self.class.name}: Ignoring unsupported attribute '#{method_name}' (from key '#{k}')".colorize(:red)
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
        hash.compact
      end

      alias to_hash to_h

      def to_json(opts = nil)
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
        super(data, accessor_map: ACCESSOR_MAP)
      end

      def date_parts=(date_parts)
        unless date_parts.is_a?(Array) && date_parts.length.positive?
          raise "Invalid date-parts format: #{date_parts}"
        end

        date_parts.map! do |part|
          case part
          when String
            part.split('-').map {|p| p.to_i}
          when Array
            part
          else
            raise "Invalid date-part component #{part}"
          end
        end

        @date_parts = date_parts
      end

      def to_s
        @raw || @date_parts.first.join('-')
      end

      # Returns the date's year as an integer, if available, otherwise nil
      # @return [Integer]
      def to_year
        (@date_parts&.first&.first || @raw&.scan(/\d{4}/)&.first)&.to_i
      end
    end

    # A name/creator field such as author, editor, translator...
    class Creator < Object
      # csl standard
      attr_accessor :family, :given, :literal, :suffix, :dropping_particle, :non_dropping_particle, :sequence, :particle

      # extensions
      attr_accessor :x_orcid, :x_author_id, :x_author_api_url, :x_raw_affiliation_string

      # @!attribute x_affiliations
      # @return [Array<Affiliation>]
      attr_reader :x_affiliations

      # @param [Array<Hash|Affiliation>] affiliations
      def x_affiliations=(affiliations)
        raise 'Value must be an array' unless affiliations.is_a?(Array)

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

      def family_and_given
        if family
          [family, given]
        elsif (l = literal)
          case l
          when /^\p{Lu}+ \p{Lu}{1,3}$/ # this handles WoS entries, shouldn't be here
            p = l.split(' ')
            [p[0].capitalize, p[1]]
          when /^\p{Lu}\p{Ll}+ \p{Lu}{1,3}$/ # this handles WoS entries, shouldn't be here
            p = l.split(' ')
            [p[0].capitalize, p[1]]
          when /^\p{Lu}+$/ # this handles WoS entries, shouldn't be here
            [l.capitalize, '']
          else
            # normal case
            [parse_family(l), parse_given(l)]
          end
        end
      end

      def initial
        given.scan(/\p{L}+/)&.map { |n| n[0] }&.join('')
      end

      private

      def affiliation_factory(data)
        Affiliation.new(data)
      end

      def parse_family(name)
        n = Namae.parse(name).first
        return if n.nil?

        [n.particle, n.family].reject(&:nil?).join(' ')
      end

      def parse_given(name)
        Namae.parse(name).first&.given
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
    end

    # Custom
    class Custom < Object
      def initialize(data)
        @validated_by = {}
        super
      end

      # @!attribute validated_by
      # @return [Hash<{String => Item}>
      attr_accessor :times_cited, :validated_by, :metadata_source, :metadata_id, :metadata_api_url,
                    :reference_data_source, :cited_by_api_url, :container_id, :generated_keywords
    end

    # A CSL-JSON item.
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
      attr_accessor :type, :title

      # to do : check type

      # creator fields
      # @!attribute author
      # @return [Array<Creator>]
      # @!attribute editor
      # @return [Array<Creator>]
      attr_reader :author, :editor

      # @param [Hash] data
      # @param [Hash] accessor_map
      def initialize(data, accessor_map: {})
        @isbn = []
        @issn = []
        super(data, accessor_map: ACCESSOR_MAP.merge(accessor_map))
      end

      # An unique string identifying the item. Returns DOI, ISBN or citation_key if exists, otherwise a 50 character
      # creator_year_title string value
      # @!attribute id
      # @return [String]
      def id
        doi || isbn&.first || citation_key || creator_year_title.join('_').gsub(' ', '_')[..50]
      end

      def author=(authors)
        raise "Author data must be an array, got #{authors}" unless authors.is_a?(Array)

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
        raise 'Value must be an array' unless editors.is_a?(Array)

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
      # @!attribute issued
      # @return [Date]
      attr_reader :issued

      def issued=(date_obj)
        # parse different formats
        @issued = case date_obj
                  when Date
                    date
                  when Hash
                    Date.new(date_obj)
                  when String
                    if (m = date_obj.match(/^(\d{4})-(\d\d)-(\d\d)$/))
                      date_parts = [m[1..3].map(&:to_i)]
                      Date.new({ "date-parts": date_parts })
                    elsif (m = date_obj.match(/^(\d{4})$/))
                      date_parts = [[m[1].to_i]]
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

      # @return [Custom]
      def custom
        @custom = Custom.new({}) if @custom.nil?
        @custom
      end

      # references
      # @param [Array<Hash|Item>] references
      def x_references=(references)
        unless references.is_a?(Array)
          raise 'References must be an array'
        end

        @x_references = references.first.is_a?(Item) ? references : references.map{ | data | Item.new(data) }
      end

      # @return [Array<Item>]
      def x_references
        @x_references || []
      end

      # other metadata

      # @!attribute keyword
      # @return [Array]
      def keyword
        @keyword || []
      end

      def keyword=(keywords)
        raise 'Argument must be Array' unless keywords.is_a? Array

        @keyword = keywords
      end

      def first_page=(page)
        self.page_first = page
      end

      attr_accessor :authority, :citation_number, :doi, :isbn, :issn, :url, :abstract, :citation_key,
                    :edition, :issue, :journal_abbreviation, :language, :locator, :note,
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
                    :call_number, :categories, :chapter_number, :citation_label, :collection_number,
                    :collection_title, :container_title, :container_title_short, :dimensions, :division,
                    :event, :event_place, :event_title, :first_reference_note_number, :genre, :jurisdiction,
                    :medium, :number, :number_of_pages, :number_of_volumes, :original_publisher,
                    :original_publisher_place, :original_title, :page_first, :part, :part_title, :printing,
                    :reviewed_genre, :reviewed_title, :scale, :section, :short_title, :source, :status, :supplement,
                    :title_short, :version, :volume_title, :volume_title_short, :year_suffix

      # #####################################################
      # Utility methods
      # ######################################################

      # Mark current item as validated by the given item
      # @param [Item] item
      def validate_by(item)
        raise "Argument must be a (subclass of) #{Item.class.name}" unless item.is_a? Item

        source = item.custom.metadata_source
        source_id = item.doi || item.custom.metadata_id

        raise 'Cannot determine item source' if source.nil?

        custom.validated_by.merge!({ source => source_id })
      end

      def validated?
        !custom.validated_by.empty?
      end

      def year
        issued&.to_year
      end

      # Return an array of Creator items which are either the authors or in case of edited collections,
      # the editors
      # @return [Array<Creator>]
      def creators
        author || editor || []
      end

      # return an array of arrays [[family, given], ...] with the family
      # names and the given names of the creators (author OR editor) entry.
      # @return [Array<[Array, Array]>]
      def creator_names
        creators.map(&:family_and_given)
      end

      # return an array with author, year and title
      # @param [Boolean] downcase
      # @return [Array<String, Integer, String>]
      def creator_year_title(downcase: false)
        first_creator = creator_names.first&.first
        if downcase
          [first_creator&.downcase, year, title&.downcase]
        else
          [first_creator, year, title]
        end
      end

      private

      def creator_factory(data)
        CSL::Creator.new(data)
      end
    end
  end
end
