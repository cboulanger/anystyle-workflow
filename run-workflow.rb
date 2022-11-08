# frozen_string_literal: true

require './lib/workflow'

# Workflow.create_gold_csl
# Workflow.extract_text_from_pdf
# Workflow.extract_refs_from_text overwrite: true, output_intermediaries: true
Workflow.extraction_stats
# Workflow.match_references
# Workflow.fetch_metadata
# Workflow.export_to_wos
# Workflow.export_to_neo4j
