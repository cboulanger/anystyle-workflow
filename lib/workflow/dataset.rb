# frozen_string_literal: true

require 'damerau-levenshtein'

module Workflow
  class Dataset
    include ::Utils::NLP

    class NoDataError < StandardError; end

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
    # @!attribute [Boolean] add_metadata_from_text
    # @!attribute [Array<String>] policies Policies for merging, @see [Workflow::Dataset::MERGE_POLICIES]
    # @!attribute [Boolean] reference_lookup Try to lookup references if they do not have a DOI
    # @!attribute [Integer] ref_year_start The first year for which to include references, defaults to 1700
    # # @!attribute [Integer] ref_year_end The last year for which to include references, defaults to current year plus 2
    Options = Struct.new(
      :generate_abstract,
      :text_dir,
      :stopword_files,
      :generate_keywords,
      :verbose,
      :reference_lookup,
      :use_cache,
      :cache_file_prefix,
      :policies,
      :authors_ignore_list,
      :affiliation_ignore_list,
      :abbr_disamb_langs,
      :abbreviate_titles,
      :ref_year_start,
      :ref_year_end,
      keyword_init: true
    ) do
      def initialize(*)
        super
        self.generate_abstract = true if generate_abstract.nil?
        self.generate_keywords = true if generate_keywords.nil?
        self.reference_lookup = true if reference_lookup.nil?
        self.use_cache = true if use_cache.nil?
        self.abbreviate_titles = false if abbreviate_titles.nil?
        self.policies ||= [ADD_MISSING_ALL, ADD_UNVALIDATED, REMOVE_DUPLICATES, ADD_AFFILIATIONS]
        self.authors_ignore_list ||= []
        self.affiliation_ignore_list ||= []
        self.abbr_disamb_langs ||= %w[eng ger]
        self.ref_year_start = 1700 if ref_year_start.to_i.zero?
        self.ref_year_end = Date.today.year + 2 if ref_year_end.to_i.zero?
        raise "Invalid text_dir #{text_dir}" unless text_dir.nil? || Dir.exist?(text_dir)
        return unless stopword_files.is_a?(Array) &&
          (invalid = stopword_files.reject { |f| File.exist? f }).length.positive?

        raise "The following stopword files do not exist or are not accessible: \n#{invalid.join("\n")}"
      end
    end

    # Preprocessing and postprocessing instructions
    Instruction = Struct.new(:type, :command, :message, keyword_init: true) do
      def initialize(*)
        super
        raise 'Instruction requires a type' if type.to_s.empty?
        raise 'Instruction requires a command' if command.to_s.empty?
      end
    end

    # Creates a dataset of Format::CSL::Item objects which can be exported to
    # target formats
    #
    # @param [Array<Format::CSL::Items>] items
    # @param [Workflow::Dataset::Options] options
    # @param [String] name Optional dataset name
    def initialize(items = [], options: nil, name: nil)
      raise 'Argument must be array of Format::CSL::Items' \
          unless items.is_a?(Array) && items.reject { |i| i.is_a? Format::CSL::Item }.empty?

      options ||= Workflow::Dataset::Options.new
      raise 'Options must be Workflow::Dataset::Options object' \
          unless options.is_a? Workflow::Dataset::Options

      @options = options
      @name = name
      @journal_abbreviations = {}
      # @type [Array<Format::CSL::Item>]
      @items = []
      @id_index = {}
      @affiliation_index = {}
      items.each { |item| add_item item }
    end

    # @return  [Array<Format::CSL::Item>]
    attr_reader :items, :name

    alias to_a items

    # @!attribute [r] length
    # @return [Integer]
    def length
      @items.length
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      raise 'Argument must be a Format::CSL::Item' unless item.is_a?(Format::CSL::Item)

      @items.append(item)
      @id_index[item.id] = item
    end

    # @return [Format::CSL::Item]
    def item_by_id(id)
      @id_index[id]
    end

    # @param [Array<String>] ids An array of ids that identify the references, such as a DOI, which can be used
    #   to call #merge_and_validate_citation_data
    # @param [Integer] limit Limits the number of generated items (mainly for test purposes)
    def import(ids, limit: nil)
      raise 'Argument must be an non-empty array of string ids' \
        unless ids.is_a?(Array) && ids.first.is_a?(String)

      @ids = ids

      # @type [Array<Format::CSL::Item>]
      num_refs = 0
      counter = 0
      total = [@ids.length, limit || @ids.length].min

      progress_or_message('Generating consolidated data', total:)

      # iterate over ids
      @ids.each do |id|
        counter += 1
        progress_or_message "Processing #{id} (#{counter}/#{total})\n#{'=' * 80}".colorize(:blue), increment: true,
                            title: "Processing #{id}"

        if @options.use_cache &&
          (item_data = Cache.load(id, prefix: 'dataset-item-'))
          # use the cached item if exists
          item = Format::CSL::Item.new(item_data)
          add_item(item)
          progress_or_message ' - Using cached data'
          break if limit && counter >= limit

          next
        else
          # get the item merged from the different datasources
          progress_or_message "no cache for #{id}".colorize(:yellow)
          begin
            # merge available data according to the policies
            item = merge_and_validate(id)
          rescue NoDataError => e
            puts e.to_s.colorize(:red)
            next
          rescue StandardError => e
            puts e.to_s.colorize(:red)
            puts e.backtrace.join("\n").to_s.colorize(:red)
            next
          end
        end

        # add generated abstract and keywords if there are no in the metadata
        if (item.abstract.to_s.empty? && @options.generate_abstract) || \
           (item.keyword.to_a.empty? && @options.generate_keywords)
          progress_or_message ' - Generating abstract and keywords from fulltext'
          txt_file_path = File.join(@options.text_dir, "#{Workflow::Utils.to_filename(id)}.txt")
          if File.exist? txt_file_path
            text = File.read(txt_file_path, encoding: 'utf-8')
            add_metadata_from_text(item, text)
          else
            puts "Fulltext file does not exist: #{txt_file_path}".colorize(:red)
          end
        end

        # references
        references = item.x_references
        n = references&.length || 0
        num_refs += n
        progress_or_message " - Found #{n} references"

        # get missing reference metadata
        if n.positive? && @options.reference_lookup
          item.x_references = references.map.with_index do |ref, i|
            progress_or_message "   - verifying reference #{i + 1}/#{n}: #{ref.to_s}",
                                title: "Verifying reference #{i + 1}/#{n}"
            if ref.doi
              puts "     - DOI exists: https://doi.org/#{ref.doi}".colorize(:green) if @options.verbose
              ref
            elsif !ref.isbn.nil? && !ref.isbn.empty?
              puts "     - ISBN exists: #{ref.ISBN}".colorize(:green) if @options.verbose
              ref
            else
              reconcile ref
            end
          end
        end

        # iso4 abbreviations
        if item.type == Format::CSL::ARTICLE_JOURNAL
          add_journal_abbreviation(item) if item.journal_abbreviation.to_s.empty?
        elsif @options.abbreviate_titles
          add_title_abbreviations(item)
        end

        # keywords generated from references
        if @options.generate_keywords && n.positive?
          progress_or_message ' - Adding reference-generated keywords '
          add_reference_keywords(item)
        end

        # save and cache item
        add_item(item)
        Cache.save(id, item.to_h(compact: true), prefix: 'dataset-item-')

        break if limit && counter >= limit
      end
      progress_or_message finish: true
      items
    end

    # Export the dataset using the given exporter class
    # @param [Export::Exporter] exporter
    # @param [Integer] limit
    # @param [Array<Instruction>] preprocess An optional list of Instruction objects containing information
    #   on how to preprocess the data to be exported, to be handled by the exporter.
    # @param [Array<Instruction>] postprocess An optional list of Instruction objects containing information
    #   on how to postprocess the data to be exported, to be handled by the exporter.
    def export(exporter, limit: nil, preprocess: [], postprocess: [])
      raise 'First argument must be an Export::Exporter subclass' unless exporter.is_a? ::Export::Exporter
      raise 'Pre/postprocess arguments must be arrays of Workflow::Dataset::Instruction instances' \
        unless (preprocess.to_a + postprocess.to_a).reject { |i| i.is_a? Instruction }.empty?

      items = @items
      counter = 0
      total = [items.length, limit || items.length].min
      progress_or_message("Exporting #{total} items to #{exporter.class.name}...", total:)

      # preprocessing
      preprocess.to_a.each do |instruction|
        msg = instruction.message || 'Preprocessing'
        progress_or_message " - #{msg}", title: msg, progress: 0
        items = exporter.preprocess items, instruction
      end

      # export all items
      exporter.start
      items.each do |item|
        counter += 1
        creator, year = item.creator_year_title
        progress_or_message " - Exporting #{creator} (#{year}) #{counter}/#{total}",
                            title: "Exporting #{creator} (#{year})",
                            increment: true
        exporter.add_item item
        break if counter >= total
      end

      # postprocessing
      postprocess.to_a.each do |instruction|
        msg = instruction.message || 'Postprocessing'
        progress_or_message " - #{msg}", title: msg
        exporter.postprocess instruction
      end

      # finishing
      exporter.finish
      progress_or_message finish: true
    end

    # @param [String] dataset_name
    # @return [Workflow::Dataset]
    def self.load(dataset_name, options: nil)
      raise "Dataset '#{dataset_name}' does not exist." unless exist? dataset_name

      dataset_path = dataset_path(dataset_name)
      # @type [Array<Format::CSL::Item]
      items = Marshal.load(File.binread(dataset_path))
      new(items, options:, name: dataset_name)
    end

    def self.exist? (dataset_name)
      dataset_path = dataset_path(dataset_name)
      File.exist? dataset_path
    end

    def self.dataset_path(dataset_name)
      File.join(Workflow::Path.datasets, "#{dataset_name}.dataset")
    end

    def save(dataset_name)
      add_missing_references
      add_missing_affiliations
      File.binwrite(Dataset.dataset_path(dataset_name), Marshal.dump(@items))
    end

    protected

    # Given an identifier, merge available data
    # @param [String] item_id
    # @return [Format::CSL::Item]
    def merge_and_validate(item_id)
      raise 'Id currently must be a DOI' unless item_id.start_with? '10.'

      policies = @options.policies

      # The validated references
      # @type [Array<Format::CSL::Item>]
      validated_references = []
      num_anystyle_added_refs = 0
      num_anystyle_validated_refs = 0
      num_anystyle_unvalidated_refs = 0
      item = nil

      # lookup with crossref metadata by doi
      Datasource.citation_data_providers.each do |datasource|

        datasource.verbose = @options.verbose

        if item.nil?
          # get anystyle item (enriched with crossref metadata) this works because anystyle
          # is the first in the list
          # @type [Item]
          item = datasource.import_items([item_id]).first
          next
        end

        # @type [Format::CSL::Item]
        vendor_item = datasource.import_items([item_id]).first

        raise NoDataError, "No AnyStyle data available for ID #{item_id}" if item.nil?

        if vendor_item.nil?
          puts " - #{datasource.id}: No data available".colorize(:red) if @options.verbose
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
          if @options.verbose && vendor_refs.length.positive? && @options.verbose
            puts " - #{datasource.id}: added #{vendor_refs.length} references"
          end
        elsif item.x_references.to_a.length.positive?
          # match each anystyle reference against all vendor references since we cannot be sure they are in the same order
          # this can certainly be optimized but is good enough for now
          vendor_refs.each do |vendor_ref|
            vendor_author, vendor_year = vendor_ref.creator_year_title(downcase: true)
            next if vendor_author.nil?

            matched = false
            item.x_references.each do |ref|
              # add missing type
              ref.type ||= vendor_ref.type || Format::CSL.guess_type(ref)

              # iso4 abbreviations
              if ref.type == Format::CSL::ARTICLE_JOURNAL
                add_journal_abbreviation(ref) if ref.journal_abbreviation.to_s.empty?
              else
                add_title_abbreviations(ref)
              end

              # validation is done by author / year exact match. this will produce some false positives/negatives
              author, year = ref.creator_year_title(downcase: true)
              next unless author == vendor_author && year == vendor_year

              # validate
              ref.validate_by(vendor_ref)

              # add affiliations
              add_affiliations(ref, vendor_ref, datasource.id)

              # add missing doi
              ref.doi ||= vendor_ref.doi if vendor_ref.doi

              # add only if reference hasn't been validated already
              unless ref.custom.validated_by.keys.count > 1
                validated_references.append(ref)
                puts " - anystyle: Added #{author} #{year} (validated by #{datasource.id})" if @options.verbose
                num_anystyle_added_refs += 1
              end
              num_anystyle_validated_refs += 1
              matched = true
            end
            next if matched

            # add vendor reference that we don't already have only if so instructed
            unless policies.include?(ADD_MISSING_ALL) || (policies.include?(ADD_MISSING_FREE) && datasource.id != 'wos')
              next
            end

            # add missing type
            vendor_ref.type ||= Format::CSL::Item.guess_type(vendor_ref)

            # iso4 abbreviations
            if vendor_ref.type == Format::CSL::ARTICLE_JOURNAL
              add_journal_abbreviation(vendor_ref) if vendor_ref.journal_abbreviation.to_s.empty?
            else
              add_title_abbreviations(vendor_ref)
            end

            validated_references.append(vendor_ref)
            puts " - #{datasource.id}: Added #{vendor_author} (#{vendor_year}) " if @options.verbose
            num_vendor_added_refs += 1
          end
        end

        if @options.verbose && num_vendor_added_refs.positive?
          puts " - #{datasource.id}: validated #{num_anystyle_validated_refs} anystyle references " \
                 "(of which #{num_anystyle_added_refs} were added), " \
                 "and added #{num_vendor_added_refs} missing references"
        end

        # use the highest "times-cited" value found
        item.custom.times_cited = [vendor_item.custom.times_cited || 0, item.custom.times_cited || 0].max

        # add affiliation data if missing
        add_affiliations(item, vendor_item, datasource.id) if policies.include?(ADD_AFFILIATIONS)

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

      # add references if they are in the configured period
      item.x_references = validated_references.reject do |item|
        item.year.to_i < @options.ref_year_start || item.year.to_i > @options.ref_year_end
      end
      # return result
      item
    end

    # Try to reconcile an extracted reference with datasources that allow a metadata look
    # @param [Format::CSL::Item] ref
    def reconcile(ref)
      a1, y1, t1 = ref.creator_year_title(downcase: true)
      if a1.to_s.empty? || a1 == 'no_author' || t1.to_s.empty? || t1 == 'no_title'
        puts '   - insufficient data'.colorize(:yellow) if @options.verbose
        return ref
      end
      type_supported = false
      Datasource.metadata_providers.each do |provider|
        lang = guess_language(ref.title).iso_639_1
        if provider.metadata_types.include?(ref.type || ref.guess_type) &&
            (provider.languages.empty? || provider.languages.include?(lang))
          puts "     - #{provider.id}: looking up #{ref.to_s[..80]}" if @options.verbose
        else
          puts "     - #{provider.id}: no support for type #{ref.type} and/or language #{lang}" if @options.verbose
          next
        end

        type_supported = true
        begin
          # @type [Format::CSL::Item]
          found_ref = provider.lookup(ref)
        rescue StandardError => e
          puts e.message.to_s.colorize(:red)
          puts e.backtrace.join("\n").colorize(:red) if @options.verbose
          next
        end
        if found_ref.nil?
          puts "     - #{provider.id}: nothing found.".colorize(:yellow) if @options.verbose
          next
        end
        puts "     - #{provider.id}: lookup returned #{found_ref.to_s[..80]}" if @options.verbose
        a2, y2, t2 = found_ref.creator_year_title(downcase: true)
        # check if items are the same or at least similar enough
        if y1 != y2 || a2.nil? ||
          (a1 != a2 && (DamerauLevenshtein.distance(a1, a2) > 3 || DamerauLevenshtein.distance(t1, t2) > 5))
          puts "     - #{provider.id}: data does not match".colorize(:yellow) if @options.verbose
          next
        end
        # we have a match
        if found_ref.to_h.keys.length < ref.to_h.keys.length
          puts "     - #{provider.id}: found data contains less information than what we have".colorize(:yellow) if @options.verbose
          ref.doi ||= found_ref.doi
          ref.isbn ||= found_ref.isbn
          next
        end
        puts "     - merging #{provider.id} metadata to reference".colorize(:green) if @options.verbose
        # save the reconciliation data
        found_ref.custom.validated_by = ref.custom.validated_by
        found_ref.custom.original_data = ref
        ref = found_ref
        add_journal_abbreviation(ref)
        break
      end
      puts "   - no reconciliation service available for type '#{ref.type}'" if !type_supported && @options.verbose
      ref
    end

    def build_indexes
      raise 'You must first load or import dataset items' if @items.to_a.empty?

      @items.each do |item|
        author, year, title = item.creator_year_title(downcase: true)
        @id_index[author] = {} if @id_index[author].nil?
        @id_index[author][year] = {} if @id_index[author][year].nil?
        @id_index[author][year][title] = item.id
        item.creators.each do |c|
          @affiliation_index["#{c.family} #{c.initial}"] ||= c.x_affiliations.to_a.first
        end
      end
    end

    def add_missing_references
      build_indexes if @id_index.empty?
      @items.each do |item|
        item.x_references.each do |ref|
          next unless ref.doi.to_s.empty?

          author, year, title = ref.creator_year_title(downcase: true)
          next if @id_index[author].to_h[year].to_h.empty?

          ref.doi = @id_index[author][year][title] || @id_index[author][year].values.first
        end
      end
    end

    def add_missing_affiliations
      build_indexes if @id_index.empty?
      @items.each do |item|
        item.creators.each do |c|
          if c.x_affiliations.to_a.empty? && (aff = @affiliation_index["#{c.family} #{c.initial}"])
            c.x_affiliations = [aff]
          end
        end
      end
    end

    # @param [Format::CSL::Item] item
    # @param [Format::CSL::Item] vendor_item
    # @param [String] vendor
    def add_affiliations(item, vendor_item, vendor)
      item.creators.each do |creator|
        vendor_item.creators.each do |vendor_creator|
          # ignore if the family name does not match
          next if creator.family != vendor_creator.family

          raw_affiliation = vendor_creator.x_raw_affiliation_string
          next if raw_affiliation.to_s.empty? && vendor_creator.x_affiliations&.empty?

          # ignore specific affiliations or false positives

          next if @options.affiliation_ignore_list.any? do |expr|
            affiliations_data = vendor_creator.x_affiliations&.reduce([]) do |data, aff|
              aff.to_h(compact: true).each_value { |v| data.append v.to_s }
              data
            end
            raw_affiliation&.match(expr) || affiliations_data&.any? { |i| i.match(expr) }
          end

          creator.x_raw_affiliation_string ||= raw_affiliation
          vendor_aff = vendor_creator.x_affiliations&.first&.to_h(compact: true)
          next if vendor_aff.nil?

          creator.x_affiliations ||= []
          aff = creator.x_affiliations.first&.to_h(compact: true)
          new_aff = Format::CSL::Affiliation.new(vendor_aff)
          if aff.nil? || vendor_aff.keys.length > aff.keys.length
            # assume the better affiliation data is the one with more keys, prepend it
            creator.x_affiliations.prepend new_aff
          else
            # otherwise add so it is not lost
            creator.x_affiliations.append new_aff
          end

          puts " - #{vendor}: Added affiliation data #{JSON.dump(vendor_aff)}" if @options.verbose
        end
      end
    end

    # @param [Format::CSL::Item] item
    def add_journal_abbreviation(item)
      journal_name = item.container_title
      disambiguation_langs = @options.abbr_disamb_langs
      item.journal_abbreviation ||= Workflow::Utils.abbrev_iso4(journal_name, disambiguation_langs:)
    end

    # @param [Format::CSL::Item] item
    def add_title_abbreviations(item)
      disambiguation_langs = @options.abbr_disamb_langs
      item.custom.iso4_title ||= Workflow::Utils.abbrev_iso4(item.title, disambiguation_langs:)
      return if item.container_title.nil?

      item.custom.iso4_container_title ||= Workflow::Utils.abbrev_iso4(item.container_title, disambiguation_langs:)
    end

    # This auto-generates an abstract and keywords and also adds a language if none has been set
    # @param [Format::CSL::Item] item
    # @param [String] text
    def add_metadata_from_text(item, text)
      if text.to_s.strip.empty?
        warn "Cannot add metadata from empty text for document with id '#{item.id}'.".colorize(:red)
        return

      end
      begin
        abstract, keywords, language = summarize(text, ratio: 5, topics: true, stopword_files: @options.stopword_files)
      rescue StandardError => e
        warn "Problem summarizing document with id '#{item.id}': #{e}".colorize(:red)
        return
      end
      item.abstract = abstract if @options.generate_abstract && item.abstract.to_s.empty?
      item.keyword = keywords if @options.generate_keywords && item.keyword.empty?
      item.language ||= language if language
    end

    # @param [Format::CSL:Item] item
    def add_reference_keywords(item)
      reference_corpus = item.x_references.map { |ref| [ref.title, ref.abstract].compact.join(' ') }.join(' ')
      return if reference_corpus.to_s.strip.empty?

      begin
        _, keywords = summarize(reference_corpus, topics: true, stopword_files: @options.stopword_files)
      rescue StandardError => e
        warn "Problem summarizing references of document with id '#{item.id}': #{e}\n#{reference_corpus}".colorize(:red)
        return
      end
      item.custom.generated_keywords = keywords.reject { |kw| kw.length < 4 }
    end

    private

    def progress_or_message(message = nil, increment: false, total: 0, finish: false, progress: nil, title: nil)
      if @options.verbose
        puts message if message
      else
        if @progressbar.nil?
          @progressbar = ProgressBar.create(title:, total:, **::Workflow::Config.progress_defaults)
        elsif title.is_a? String
          @progressbar.title = Utils.truncate(title, pad_char: ' ')
        end
        if increment
          @progressbar.increment
        elsif progress.is_a? Integer
          @progressbar.progress = progress
        elsif finish
          @progressbar.finish
          @progressbar = nil
        end
      end
    end
  end
end
