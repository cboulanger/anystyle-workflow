# frozen_string_literal: true

require './lib/bootstrap'

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
  #Workflow::Evaluation.create_eval_data
  Workflow::Evaluation.run
end

if ARGV.include? 'check'
  parser_gold_path = Workflow::Path.gold_anystyle_xml
  finder_gold_path = Workflow::Path.gold_anystyle_ttx

  puts "Using default model at at #{AnyStyle.parser.model.path}:"

  puts "Checking finder gold at #{finder_gold_path}..."
  Workflow::Check.run finder_gold_path, outfile_name: "check-default-finder"

  puts "Checking parser gold at #{parser_gold_path} ..."
  Workflow::Check.run parser_gold_path, outfile_name: "check-default-parser"

  Datamining::AnyStyle.load_models
  puts "Using custom model at at #{AnyStyle.parser.model.path}:"

  puts "Checking finder gold at #{finder_gold_path}..."
  Workflow::Check.run finder_gold_path, outfile_name: "check-custom-finder"

  puts "Checking parser gold at #{parser_gold_path}..."
  Workflow::Check.run parser_gold_path, outfile_name: "check-custom-parser"

end

# Reconciliation/linking workflow
# Workflow::Workflow.match_references

# Export workflow
# Retrieve metadata for the files to be extracted
# Workflow::Reconciliation.generate_csl_metadata datasources: ['openalex']
# Workflow::Workflow.export_to_wos
# Workflow::Workflow.export_to_neo4j
