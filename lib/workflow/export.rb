# frozen_string_literal: true

module Workflow
  class Export
    class << self
      include Format::CSL
      include Nlp

      # enums
      MERGE_POLICIES = [
        # validate using author / year comparison
        # VALIDATE_METHOD_AUTHOR_YEAR = 'validate_method_author_year',
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

      # Given a DOI, merge available data into a CSL hash (having a "reference" field containing the cited
      # references as CSL items). Anystyle references will be matched against the vendor references.
      # If one matches, reference will have a custom/validated-by field, which is a hash, having the
      # vendor name as key and the reference that validates the anystyle data as value
      # @param [String] doi
      # @param [Boolean] verbose
      # @param [Array<Export.POLICIES>] policies
      # @return [Format::CSL::Item]
      def merge_and_validate(doi, verbose: false,
                             policies: [ADD_MISSING_ALL, ADD_UNVALIDATED, REMOVE_DUPLICATES, ADD_AFFILIATIONS])

        Datasource::Anystyle.verbose = verbose
        Datasource::Crossref.verbose = verbose

        # get anystyle item (enriched with crossref metadata)
        # @type [Item]
        item = Datasource::Anystyle.import_items_by_doi([doi]).first

        raise "No data available for DOI #{doi}" if item.nil?

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
          vendor_item = ::Datasource.get_provider_by_name(vendor).import_items_by_doi([doi]).first

          # add reference data
          # @type [Array<Item>]
          vendor_refs = vendor_item.x_references
          num_vendor_added_refs = 0

          if policies.include?(DUMP_ALL)
            validated_references += vendor_refs
            num_vendor_added_refs += vendor_refs.length
            puts " - #{vendor}: added #{vendor_refs.length} references" if verbose && vendor_refs.length.positive?
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
                  puts " - anystyle: Added #{author} #{year} (validated by #{vendor})" if verbose
                  num_anystyle_added_refs += 1
                end
                num_anystyle_validated_refs += 1
                matched = true
              end
              next if matched

              next unless policies.include?(ADD_MISSING_ALL) || (policies.include?(ADD_MISSING_FREE) && vendor != 'wos')

              validated_references.append(vendor_ref)
              puts " - #{vendor}: Added #{vendor_author} (#{vendor_year}) " if verbose
              num_vendor_added_refs += 1
            end
          end
          if verbose && num_vendor_added_refs.positive?
            puts " - #{vendor}: validated #{num_anystyle_validated_refs} anystyle references " +
                   "(of which #{num_anystyle_added_refs} were added), " +
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

            puts " - anystyle: Added unvalidated #{author} #{year}" if verbose
            validated_references.append(ref)
            num_anystyle_unvalidated_refs += 1
          end
          puts " - added #{num_anystyle_unvalidated_refs} unvalidated anystyle references" if verbose
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

      private def add_affiliations(item, vendor_item, vendor)
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
            puts " - #{vendor}: Added richer affiliation data"
          end
        end
      end

      # Generate a hash, the keys being the file basenames of the anystyle csl file, the values being
      # consolidated csl items where the data is drawn from existing data from the different
      # datasources
      #
      # @param [String] source_dir Path to the directory containing the CSL-JSON anystyle data. Optional, defaults to
      #       the workflow dir
      # @param [Boolean] verbose If true, output verbose logging instead of progress meter
      # @param [String] text_dir Optional path to directory containing the original .txt files. Needed if abstracts and
      #       topics are missing in the metadata and should be generated automatically from the text
      # @param [Array] remove_list An array of words that should be disregarded for auto-generating abstracts and keywords
      def to_consolidated_csl(text_dir:, remove_list:, limit:, source_dir: Path.csl,
                              verbose: false,
                              use_cache: true)

        files = Dir.glob(File.join(source_dir, '*.json'))

        # use cache if it exists to speed up process
        item_cache_path = File.join(Path.tmp, 'metadata_cache.json')
        item_cache = File.exist?(item_cache_path) ? JSON.load_file(item_cache_path) : {}

        unless verbose
          progressbar = ProgressBar.create(title: 'Generating consolidated data:',
                                           total: files.length,
                                           **::Workflow::Config.progress_defaults)
        end

        num_refs = 0
        counter = 0
        # iterate over CSL-JSON files in source directory
        files.each do |file_path|

          progressbar.increment unless verbose

          file_name = File.basename(file_path, '.json')
          doi = file_name.sub('_', '/')
          puts "Processing #{file_name}.json:" if verbose

          if use_cache && (item = item_cache[file_name])
            # use the cached item if exists
            puts " - Using cached data" if verbose
          else
            # get the item merged from the different datasources
            item = merge_and_validate(doi, verbose:)
          end

          # ignore items without any authors (such as book report sections)
          next if get_csl_creator_list(item).empty?

          # add generated abstract and keywords if there are no in the metadata
          if text_dir && (item['abstract'].nil? || item['keyword'].nil?)
            # try cache first to avoid costly recalculation
            abstract = item_cache.dig(file_name, 'abstract')
            if abstract.nil?
              puts ' - Generating abstract and keywords from fulltext' if verbose
              txt_file_path = File.join(text_dir, "#{file_name}.txt")
              abstract, keyword = summarize_file txt_file_path, ratio: 5, topics: true, remove_list:
            else
              puts ' - Using previously generated abstract and keywords' if verbose
              keyword = item_cache.dig(file_name, 'keyword')
            end
            item['abstract'] ||= abstract
            item['keyword'] ||= keyword
          end

          # references
          references = item['reference']
          n = references&.length || 0
          num_refs += n
          puts " - Found #{n} references" if verbose

          # keywords generated from references
          if n.positive?
            generated_keywords = item_cache.dig(file_name, 'custom', CUSTOM_GENERATED_KEYWORDS)
            if generated_keywords.is_a?(Array) && generated_keywords.length.positive?
              puts " - Using previously reference-generated keywords: #{generated_keywords.join('; ')}" if verbose
            else
              refs_titles = references.map { |ref| ref['title'] }.join(' ')
              _, kw = refs_titles.summarize(topics: true)
              generated_keywords = kw.force_encoding('utf-8').split(',')
              puts " - Adding reference-generated keywords: #{generated_keywords.join('; ')}" if verbose
            end
            item['custom'][CUSTOM_GENERATED_KEYWORDS] = generated_keywords
          end

          item_cache[file_name] = item
          counter += 1
          break if limit && counter >= limit
        end

        progressbar.finish unless verbose

        File.write(item_cache_path, JSON.dump(item_cache))
        puts "Saved JSON data of that export to #{item_cache_path}." if verbose

        # return the items
        item_cache
      end

      # Generates a tagged file with the metadata and reference data that mimics a Web of Science export file and can
      # be imported in application which expect WoS data.
      #
      # @param [String] export_file_path Path to the output file
      # @param [String] source_dir Path to the directory containing the CSL-JSON anystyle data. Optional, defaults to
      #       the workflow dir
      # @param [Boolean] verbose If true, output verbose logging instead of progress meter
      # @param [Boolean] compact If true, remove all empty tags. Default is true, pass false if an app complains about
      #       missing fields
      # @param [String] text_dir Optional path to directory containing the original .txt files. Needed if abstracts and
      #       topics are missing in the metadata and should be generated automatically from the text
      # @param [Array] remove_list
      # @param [String (frozen)] encoding
      def to_wos(text_dir:, remove_list:, limit:, use_cache:, export_file_path: nil,
                 source_dir: Path.csl,
                 verbose: false,
                 compact: true,
                 encoding: 'utf-8')

        export_file_path ||= File.join(Path.export, "export-wos-#{Utils.timestamp}.txt")

        csl_items = to_consolidated_csl(
          source_dir:,
          verbose:,
          text_dir:,
          remove_list:,
          limit:,
          use_cache:
        )

        counter = 0
        total = [csl_items.length, limit || csl_items.length].min
        if verbose
          puts "Exporting #{total} items to #{export_file_path}."
        else
          progressbar = ProgressBar.create(title: 'Exporting to ISI/WoS-tagged file:',
                                           total:,
                                           **::Workflow::Config.progress_defaults)
        end
        ::Export::Wos.write_header(export_file_path, encoding:)
        csl_items.each do |file_name, item|
          counter += 1
          if verbose
            puts " - Processing #{file_name} #{counter}/#{total}"
          else
            progressbar.increment
          end
          ::Export::Wos.append_record(export_file_path, item, compact:, add_ref_source: false, encoding:)
          break if counter >= limit
        end
        progressbar.finish unless verbose
      end
    end
  end
end
