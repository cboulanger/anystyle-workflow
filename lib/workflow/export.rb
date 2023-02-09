# frozen_string_literal: true

module Workflow
  class Export
    class << self
      include Format::CSL

      def get_item_by_doi(doi, verbose: false)
        key = doi.sub('/', '_')
        if @vendor_data.nil?
          @vendor_data = ::Datasource::Utils.get_vendor_data
          @vendor_data['anystyle'] = {}
        end

        if @vendor_data.dig('anystyle', key, 'reference').nil?
          file_path = File.join(::Workflow::Path.csl, "#{key}.json")
          # puts " - Anystyle: Looking for references for #{doi} in #{file_path}" if verbose
          if File.exist? file_path
            cited_items = JSON.load_file(file_path)
            filtered_items = filter_items(cited_items)
            if verbose
              puts " - Anystyle: Found #{cited_items.length}, ignored #{cited_items.length - filtered_items.length} items"
            end
            @vendor_data['anystyle'][key] = {
              'reference' => filtered_items
            }
          end
        end

        # merge available reference data
        item = @vendor_data.dig('crossref', key)
        references = item['reference'] || []
        @vendor_data.each_key do |vendor|
          if vendor == 'crossref'
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
            next
          end

          refs = @vendor_data.dig(vendor, key, 'reference')
          next unless refs.is_a? Array

          refs.each { |ref| ref['source'] = vendor }
          references += refs
          puts " - #{vendor}: added #{refs.length} references" if verbose && refs.length.positive?
        end
        item['reference'] = remove_duplicates(references)
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

      def to_wos(export_file_path: nil, source_dir: Path.csl, verbose: false, compact: true)
        files = Dir.glob(File.join(source_dir, '*.json')).map(&:untaint)
        progressbar = ProgressBar.create(title: 'Exporting to ISI/WoS-tagged file:',
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)

        # start export
        export_file_path ||= File.join(Path.export, "export-wos-#{Utils.timestamp}.txt")
        ::Export::Wos.write_header(export_file_path)
        num_refs = 0
        counter = 0
        files.each do |file_path|
          progressbar.increment unless verbose
          file_name = File.basename(file_path, '.json')
          puts "Processing #{file_name}.json:" if verbose
          doi = file_name.sub('_', '/')
          item = get_item_by_doi(doi, verbose:)
          references = item['reference']
          n = references&.length || 0
          num_refs += n
          puts " - Found #{n} references" if verbose
          ::Export::Wos.append_record(export_file_path, item, compact:, add_ref_source: false)
          counter += 1
          #break if counter.positive?
        end
        progressbar.finish unless verbose
        puts "Exported #{num_refs} references from #{files.length} files."
      end
    end
  end
end
