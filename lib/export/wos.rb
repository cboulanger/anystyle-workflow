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

      def custom_times_cited
        'wos-times-cited'
      end

      def custom_item_authors_affiliation
        'wos-item-authors-affiliations'
      end

      def to_au(item, initialize_given_names: true, separator: ", ")
        creator_names = get_csl_creator_names(item)
        return "UNKNOWN" unless creator_names.is_a?(Array) && creator_names.length.positive?

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
        to_au(csl_item, separator: " ").first
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
        cit.append "SOURCE #{item['source']}" if item['source'] if add_ref_source
        cit.join(', ')
      end

      def create_unique_identifier(item)
        item['DOI'] || item['ISBN'].scan(/\d+/)&.first || "#{to_cr_au(item)} #{to_pd(item)}"
      end

      def titleize_if_uppercase(text)
        text.split(' ').map { |w| w.match(/^[\p{Lu}\p{P}]+$/) ? w.capitalize : w }.join(' ')
      end

      def create_cr_field(references, add_ref_source: false)
        references.map { |cr| create_cr_entry(cr, add_ref_source:) }.sort
      end

      # C1 [Milojevic, Stasa; Sugimoto, Cassidy R.; Dinga, Ying] Indiana Univ, Sch Informat & Comp, Bloomington, IN 47405 USA.
      #    [Lariviere, Vincent] Univ Montreal, Ecole Bibliothecon & Sci Informat, Montreal, PQ H3C 3J7, Canada.
      #    [Thelwall, Mike] Wolverhampton Univ, Sch Technol, Wolverhampton WV1 1LY, W Midlands, England.
      def to_c1(csl_item)
        affiliations = csl_item.dig('custom', custom_item_authors_affiliation)
        return if affiliations.nil?

        i = -1
        affiliations.map do |aff|
          org = aff['organization']
          org = org.first if org.is_a?(Array)
          country = aff['country']
          i += 1
          "[#{to_af(csl_item)[i]}] #{org},X,X,#{country}."
        end
      end

      # RP Milojevic, S (reprint author), Indiana Univ, Sch Informat & Comp, Bloomington, IN 47405 USA.
      def to_rp(csl_item)
        aff = csl_item.dig('custom', custom_item_authors_affiliation)
        return if aff.nil? || !aff.is_a?(Array) || !aff.length.positive?

        aff = aff.first
        org = aff['organization']
        org = org.first if org.is_a?(Array)
        country = aff['country']
        "#{to_au(csl_item)&.first}] #{org},X,X,#{country}."
      end

      def to_di(doi)
        doi.sub(/^https?:\/\/doi.org\//, '')
      end

      def to_tc(csl_item)
        csl_item.dig('custom', custom_times_cited)
      end

      def to_ab(abstract, width: 80)
        abstract.gsub(/(.{1,#{width}})(\s+|\Z)/, "\\1\n").split("\n")
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
          "AU": to_au(item), # Author's
          "AF": to_af(item),
          "TI": item['title'],
          "SO": item['container-title'],
          "LA": na,
          "DT": to_dt(item['type']),
          "DE": item['keyword'],
          "ID": na,
          "AB": to_ab(item['abstract']),
          "C1": to_c1(item),
          "RP": na,
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
          "UT": create_unique_identifier(item)
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
          'FN Generated by https://github.com/cboulanger/citext',
          'VR 1.0',
          ''
        ].join("\n")
        if encoding != "utf-8"
          header.encode!(encoding, invalid: :replace, undef: :replace)
            end
          File.write(outfile, header, encoding: encoding)
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
            puts "Error processing the following item:"
            puts item
            raise
          end
          records = []
          fields.each do |key, value|
            records.append("#{key} #{value}")
          end
          text = "#{records.join("\n")}\nER\n\n"
          if encoding != "utf-8"
            text = text.encode(encoding, invalid: :replace, undef: :replace)
          end
          File.write(outfile, text, 0, encoding:, mode: 'ab')
        end
      end
    end
  end
