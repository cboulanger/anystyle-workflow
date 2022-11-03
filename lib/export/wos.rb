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

        creator_field.map do |c|
          c['literal'] || "#{c['family'] || 'UNKNOWN'}, #{first_name_initials(c)}"
        end.join("\n   ")
      end

      def to_af(creator_field)
        return 'NO AUTHOR' unless creator_field.is_a? Array

        creator_field.map { |c| c['literal'] || "#{c['family']}, #{c['given']}" }.join("\n   ")
      end

      def to_cr_au(creator_field)
        c = creator_field.first
        c['literal'] || "#{c['family']} #{first_name_initials(c)}"
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
        when 'article'
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

      # convert a CSL-JSON datastructure as a WOS/RIS text record
      def create_record(item, cited_records = [])
        fields = {
          "PT": to_pt(item['type']),
          "DT": to_dt(item['type']),
          "AU": to_au(item['author'] || item['editor']),
          "AF": to_af(item['author'] || item['editor']),
          "TI": item['title'],
          "SO": item['container-title'],
          "PD": to_pd(item['issued']),
          "PY": to_py(item['issued']),
          "VL": item['volume'],
          "IS": item['issue'],
          "BP": item['page']&.scan(/\d+/)&.first,
          "EP": item['page']&.scan(/\d+/)&.last,
          "DI": item['DOI'],
          "BN": item['ISBN'],
          "CR": cited_records.map { |cr| create_cr_entry(cr) }.join("\n   "),
          "NR": cited_records.length
        }
        # fields.compact
        fields.delete_if { |_k, v| v.nil? || v.to_s.empty? }
      end
    end
  end
end
