# frozen_string_literal: true

require './lib/bootstrap'
require 'fileutils'
require 'pathname'
require 'json'

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

HELP = \
  <<~TEXT.freeze
    Usage:
    run-workflow.rb <command>
    Commands:
    extract
        [--model-dir /to/model/dir]
        [--write-files]                   write all intermediary files for inspection purposes
        [--overwrite]
        [--use-(parser|finder)-gold-from /path/to/gold]
                                          overwrite output files with existing gold files of the same
                                          name to improve quality
        --from-(text|pdf) /to/text/dir'   Use either text or pdf as source - must be last argument
    check
        [--include-default]
        [--fix]                           add missing end-of-line spaces
        [--write-files]                   write the re-labelled gold files to its output folder
        [--parser|--finder]               check only the given model, both if omitted
        [--gold-dir /path/to/gold']       path to the dir containing the gold to be checked, must be last argument
                                          if omitted, the data/0-gold-* folders are used
    evaluate

    General parameters:
    --verbose                             output additional information
    --clean                               clean output directories before running command

  TEXT

puts HELP if ARGV.include?('--help') || ARGV.length.zero?

if ARGV.include? '--clean'
  cleanup_paths.each do |dir_path|
    puts "Cleaning up #{dir_path}..."
    Dir.glob("#{dir_path}/*").select { |f| File.file?(f) && !File.basename(f).start_with?('.') }.each do |file|
      FileUtils.rm(file)
    end
  end
end

# Extraction workflow
if ARGV.include? 'extract'
  pdf_dir = ARGV.last if ARGV.include? '--from-pdf'
  text_dir = ARGV.last if ARGV.include? '--from-text'

  arg_name = '--use-parser-gold-from'
  parser_gold_dir = ARGV[(ARGV.index(arg_name) + 1)] if ARGV.include? arg_name

  arg_name = '--use-finder-gold-from'
  finder_gold_dir = ARGV[(ARGV.index(arg_name) + 1)] if ARGV.include? arg_name

  arg_name = '--model-dir'
  model_dir = ARGV[(ARGV.index(arg_name) + 1)] if ARGV.include? arg_name
  
  if ARGV.include? '--verbose'
    puts \
    <<~TEXT.freeze
    pdf_dir:          #{pdf_dir}
    text_dir:         #{text_dir}
    parser_gold_dir:  #{parser_gold_dir}
    finder_gold_dir:  #{finder_gold_dir}
    model_dir:        #{model_dir}
    TEXT
  end

  if !pdf_dir.nil?
    Workflow::Extraction.pdf_to_txt pdf_dir
  elsif text_dir.nil?
    raise RuntimeError('You have to provide either a PDF or text source dir')
  end

  Workflow::Extraction.doc_to_csl_json(
    source_dir: text_dir,
    overwrite: ARGV.include?('--overwrite'),
    output_intermediaries: ARGV.include?('--write-files'),
    model_dir:,
    parser_gold_dir:,
    finder_gold_dir:,
    verbose: ARGV.include?('--verbose')
  )
  Workflow::Extraction.write_statistics
end

if ARGV.include? 'check'
  maybe_path = ARGV.last
  if ARGV.include?('--gold-dir') && !maybe_path.nil?
    parser_gold_path = File.join(maybe_path.untaint, 'parser')
    finder_gold_path = File.join(maybe_path.untaint, 'finder')
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
    if ARGV.include? '--write-files'
      Dir.glob("#{finder_gold_path}/*.ttx").each do |file_path|
        copy_of_gold_path = File.join(Workflow::Path.ttx, "#{File.basename(file_path, '.ttx')}-gold.ttx").untaint
        FileUtils.copy(file_path, copy_of_gold_path)
        out_path = File.join(Workflow::Path.ttx, File.basename(file_path)).untaint
        puts "- #{File.basename(file_path)}" if ARGV.include? '--verbose'
        File.write(out_path, Workflow::Check.relabel(file_path))
      end
    end
    Workflow::Check.run finder_gold_path, outfile_name: 'check-custom-finder'
  end

  if ARGV.include?('--parser') || !ARGV.include?('--finder')
    puts "Evaluating parser gold at #{parser_gold_path}..."
    if ARGV.include? '--write-files'
      Dir.glob("#{parser_gold_path}/*.xml").each do |file_path|
        copy_of_gold_path = File.join(Workflow::Path.anystyle_xml,
                                      "#{File.basename(file_path, '.xml')}-gold.xml").untaint
        FileUtils.copy(file_path, copy_of_gold_path)
        out_path = File.join(Workflow::Path.anystyle_xml, File.basename(file_path)).untaint
        puts "- #{File.basename(file_path)}" if ARGV.include? '--verbose'
        File.write(out_path, Workflow::Check.relabel(file_path))
      end
    end
    Workflow::Check.run parser_gold_path, outfile_name: 'check-custom-parser'
  end
end

if ARGV.include? 'evaluate'
  # Evaluation workflow
  # Workflow::Evaluation.create_eval_data
  Workflow::Evaluation.run
end

# Reconciliation/linking workflow
# Workflow::Workflow.match_references

# Export workflow
# Retrieve metadata for the files to be extracted
# Workflow::Reconciliation.generate_csl_metadata datasources: ['openalex']
# Workflow::Workflow.export_to_wos
# Workflow::Workflow.export_to_neo4j