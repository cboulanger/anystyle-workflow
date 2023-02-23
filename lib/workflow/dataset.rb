# frozen_string_literal: true

module Workflow
  class Dataset

    include ::Utils::NLP

    MERGE_POLICIES = [
      # add all missing references found in the vendor data
      ADD_MISSING_ALL = 'add_missing_all',
      # add missing references found in open access vendor data (excluding WoS, for example)  NOT IMPLEMENTED
      ADD_MISSING_FREE = 'add_missing_open',
      # Add unvalidated anystyle referencex
      ADD_UNVALIDATED = 'add_unvalidated',
      # simply add all vendor data, this leads to lots of duplicated
      DUMP_ALL = 'dump_all',
      # remove duplicates, using an author/year heuristic
      REMOVE_DUPLICATES = 'remove_duplicates',
      # Add affiliation data if available
      ADD_AFFILIATIONS = 'add_affiliations',
    ].freeze

    # @!attribute [Boolean] verbose If true, output verbose logging instead of progress meter
    # @!attribute [String] text_dir Optional path to directory containing the original .txt files.
    #   Needed if abstracts and topics are missing in the metadata and should be generated automatically from the text
    # @!attribute [Array] remove_list An array of words that should be disregarded for auto-generating abstracts and keywords
    # @!attribute [Boolean] use_cache
    # @!attribute [Boolean] add_metadata_from_text
    # @!attribute [Array<String>] policies
    Options = Struct.new(
      :generate_abstract,
      :text_dir,
      :stopword_files,
      :generate_keywords,
      :verbose,
      :use_cache,
      :policies,
      :authors_ignore_list,
      :affiliation_ignore_list,
      keyword_init: true
    ) do
      def initialize(*)
        super
        self.generate_abstract = true if generate_abstract.nil?
        self.generate_keywords = true if generate_keywords.nil?
        self.use_cache = true if use_cache.nil?
        self.policies ||= [ADD_MISSING_ALL, ADD_UNVALIDATED, REMOVE_DUPLICATES, ADD_AFFILIATIONS]
        self.authors_ignore_list ||= []
        self.affiliation_ignore_list ||= []
        raise "Invalid text_dir #{text_dir}" unless text_dir.nil? || Dir.exist?(text_dir)
        return unless stopword_files.is_a?(Array) &&
          (invalid = stopword_files.reject { |f| File.exist? f }).length.positive?

        raise "The following stopword files do not exist or are not accessible: \n#{invalid.join("\n")}"
      end
    end

    # Creates a dataset of Format::CSL::Item objects which can be exported to
    # target formats
    #
    # @param [Array<String>] ids Array of ids that identify the references, such as a DOI, which can be used to call #merge_and_validate
    # @param [Workflow::Dataset::Options] options
    def initialize(ids, options: {})
      @options = options || Workflow::Dataset::Options.new
      @ids = ids
      @iso4 = PyCall.import_module('iso4')
      @journal_abbreviations = {}
    end

    # @param [Integer] limit Limits the number of generated items (for test purposes)
    def generate(limit: nil)
      # use cache if it exists to speed up process,
      items_cache = (@options.use_cache && Cache.load(@ids, prefix: 'dataset-')) || {}
      items = []
      num_refs = 0
      counter = 0
      total = [@ids.length, limit || @ids.length].min

      progress_or_message 'Generating consolidated data', total: total

      # iterate over CSL-JSON files in source directory
      @ids.each do |id|

        progress_or_message "Processing #{id}\n#{'=' * 80}".colorize(:blue), increment: true

        if @options.use_cache && (item_data = items_cache[id])
          # use the cached item if exists
          item = Format::CSL::Item.new(item_data)
          progress_or_message ' - Using cached data'
        else
          # get the item merged from the different datasources
          item = merge_and_validate(id)
        end

        # ignore items without any authors (such as book report sections)
        next if item.creators.empty?

        # add generated abstract and keywords if there are no in the metadata
        if @options.generate_abstract
          progress_or_message ' - Generating abstract and keywords from fulltext'
          txt_file_path = File.join(@options.text_dir, "#{id}.txt")
          text = File.read(txt_file_path, encoding: 'utf-8')
          add_metadata_from_text(item, text)
        end

        # references
        references = item.x_references
        n = references&.length || 0
        num_refs += n
        progress_or_message " - Found #{n} references"

        # journal abbreviation
        if item.type == Format::CSL::JOURNAL_ARTICLE && item.journal_abbreviation.nil?
          add_journal_abbreviation(item)
        end

        # keywords generated from references
        if @options.generate_keywords && n.positive?
          progress_or_message ' - Adding reference-generated keywords '
          add_reference_keywords(item)
        end

        items.append(item)
        items_cache[id] = item.to_h
        counter += 1
        break if limit && counter >= limit
      end

      progress_or_message finish: true

      Cache.save('_export', items_cache, use_literal: true)

      # @type [Array<Format::CSL::Item>]
      @items = items
    end

    # Export the dataset using the given exporter class
    # @param [Export::Exporter] exporter
    # @param [Integer] limit
    def export(exporter, limit: nil)
      raise 'Argument must be an Export::Exporter subclass' unless exporter.is_a? Export::Exporter

      counter = 0
      total = [@items.length, limit || @items.length].min
      progress_or_message("Exporting #{total} items to #{exporter.name}...", total:)
      exporter.start
      @items.each do |item|
        counter += 1
        creator, year = item.creator_year_title
        progress_or_message " - Processing #{creator} (#{year}) #{counter}/#{total}", increment: true
        exporter.add_item item
        break if counter >= total
      end
      progress_or_message finish: true
    end

    protected

    # Given an identifier, merge available data. Anystyle references will be validated against the vendor references.
    # @param [String] item_id
    # @return [Format::CSL::Item]
    def merge_and_validate(item_id)
      Datasource::Anystyle.verbose = @options.verbose
      Datasource::Crossref.verbose = @options.verbose

      raise 'Item id must be a DOI' unless item_id.start_with? '10.'

      doi = item_id.sub('_', '/')
      # get anystyle item (enriched with crossref metadata)
      # @type [Item]
      item = Datasource::Anystyle.import_items([doi]).first

      raise "No data available for ID #{item_id}" if item.nil?

      policies = @options.policies

      # The validated references
      # @type [Array<Format::CSL::Item>]
      validated_references = []

      num_anystyle_added_refs = 0
      num_anystyle_validated_refs = 0
      num_anystyle_unvalidated_refs = 0

      # lookup with crossref metadata by doi
      vendors = %w[crossref openalex grobid dimensions wos]
      vendors.each do |vendor|
        # @type [Format::CSL::Item]
        vendor_item = ::Datasource.get_provider_by_name(vendor).import_items([doi]).first

        if vendor_item.nil?
          puts " - #{vendor}: No data available".colorize(:red) if @options.verbose
          next
        end

        # add reference data
        # @type [Array<Format::CSL::Item>]
        vendor_refs = vendor_item.x_references
        num_vendor_added_refs = 0

        if policies.include?(DUMP_ALL)
          # add all found references, this leads to a lot of duplicates
          validated_references += vendor_refs
          num_vendor_added_refs += vendor_refs.length
          if @options.verbose && vendor_refs.length.positive?
            puts " - #{vendor}: added #{vendor_refs.length} references" if @options.verbose
          end
        else
          # match each anystyle reference against all vendor references since we cannot be sure they are in the same order
          # this can certainly be optimized but is good enough for now
          vendor_refs.each do |vendor_ref|
            vendor_author, vendor_year = vendor_ref.creator_year_title(downcase: true)
            next if vendor_author.nil?

            matched = false
            item.x_references.each do |ref|
              author, year = ref.creator_year_title(downcase: true)
              # validation is done by author / year exact match. this will produce some false positives/negatives
              next unless author == vendor_author && year == vendor_year

              # validate
              ref.validate_by(vendor_ref)

              # add affiliations
              add_affiliations(ref, vendor_ref, vendor)

              # journal abbreviation
              if ref.type == Format::CSL::JOURNAL_ARTICLE && ref.journal_abbreviation.nil?
                add_journal_abbreviation(ref)
              end

              # add only if reference hasn't been validated already
              unless ref.custom.validated_by.keys.count > 1
                validated_references.append(ref)
                puts " - anystyle: Added #{author} #{year} (validated by #{vendor})" if @options.verbose
                num_anystyle_added_refs += 1
              end
              num_anystyle_validated_refs += 1
              matched = true
            end
            next if matched

            next unless policies.include?(ADD_MISSING_ALL) || (policies.include?(ADD_MISSING_FREE) && vendor != 'wos')

            validated_references.append(vendor_ref)
            puts " - #{vendor}: Added #{vendor_author} (#{vendor_year}) " if @options.verbose
            num_vendor_added_refs += 1
          end
        end

        if @options.verbose && num_vendor_added_refs.positive?
          puts " - #{vendor}: validated #{num_anystyle_validated_refs} anystyle references " \
                 "(of which #{num_anystyle_added_refs} were added), " \
                 "and added #{num_vendor_added_refs} missing references"
        end

        # use the highest "times-cited" value found
        item.custom.times_cited = [vendor_item.custom.times_cited || 0, item.custom.times_cited || 0].max

        # add affiliation data if missing
        add_affiliations(item, vendor_item, vendor) if policies.include?(ADD_AFFILIATIONS)

        # add abstract if missing
        item.abstract ||= vendor_item.abstract

        # add keywords that don't exist yet
        item.keyword = (item.keyword + vendor_item.keyword).compact.uniq

        # end vendors.each
      end

      if policies.include?(ADD_UNVALIDATED)
        item.x_references.each do |ref|
          next if ref.validated?

          author, year = ref.creator_year_title(downcase: true)
          next if author.nil? || author.empty?

          # ignore specific authors or false positives
          next if @options.authors_ignore_list.any? do |expr|
            expr.is_a?(Regexp) ? author.match(expr) : author == expr
          end

          puts " - anystyle: Added unvalidated #{author} #{year}" if @options.verbose
          validated_references.append(ref)
          num_anystyle_unvalidated_refs += 1
        end
        puts " - added #{num_anystyle_unvalidated_refs} unvalidated anystyle references" if @options.verbose
      end

      if policies.include?(REMOVE_DUPLICATES)
        num_before = validated_references.length
        validated_references.uniq! { |item| item.creator_year_title(downcase: true) }
        num_removed = num_before - validated_references.length
        puts " - removed #{num_removed} duplicate references" if @options.verbose && num_removed.positive?
      end

      item.x_references = validated_references
      # return result
      item
    end

    # @param [Format::CSL::Item] item
    # @param [Format::CSL::Item] vendor_item
    # @param [String] vendor
    def add_affiliations(item, vendor_item, vendor)
      item.creators.each do |creator|
        vendor_item.creators.each do |vendor_creator|
          next if creator.family != vendor_creator.family

          raw_affiliation = vendor_creator.x_raw_affiliation_string
          # ignore specific affiliations or false positives
          next if raw_affiliation && @options.affiliation_ignore_list.any? do |expr|
            if expr.is_a?(Regexp)
              raw_affiliation&.match(expr) || vendor_creator.x_affiliations&.any? { |a| a.literal.match(expr) }
            else
              raw_affiliation&.include?(expr) || vendor_creator.x_affiliations&.any? { |a| a.literal.include(expr) }
            end
          end

          creator.x_raw_affiliation_string ||= raw_affiliation
          aff = creator.x_affiliations&.first&.to_h&.compact
          vendor_aff = vendor_creator.x_affiliations&.first&.to_h&.compact
          next if vendor_aff.nil?

          next unless aff.nil? || vendor_aff.keys.length > aff.keys.length

          # assume the better affiliation data is the one with more keys
          creator.x_affiliations = [Format::CSL::Affiliation.new(vendor_aff)]
          puts " - #{vendor}: Added affiliation data" if @options.verbose
        end
      end
    end

    # @param [Format::CSL::Item] item
    def add_journal_abbreviation(item)
      journal_name = item.container_title
      abbr = @journal_abbreviations[journal_name]
      return abbr unless abbr.nil?

      item.journal_abbreviation = @journal_abbreviations[journal_name] = @iso4.abbreviate(journal_name)
    end

    # This auto-generates an abstract and keywords and also adds a language if none has been set
    # @param [Format::CSL::Item] item
    # @param [String] text
    def add_metadata_from_text(item, text)
      abstract, keywords, language = summarize(text, ratio: 5, topics: true, stopword_files: @options.stopword_files)
      item.abstract = abstract if item.abstract.nil? || item.abstract.empty?
      item.keyword = keywords if @options.generate_keywords && item.keyword.empty?
      item.language ||= language if language
    end

    # @param [Format::CSL:Item] item
    def add_reference_keywords(item)
      reference_corpus = item.x_references.map { |ref| [ref.title, ref.abstract].compact.join(' ') }.join(' ')
      _, keywords = summarize(reference_corpus, topics: true, stopword_files: @options.stopword_files)
      item.custom.generated_keywords = keywords.reject { |kw| kw.length < 4 }
    end

    private

    def progress_or_message(message = nil, increment: false, total: 0, finish: false)
      if @options.verbose
        puts message if message
      elsif @progressbar.nil?
        @progressbar = ProgressBar.create(message:, total:, **::Workflow::Config.progress_defaults)
      elsif increment
        @progressbar.increment
      elsif finish
        @progressbar.finish
        @progressbar = nil
      end
    end
  end
end
