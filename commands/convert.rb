# frozen_string_literal: true

require 'gli'

module AnyStyleWorkflowCLI
  extend GLI::App
  desc "Convert between different formats"
  command :convert do |c|
    c.flag [:x, 'from-xml'], type: String, desc: 'Path to anystyle parser xml file or directory containing such files'
    c.switch [:r, :recursive], desc: 'If input path is a directory, recurse into subfolders'
    c.flag [:c, 'to-csl'], type: String, desc: 'Path to output file in CSL-JSON format'
    c.switch ['add-file-id'], desc: 'Add the file name as id for the source of the citation'
    c.switch ['add-raw-citation'], desc: 'Add the file name as id for the source of the citation'

    c.action do |global_options, options, args|

      # input
      input_path = options['from-xml']
      if File.file? input_path
        files = [input_path]
      elsif File.directory? input_path
        if options[:recursive]
          files = Dir.glob(File.join(input_path, '**', '*.xml'))
        else
          files = Dir.glob(File.join(input_path, '*.xml'))
        end
      else
        raise 'Invalid input path'
      end

      mapped_ds = {}
      as = Datamining::AnyStyle.new(use_default_models:true)
      files.each do |file_path|
        xml = File.read(file_path, encoding:'utf-8').gsub('­', '')
        mapped_ds[file_path] = as.xml_to_wapiti(xml)
      end

      raise "No input given" if mapped_ds.empty?

      # output
      output_path = options['to-csl']
      raise 'No output path given' if output_path.nil?
      json = []
      mapped_ds.each do |file_path, ds|
        raw_citations = ds.to_txt(separator: "\n\n").split("\n\n")
        as.wapiti_to_csl(ds).each_with_index do |item, index|
          item['x-citation-source-id'] = File.basename(file_path, File.extname(file_path)) if options['add-file-id']
          item['x-raw-citation'] = raw_citations[index] if options['add-raw-citation']
          json.append item
        end
      end
      csl_json = JSON.pretty_generate(json)
      File.write(output_path, csl_json, encoding:'utf-8')

    end
  end
end
