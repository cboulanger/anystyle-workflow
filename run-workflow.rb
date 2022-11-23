# frozen_string_literal: true
require './lib/bootstrap'

# Workflow::Workflow.create_gold_json
# Workflow::Workflow.extract_text_from_pdf ENV['PDF_SOURCE_DIR']
# Workflow::Workflow.extract_refs_from_text overwrite: false, output_intermediaries: true
# Workflow::Workflow.generate_csl_metadata datasources: ['openalex']
# Workflow::Workflow.match_references
# Workflow::Workflow.extraction_stats
# Workflow::Workflow.export_to_wos
# Workflow::Workflow.export_to_neo4j
Workflow::Converters.anystyle_json_to_tei_xml
# Workflow::Evaluation.run
