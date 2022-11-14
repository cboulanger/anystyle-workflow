# frozen_string_literal: true

require './lib/workflow'

# Workflow.create_gold_csl
# Workflow.extract_text_from_pdf ENV['PDF_SOURCE_DIR']
# Workflow.extract_refs_from_text overwrite: false, output_intermediaries: true
Workflow.generate_csl_metadata datasources: ['openalex']
# Workflow.match_references
Workflow.extraction_stats
# Workflow.export_to_wos
# Workflow.export_to_neo4j
