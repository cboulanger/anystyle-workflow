# frozen_string_literal: true

module Workflow
  class Converters
    class << self
      def anystyle_json_to_tei_xml
        json_to_tei = PyCall.import_module('json_to_tei_anystyle')
        files = Dir.glob('data/0-gold-anystyle-json/*.json').map(&:untaint)
        files.each do |csl_file|
          tei_file = "data/0-gold-tei/#{File.basename(csl_file, '.json')}.xml"
          json_to_tei.anystyle_parser csl_file, tei_file
        end
      end
    end
  end
end
