# frozen_string_literal: true

require 'anystyle'
require 'rexml'

module Datamining
  class AnyStyle
    include ::AnyStyle::PDFUtils

    attr_accessor :output_intermediaries

    def initialize(finder_model_path = nil, parser_model_path = nil)
      ::AnyStyle.finder.load_model(finder_model_path || File.join(Dir.pwd, ENV['MODEL_PATH'], 'finder.mod').untaint)
      ::AnyStyle.parser.load_model(parser_model_path || File.join(Dir.pwd, ENV['MODEL_PATH'], 'parser.mod').untaint)
    end

    def extract_text(file_path)
      pdf_to_text(file_path)
    end

    def extract_references(file_path)
      # remove leading spaces
      File.write(file_path, File.read(file_path).split("\n").map(&:strip).join("\n"))
      refs = ::AnyStyle.finder.find(file_path, format: :references)[0]
      refs_txt = refs.map(&:strip).join("\n")
      if @output_intermediaries
        File.write("data/3-refs/#{File.basename(file_path)}", refs_txt)
        ttx = ::AnyStyle.finder.find(file_path, format: :wapiti)[0].to_s(tagged: true)
        File.write("data/3-ttx/#{"#{File.basename(file_path, '.txt')}.ttx"}", ttx)
      end
      seqs = ::AnyStyle.parser.label refs_txt
      xml_to_wapiti seqs.to_xml(indent: 2)
    end

    def xml_to_wapiti(xml)
      doc = REXML::Document.new xml.gsub(/\n */, '')
      doc = split_multiple_references(doc)
      Wapiti::Dataset.parse(doc)
    end

    def xml_to_csl(xml)
      fix_csl ::AnyStyle.parser.format_csl(xml_to_wapiti(xml))
    end

    def extract_refs_as_hash(file_path)
      ::AnyStyle.parser.format_hash(extract_references(file_path))
    end

    def extract_refs_as_csl(file_path)
      items = ::AnyStyle.parser.format_csl(extract_references(file_path))
      selected, rejected = filter_invalid_items(items)
      if output_intermediaries
        File.write("data/3-csl-rejected/#{File.basename(file_path, '.txt')}.json", JSON.pretty_generate(rejected))
      end
      fix_csl(selected)
    end

    def fix_csl(items)
      items.map do |item|
        # we don't need "scripts" info, it's not CSL-JSON compliant anyways
        item.delete(:scripts)
        # add citation data source
        item[:'citation-data-source'] = 'https://github.com/cboulanger/anystyle-workflow'
        # fix missing/incorrect types
        item[:type] = 'book' if item[:type].nil? && (item[:issued] && !item['container-title'])
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
    def filter_invalid_items(items)
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
