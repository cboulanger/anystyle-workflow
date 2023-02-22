module Export
  class WebOfScience < Exporter

    # @param [String] outfile path to output file
    # @param [Boolean] compact If true, remove all empty tags. Default is true, pass false if an app complains about
    #   missing fields
    # @param [String] encoding
    # @param [Boolean] add_ref_source
    def initialize(outfile = nil, compact: true, encoding: 'utf-8', add_ref_source: false)
      super
      @outfile = outfile || File.join(Path.export, "export-wos-#{Utils.timestamp}.txt")
      @compact = compact
      @encoding = encoding
      @add_ref_source = add_ref_source
    end

    def name
      "Web of Science/ISI format exporter"
    end

    def start
      header = Format::Wos.header
      header.encode!(@encoding, invalid: :replace, undef: :replace) if @encoding != 'utf-8'
      File.write(@outfile, header, encoding:@encoding)
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      begin
        fields = Format::Wos.create_record(item, compact: @compact, add_ref_source: @add_ref_source)
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