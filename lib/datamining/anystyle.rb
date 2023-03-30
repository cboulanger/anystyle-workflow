# frozen_string_literal: true

require 'anystyle'
require 'rexml'

module Datamining

  REFERENCE_LABEL_REGEX = /^(ref|bib|intext)/

  class AnyStyle
    include ::AnyStyle::PDFUtils

    # it doesn't make sense to use an instance here if the underlying AnyStyle object is a singleton,
    # this needs to be refactored
    def initialize(finder_model_path: nil, parser_model_path: nil, use_default_models: false)
      AnyStyle.load_models(finder_model_path, parser_model_path) unless use_default_models
    end

    # loads the models, defaults to loading from models dir
    def self.load_models(finder_model_path = nil, parser_model_path = nil)
      finder_model_path ||= File.join(Workflow::Path.models, 'finder.mod')
      parser_model_path ||= File.join(Workflow::Path.models, 'parser.mod')
      ::AnyStyle.finder.load_model(finder_model_path)
      ::AnyStyle.parser.load_model(parser_model_path)
    end

    # Given a path to a .txt file, return the unparsed references as a newline-separated text
    # @param [String] file_path
    def doc_to_refs(file_path)
      refs = ::AnyStyle.finder.find(file_path, format: :references)[0]
      refs.map(&:strip).join("\n")
    end

    # Given a path to a .ttx file, return unparsed references as a newline-separated text
    # @param [String] file_path
    def ttx_to_refs(file_path)
      in_ref = false
      File.read(file_path).split("\n").reduce([]) do |refs, line|
        label, text = line.split("|", 2)
        if label.match(REFERENCE_LABEL_REGEX)
          in_ref = true
        elsif !label.strip.empty?
          in_ref = false
        end
        refs << text.strip if in_ref
        refs
      end.join("\n")
    end

    # Given the path to a .txt file containing the raw text of the document, return
    # the line-tagged format that can be saved as a '.ttx' file
    # @param [String] file_path
    def doc_to_ttx(file_path)
      ::AnyStyle.finder.find(file_path, format: :wapiti)[0].to_s(tagged: true)
    end

    # Given the path to a .txt file containing the raw text of the document, return
    # an xml-annotated version that can be saved as an '.xml' file
    # This isn't working - need to file an issue
    # @param [String] file_path
    def doc_to_xml(file_path)
      #::AnyStyle.finder.find(file_path, format: :wapiti)[0].to_xml()
    end

    # Given the unparsed references as a newline-separated text, return the tagged
    # xml-tagged format
    # @param [string] refs_txt
    def refs_to_xml(refs_txt)
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
    # @param [Array<Hash>] items
    def fix_csl(items)
      last_author = nil
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

        # fix backreferences: Ders., Dies.,
        author = item.dig('author', 0, 'family')
        if last_author && author && author.match(/^(ders\.?|dies\.?|\p{Pd}$)/i)
          item['author'] = last_author
        else
          last_author = item['author']
        end
        # do editor, too
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
