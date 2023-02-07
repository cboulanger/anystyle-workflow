# frozen_string_literal: true

require 'ruby-progressbar'
require 'json'
require 'csv'

module Workflow
  class Path
    class << self
      attr_accessor :base, :tmp, :models

      # path to the directory containing reference gold standard in
      # AnyStyle's native JSON format
      # @return [String]
      def gold_anystyle_json
        File.join(base, '0-gold-anystyle-json').untaint
      end

      # path to the directory containing reference parser gold standard in
      # XML format
      # @return [String]
      def gold_anystyle_xml
        File.join(base, '0-gold-anystyle-xml').untaint
      end

      # path to the directory containing reference finder gold standard in
      # the '.ttx' format
      # @return [String]
      def gold_anystyle_ttx
        File.join(base, '0-gold-anystyle-ttx').untaint
      end

      # path to the directory containing reference gold standard in
      # CSL-JSON format
      # @return [String]
      def gold_csl
        gold_anystyle_xml
        File.join(base, '0-gold-csl').untaint
      end

      # path to the directory containing reference gold standard in
      # TEI-XML format
      # @return [String]
      def gold_tei
        File.join(base, '0-gold-tei').untaint
      end

      # path to the directory containing metadata in various formats
      # @return [String]
      def metadata
        File.join(base, '0-metadata').untaint
      end

      # path to the directory containing the PDF files from which to
      # extract references
      # @return [String]
      def pdf
        File.join(base, '1-pdf').untaint
      end

      # path to the directory containing files with the raw text extracted from PDFs
      # or any kind of textual data from which to extract reference data
      # @return [String]
      def txt
        File.join(base, '2-txt').untaint
      end

      # path to the directory containing files with the extracted references
      # in CSL-JSON format
      # @return [String]
      def csl
        File.join(base, '3-csl').untaint
      end

      # path to the directory containing files with reference data in CSL-JSON format that
      # is not suitable for matching, most likely false positives. Only used for debugging.
      # @return [String]
      def csl_rejected
        File.join(base, '3-csl-rejected').untaint
      end

      # path to the directory containing files with the raw reference strings extracted from
      # the text files. Only used for debugging.
      # @return [String]
      def refs
        File.join(base, '3-refs').untaint
      end

      # path to the directory containing files with the tagged document text. Only used for debugging.
      # @return [String]
      def ttx
        File.join(base, '3-ttx').untaint
      end

      # path to the directory containing files with the anystyle xml
      # @return [String]
      def anystyle_xml
        File.join(base, '3-anystyle-xml').untaint
      end

      # path to the directory containing files with the extracted references
      # in AnyStyle's native JSON format
      # @return [String]
      def anystyle_json
        File.join(base, '3-anystyle-json').untaint
      end

      # path to the directory containing files with the CSL-JSON data that has been reconciled
      # against external datasources and is most likely correct.
      # @return [String]
      def csl_matched
        File.join(base, '4-csl-matched').untaint
      end

      # path to the directory containing files with the extracted reference data in
      # TEI-XML format. Used for evaluation
      # @return [String]
      def tei
        File.join(base, '4-tei').untaint
      end

      # path to the directory containing exported data
      # @return [String]
      def export
        File.join(base, '5-export').untaint
      end
    end
  end
end

Workflow::Path.base = File.join(File.dirname($PROGRAM_NAME), 'data').untaint
Workflow::Path.tmp = File.join(File.dirname($PROGRAM_NAME), 'tmp').untaint
Workflow::Path.models = File.join(File.dirname($PROGRAM_NAME), 'models').untaint
