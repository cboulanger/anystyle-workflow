# frozen_string_literal: true

module Export
  class Wos
    class << self
      def create_file(outfile, encoding = 'utf-8')
        header = [
          'FN Thomson Reuters Web of Science™',
          'VR 1.0',
          ''
        ]
        File.write(outfile, header.join("\n"),0, { encoding: })
      end

      def append_record(outfile, item, cited_items, encoding = 'utf-8')
        fields = create_record(item, cited_items)
        records = []
        fields.each do |key, value|
          records.append("#{key} #{value}") unless value.empty?
        end
        text = "#{records.join("\n")}\nER\n\n"
        File.write(outfile, text, 0, { encoding:, mode: 'a' })
      end

      def to_au(creator_field)
        creator_field.map { |c| c['literal'] || "#{c['family']}, #{c['given'][0]}" }.join("\n   ")
      end

      def to_af(creator_field)
        creator_field.map { |c| c['literal'] || "#{c['family']}, #{c['given']}" }.join("\n   ")
      end

      def to_dt(csl_type)
        case csl_type
        when 'article'
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
        cit.append(to_au(item['author'][0] || item['editor'][0]))
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

      # format a CSL-JSON datastructure as a WOS/RIS text record
      # see https://images.webofknowledge.com/images/help/WOS/hs_wos_fieldtags.html
      def create_record(item, cited_records = [])
        fields = {
          "PT": to_pt(item['type']),
          "DT": to_dt(item['type']),
          "AU": to_au(item['author']),
          "AF": to_af(item['author']),
          "TI": item['title'],
          "SO": item['container-title'],
          "PD": item['issued'],
          "PY": to_py(item['issued']),
          "VL": item['volume'],
          "IS": item['issue'],
          "BP": item['page'].scan(/\d+/).first,
          "EP": item['page'].scan(/\d+/).last,
          "DI": item['DOI'],
          "BN": item['ISBN'],
          "CR": cited_records.map { |cr| create_cr_entry(cr) }.join("\n   "),
          "NR": cited_records.length
        }
        # fields.compact
        fields.delete_if { |_k, v| v.nil? || v.empty? }
      end
    end
  end
end
