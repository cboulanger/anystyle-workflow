# frozen_string_literal: true
require 'fileutils'

module Workflow
  class Extraction
    class << self
      include ::Format::CSL

      # extracts text from PDF documents
      # @param [String, nil] source_dir Defaults to workflow pdf dir
      # @param [String, nil] target_dir Defaults to workflow txt dir
      # @param [Boolean] overwrite
      def pdf_to_txt(source_dir = Path.pdf, target_dir= Path.txt, overwrite: false)
        anystyle = Datamining::AnyStyle.new
        files = Dir.glob(File.join(source_dir, '*.pdf'))
        progressbar = ProgressBar.create(title: 'Extracting text from PDF:',
                                         total: files.length,
                                         **Config.progress_defaults)
        files.each do |file_path|
          file_name = File.basename(file_path, '.pdf')
          outfile = File.join(target_dir, "#{file_name}.txt")
          progressbar.increment
          next if !overwrite && File.exist?(outfile)

          text = anystyle.pdf_to_text(file_path)
          File.write(outfile, text)
        end
      end

      def mkdir(file_path)
        unless Dir.exist? File.dirname(file_path)
          FileUtils.mkdir_p File.dirname(file_path)
        end
        file_path
      end

      # Extracts reference information from the raw text of the documents and writes the corresponding output files
      # @param [String,Array<String>] source If String, directory containing the text files.
      #   If array, list of files to extract from. Defaults to data/2-txt
      # @param [Boolean] output_intermediaries If true, write intermediary file formats to disk for debugging purposes, will slow down extraction considerably
      # @param [Boolean] overwrite If true, overwrite existing files
      # @param [String, nil] model_dir
      # @param [String, nil] parser_gold_dir
      # @param [String, nil] finder_gold_dir
      # @param [Integer, nil] limit
      # @param [String, nil] prefix The prefix is added to the output files. can contain a directory path
      def doc_to_csl_json(source: Path.txt,
                          model_dir: Path.models,
                          overwrite: false,
                          output_intermediaries: false,
                          parser_gold_dir: nil,
                          finder_gold_dir: nil,
                          prefix: '',
                          verbose: false,
                          limit: nil)
        files = case source
                when String
                  raise "Invalid directory '#{source}'" unless Dir.exist? source
                  Dir.glob(File.join(source, '*.txt'))
                when Array
                  source.each do |f|
                    raise "File does not exist: '#{f}'" unless File.exist? f
                    raise "File does not end in '.txt': '#{f}'" unless f.end_with? '.txt'
                  end
                else
                  raise 'Invalid `source` argument'
                end
        finder_model_path = File.join model_dir, 'finder.mod'
        parser_model_path = File.join model_dir, 'parser.mod'
        anystyle = Datamining::AnyStyle.new(finder_model_path:, parser_model_path:)

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
          csl_path = mkdir(File.join Path.csl, "#{prefix}#{file_name}.json")
          anystyle_json_path = mkdir(File.join Path.anystyle_json, "#{prefix}#{file_name}.json")

          # we can skip all remaining steps if they exist and we don't need the intermediaries
          if File.exist?(csl_path) && File.exist?(anystyle_json_path) && !overwrite && !output_intermediaries
            puts ' - Output files exist, skipping...' if verbose
            next
          end

          # get untagged references from gold if exists, otherwise run finder parsing
          finder_gold_path = !finder_gold_dir.nil? && File.join(finder_gold_dir, "#{file_name}.ttx")
          refs_txt = if finder_gold_path && File.exist?(finder_gold_path)
                       puts " - Using finder gold from #{finder_gold_path}" if verbose
                       anystyle.ttx_to_refs(finder_gold_path)
                     else
                       # anystyle.doc_to_refs(file_path)
                       # parsing the ttx so that we can use alternative reference labels
                       ttx_path = mkdir(File.join(Path.ttx, "#{prefix}#{file_name}.ttx"))
                       unless File.exist?(ttx_path) && !overwrite
                         ttx = anystyle.doc_to_ttx file_path
                         puts " - Writing finder .ttx to #{ttx_path}" if verbose
                         File.write ttx_path, ttx
                       end
                       anystyle.ttx_to_refs(ttx_path)
                     end

          # write the intermediary files
          if output_intermediaries
            refs_path = mkdir(File.join(Path.refs, "#{prefix}#{file_name}.txt"))
            puts " - Writing unparsed references to #{refs_path}" if verbose
            File.write(refs_path, refs_txt) unless File.exist?(refs_path) && !overwrite
            # finder_xml_path = File.join(Path.anystyle_finder_xml, "#{file_name}.xml")
            # unless File.exist?(finder_xml_path) && !overwrite
            #   xml = anystyle.doc_to_xml file_path
            #   puts " - Writing finder .xml to #{finder_xml_path}" if verbose
            #   File.write(finder_xml_path, xml)
            # end
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
            xml_path = mkdir(File.join(Path.anystyle_parser_xml, "#{prefix}#{file_name}.xml"))
            unless File.exist?(xml_path) && !overwrite
              puts " - Writing xml to #{xml_path}" if verbose
              File.write(xml_path, xml)
            end
          end

          # parse xml into dataset
          ds = anystyle.xml_to_wapiti xml

          # anystyle json representation of all found references
          unless File.exist?(anystyle_json_path) && !overwrite
            puts " - Writing anystyle json file to #{anystyle_json_path}" if verbose
            anystyle_json = anystyle.wapiti_to_hash ds
            File.write anystyle_json_path, JSON.pretty_generate(anystyle_json)
          end

          # csl
          csl_items = anystyle.wapiti_to_csl ds
          selected, rejected = anystyle.filter_invalid_csl_items csl_items
          puts " - Writing valid csl to #{csl_path}" if verbose
          File.write csl_path, JSON.pretty_generate(selected) unless !overwrite && File.exist?(csl_path)
          csl_rejected_file = mkdir(File.join(Path.csl_rejected, "#{prefix}#{file_name}.json"))
          unless !overwrite && File.exist?(csl_rejected_file)
            puts " - Writing rejected csl json to #{csl_rejected_file}" if verbose
            File.write csl_rejected_file, JSON.pretty_generate(rejected)
          end

          counter += 1
          break if limit && counter >= limit
        end
      end
    end
  end
end
