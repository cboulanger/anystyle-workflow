# frozen_string_literal: true

module Workflow
  class Extraction
    class << self
      # extracts text from PDF documents
      # @param [String] dir_path
      # @param [Boolean] overwrite
      def pdf_to_txt(dir_path = Path.pdf, overwrite: false)
        anystyle = Datamining::AnyStyle.new('./models/finder.mod', './models/parser.mod')
        files = Dir.glob(File.join(dir_path, '*.pdf')).map(&:untaint)
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

      # extracts reference information from the raw text of the documents
      # @param [Boolean] output_intermediaries If true, write intermediary file formats to disk for debugging purposes, will slow down extraction considerably
      # @param [Boolean] overwrite If true, overwrite existing files
      def txt_to_refs(overwrite: false, output_intermediaries: false)
        anystyle = Datamining::AnyStyle.new('./models/finder.mod', './models/parser.mod')
        files = Dir.glob(File.join(Path.txt, '*.txt')).map(&:untaint)
        progressbar = ProgressBar.create(title: 'Extracting references from text:',
                                         total: files.length,
                                         **Config.progress_defaults)
        files.each do |file_path|
          file_name = File.basename(file_path, '.txt')
          progressbar.increment

          # these are the main files we need for linking and evaluation
          csl_file = File.join Path.csl, "#{file_name}.json"
          anystyle_json_file = File.join Path.anystyle_json, "#{file_name}.json"

          # we can skip all remaining steps if they exist and we don't need the intermediaries
          next if File.exist?(csl_file) && File.exist?(anystyle_json_file) && !overwrite && !output_intermediaries

          # raw references
          refs_txt = anystyle.file_to_refs_txt(file_path)
          if output_intermediaries
            refs_path = File.join(Path.refs, File.basename(file_path))
            File.write(refs_path, refs_txt) unless File.exist?(refs_path) && !overwrite
            ttx_path = File.join(Path.ttx, "#{file_name}.ttx")
            unless File.exist?(ttx_path) && !overwrite
              ttx = anystyle.file_to_ttx file_path
              File.write(ttx_path, ttx)
            end
          end

          # label the raw references and convert to xml
          xml = anystyle.refs_txt_to_xml(refs_txt)
          if output_intermediaries
            xml_path = File.join(Path.anystyle_xml, "#{file_name}.xml")
            unless File.exist?(xml_path) && !overwrite
              File.write(xml_path, xml)
            end
          end

          # parse xml into dataset
          ds = anystyle.xml_to_wapiti xml

          # anystyle json representation of all found references
          unless File.exist?(anystyle_json_file) && !overwrite
            anystyle_json = anystyle.wapiti_to_hash ds
            File.write anystyle_json_file, JSON.pretty_generate(anystyle_json)
          end

          # csl
          csl_items = anystyle.wapiti_to_csl ds
          selected, rejected = anystyle.filter_invalid_csl_items csl_items

          File.write csl_file, JSON.pretty_generate(selected) unless !overwrite && File.exist?(csl_file)
          csl_rejected_file = File.join(Path.csl_rejected, "#{file_name}.json")
          File.write csl_rejected_file, JSON.pretty_generate(rejected) unless !overwrite && File.exist?(csl_rejected_file)
        end
      end



      def write_statistics
        files = Dir.glob(File.join(Path.anystyle_json, "*.json")).map(&:untaint)
        progressbar = ProgressBar.create(title: 'Collecting extraction statistics:',
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)
        outfile = File.join(Path.export, "extraction-stats-#{Utils.timestamp}.csv")
        stats = []
        columns = %w[file journal year a_all a_rejected a_potential]

        # vendor data
        vendors = %w[crossref dimensions openalex wos]
        columns += vendors
        vendor_cache = {}
        vendors.each do |vendor|
          vendor_path = File.join Path::metadata, "#{vendor}.json"
          vendor_cache[vendor] = (JSON.load_file vendor_path if File.exist? vendor_path)
        end
        crossref_meta = vendor_cache['crossref']
        raise 'CrossRef metadata is required' unless crossref_meta

        stats.append columns
        files.each do |file_path|
          progressbar.increment
          file_name = File.basename(file_path, '.json')
          begin
            year = crossref_meta[file_name]['issued']['date-parts'].first.first
            # this is not generalizable
            journal = case crossref_meta[file_name]['container-title']
                      when /^Zeitschrift/
                        'zfrsoz'
                      else
                        'jls'
                      end
          rescue StandardError
            $logger.error "Problem parsing year/journal for #{file_name}"
            next
          end
          row = [file_name, journal, year]
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
            refs = vendor_cache.dig(vendor, file_name)
            refs = refs.first if refs.is_a? Array
            refs = refs['reference'] if refs.is_a? Hash
            row.append(refs.is_a?(Array) ? refs.length : 0)
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
