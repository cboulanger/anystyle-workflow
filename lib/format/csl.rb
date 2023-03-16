# frozen_string_literal: true

module Format
  # This module hold information and methods that work with the CSL standard and
  # non-standard vendor extension or those defined by this app
  # Extensions to the standard schema are prefixed with "x_"
  # @see https://citeproc-js.readthedocs.io/en/latest/csl-json/markup.html
  # @see https://github.com/citation-style-language/schema/blob/master/schemas/input/csl-data.json
  # To do: this is not a "format", this is a data model and will be moved to the "Model" module.
  # The format would be the serialized CSL-JSON version which is produced by the exporter.
  module CSL
    CSL_TYPES = [
      'article',
      ARTICLE_JOURNAL = 'article-journal',
      'article-magazine',
      'article-newspaper',
      'bill',
      BOOK = 'book',
      'broadcast',
      CHAPTER = 'chapter',
      'classic',
      COLLECTION = 'collection',
      'dataset',
      'document',
      'entry',
      'entry-dictionary',
      'entry-encyclopedia',
      'event',
      'figure',
      'graphic',
      'hearing',
      'interview',
      LEGAL_CASE = 'legal_case',
      LEGISLATION = 'legislation',
      'manuscript',
      'map',
      'motion_picture',
      'musical_score',
      'pamphlet',
      PAPER_CONFERENCE = 'paper-conference',
      'patent',
      'performance',
      'periodical',
      'personal_communication',
      'post',
      'post-weblog',
      'regulation',
      REPORT = 'report',
      'review',
      'review-book',
      'software',
      'song',
      'speech',
      'standard',
      THESIS = 'thesis',
      'treaty',
      'webpage'
    ].freeze

    class Model < ::Model::Model
      # Initialize an object with values
      #
      # @param [Hash] data
      # @param [Hash, nil] accessor_map
      # rubocop:disable Lint/MissingSuper
      def initialize(data, accessor_map: nil)
        @_accessor_map = accessor_map || {}
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

      protected

      def accessor_name(key)
        @_key_map[key.to_s] || key.to_s.downcase.gsub('-', '_').to_sym
      end

      def key_name(attribute)
        @_accessor_map[attribute.to_sym] || attribute.to_s.gsub('_', '-')
      end
    end

    # A CSL-JSON date field such as issued, accessed ...
    class Date < Model
      ACCESSOR_MAP = {
        "date_parts": 'date-parts'
      }.freeze

      attr_accessor :raw, :season, :circa, :literal
      attr_reader :date_parts

      def initialize(data)
        super(data, accessor_map: ACCESSOR_MAP)
      end

      def date_parts=(date_parts)
        raise "Invalid date-parts format: #{date_parts}" unless date_parts.is_a?(Array) && date_parts.length.positive?

        date_parts.map! do |part|
          case part
          when String
            part.split('-').map(&:to_i)
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
      # @return [Integer, nil]
      def to_year
        @date_parts&.first&.first || @raw&.scan(/\d{4}/)&.first
      end
    end

    # A name/creator field such as author, editor, translator...
    class Creator < Model
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

      # Returns family and given names and tries to parse them from the literal data if they don't exist
      # TO DO:
      # @return [Array<String>]
      def family_and_given
        if family || given
          # TO DO "only given name exists" needs to be fixed in the import step
          if family.nil? && given
            [given, '']
          else
            family
            [family, given || '']
          end
        elsif (l = literal)
          case l
          when /^\p{Lu}+ \p{Lu}{1,3}$/ # this handles WoS entries, shouldn't be here
            p = l.split(' ')
            [p[0].capitalize, p[1] || '']
          when /^\p{Lu}\p{Ll}+ \p{Lu}{1,3}$/ # this handles WoS entries, shouldn't be here
            p = l.split(' ')
            [p[0].capitalize, p[1] || '']
          when /^\p{Lu}+$/ # this handles WoS entries, shouldn't be here
            [l.capitalize, '']
          else
            # normal case
            [parse_family(l), parse_given(l)]
          end
        else
          ['NO_AUTHOR', '']
        end
      end

      def to_s
        family_and_given.join(', ')
      end

      def initial
        given.to_s.scan(/\p{L}+/)&.map { |n| n[0] }&.join('')
      end

      private

      def affiliation_factory(data)
        Affiliation.new(data)
      end

      def parse_family(name)
        n = Namae.parse(name).first
        return '' if n.nil?

        [n.particle, n.family].reject(&:nil?).join(' ')
      end

      def parse_given(name)
        Namae.parse(name).first&.given || ''
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
    class Affiliation < Model
      attr_accessor :center, :institution, :department, :address, :country,
                    :country_code, :ror, :x_affiliation_api_url, :x_affiliation_id, :x_affiliation_source

      attr_reader :literal

      def literal=(literal)
        @literal = case literal
                   when Array
                     literal.join(', ')
                   when Hash
                     literal.values.join(', ')
                   else
                     literal
                   end
      end

      def to_s
        @literal || [@center, @department, @institution].compact.join(", ")
      end

    end

    # Custom
    class Custom < Model
      def initialize(data)
        @validated_by = {}
        super
      end

      # @!attribute validated_by
      # @return [Hash<{String => Item}>
      attr_accessor :times_cited, :validated_by, :metadata_source, :metadata_id, :metadata_api_url,
                    :reference_data_source, :cited_by_api_url, :container_id, :generated_keywords

      # Contains a precalculated iso4-abbreviated title that can be used to compare records
      # @!attribute
      # @return [String]
      attr_accessor :iso4_title

      # Contains a precalculated iso4-abbreviated container-title that can be used to compare records
      # @!attribute
      # @return [String]
      attr_accessor :iso4_container_title
    end

    # A CSL-JSON item.
    class Item < Model
      ACCESSOR_MAP = {
        'doi': 'DOI',
        'isbn': 'ISBN',
        'issn': 'ISSN',
        'url': 'URL',
        'citation_key': 'citation-key',
        'journal_abbreviation': 'journalAbbreviation',
        'publisher_place': 'publisher-place',
        'short_title': 'shortTitle'
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
        doi || isbn&.first || citation_key ||
          creator_year_title(downcase: true).compact.join('_').gsub(%r{[^_\p{L}\p{N}]}, '')[..30]
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

      def custom=(custom_or_hash)
        @custom = case custom_or_hash
                  when Hash
                    Custom.new(custom_or_hash)
                  when Custom
                    custom_or_hash
                  else
                    raise 'custom must be a Custom object or a hash'
                  end
      end

      # @return [Custom]
      def custom
        @custom = Custom.new({}) if @custom.nil?
        @custom
      end

      # references
      # @param [Array<Hash|Item>] references
      def x_references=(references)
        raise 'References must be an array' unless references.is_a?(Array)

        @x_references = references.first.is_a?(Item) ? references : references.map { |data| Item.new(data) }
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

      def page_first
        @page_first || page.to_s.scan(/\d+/).first
      end

      def url
        @url || (@doi && "https://doi.org/#{@doi}") || @custom.metadata_api_url || ''
      end

      attr_accessor :authority, :citation_number, :doi, :isbn, :issn, :abstract, :citation_key,
                    :edition, :issue, :journal_abbreviation, :language, :locator, :note,
                    :page, :publisher, :publisher_place, :references, :volume

      attr_writer :page_first, :url

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
                    :original_publisher_place, :original_title, :part, :part_title, :printing,
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
      # @param [Boolean] normalize_nil return empty string or 0 instead of nil
      def creator_year_title(downcase: false, normalize_nil: false)
        c = creator_names.first&.first
        y = year
        t = title
        if normalize_nil
          c = c.to_s
          y = y.to_i
          t = t.to_s
        end
        if downcase
          c = c&.downcase
          t = t&.downcase
        end
        [c, y, t]
      end

      # @param [Item] item
      # @return [String]
      def self.guess_type(item)
        if item.container_title && item.editor.to_a.empty?
          # how to differentiate from REPORT?
          ARTICLE_JOURNAL
        elsif !item.author.to_a.empty? && !item.editor.to_a.empty? && item.container_title
          CHAPTER
        elsif !item.editor.to_a.empty?
          COLLECTION
        else
          BOOK
        end
      end

      private

      def creator_factory(data)
        CSL::Creator.new(data)
      end
    end
  end
end
