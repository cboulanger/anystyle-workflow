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
      
      def write_header(outfile, encoding = 'utf-8')
        header = [
          'FN Thomson Reuters Web of Science™',
          'VR 1.0',
          ''
        ]
        File.write(outfile, header.join("\n"), encoding:)
      end

      def append_record(outfile, item, encoding: 'utf-8', compact: true, add_ref_source: false)
        begin
          fields = create_record(item, compact:, add_ref_source:)
        rescue StandardError
          puts item
          raise
        end
        records = []
        fields.each do |key, value|
          records.append("#{key} #{value}")
        end
        text = "#{records.join("\n")}\nER\n\n"
        File.write(outfile, text, 0, encoding:, mode: 'a')
      end

      def to_au(item, initialize_given_names: true)
        creator_names = get_csl_creator_names(item)
        return "UNKNOWN" unless creator_names.is_a?(Array) && creator_names.length.positive?

        creator_names.map do | family, given |
          if initialize_given_names
            initials = initialize_given_name(given || '')
            [family, initials].reject(&:nil?).join(' ').strip || 'UNKNOWN'
          else
            [family, given].reject(&:nil?).join(' ').strip || 'UNKNOWN'
          end
        end
      end

      def to_af(csl_item)
        to_au(csl_item, initialize_given_names: false)
      end

      def to_cr_au(csl_item)
        to_au(csl_item).first
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
          cit.append("DOI #{item['DOI']}") if item['DOI']
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

      def create_cr_field(references, add_ref_source:false)
        references.map { |cr| create_cr_entry(cr, add_ref_source:) }.sort
      end

      # convert a CSL-JSON datastructure as a WOS/RIS text record
      def create_record(item, na: nil, compact: true, add_ref_source:false)
        references = item['reference'] || []
        fields = {
          "PT": to_pt(item['type']),
          "AU": to_au(item),
          "AF": to_af(item),
          "TI": item['title'],
          "SO": item['container-title'],
          "LA": na,
          "DT": to_dt(item['type']),
          "DE": na,
          "ID": na,
          "AB": item['abstract'],
          "C1": na,
          "RP": na,
          "EM": na,
          "RI": na,
          "BN": item['ISBN'],
          "CR": create_cr_field(references, add_ref_source:),
          "NR": references.length,
          "TC": item['references-count'],
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
          "DI": item['DOI'],
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
    end
  end
end
