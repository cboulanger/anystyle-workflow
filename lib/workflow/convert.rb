# frozen_string_literal: true

module Workflow
  class Convert
    class << self
      # convert the anystyle JSON files in in_dir to TEI XML files in out_dir
      # @param [String] in_dir
      # @param [String] out_dir
      def anystyle_json_to_tei_xml(in_dir, out_dir, overwrite: false)
        json_to_tei = PyCall.import_module('json_to_tei_anystyle')
        files = Dir.glob(File.join(in_dir, '*.json')).map(&:untaint)
        files.each do |csl_file|
          tei_file = File.join(out_dir, "#{File.basename(csl_file, '.json')}.xml")
          next if File.exist?(tei_file) && !overwrite

          begin
            json_to_tei.anystyle_parser csl_file, tei_file
          rescue StandardError => e
            puts e.message.to_s
          end
        end
      end

      # convert the anystyle XML files in in_dir to CSL-JSON files in out_dir
      # @param [String] in_dir
      # @param [String] out_dir
      def anystyle_xml_to_csl_json(in_dir, out_dir, overwrite: false)
        anystyle = Datamining::AnyStyle.new
        files = Dir.glob(File.join(in_dir, '*.xml')).map(&:untaint)
        files.each do |file_path|
          file_name = File.basename file_path, '.xml'
          outfile = File.join(out_dir, "#{file_name}.json")
          next if File.exist?(outfile) && !overwrite

          xml = File.read file_path
          ds = anystyle.xml_to_wapiti xml
          csl = anystyle.wapiti_to_csl ds
          File.write(outfile, JSON.pretty_generate(csl))
        end
      end

      # given a hash in the anystyle native annotation format, add a type information
      def add_type_to_anystyle_hash(item)
        unless item[:type]
          item[:type] = if item[:'container-title']
                          'chapter'
                        elsif item[:journal]
                          'article-journal'
                        elsif item[:editor] || item[:publisher] || item[:location] || item[:edition]
                          'book'
                          # more cases as needed
                        else
                          # fallback
                          'book'
                        end
        end
        item
      end

      # convert the anystyle XML sequence dataset files in in_dir to amystyle JSON files in out_dir,
      # separating multiple references into separate items
      # @param [String] in_dir
      # @param [String] out_dir
      def anystyle_xml_to_anystyle_json(in_dir, out_dir, overwrite: false)
        anystyle = Datamining::AnyStyle.new
        files = Dir.glob(File.join(in_dir, '*.xml')).map(&:untaint)
        files.each do |file_path|
          file_name = File.basename file_path, '.xml'
          outfile = File.join(out_dir, "#{file_name}.json")
          next if File.exist?(outfile) && !overwrite

          xml = File.read file_path
          ds = anystyle.xml_to_wapiti xml
          hashes = anystyle.wapiti_to_hash(ds).map { |item| add_type_to_anystyle_hash item }
          File.write(outfile, JSON.pretty_generate(hashes))
        end
      end
    end
  end
end
