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

# Reconciliation/linking workflow
# Workflow::Workflow.match_references

# Export workflow
# Retrieve metadata for the files to be extracted
# Workflow::Reconciliation.generate_csl_metadata datasources: ['openalex']
# Workflow::Workflow.export_to_wos
# Workflow::Workflow.export_to_neo4j
