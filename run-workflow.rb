# frozen_string_literal: true

require './lib/bootstrap'
require 'fileutils'
require 'pathname'

# cleanup
cleanup_paths = [
  Workflow::Path.gold_anystyle_json,
  Workflow::Path.gold_csl,
  Workflow::Path.gold_tei,
  Workflow::Path.txt,
  Workflow::Path.ttx,
  Workflow::Path.refs,
  Workflow::Path.anystyle_json,
  Workflow::Path.anystyle_xml,
  Workflow::Path.csl,
  Workflow::Path.csl_rejected,
  Workflow::Path.csl_matched,
  Workflow::Path.tei
]

if ARGV.include? '--clean'
  cleanup_paths.each do |dir_path|
    puts "Cleaning up #{dir_path}..."
    Dir.glob("#{dir_path}/*").select { |f| File.file?(f) && !File.basename(f).start_with?('.') }.each do |file|
      FileUtils.rm(file)
    end
  end
end

if ARGV.include? 'extract'
  # Extraction workflow
  Workflow::Extraction.pdf_to_txt ENV['PDF_SOURCE_DIR']
  Workflow::Extraction.txt_to_refs(
    overwrite: ARGV.include?('--overwrite'),
    output_intermediaries: ARGV.include?('--debug')
  )
  Workflow::Extraction.write_statistics
end

if ARGV.include? 'evaluate'
  # Evaluation workflow
  # Workflow::Evaluation.create_eval_data
  Workflow::Evaluation.run
end

if ARGV.include? 'check'
  if ENV['GOLD_PATH']
    parser_gold_path = File.join(ENV['GOLD_PATH'], 'parser')
    finder_gold_path = File.join(ENV['GOLD_PATH'], 'finder')
  else
    parser_gold_path = Workflow::Path.gold_anystyle_xml
    finder_gold_path = Workflow::Path.gold_anystyle_ttx
  end

  if ARGV.include? '--include-default'
    puts "Using default model at at #{AnyStyle.parser.model.path}:"

    puts "Evaluating finder gold at #{finder_gold_path}..."
    Workflow::Check.run finder_gold_path, outfile_name: 'check-default-finder'

    puts "Evaluating parser gold at #{parser_gold_path} ..."
    Workflow::Check.run parser_gold_path, outfile_name: 'check-default-parser'
  end

  if ARGV.include? '--fix'
    Dir.glob("#{finder_gold_path}/*.ttx").each do |file_path|
      content = File.read(file_path.untaint)
      lines = content.split("\n").map do |line|
        (line.end_with? '|') ? "#{line} " : line
      end
      File.write(file_path, lines.join("\n"))
    end
  end

  Datamining::AnyStyle.load_models
  puts "Using custom model at at #{AnyStyle.parser.model.path}:"

  if ARGV.include?('--finder') || !ARGV.include?('--parser')
    puts "Evaluating finder gold at #{finder_gold_path}..."
    if ARGV.include? '--parse'
      Dir.glob("#{finder_gold_path}/*.ttx").each do |file_path|
        copy_of_gold_path = File.join(Workflow::Path.ttx, "#{File.basename(file_path, '.ttx')}-gold.ttx").untaint
        FileUtils.copy(file_path, copy_of_gold_path)
        out_path = File.join(Workflow::Path.ttx, File.basename(file_path)).untaint
        puts "- #{File.basename(file_path)}" if ARGV.include? "--verbose"
        File.write(out_path, Workflow::Check.relabel(file_path))
      end
    end
    Workflow::Check.run finder_gold_path, outfile_name: 'check-custom-finder'
  end

  if ARGV.include?('--parser') || !ARGV.include?('--finder')
    puts "Evaluating parser gold at #{parser_gold_path}..."
    if ARGV.include? '--parse'
      Dir.glob("#{parser_gold_path}/*.xml").each do |file_path|
        copy_of_gold_path = File.join(Workflow::Path.anystyle_xml,
                                      "#{File.basename(file_path, '.xml')}-gold.xml").untaint
        FileUtils.copy(file_path, copy_of_gold_path)
        out_path = File.join(Workflow::Path.anystyle_xml, File.basename(file_path)).untaint
        puts "- #{File.basename(file_path)}" if ARGV.include? "--verbose"
        File.write(out_path, Workflow::Check.relabel(file_path))
      end
    end
    Workflow::Check.run parser_gold_path, outfile_name: 'check-custom-parser'
  end

end

# Reconciliation/linking workflow
# Workflow::Workflow.match_references

# Export workflow
# Retrieve metadata for the files to be extracted
# Workflow::Reconciliation.generate_csl_metadata datasources: ['openalex']
# Workflow::Workflow.export_to_wos
# Workflow::Workflow.export_to_neo4j
