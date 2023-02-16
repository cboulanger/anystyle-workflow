# frozen_string_literal: true

require 'fileutils'
require 'json'

module Workflow
  class Evaluation
    class << self

      def parser_name
        'AnyStyle'
      end

      def gold_dir
        File.join(Path.tmp, 'gold')
      end

      def output_dir
        File.join(Path.tmp, 'output')
      end

      def output_dir_anystyle
        File.join(output_dir, parser_name)
      end

      def create_eval_data
        puts 'Generating gold TEI'
        Convert.anystyle_xml_to_anystyle_json Path.gold_anystyle_xml, Path.gold_anystyle_json, overwrite: true
        Convert.anystyle_xml_to_csl_json Path.gold_anystyle_xml, Path.gold_csl, overwrite: true
        Convert.anystyle_json_to_tei_xml Path.gold_anystyle_json, Path.gold_tei, overwrite: true
        puts 'Generating extraction output TEI'
        Convert.anystyle_json_to_tei_xml Path.anystyle_json, Path.tei
        puts 'Creating evaluation data'
        FileUtils.mkdir_p gold_dir
        FileUtils.mkdir_p output_dir_anystyle
        gold_files = Dir.glob(File.join(Path.gold_tei, '*.xml'))
        gold_files.each do |gold_file_path|
          FileUtils.copy gold_file_path, gold_dir
          FileUtils.copy File.join(Path.tei, File.basename(gold_file_path)), output_dir_anystyle
        end
      end

      Utils.timestamp

      def run
        puts 'Running evaluation'
        py_eval = PyCall.import_module('get_evaluation_metrics')
        # result = py_eval.get_parser_data([parser_dir], gold_dir, output_dir)
        result = Utils.py_to_rb py_eval.get_parser_data([parser_name], gold_dir, output_dir, diagnostic: true)
        outfile = File.join(Path.export, "evaluation-stats-#{Utils.timestamp}.json")
        File.write outfile, JSON.pretty_generate(result)
        puts "Results written to #{File.realpath outfile}"
      end
    end
  end
end
