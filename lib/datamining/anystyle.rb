# frozen_string_literal: true

require 'anystyle'
require 'rexml'

module Datamining

  REGEX_FOOTNOTE_LABEL = /^ref/
  REGEX_BIBLIOGARPY_LABEL = /^bib/
  REGEX_INTEXT_LABEL = /^intext/
  REGEX_FOOTNOTE = /^([\d]{1,3})(\.?\s+)(\p{L}.{10,})$/iu
  REGEX_DASH_AT_LINE_END = /\p{Pd}$/
  REGEX_PUNC_OR_NUM_AT_LINE_END = /[\p{N}\p{P}]$/u

  class AnyStyle
    include ::AnyStyle::PDFUtils

    # it doesn't make sense to use an instance here if the underlying AnyStyle object is a singleton,
    # this needs to be refactored
    def initialize(finder_model_path: nil, parser_model_path: nil, use_default_models: false, verbose: false)
      AnyStyle.load_models(finder_model_path, parser_model_path) unless use_default_models
      @verbose = verbose
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

    # Given the path to a .txt file containing the raw text of the document, return
    # the line-tagged format that can be saved as a '.ttx' file
    # @param [String] file_path
    def doc_to_ttx(file_path)
      ::AnyStyle.finder.find(file_path, format: :wapiti)[0].to_s(tagged: true)
    end

    # Given a path to a .ttx file, return unparsed references as a newline-separated text
    # TODO: Insert newline between references / footnotes
    # @param [String] file_path
    def ttx_to_refs(file_path)
      lines = File.read(file_path).split("\n")
      footnote_lines = extract_lines(lines, REGEX_FOOTNOTE_LABEL)
      bibliography_lines = extract_lines(lines, REGEX_BIBLIOGARPY_LABEL)
      (split_paragraphs(footnote_lines, is_footnote: true) + split_paragraphs(bibliography_lines)).join("\n")
    end

    # Extracts the lines which of which the label matches the given regexpr
    # @param [Regexp] label_regex
    # @return [Array<String>]
    def extract_lines(lines, label_regex)
      is_label = false
      lines.reduce([]) do |refs, line|
        label, text = line.split("|", 2).map(&:strip)
        if label.match(label_regex)
          is_label = true
        elsif !label.strip.empty?
          is_label = false
        end
        refs << text if is_label
        refs
      end
    end

    # given an array of lines of text, split them into paragraphs using
    # some simple heuristics. this really should be done using a language model.
    # @param [Array<String>] lines
    # @param [Boolean] is_fotnote
    # @return [Array<String>]
    def split_paragraphs(lines, is_footnote: false)
      para = ""
      current_fn_number = 0
      lines.each_with_index.reduce([]) do |paras, (line, index)|
        line = line.strip
        # apply heuristics
        previous_ends_with_dash = index > 0 && lines[index - 1].strip.match?(REGEX_DASH_AT_LINE_END)
        previous_ends_with_num_punct = index > 0 && lines[index - 1].strip.match?(REGEX_PUNC_OR_NUM_AT_LINE_END)
        is_longer_than_previous = index > 0 && line.length - lines[index - 1].length > 3
        is_new_paragraph = if previous_ends_with_dash
                             false
                           elsif is_footnote
                             fn_number = line.match(REGEX_FOOTNOTE).to_a.dig(1)&.to_i
                             probably_next_fn_num = fn_number && (fn_number - current_fn_number).between?(1, 5)
                             if probably_next_fn_num
                                current_fn_number = fn_number
                                (is_longer_than_previous || previous_ends_with_num_punct)
                             end
                           else
                             is_longer_than_previous
                           end
        if is_new_paragraph
          paras << para if para != ""
          para = ""
        end
        para += self.prepare_unwrap_line(line)
        paras
      end
    end

    def prepare_unwrap_line(line)
      if line.match(REGEX_DASH_AT_LINE_END)
        line = line.gsub(REGEX_DASH_AT_LINE_END, '')
      else
        line += " "
      end
      line.strip
    end

    # Given the path to a .txt file containing the raw text of the document, return
    # an xml-annotated version that can be saved as an '.xml' file
    # This isn't working - need to file an issue
    # @param [String] file_path
    def doc_to_xml(file_path)
      raise 'not implemented because of wapiti bug'
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
      last_creator = {}
      items.map do |item|

        # we don't need "scripts" info, it's not CSL-JSON compliant anyways
        item.delete(:scripts)

        # rename non-csl fields as extensions
        [:signal, :note, :backref].each do |symb|
          unless item[symb].nil?
            item[('x-' + symb.to_s).to_sym] = item.delete(symb)
          end
        end

        # fix date fields
        [:accessed, :issued].each do |date_field|
          item[date_field] = { 'raw': item[date_field] } unless item[date_field].nil?
        end

        # fix missing/incorrect types

        # Assign 'book' if type is missing and specific conditions are met
        if item[:type].nil?
          item[:type] = 'book' if (item[:issued] && !item[:'container-title']) || item[:'collection-title']
        end

        # Assign 'chapter' or 'book' based on the presence of certain keys
        if item[:editor] || item[:'publisher-place'] || item[:publisher] || item[:edition]
          item[:type] = (item[:'container-title'] || (item[:author] && item[:editor])) ? 'chapter' : 'book'
        end

        # fallback type
        item[:type] = 'document' if item[:type].nil?

        # page info is a locator unless container-title is given
        if item[:'container-title'].nil? && item[:page]
          item[:'x-locator'] = item.delete(:page)
        end

        # add backreferences in name fields: Ders., Dies.,
        [:author, :editor].each do |key|
          unless (creator = item[key]&.first).nil?
            family = creator[:family].to_s.strip
            given = creator[:given].to_s.strip
            literal = creator[:literal].to_s.strip
            # switch family and given if family is empty
            if family.empty? && !given.empty?
              creator[:given] = family
              creator[:family] = given
            end
            name = [family,given,literal].reject { |n| n.empty? }.first
            if name
              if last_creator[key] && name.downcase.match(/^([Dd]ers\.?|[Dd]ies\.?|\p{Pd})$/)
                item[key][0] = last_creator[key]
                puts "   - Replaced #{key.to_s} '#{name}' with '#{last_creator[key]}'" if @verbose
              else
                last_creator[key] = creator
              end
            end
          end
        end

        # return item
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
