# frozen_string_literal: true

require 'damerau-levenshtein'
require 'text/levenshtein'
require 'matrix'

module Export
  # class to create a file compatible to the WOS plain text export format
  # from an array of CSL-JSON data
  # @see https://images.webofknowledge.com/images/help/WOS/hs_wos_fieldtags.html
  # @see https://aurimasv.github.io/z2csl/typeMap.xml
  class Wos
    class << self
      include Format::CSL

      def custom_id
        'wos-id'
      end

      # Given a CSL item, return an array of arrays with family and given name
      def to_au(item, initialize_given_names: true, separator: ', ')
        creator_names = get_csl_creator_names(item)
        return [] unless creator_names.is_a?(Array) && creator_names.length.positive?

        creator_names.map do |family, given|
          if initialize_given_names
            initials = initialize_given_name(given || '')
            [family, initials].reject(&:nil?).join(separator).strip || 'UNKNOWN'
          else
            [family, given].reject(&:nil?).join(separator).strip || 'UNKNOWN'
          end
        end
      end

      def to_af(csl_item)
        to_au(csl_item, initialize_given_names: false)
      end

      def to_cr_au(csl_item)
        to_au(csl_item, separator: ' ').first
      end

      def to_dt(csl_type)
        case csl_type
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

      def to_pt(csl_type)
        case csl_type
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

      def to_pd(item)
        get_csl_date(item)
      end

      def to_py(item)
        get_csl_year(item)
      end

      def add_abbreviations(string)
        string
          .sub(/journal/i, 'J')
          .sub(/review/i, 'Rev')
          .sub(/university/i, 'Univ')
      end

      def create_cr_entry(item, add_ref_source: false)
        cit = []
        cit.append(to_cr_au(item))
        cit.append(to_py(item))
        if item['container-title']
          cit.append(item['container-title'])
          cit.append("V#{item['volume']}") if item['volume']
          cit.append("P#{item['page'].scan(/\d+/).first}") if item['page']
          cit.append("DOI #{to_di(item['DOI'])}") if item['DOI']
        else
          cit.append(item['title'])
          cit.append("ISBN #{item['ISBN']}") if item['ISBN']
        end
        cit.append "SOURCE #{item['source']}" if add_ref_source && (item['source'])
        add_abbreviations(cit.join(', '))
      end

      def to_ut(item)
        item['DOI'] || item['ISBN'].scan(/\d+/)&.first || "#{to_cr_au(item)} #{to_pd(item)}"
      end

      def titleize_if_uppercase(text)
        text.split(' ').map { |w| w.match(/^[\p{Lu}\p{P}]+$/) ? w.capitalize : w }.join(' ')
      end

      def create_cr_field(references, add_ref_source: false)
        references
          .select { |ref| to_au(ref).length.positive? }
          .map { |ref| create_cr_entry(ref, add_ref_source:) }
          .map(&:downcase).uniq.sort
      end

      def get_affiliations(csl_item)
        affs = CUSTOM_AUTHORS_AFFILIATIONS_FIELDS.map { |f| csl_item.dig('custom', f) }.reject(&:nil?)
        affs.length.positive? ? Array(affs.first) : []
      end

      # C1 [Milojevic, Stasa; Sugimoto, Cassidy R.; Dinga, Ying] Indiana Univ, Sch Informat & Comp, Bloomington, IN 47405 USA.
      #    [Lariviere, Vincent] Univ Montreal, Ecole Bibliothecon & Sci Informat, Montreal, PQ H3C 3J7, Canada.
      #    [Thelwall, Mike] Wolverhampton Univ, Sch Technol, Wolverhampton WV1 1LY, W Midlands, England.
      def to_c1(csl_item)
        affs = get_affiliations(csl_item)
        to_af(csl_item).map.with_index do |author, i|
          aff = affs[i]
          case aff
          when Hash
            org = aff['organization']
            org = org.first if org.is_a?(Array)
            country = aff['country']
            aff_str = "#{org},#{country}"
          when String
            aff_str = aff
          else
            aff_str = 'unknown affiliation'
          end
          "[#{author}] #{aff_str}."
        end
      end

      # RP Milojevic, S (reprint author), Indiana Univ, Sch Informat & Comp, Bloomington, IN 47405 USA.
      def to_rp(csl_item)
        affs = get_affiliations(csl_item)
        author = to_au(csl_item)&.first
        return if author.nil?

        aff = affs.first
        case aff
        when Hash
          org = aff['organization']
          org = org.first if org.is_a?(Array)
          country = aff['country']
          "#{author} #{org},#{country}."
        when String
          "#{author} (reprint author), #{aff}."
        else
          "#{author} (reprint author),unknown affiliation."
        end
      end

      def to_di(doi)
        doi.sub(%r{^https?://doi.org/}, '')
      end

      def to_tc(csl_item)
        tc = {}
        CUSTOM_TIMES_CITED_FIELDS.each { |f| tc[f] = csl_item.dig('custom', f)&.to_i || 0 }
        tc.values.max.to_s
      end

      def to_ab(abstract, width: 80)
        abstract.gsub(/(.{1,#{width}})(\s+|\Z)/, "\\1\n").split("\n")
      end

      def to_de(csl_item)
        kw = csl_item['keyword']
        Array(kw).join('; ') unless kw.nil?
      end

      def to_id(csl_item)
        id = csl_item.dig('custom', CUSTOM_GENERATED_KEYWORDS)
        Array(id).join('; ') unless id.nil?
      end

      # convert a CSL-JSON datastructure as a WOS/RIS text record
      # see https://www.bibliometrix.org/vignettes/Data-Importing-and-Converting.html
      # AU 	Authors’ Names
      # TI 	Document Title
      # SO 	Journal Name (or Source)
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
      def create_record(item, na: nil, compact: true, add_ref_source: false)
        references = item['reference'] || []
        fields = {
          "PT": to_pt(item['type']),
          "AU": to_au(item),
          "AF": to_af(item),
          "TI": item['title'],
          "SO": item['container-title'],
          "LA": item['language'],
          "DT": to_dt(item['type']),
          "DE": to_de(item),
          "ID": to_id(item),
          "AB": to_ab(item['abstract']),
          "C1": to_c1(item),
          "RP": to_rp(item),
          "EM": na,
          "RI": na,
          "BN": item['ISBN'],
          "CR": create_cr_field(references, add_ref_source:),
          "NR": references.length,
          "TC": to_tc(item),
          "Z9": 0,
          "PU": na,
          "PI": na,
          "PA": na,
          "SN": item['ISSN']&.first,
          "EI": item['ISSN']&.last,
          "J9": item['type'] == 'journal-article' ? item['container-title'] : na,
          "JI": na,
          "PD": to_pd(item),
          "PY": to_py(item),
          "VL": item['volume'],
          "IS": item['issue'],
          "BP": item['page']&.scan(/\d+/)&.first,
          "EP": item['page']&.scan(/\d+/)&.last,
          "DI": to_di(item['DOI']),
          "PG": 0,
          "WC": na,
          "SC": na,
          "GA": na,
          "UT": to_ut(item)
        }
        # cleanup
        fields.delete_if { |_k, v| v.nil? || v.to_s.empty? || v == na } if compact
        remove_re = /\n|<[^>\s]+>/
        fields.each do |k, v|
          fields[k] = case v
                      when String
                        v.gsub(remove_re, '')
                      when Array
                        # put array items on new lines
                        v.map { |i| i.gsub(remove_re, '') }.join("\n   ")
                      else
                        v.to_s
                      end
        end
      end

      # @param [String] outfile
      # @param [String (frozen)] encoding
      def write_header(outfile, encoding: 'utf-8')
        header = [
          'FN Generated by github.com/cboulanger/anystyle-workflow',
          'VR 1.0',
          ''
        ].join("\n")
        header.encode!(encoding, invalid: :replace, undef: :replace) if encoding != 'utf-8'
        File.write(outfile, header, encoding:)
      end

      # @param [String] outfile
      # @param [Object] item
      # @param [String (frozen)] encoding
      # @param [Boolean] compact
      # @param [Boolean] add_ref_source
      def append_record(outfile, item, encoding: 'utf-8', compact: true, add_ref_source: false)
        begin
          fields = create_record(item, compact:, add_ref_source:)
        rescue StandardError
          puts 'Error processing the following item:'
          puts item
          raise
        end
        records = []
        fields.each do |key, value|
          records.append("#{key} #{value}")
        end
        text = "#{records.join("\n")}\nER\n\n"
        text = text.encode(encoding, invalid: :replace, undef: :replace) if encoding != 'utf-8'
        File.write(outfile, text, 0, encoding:, mode: 'ab')
      end
    end
  end
end
