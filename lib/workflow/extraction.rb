# frozen_string_literal: true

module Workflow
  class Extraction
    class << self
      include ::Format::CSL

      # extracts text from PDF documents
      # @param [String] source_dir
      # @param [Boolean] overwrite
      def pdf_to_txt(source_dir = Path.pdf, overwrite: false)
        anystyle = Datamining::AnyStyle.new
        files = Dir.glob(File.join(source_dir, '*.pdf'))
        progressbar = ProgressBar.create(title: 'Extracting text from PDF:',
                                         total: files.length,
                                         **Config.progress_defaults)
        files.each do |file_path|
          file_name = File.basename(file_path, '.pdf')
          outfile = File.join(Path.txt, "#{file_name}.txt")
          progressbar.increment
          next if !overwrite && File.exist?(outfile)

          text = anystyle.pdf_to_text(file_path)
          File.write(outfile, text)
        end
      end

      # extracts reference information from the raw text of the documents and writes the corresponding output files
      # @param [String] source_dir Defaults to data/2-txt
      # @param [Boolean] output_intermediaries If true, write intermediary file formats to disk for debugging purposes, will slow down extraction considerably
      # @param [Boolean] overwrite If true, overwrite existing files
      # @param [String, nil] model_dir
      # @param [String, nil] parser_gold_dir
      # @param [String, nil] finder_gold_dir
      def doc_to_csl_json(limit:, source_dir: Path.txt,
                          overwrite: false,
                          output_intermediaries: false,
                          model_dir: Path.models,
                          parser_gold_dir: nil,
                          finder_gold_dir: nil,
                          verbose: false)
        finder_model_path = File.join model_dir, 'finder.mod'
        parser_model_path = File.join model_dir, 'parser.mod'
        anystyle = Datamining::AnyStyle.new(finder_model_path:, parser_model_path:)
        files = Dir.glob(File.join(source_dir, '*.txt'))
        unless verbose
          progressbar = ProgressBar.create(title: 'Extracting references from text:',
                                           total: files.length,
                                           **Config.progress_defaults)
        end
        counter = 0
        files.each do |file_path|
          file_name = File.basename(file_path, '.txt')
          if verbose
            puts "Processing #{file_path}"
          else
            progressbar.increment
          end

          # these are the main files we need for linking and evaluation
          csl_file = File.join Path.csl, "#{file_name}.json"
          anystyle_json_file = File.join Path.anystyle_json, "#{file_name}.json"

          # we can skip all remaining steps if they exist and we don't need the intermediaries
          if File.exist?(csl_file) && File.exist?(anystyle_json_file) && !overwrite && !output_intermediaries
            puts ' - Output files exist, skipping...' if verbose
            next
          end

          # get untagged references from gold if exists or via finder parsing
          finder_gold_path = !finder_gold_dir.nil? && File.join(finder_gold_dir, "#{file_name}.ttx")
          refs_txt = if finder_gold_path && File.exist?(finder_gold_path)
                       puts " - Using finder gold from #{finder_gold_path}" if verbose
                       anystyle.ttx_to_refs(finder_gold_path)
                     else
                       anystyle.doc_to_refs(file_path)
                     end

          # write the intermediary .ttx file and ref-txt files
          if output_intermediaries
            refs_path = File.join(Path.refs, File.basename(file_path))
            puts " - Writing unparsed references to #{refs_path}" if verbose
            File.write(refs_path, refs_txt) unless File.exist?(refs_path) && !overwrite
            ttx_path = File.join(Path.ttx, "#{file_name}.ttx")
            unless File.exist?(ttx_path) && !overwrite
              ttx = anystyle.doc_to_ttx file_path
              puts " - Writing finder .ttx to #{ttx_path}" if verbose
              File.write(ttx_path, ttx)
            end
            finder_xml_path = File.join(Path.anystyle_finder_xml, "#{file_name}.xml")
            unless File.exist?(finder_xml_path) && !overwrite
              xml = anystyle.doc_to_xml file_path
              puts " - Writing finder .xml to #{finder_xml_path}" if verbose
              File.write(finder_xml_path, xml)
            end
          end

          # get xml from gold if a corresponding file exists, if not, by labelling the raw references
          parser_gold_path = !parser_gold_dir.nil? && File.join(parser_gold_dir, "#{file_name}.xml")
          xml = if parser_gold_path && File.exist?(parser_gold_path)
                  puts " - Using parser gold from #{parser_gold_path}" if verbose
                  File.read(parser_gold_path)
                else
                  anystyle.refs_to_xml(refs_txt)
                end

          # write the intermediary .xml file
          if output_intermediaries
            xml_path = File.join(Path.anystyle_parser_xml, "#{file_name}.xml")
            unless File.exist?(xml_path) && !overwrite
              puts " - Writing xml to #{xml_path}" if verbose
              File.write(xml_path, xml)
            end
          end

          # parse xml into dataset
          ds = anystyle.xml_to_wapiti xml

          # anystyle json representation of all found references
          unless File.exist?(anystyle_json_file) && !overwrite
            puts " - Writing anystyle json file to #{anystyle_json_file}" if verbose
            anystyle_json = anystyle.wapiti_to_hash ds
            File.write anystyle_json_file, JSON.pretty_generate(anystyle_json)
          end

          # csl
          csl_items = anystyle.wapiti_to_csl ds
          selected, rejected = anystyle.filter_invalid_csl_items csl_items
          puts " - Writing valid csl to #{csl_file}" if verbose
          File.write csl_file, JSON.pretty_generate(selected) unless !overwrite && File.exist?(csl_file)
          csl_rejected_file = File.join(Path.csl_rejected, "#{file_name}.json")
          unless !overwrite && File.exist?(csl_rejected_file)
            puts " - Writing rejected csl json to #{csl_rejected_file}" if verbose
            File.write csl_rejected_file, JSON.pretty_generate(rejected)
          end

          counter += 1
          break if limit && counter >= limit
        end
      end

      def write_statistics(verbose: false, type: 'reference')
        files = Dir.glob(File.join(Path.anystyle_json, '*.json'))
        unless verbose
          progressbar = ProgressBar.create(title: "Collecting statistics on #{type}s:",
                                           total: files.length,
                                           **::Workflow::Config.progress_defaults)
        end
        outfile = File.join(Path.stats, "#{type}-stats-#{Utils.timestamp}.csv")
        stats = []
        case type
        when 'reference'
          columns = %w[file journal year a_all a_rejected a_potential]
        when 'affiliation'
          columns = %w[file journal year]
        else
          raise "Type must be 'reference' or 'affiliation'"
        end

        # vendor data
        vendor_cache = ::Datasource.get_vendor_data
        vendors = vendor_cache.keys
        columns += vendors
        crossref_meta = vendor_cache['crossref']
        raise 'CrossRef metadata is required' unless crossref_meta

        stats.append columns
        puts "Analysing #{files.length} files..." if verbose
        files.each do |file_path|
          file_name = File.basename(file_path, '.json')
          doi = file_name.sub('_', '/')

          if verbose
            puts " - #{file_name}"
          else
            progressbar.increment unless verbose
          end

          crossref_item = crossref_meta[file_name]
          raise "No metadata for #{file_name}" if crossref_item.nil?

          year = get_csl_year(crossref_item)
          journal_abbrv = crossref_meta[file_name]['container-title'].scan(/\S+/).map { |w| w[0] }.join
          row = [file_name, journal_abbrv, year]

          case type
          when 'reference'
            # all found from anystyle json
            all = JSON.load_file(file_path)
            row.append(all.length)
            # rejected csl items
            rf_path = File.join Path.csl_rejected, "#{file_name}.json"
            row.append(File.exist?(rf_path) ? JSON.load_file(rf_path).length : nil)
            # potential csl items
            pf_path = File.join Path.csl, "#{file_name}.json"
            row.append(File.exist?(pf_path) ? JSON.load_file(pf_path).length : nil)
            # vendor data
            vendors.each do |vendor|
              ref = vendor_cache.dig(vendor, file_name)
              ref = ref.first if ref.is_a? Array
              ref = ref['reference'] if ref.is_a? Hash
              row.append(ref.is_a?(Array) ? ref.length : 0)
            end
          else
            # vendor data only
            vendors.each do |vendor|
              ref = vendor_cache.dig(vendor, file_name) || ref = vendor_cache.dig(vendor, doi)
              ref = refs.first if ref.is_a? Array
              num_affiliations = if ref.nil?
                                   puts " - #{vendor}: No entry for '#{file_name}'" if verbose
                                   0
                                 else
                                   author = ref['author'] || []
                                   case vendor
                                   when 'grobid'
                                     author.reject { |a| a[Datasource::Grobid::AUTHOR_AFFILIATIONS].nil? }
                                   when 'openalex'
                                     author.reject { |a| a[Datasource::OpenAlex::AUTHORS_AFFILIATION_LITERAL].empty? }
                                   when 'crossref'
                                     author.reject { |a| a['affiliation'].empty? }
                                   when 'dimensions'
                                     ref['custom'][Datasource::Dimensions::AUTHORS_AFFILIATIONS] || []
                                   when 'wos'
                                     ref['custom'][Datasource::Wos::AUTHORS_AFFILIATIONS] || []
                                   else
                                     raise "Unhandled vendor #{vendor}"
                                   end.length
                                 end
              row.append(num_affiliations)
            end
          end
          # write row
          stats.append(row)
        end
        File.write(outfile, stats.map(&:to_csv).join)
        puts "Data written to #{outfile}..."
      end
    end
  end
end
