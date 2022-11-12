# frozen_string_literal: true

module Export
  # class to create a file compatible to the WOS plain text export format
  # from an array of CSL-JSON data
  # @see https://images.webofknowledge.com/images/help/WOS/hs_wos_fieldtags.html
  # @see https://aurimasv.github.io/z2csl/typeMap.xml
  class Wos
    class << self
      def write_header(outfile, encoding = 'utf-8')
        header = [
          'FN Thomson Reuters Web of Science™',
          'VR 1.0',
          ''
        ]
        File.write(outfile, header.join("\n"), encoding:)
      end

      def append_record(outfile, item, cited_items, encoding = 'utf-8')
        fields = create_record(item, cited_items)
        records = []
        fields.each do |key, value|
          records.append("#{key} #{value}")
        end
        text = "#{records.join("\n")}\nER\n\n"
        File.write(outfile, text, 0, encoding:, mode: 'a')
      end

      def first_name_initials(creator)
        creator['given']&.scan(/\p{L}+/)&.map { |n| n[0] }&.join('')
      end

      def to_au(creator_field)
        return 'NO AUTHOR' unless creator_field.is_a? Array

        creator_field.map { |c| c['literal'] || "#{c['family'] || 'UNKNOWN'}, #{first_name_initials(c)}" }
      end

      def to_af(creator_field)
        return 'NO AUTHOR' unless creator_field.is_a? Array

        creator_field.map { |c| c['literal'] || "#{c['family'] || 'UNKNOWN'}, #{c['given']}" }
      end

      def to_cr_au(creator_field)
        c = creator_field.first
        c['literal'] || "#{c['family'] || 'UNKNOWN'} #{first_name_initials(c)}"
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

      def to_pd(date)
        case date
        when Hash
          if date['raw']
            date['raw']
          elsif date['date-parts']
            date['date-parts'].join('-')
          else
            raise 'Invalid date hash'
          end
        when String
          date
        end
      end

      def to_py(date)
        case date
        when Hash
          if date['raw']
            date['raw'].scan(/\d{4}/).first
          elsif date['date-parts']
            date['date-parts'].first.first
          else
            raise 'Invalid date hash'
          end
        when String
          date.scan(/\d{4}/).first
        else
          raise 'Date must be string or hash'
        end
      end

      def create_cr_entry(item)
        cit = []
        creators = item['author'] || item['editor']
        if (creators.is_a? Array) && creators.length.positive?
          cit.append(to_cr_au(creators))
        else
          cit.append('NO AUTHOR')
        end
        cit.append(to_py(item['issued']))
        if item['container-title']
          cit.append(item['container-title'])
          cit.append("V#{item['volume']}") if item['volume']
          cit.append("P#{item['page'].scan(/\d+/).first}") if item['page']
          cit.append("DOI #{item['DOI']}") if item['DOI']
        else
          cit.append(item['title'])
          cit.append("ISBN #{item['ISBN']}") if item['ISBN']
        end
        cit.join(', ')
      end

      def create_unique_identifier(item)
        item['DOI'] || item['ISBN'].scan(/\d+/)&.first || "#{to_cr_au(item['author'] || item['editor'])} #{to_pd(item['date'])}"
      end

      # convert a CSL-JSON datastructure as a WOS/RIS text record
      def create_record(item, cited_records = [])
        fields = {
          "AF": to_af(item['author'] || item['editor']),
          "AB": item['abstract'],
          "AU": to_au(item['author'] || item['editor']),
          "BN": item['ISBN'],
          "BP": item['page']&.scan(/\d+/)&.first,
          "C1": 'N/A',
          "CR": cited_records.map { |cr| create_cr_entry(cr) },
          "DE": 'N/A',
          "DI": item['DOI'],
          "DT": to_dt(item['type']),
          "EP": item['page']&.scan(/\d+/)&.last,
          "IS": item['issue'],
          "J9": if item['type']== "journal-article"
                  item['container-title']
                end,
          "NR": cited_records.length,
          "PD": to_pd(item['issued']),
          "PT": to_pt(item['type']),
          "PY": to_py(item['issued']),
          "RP": 'N/A',
          "SN": item['ISSN']&.join(" "),
          "SO": item['container-title'],
          "TC": item['references-count'],
          "TI": item['title'],
          "VL": item['volume'],
          "UT": create_unique_identifier(item)
        }
        # cleanup
        fields.delete_if { |_k, v| v.nil? || v.to_s.empty? }
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
