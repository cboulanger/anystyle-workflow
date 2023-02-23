# frozen_string_literal: true

# require 'damerau-levenshtein'
# require 'text/levenshtein'
require 'matrix'

module Format
  # class to create a file compatible to the WOS plain text export format
  # from an array of CSL-JSON data
  # @see https://images.webofknowledge.com/images/help/WOS/hs_wos_fieldtags.html
  # @see https://aurimasv.github.io/z2csl/typeMap.xml
  class Wos
    # Static methods
    class << self
      def header
        [
          'FN Generated by github.com/cboulanger/anystyle-workflow',
          'VR 1.0',
          ''
        ].join("\n")
      end

      # Given a CSL item, return an array of arrays with family and given name
      # @param [Format::CSL::Item] item
      # @return [Array<String>]
      def to_au(item, initialize_given_names: true, separator: ', ')
        creator_names = item.creator_names
        return [] unless creator_names.is_a?(Array) && creator_names.length.positive?

        creator_names.map do |family, given|
          if initialize_given_names
            initials = Workflow::Utils.initialize_given_name(given || '')
            [family, initials].reject(&:nil?).join(separator).strip || 'UNKNOWN'
          else
            [family, given].reject(&:nil?).join(separator).strip || 'UNKNOWN'
          end
        end
      end

      # @param [Format::CSL::Item] item
      # @return [Array<String>]
      def to_af(item)
        to_au(item, initialize_given_names: false)
      end

      # @param [Format::CSL::Item] item
      def to_cr_au(item)
        to_au(item, separator: ' ').first
      end

      # @param [Format::CSL::Item] item
      def to_dt(item)
        case item.type
        when 'journal-article'
          'Article'
        when 'book'
          'Book'
        when 'chapter'
          'Chapter'
        else
          'Unknown'
        end
      end

      # @param [Format::CSL::Item] item
      def to_pt(item)
        case item.type
        when 'journal-article'
          'J'
        when 'book'
          'B'
        when 'chapter'
          'J'
        else
          'J'
        end
      end

      # @param [Format::CSL::Item] item
      def to_pd(item)
        item.issued.to_s
      end

      # @param [Format::CSL::Item] item
      def to_py(item)
        item.year
      end

      # @param [Format::CSL::Item] item
      def to_cr_entry(item)
        cit = []
        cit.append(to_cr_au(item))
        cit.append(to_py(item))
        if item.container_title
          cit.append(to_ji(item))
          cit.append("V#{item.volume}") if item.volume
          cit.append("P#{item.page.scan(/\d+/).first}") if item.page
          cit.append("DOI #{to_di(item)}") if item.doi
        else
          cit.append(item.title)
          cit.append("ISBN #{item.isbn}") if item.isbn
        end
        cit.join(', ')
      end

      # @param [Format::CSL::Item] item
      def to_ut(item)
        item.doi || item.isbn.scan(/\d+/)&.first || "#{to_cr_au(item)}_#{to_pd(item)}"
      end

      # @param [Format::CSL::Item] item
      # @return [Array<String>]
      def to_cr(item)
        item.x_references
            .select { |item| to_au(item).length.positive? }
            .map { |item| to_cr_entry(item) }
            .map(&:downcase).uniq.sort
      end

      # @param [Format::CSL::Item] item
      # @return [String]
      def to_nr(item)
        item.x_references.length.to_s
      end

      # @param [Format::CSL::Item] item
      # @return [Array<Format::CSL::Affiliation>]
      def get_affiliations(item)
        item.creators.map(&:x_affiliations)
      end

      # C1 [Milojevic, Stasa; Sugimoto, Cassidy R.; Dinga, Ying] Indiana Univ, Sch Informat & Comp, Bloomington, IN 47405 USA.
      #    [Lariviere, Vincent] Univ Montreal, Ecole Bibliothecon & Sci Informat, Montreal, PQ H3C 3J7, Canada.
      #    [Thelwall, Mike] Wolverhampton Univ, Sch Technol, Wolverhampton WV1 1LY, W Midlands, England.
      # @param [Format::CSL::Item] item
      # @return [Array<String>]
      def to_c1(item)
        affs = get_affiliations(item)
        to_af(item).map.with_index do |author, i|
          aff = affs[i]&.first
          next if aff.nil?

          aff_arr = [aff.institution, aff.department, aff.center, aff.address, aff.country].compact.reject(&:empty?)
          aff_str = aff_arr.length.positive? ? aff_arr.join(', ') : aff.literal
          "[#{author}] #{aff_str}." unless aff_str.empty?
        end.compact
      end

      # RP Milojevic, S (reprint author), Indiana Univ, Sch Informat & Comp, Bloomington, IN 47405 USA.
      # @param [Format::CSL::Item] item
      def to_rp(item)
        author = to_au(item).first
        aff = get_affiliations(item).first&.first
        return unless author && aff

        aff_arr = [aff.institution, aff.department, aff.center, aff.address, aff.country].compact.reject(&:empty?)
        aff_str = aff_arr.length.positive? ? aff_arr.join(', ') : aff.literal
        "#{author} (reprint author), #{aff_str}."
      end

      # @param [Format::CSL::Item] item
      # @return [String]
      def to_di(item)
        item.doi.sub(%r{^https?://doi.org/}, '')
      end

      # @param [Format::CSL::Item] item
      def to_tc(item)
        item.custom.times_cited
      end

      # @param [Format::CSL::Item] item
      def to_ab(item, width: 80)
        item.abstract.gsub(/(.{1,#{width}})(\s+|\Z)/, "\\1\n").split("\n")
      end

      # @param [Format::CSL::Item] item
      def to_de(item)
        kw = item.keyword
        Array(kw).join('; ') unless kw.nil?
      end

      # @param [Format::CSL::Item] item
      def to_id(item)
        id = item.custom.generated_keywords
        Array(id).join('; ') unless id.nil?
      end

      # J9 29-Character Source Abbreviation
      # @param [Format::CSL::Item] item
      def to_j9(item)
        item.journal_abbreviation
      end

      # JI 	ISO Source Abbreviation
      # @param [Format::CSL::Item] item
      def to_ji(item)
        item.journal_abbreviation&.gsub('.', '')
      end

      # Convert a Format::CSL::Item to a WOS/RIS text record
      # AU 	Authors’ Names
      # TI 	Document Title
      # SO 	Journal Name (or Source)
      # J9  29-Character Source Abbreviation
      # JI 	ISO Source Abbreviation
      # DT 	Document Type
      # DE 	Authors’ Keywords
      # ID 	Keywords associated by SCOPUS or WoS database
      # AB 	Abstract
      # C1 	Authors’ Affiliations
      # RP 	Corresponding Author’s Affiliation
      # CR 	Cited References
      # TC 	Times Cited
      # PY 	Publication Year
      # SC 	Subject Category
      # UT 	Unique Article Identifier
      # DB 	Bibliographic Database
      #
      # @param [Format::CSL::Item] item
      # @param [String, nil] na
      # @param [Boolean] compact
      def create_record(item, na: nil, compact: true)
        fields = {
          "PT": to_pt(item),
          "AU": to_au(item),
          "AF": to_af(item),
          "TI": item.title,
          "SO": item.container_title,
          "LA": item.language,
          "DT": to_dt(item),
          "DE": to_de(item),
          "ID": to_id(item),
          "AB": to_ab(item),
          "C1": to_c1(item),
          "RP": to_rp(item),
          "EM": na,
          "RI": na,
          "BN": item.isbn,
          "CR": to_cr(item),
          "NR": to_nr(item),
          "TC": to_tc(item),
          "Z9": 0,
          "PU": na,
          "PI": na,
          "PA": na,
          "SN": item.issn&.first,
          "EI": item.issn&.last,
          "J9": to_j9(item),
          "JI": to_ji(item),
          "PD": to_pd(item),
          "PY": to_py(item),
          "VL": item.volume,
          "IS": item.issue,
          "BP": item.page&.scan(/\d+/)&.first,
          "EP": item.page&.scan(/\d+/)&.last,
          "DI": to_di(item),
          "PG": 0,
          "WC": na,
          "SC": na,
          "GA": na,
          "UT": to_ut(item)
        }
        # cleanup
        if compact
          fields.delete_if do |_k, v|
            case v
            when Array
              v.empty?
            when String
              v.strip.empty?
            else
              v.nil? || v == na
            end
          end
        end
        remove_re = /\n|<[^>\s]+>/
        fields.each do |k, v|
          fields[k] = case v
                      when String
                        v.gsub(remove_re, '')
                      when Array
                        # put array items on new lines
                        v.map { |i| i&.gsub(remove_re, '') }.compact.join("\n   ")
                      else
                        v.to_s
                      end
        end
      end
    end
  end
end
