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
      ]

      # Given a DOI, merge available data into a CSL hash (having a "reference" field containing the cited
      # references as CSL items). Anystyle references will be matched against the vendor references.
      # If one matches, reference will have a custom/validated-by field, which is a hash, having the
      # vendor name as key and the reference that validates the anystyle data as value
      # @param [String] doi
      # @param [Boolean] verbose
      # @param [Export.POLICIES[]] policies
      def merge_and_validate(doi, verbose: false, policies: [ADD_MISSING_ALL, ADD_UNVALIDATED])

        # load all available metadata in memory except the anystyle data, which will be loaded on demand
        if @vendor_data.nil?
          @vendor_data = ::Datasource::Utils.get_vendor_data
        end

        file_name = doi.sub('/', '_')

        # lookup with crossref metadata by doi (or file name, deprecated)
        item = @vendor_data.dig('crossref', doi) || @vendor_data.dig('crossref', file_name)
        if item.nil?
          raise "No metadata exists for #{doi}, cannot continue."
        else
          item = Datasource::Crossref.fix_crossref_item(item)
        end

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
          item[FIELD_CUSTOM] = {} if item[FIELD_CUSTOM].nil?
          case vendor
          when "crossref"
            # move cited-by-count to custom
            item[FIELD_CUSTOM][Datasource::Crossref::TIMES_CITED] = item[Datasource::Crossref::TIMES_CITED_ORIG]
            # move authors affiliations to custom
            affiliations = get_csl_creator_list(item).map { |creator|
              creator.dig('affiliation', 0, 'name')
            }.reject { |item| item.nil? }
            item[FIELD_CUSTOM][Datasource::Crossref::AUTHORS_AFFILIATIONS] = affiliations if affiliations.length.positive?
          when "openalex"
            # move authors affiliations to custom
            affiliations = get_csl_creator_list(item).map { |creator|
              creator.dig(Datasource::OpenAlex::AUTHORS_AFFILIATION_LITERAL)
            }.reject { |item| item.nil? }
            item[FIELD_CUSTOM][Datasource::OpenAlex::AUTHORS_AFFILIATIONS] = affiliations if affiliations.length.positive?
          end

          if vendor != "crossref"
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
                if author == vauthor && year == vyear
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
              end
              if matched == false
                if policies.include?(ADD_MISSING_ALL) || (policies.include?(ADD_MISSING_FREE) && vendor != "wos")
                  references.append(vendor_ref)
                  puts " - #{vendor}: Added #{vauthor} (#{vyear}) " if verbose
                  num_vendor_refs += 1
                end
              end
            end
          end
          puts " - #{vendor}: validated #{num_validated_refs} anystyle references (of which #{num_anystyle_refs} were added), and added #{num_vendor_refs} missing references" if verbose && num_vendor_refs.positive?
        end
        num_vendor_refs = references.length

        if policies.include?(ADD_UNVALIDATED)
          anystyle_references.each do |ref|
            unless ref.dig(FIELD_CUSTOM, CUSTOM_VALIDATED_BY)&.keys&.length&.positive?
              author, year = get_csl_author_year_title(ref, downcase: true)
              next if author.nil? || author.empty?
              puts " - anystyle: Added unvalidated #{author} #{year}" if verbose
              references.append(ref)
            end
          end
          puts " - added #{references.length - num_vendor_refs} unvalidated anystyle references" if verbose
        end

        item['reference'] = references
        # return result
        item
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
      def to_wos(export_file_path: nil,
                 source_dir: Path.csl,
                 verbose: false,
                 compact: true,
                 text_dir:,
                 remove_list:,
                 encoding: "utf-8",
                 limit:)

        files = Dir.glob(File.join(source_dir, '*.json')).map(&:untaint)
        export_file_path ||= File.join(Path.export, "export-wos-#{Utils.timestamp}.txt")
        item_cache_path = File.join(Path.tmp, "metadata_cache.json")
        item_cache = File.exist?(item_cache_path) ? JSON.load_file(item_cache_path) : {}
        progressbar = ProgressBar.create(title: 'Exporting to ISI/WoS-tagged file:',
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)

        # start export
        ::Export::Wos.write_header(export_file_path, encoding:)
        num_refs = 0
        counter = 0

        # iterate over CSL-JSON files in source directory
        files.each do |file_path|
          progressbar.increment unless verbose
          file_name = File.basename(file_path, '.json')
          puts "Processing #{file_name}.json:" if verbose
          doi = file_name.sub('_', '/')
          item = merge_and_validate(doi, verbose:)
          # do not include items without any authors (such as book report sections)
          next if get_csl_creator_list(item).length == 0

          # add generated abstract and keywords if there are no in the metadata
          if text_dir && (item['abstract'].nil? || item['keyword'].nil?)
            # try cache first to avoid recalculation
            abstract = item_cache.dig(file_name, 'abstract')
            if abstract.nil?
              puts " - Generating abstract and keywords from fulltext" if verbose
              txt_file_path = File.join(text_dir, file_name + ".txt")
              abstract, keyword = summarize_file txt_file_path, ratio: 5, topics: true, remove_list: remove_list
            else
              puts " - Using previously generated abstract and keywords" if verbose
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
          if n.positive? && item['custom'][CUSTOM_GENERATED_KEYWORDS].nil?
            generated_keywords = item_cache.dig(file_name, 'custom', CUSTOM_GENERATED_KEYWORDS)
            if generated_keywords.nil?
              refs_titles = references.map { |ref| ref['title'] }.join(" ")
              _, generated_keywords = refs_titles.summarize(topics: true)
              item['custom'][CUSTOM_GENERATED_KEYWORDS] = generated_keywords.force_encoding("utf-8").split(",")
              puts " - Generated additional keywords from references: #{generated_keywords}" if verbose
            else
              puts " - Using previously reference-generated keywords: #{generated_keywords}" if verbose
            end
          end

          # write to file
          ::Export::Wos.append_record(export_file_path, item, compact:, add_ref_source: false, encoding:)
          item_cache[file_name] = item
          counter += 1
          break if limit && counter >= limit
        end
        progressbar.finish unless verbose
        puts "Exported #{num_refs} references from #{counter} documents to #{export_file_path}."
        File.write(item_cache_path, JSON.dump(item_cache))
        puts "In addition, saved JSON data of that export to #{item_cache_path}." if verbose
      end
    end
  end
end
