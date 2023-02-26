module Export
  class WebOfScience < Exporter

    def name
      'Web of Science/ISI format exporter'
    end

    def start
      header = Format::Wos.header
      header.encode!(@encoding, invalid: :replace, undef: :replace) if @encoding != 'utf-8'
      File.write(@outfile, header, encoding: @encoding)
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      begin
        fields = Format::Wos.create_record(item, compact: @compact)
      rescue StandardError
        puts 'Error processing the following item:'
        puts item.to_json
        raise
      end
      records = []
      fields.each do |key, value|
        records.append("#{key} #{value}")
      end
      text = "#{records.join("\n")}\nER\n\n"
      text = text.encode(@encoding, invalid: :replace, undef: :replace) if @encoding != 'utf-8'
      File.write(@outfile, text, 0, encoding: @encoding, mode: 'ab')
    end
  end
end