require './lib/export/exporter'
require 'csv'

module Export
  class CitnetExplorer < Exporter
    # @return [String]
    def self.id
      'citnetexplorer'
    end

    # @return [String]
    def self.name
      'CitnetExplorer CSV files exporter'
    end

    def initialize(target: nil, compact: nil, encoding: nil, pretty: nil, verbose: nil)
      super
      # ignore any other encoding since this is the only encoding the software understands
      @encoding = "ISO-8859-1"
      @pub_header = %w[authors title source year doi cit_score incomplete_record]
      @cit_header = %w[citing_pub_index cited_pub_index]
    end

    def start
      @publications = []
      @citations = []
      @index = {}
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      row = item_to_row(item)
      return unless row.is_a? Array

      # add publication
      @publications << row
      citing_pub_index = @publications.length
      @index[item.id] = citing_pub_index

      # add references and link with reference
      item.x_references.to_a.each do |ref|
        if (cited_pub_index = @index[ref.id]).nil?
          row = item_to_row(ref)
          next unless row.is_a? Array

          @publications << row
          cited_pub_index = @publications.length
        end
        @index[ref.id] = cited_pub_index
        @citations << [citing_pub_index, cited_pub_index]
      end
    end

    def finish
      [
        ["#{@target}.pub.csv", @pub_header, @publications],
        ["#{@target}.cit.csv", @cit_header, @citations]
      ].each do |file, header, data|
        csv_str = CSV.generate(col_sep: "\t") do |csv|
          csv << header
          data.each { |row| csv << row }
        end
        csv_str.encode!(@encoding, invalid: :replace, undef: :replace) if @encoding != 'utf-8'
        File.write(file, csv_str, encoding: @encoding)
      end
    end

    protected

    def item_to_row(item)
      author, year, title = item.creator_year_title(downcase: true, normalize_nil: true)
      return if author.empty? || year.zero?

      source = item.container_title.to_s.downcase.gsub(/\p{Cntrl}/, '')
      title.gsub!(/\p{Cntrl}/,'')
      [
        author,
        title,
        source,
        year,
        item.doi || '',
        0, #item.custom.times_cited || 0,
        item.x_references.to_a.length.positive? ? 1 : 0
      ]
    end
  end
end