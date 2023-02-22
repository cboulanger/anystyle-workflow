# frozen_string_literal: true

module Workflow
  class Dataset
    # Static methods of Dataset class
    class << self
      include Format::CSL
      include Nlp

      # enums
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
        ADD_AFFILIATIONS = 'add_affiliations'
      ].freeze

      # @!attribute [Boolean] verbose If true, output verbose logging instead of progress meter
      # @!attribute [String] text_dir Optional path to directory containing the original .txt files.
      #   Needed if abstracts and topics are missing in the metadata and should be generated automatically from the text
      # @!attribute [Array] remove_list An array of words that should be disregarded for auto-generating abstracts and keywords
      # @!attribute [Boolean] use_cache
      # @!attribute [Boolean] generate_abstract
      # @!attribute [Array<String>] policies
      Options = Struct.new(
        :generate_abstract,
        :text_dir,
        :remove_list,
        :generate_keywords,
        :verbose,
        :use_cache,
        :policies,
        keyword_init: true
      ) do
        def initialize(*)
          super
          self.generate_abstract = true if generate_abstract.nil?
          self.generate_keywords = true if generate_keywords.nil?
          self.use_cache = true if use_cache.nil?
          self.policies ||= [ADD_MISSING_ALL, ADD_UNVALIDATED, REMOVE_DUPLICATES, ADD_AFFILIATIONS]
        end
      end

      # Given an identifier, merge available data. Anystyle references will be validated against the vendor references.
      # @param [String] item_id
      # @return [Format::CSL::Item]
      def merge_and_validate(item_id)
        Datasource::Anystyle.verbose = @options.verbose
        Datasource::Crossref.verbose = @options.verbose

        # get anystyle item (enriched with crossref metadata)
        # @type [Item]
        item = Datasource::Anystyle.import_items_by_doi([item_id]).first

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
          # @type [Item]
          vendor_item = ::Datasource.get_provider_by_name(vendor).import_items_by_doi([item_id]).first

          # add reference data
          # @type [Array<Item>]
          vendor_refs = vendor_item.x_references
          num_vendor_added_refs = 0

          if policies.include?(DUMP_ALL)
            validated_references += vendor_refs
            num_vendor_added_refs += vendor_refs.length
            if @options.verbose && vendor_refs.length.positive?
              puts " - #{vendor}: added #{vendor_refs.length} references"
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

          next unless policies.include?(ADD_AFFILIATIONS)

          add_affiliations(item, vendor_item, vendor)
        end

        if policies.include?(ADD_UNVALIDATED)
          item.x_references.each do |ref|
            next if ref.validated?

            author, year = ref.creator_year_title(downcase: true)
            next if author.nil? || author.empty?

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
          puts " - removed #{num_removed} duplicate references" if num_removed.positive?
        end

        item.x_references = validated_references
        # return result
        item
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
    end

    # @param [Integer] limit Limits the number of generated items (for test purposes)
    def generate(limit:)
      # use cache if it exists to speed up process,
      items_cache = (@options.use_cache && Cache.load(ids, prefix: 'dataset-')) || {}
      items = []

      unless @options.verbose
        progressbar = ProgressBar.create(title: 'Generating consolidated data:',
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)
      end

      num_refs = 0
      counter = 0
      # iterate over CSL-JSON files in source directory
      @ids.each do |id|
        progressbar.increment unless @options.verbose

        puts "Processing #{id}\n#{'=' * 80}" if @options.verbose

        if @options.use_cache && (item_data = items_cache[id])
          # use the cached item if exists
          item = Format::CSL::Item.new(item_data)
          puts ' - Using cached data' if @options.verbose
        else
          # get the item merged from the different datasources
          item = merge_and_validate(id)
        end

        # ignore items without any authors (such as book report sections)
        next if item.creators.empty?

        # add generated abstract and keywords if there are no in the metadata
        if @options.generate_abstract
          if @options.text_dir.nil? || !Dir.exist?(@options.text_dir)
            raise 'Missing/invalid text_dir option value needed for abstract generation'
          end

          puts ' - Generating abstract and keywords from fulltext' if @options.verbose
          txt_file_path = File.join(@options.text_dir, "#{id}.txt")
          abstract, keyword = summarize_file(txt_file_path, ratio: 5, topics: true, remove_list:)
          item.abstract ||= abstract
          item.keyword ||= keyword if @options.generate_keywords
        end

        # references
        references = item.x_references
        n = references&.length || 0
        num_refs += n
        puts " - Found #{n} references" if @options.verbose

        # keywords generated from references
        if @options.generate_keywords && n.positive?
          reference_corpus = references.map { |ref| [ref.title, ref.abstract].compact.join(' ') }.join(' ')
          _, kw = reference_corpus.summarize(topics: true)
          item.custom.generated_keywords = kw.force_encoding('utf-8').split(',')
          puts ' - Adding reference-generated keywords ' if @options.verbose
        end

        items.append(item)
        items_cache[id] = item.to_h
        counter += 1
        break if limit && counter >= limit
      end

      progressbar.finish unless @options.verbose

      Cache.save('_export', items_cache, use_literal: true)


      # @type [Array<Format::CSL::Item>]
      @items = items
    end

    # Export the dataset using the given exporter class
    # @param [Export::Exporter] exporter
    def export(exporter, limit:)

      counter = 0
      total = [@items.length, limit || @items.length].min
      if verbose
        puts "Exporting #{total} items to #{exporter.name}..."
      else
        progressbar = ProgressBar.create(title: 'Export progress:',
                                         total:,
                                         **::Workflow::Config.progress_defaults)
      end
      exporter.start

      @items.each do |item|
        counter += 1
        if @options.verbose
          creator, year = item.creator_year_title
          puts " - Processing #{creator} (#{year}) #{counter}/#{total}"
        else
          progressbar.increment
        end
        exporter.add_item item
        break if counter >= limit
      end
      progressbar.finish unless @options.verbose
    end

    private

    def add_affiliations(item, vendor_item, vendor)
      item.creators.each do |creator|
        vendor_item.creators.each do |vendor_creator|
          next if creator.family != vendor_creator.family

          creator.x_raw_affiliation_string ||= vendor_creator.x_raw_affiliation_string
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
  end
end
