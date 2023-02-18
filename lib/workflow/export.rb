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
        DUMP_ALL = 'dump_all'
      ].freeze

      # Given a DOI, merge available data into a CSL hash (having a "reference" field containing the cited
      # references as CSL items). Anystyle references will be matched against the vendor references.
      # If one matches, reference will have a custom/validated-by field, which is a hash, having the
      # vendor name as key and the reference that validates the anystyle data as value
      # @param [String] doi
      # @param [Boolean] verbose
      # @param [Export.POLICIES[]] policies
      def merge_and_validate(doi, verbose: false, policies: [ADD_MISSING_ALL, ADD_UNVALIDATED])
        # load all available metadata in memory except the anystyle data, which will be loaded on demand
        @vendor_data = ::Datasource::Utils.get_vendor_data if @vendor_data.nil?

        file_name = doi.sub('/', '_')

        # lookup with crossref metadata by doi (or file name, deprecated)
        item = @vendor_data.dig('crossref', doi) || @vendor_data.dig('crossref', file_name)
        raise "No metadata exists for #{doi}, cannot continue." if item.nil?

        item = Datasource::Crossref.fix_crossref_item(item)

        # load anystyle references for the requested item
        anystyle_references = Datasource::Anystyle.get_references_by_doi(doi)
        references = []

        # process available data from vendors
        @vendor_data.each_key do |vendor|
          vendor_item = @vendor_data.dig(vendor, doi) || @vendor_data.dig(vendor, file_name)

          if vendor_item.nil?
            puts " - No data for #{doi} in #{vendor}" if verbose
            next
          end

          # move non-standard fields into "custom" field
          # this should be done in the classes themselves
          item[FIELD_CUSTOM] = {} if item[FIELD_CUSTOM].nil?
          case vendor
          when 'crossref'
            # move cited-by-count to custom
            item[FIELD_CUSTOM][Datasource::Crossref::TIMES_CITED] = item[Datasource::Crossref::TIMES_CITED_ORIG]
            # move authors affiliations to custom
            affiliations = get_csl_creator_list(item).map do |creator|
              creator.dig('affiliation', 0, 'name')
            end.reject(&:nil?)
            if affiliations.length.positive?
              item[FIELD_CUSTOM][Datasource::Crossref::AUTHORS_AFFILIATIONS] =
                affiliations
            end
          when 'openalex'
            # move authors affiliations to custom
            affiliations = get_csl_creator_list(item).map do |creator|
              creator[Datasource::OpenAlex::AUTHORS_AFFILIATION_LITERAL]
            end.reject(&:nil?)
            if affiliations.length.positive?
              item[FIELD_CUSTOM][Datasource::OpenAlex::AUTHORS_AFFILIATIONS] =
                affiliations
            end
          end

          if vendor != 'crossref'
            # add abstract if no crossref abstract exists
            item['abstract'] ||= vendor_item['abstract'] if vendor_item['abstract'].is_a? String

            # add custom fields
            item[FIELD_CUSTOM].merge! vendor_item[FIELD_CUSTOM]
          end

          # add reference data
          vendor_refs = vendor_item['reference'] || []

          if policies.include?(DUMP_ALL)
            vendor_refs.each { |ref| ref['source'] = vendor }
            anystyle_references += vendor_refs
            puts " - #{vendor}: added #{vendor_refs.length} references" if verbose && vendor_refs.length.positive?
          else

            # match each anystyle reference against all vendor references since we cannot be sure they are in the same order
            # this can certainly be optimized but is good enough for now
            num_anystyle_refs = 0
            num_vendor_refs = 0
            num_validated_refs = 0
            vendor_refs.each do |vendor_ref|
              vauthor, vyear = get_csl_author_year_title vendor_ref, downcase: true
              next if vauthor.nil? || vauthor.strip.empty?

              matched = false
              anystyle_references.each do |ref|
                author, year = get_csl_author_year_title ref, downcase: true
                # validation is done by author / year exact match. this will produce some false positives/negatives
                next unless author == vauthor && year == vyear

                ref[FIELD_CUSTOM] = {} if ref[FIELD_CUSTOM].nil?
                ref[FIELD_CUSTOM][CUSTOM_VALIDATED_BY] = {} if ref[FIELD_CUSTOM][CUSTOM_VALIDATED_BY].nil?
                ref[FIELD_CUSTOM][CUSTOM_VALIDATED_BY].merge!({ vendor => vendor_ref })
                # add only if reference hasn't been validated already
                unless ref[FIELD_CUSTOM][CUSTOM_VALIDATED_BY].keys.count > 1
                  references.append(ref)
                  puts " - anystyle: Added #{author} #{year} (validated by #{vendor})" if verbose
                  num_anystyle_refs += 1
                end
                num_validated_refs += 1
                matched = true
              end
              next unless matched == false

              next unless policies.include?(ADD_MISSING_ALL) || (policies.include?(ADD_MISSING_FREE) && vendor != 'wos')

              references.append(vendor_ref)
              puts " - #{vendor}: Added #{vauthor} (#{vyear}) " if verbose
              num_vendor_refs += 1
            end
          end
          if verbose && num_vendor_refs.positive?
            puts " - #{vendor}: validated #{num_validated_refs} anystyle references (of which #{num_anystyle_refs} were added), and added #{num_vendor_refs} missing references"
          end
        end
        num_vendor_refs = references.length

        if policies.include?(ADD_UNVALIDATED)
          anystyle_references.each do |ref|
            next if ref.dig(FIELD_CUSTOM, CUSTOM_VALIDATED_BY)&.keys&.length&.positive?

            author, year = get_csl_author_year_title(ref, downcase: true)
            next if author.nil? || author.empty?

            puts " - anystyle: Added unvalidated #{author} #{year}" if verbose
            references.append(ref)
          end
          puts " - added #{references.length - num_vendor_refs} unvalidated anystyle references" if verbose
        end

        item['reference'] = references
        # return result
        item
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
