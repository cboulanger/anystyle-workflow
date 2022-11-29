# frozen_string_literal: true

require 'anystyle'
require 'rexml'

module Datamining
  class AnyStyle
    include ::AnyStyle::PDFUtils

    def initialize(finder_model_path = nil, parser_model_path = nil)
      unless ENV['MODEL_PATH'].nil? || ENV['MODEL_PATH'].empty?
        finder_model_path ||= File.join(Dir.pwd, ENV['MODEL_PATH'], 'finder.mod').untaint
        parser_model_path ||= File.join(Dir.pwd, ENV['MODEL_PATH'], 'parser.mod').untaint
      end
      ::AnyStyle.finder.load_model(finder_model_path) if finder_model_path
      ::AnyStyle.parser.load_model(parser_model_path) if parser_model_path
    end

    # Given a file path, return the raw references as a newline-separated text
    def file_to_refs_txt(file_path)
      refs = ::AnyStyle.finder.find(file_path, format: :references)[0]
      refs.map(&:strip).join("\n")
    end

    def file_to_ttx(file_path)
      ::AnyStyle.finder.find(file_path, format: :wapiti)[0].to_s(tagged: true)
    end

    def refs_txt_to_xml(refs_txt)
      seqs = ::AnyStyle.parser.label refs_txt
      seqs.to_xml(indent: 2)
    end

    # parses an xml string containing a dataset of reference sequences
    # into a wapiti tagged dataset. If a sequence contains several references,
    # they will be split into separate sequences.
    def xml_to_wapiti(xml)
      doc = REXML::Document.new xml.gsub(/\n */, '')
      doc = split_multiple_references(doc)
      Wapiti::Dataset.parse(doc)
    end

    # Converts dataset into an array of hashes in the CSL-JSON schema, fixing
    # problems not handled by the anystyle normalizer
    # @param [Wapiti::Dataset] ds
    # @return [Array]
    def wapiti_to_csl(ds)
      fix_csl ::AnyStyle.parser.format_csl(ds)
    end

    # Converts an AnyStyle parser xml training document into an array of hashes.
    # Splits up multiple references that occur in a sequence.
    # @param [Wapiti::Dataset] ds
    # @return [Array]
    def wapiti_to_hash(ds)
      ::AnyStyle.parser.format_hash(ds)
    end

    # fixes problems in a CSL-JSON hash
    def fix_csl(items)
      items.map do |item|
        # we don't need "scripts" info, it's not CSL-JSON compliant anyways
        item.delete(:scripts)
        # fix missing/incorrect types
        item[:type] = 'book' if item[:type].nil? && (item[:issued] && !item[:'container-title'])
        if item[:editor] || item[:'publisher-place'] || item[:publisher] || item[:edition]
          item[:type] = if item[:'container-title'] || item[:author]
                          'chapter'
                        else
                          'book'
                        end
        end
        item[:type] = 'document' if item[:type].nil?
        item
      end
    end

    # Removes items that appear to be false positives
    def filter_invalid_csl_items(items)
      selected = []
      rejected = []
      items.each do |item|
        if item.size > 2 && item[:title] && item[:issued]
          selected.append item
        else
          rejected.append item
        end
      end
      [selected, rejected]
    end

    # split multiple references in sequences, using a very naive heuristic
    # @param [REXML::Document] doc
    # @return [REXML::Document]
    def split_multiple_references(doc)
      REXML::XPath.each(doc, '//sequence') do |sequence|
        segs = {}
        curr_sequence = sequence
        sequence.elements.each do |segment|
          seg_name = segment.name
          # this assumes that a new reference sequence starts with author, signal or editor,
          # which should cover most cases but will certainly fail sometimes
          # do we have a minimally complete reference already?
          has_creator_title_date = (segs[:author] || segs[:editor]) && segs[:title] && segs[:date]
          if %w[author signal editor].include?(seg_name) && has_creator_title_date
            # add new sequence
            curr_sequence = doc.root.add_element 'sequence'
            segs = {}
          end
          if curr_sequence != sequence
            # move segment to new sequence
            sequence.delete_element segment
            curr_sequence.add_element segment
          end
          segs[seg_name.to_sym] = true
        end
      end
      doc
    end
  end
end
