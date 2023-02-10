# frozen_string_literal: true

module Workflow
  class Export
    class << self

      include Format::CSL
      include Nlp

      # Given a DOI, merge available data into a CSL hash (having a "reference" field containing the cited
      # references as CSL items)
      # @param [String] doi
      # @param [Boolean] verbose
      def get_csl_metadata(doi, verbose: false)

        # the key is the DOI with slashes substituted by underscore, which is also the filename of the
        # input and output files of our workflow
        key = doi.sub('/', '_')

        # load all available metadata in memory except the anystyle data, which will be loaded on demand
        if @vendor_data.nil?
          @vendor_data = ::Datasource::Utils.get_vendor_data
          @vendor_data['anystyle'] = {}
        end

        # load anystyle data for the requested item
        if @vendor_data.dig('anystyle', key, 'reference').nil?
          file_path = File.join(::Workflow::Path.csl, "#{key}.json")
          # puts " - Anystyle: Looking for references for #{doi} in #{file_path}" if verbose
          if File.exist? file_path
            cited_items = JSON.load_file(file_path)
            # filter out unusable data
            filtered_items = filter_items(cited_items)
            if verbose
              puts " - Anystyle: Found #{cited_items.length}, ignored #{cited_items.length - filtered_items.length} items"
            end
            @vendor_data['anystyle'][key] = {
              'reference' => filtered_items
            }
          end
        end

        # use crossref data as base
        item = @vendor_data.dig('crossref', key)
        if item.nil?
          raise "No metadata exists for #{doi}"
        end

        references = item['reference'] || []

        # remove xml tags from crossref abstract field
        item['abstract'].gsub!(/<[^<]+?>/, '') if item['abstract'].is_a? String

        # parse crossref's 'reference[]/unstructured' fields into author, date and title information
        if references.length.positive?
          references.map! do |ref|
            if ref['unstructured'].nil? || ref['DOI'].nil?
              ref
            else
              m = ref['unstructured'].match(/^(?<author>.+) \((?<year>\d{4})\) (?<title>[^.]+)\./)
              return ref if m.nil?

              {
                'author' => Namae.parse(m[:author]).map(&:to_h),
                'issued' => [{ 'date-parts' => [m[:year]] }],
                'title' => m[:title],
                'DOI' => ref['DOI']
              }
            end
          end
        end

        # merge available data from other vendors
        @vendor_data.each_key do |vendor|
          next if vendor == 'crossref'

          vendor_item = @vendor_data.dig(vendor, key)
          next if vendor_item.nil?

          # add abstract if no crossref abstract exists
          item['abstract'] ||= vendor_item['abstract'] if vendor_item['abstract'].is_a? String

          # add custom fields
          if vendor_item['custom'].is_a? Hash
            item['custom'] = {} if item['custom'].nil?
            item['custom'].merge! vendor_item['custom']
          end

          # add reference data
          refs = @vendor_data.dig(vendor, key, 'reference')
          next unless refs.is_a? Array

          refs.each { |ref| ref['source'] = vendor }
          references += refs
          puts " - #{vendor}: added #{refs.length} references" if verbose && refs.length.positive?
        end
        item['reference'] = remove_duplicates(references)
        # return result
        item
      end

      # given a list of csl hashes, remove redundant entries with the least amount of information
      def remove_duplicates(item_list)
        # item_list = filter_items(item_list)
        # titles = item_list.map { |item| item['title'] }
        # puts JSON.pretty_generate(group_by_similarity(titles))
        item_list
      end

      # https://stackoverflow.com/a/41941713
      def group_by_similarity(strings, max_distance: 5, compensation: 5)
        result = {}
        strings.each do |s|
          s.downcase!
          similar = result.keys.select do |key|
            len = [key.length, s.length].min
            Text::Levenshtein.distance(key.downcase[..len],
                                       s.downcase[..len]) < max_distance + (s.length / compensation)
          end
          if similar.any?
            result[similar.first].append(s)
          else
            result.merge!({ s => [] })
          end
        end
        result
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
      def to_wos(export_file_path: nil, source_dir: Path.csl, verbose: false, compact: true, text_dir:, remove_list:)
        files = Dir.glob(File.join(source_dir, '*.json')).map(&:untaint)
        progressbar = ProgressBar.create(title: 'Exporting to ISI/WoS-tagged file:',
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)

        export_file_path ||= File.join(Path.export, "export-wos-#{Utils.timestamp}.txt")

        # start export
        ::Export::Wos.write_header(export_file_path)
        num_refs = 0
        counter = 0

        # iterate over CSL-JSON files in source directory
        files.each do |file_path|
          progressbar.increment unless verbose
          file_name = File.basename(file_path, '.json')
          puts "Processing #{file_name}.json:" if verbose
          doi = file_name.sub('_', '/')
          item = get_csl_metadata(doi, verbose:)

          # add generated abstract and keywords if there are no in the metadata
          if text_dir && (item['abstract'].nil? || item['keyword'].nil?)
            txt_file_path = File.join(text_dir, file_name + ".txt")
            abstract, keywords = summarize_file txt_file_path, ratio: 5, topics: true, remove_list: remove_list
            item['abstract'] ||= abstract
            item['keyword'] ||= keywords
          end

          # references
          references = item['reference']
          n = references&.length || 0
          num_refs += n
          puts " - Found #{n} references" if verbose
          ::Export::Wos.append_record(export_file_path, item, compact:, add_ref_source: false)
          counter += 1
          #break if counter.positive?
        end
        progressbar.finish unless verbose
        puts "Exported #{num_refs} references from #{files.length} files to #{export_file_path}."
      end
    end
  end
end
