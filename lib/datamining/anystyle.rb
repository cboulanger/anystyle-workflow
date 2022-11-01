# frozen_string_literal: true

require 'anystyle'
require 'rexml'

module Datamining
  class AnyStyle

    include ::AnyStyle::PDFUtils

    def initialize(finder_model_path=nil, parser_model_path=nil)
      ::AnyStyle.finder.load_model(finder_model_path || File.join(Dir.pwd, ENV['MODEL_PATH'], 'finder.mod').untaint)
      ::AnyStyle.parser.load_model(parser_model_path || File.join(Dir.pwd, ENV['MODEL_PATH'], 'parser.mod').untaint)
    end

    def extract_text(file_path)
      pdf_to_text(file_path)
    end

    def extract_references(file_path)
      refs = ::AnyStyle.finder.find(file_path, format: :references)[0]
      seqs = ::AnyStyle.parser.label refs.join("\n")
      xml = seqs.to_xml(indent:2)
      doc = REXML::Document.new xml.gsub(/\n */, '')
      doc = split_multiple_references(doc)
      Wapiti::Dataset.parse(doc)
    end

    def extract_refs_as_hash(file_path)
      ::AnyStyle.parser.format_hash(extract_references file_path)
    end

    def extract_refs_as_csl(file_path)
      csl = ::AnyStyle.parser.format_csl(extract_references file_path)
      fix_csl(csl)
    end

    def fix_csl(csl)

      csl.map! do |item|
        # we don't need "scripts" info, it's not CSL-JSON compliant anyways
        item.delete(:scripts)
        # fix missing/incorrect types
        item[:type] = 'book' if item[:type].nil? && (item[:issued] && !item['container-title'])
        if item[:editor] || item[:'publisher-place'] || item[:publisher] || item[:edition]
          item[:type] = if item[:'container-title'] || item[:author]
                          'chapter'
                        else
                          'book'
                        end
        end
        if item[:type].nil?
          item[:type]= "document"
        end
        item
      end

      # filter invalid items
      csl.select! { |item| item.size > 2 && item[:title] && item[:issued] }
      csl
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
