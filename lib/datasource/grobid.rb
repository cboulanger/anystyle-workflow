require './lib/datasource/datasource'

require 'nokogiri'

module Datasource
  class Grobid < ::Datasource::Datasource
    CSL_CUSTOM_FIELDS = [
      AUTHOR_AFFILIATIONS = 'grobid-author-affiliations'
    ].freeze

    class << self

      # @return [String]
      def id
        'grobid'
      end

      # @return [String]
      def label
        'Data from TEI files produced using GROBID'
      end

      # @return [Boolean]
      def enabled?
        true
      end

      # @return [Boolean]
      def provides_metadata?
        false
      end

      # The type of identifiers that can be used to import data
      # @return [Array<String>]
      def id_types
        [::Datasource::FILE_NAME, ::Datasource::DOI]
      end

      # @return [Boolean]
      def provides_citation_data?
        true
      end

      # @return [Boolean]
      def provides_affiliation_data?
        true
      end

      # @return [Array<Item>]
      def import_items(item_ids, include_references: false, include_abstract: false, prefix: '')
        item_ids.map do |id|
          file_path = File.join(Workflow::Path.grobid_tei,
                                "#{prefix}#{Workflow::Utils.to_filename(id)}.tei.xml")
          if File.exist? file_path
            data = {
              "DOI": id
            }
            Item.from_tei_file(file_path, data)
          end
        end
      end
    end

    class Affiliation < Format::CSL::Affiliation

      def initialize(aff_node)
        super({})
        self.literal = aff_node.xpath('note/text()').to_s.strip
        self.x_affiliation_source = 'grobid'
        unless aff_node.xpath('orgName').empty?
          self.institution = aff_node.xpath('orgName[@type=\'institution\']/text()').to_s
          self.department = aff_node.xpath('rgName[@type=\'department\']/text()').to_s
          self.center = aff_node.xpath('orgName[@type=\'laboratory\']/text()').to_s
        end
        return if aff_node.xpath('address').empty?

        self.address = [
          aff_node.xpath('address/addrLine/text()').to_s,
          aff_node.xpath('address/postCode/text()').to_s,
          aff_node.xpath('address/settlement/text()').to_s
        ].reject(&:empty?).join(', ')
        self.country = aff_node.xpath('address/country/text()').to_s
        return if (country = aff_node.xpath('address/country')).empty?

        self.country_code = country[0]['key']
      end
    end

    class Creator < Format::CSL::Creator

      def initialize(author_node)
        super({})
        self.family = author_node.xpath('persName/surname/text()').to_s
        self.given = author_node.xpath('persName/forename/text()').to_s
        # affiliation
        return if author_node.xpath('affiliation').empty?
        self.x_affiliations = author_node.xpath('affiliation').map { |aff_node| Affiliation.new(aff_node) }

      end

      private def affiliation_factory(data)
        Affiliation.new(data)
      end
    end

    class Item < Format::CSL::Item

      def self.from_tei_file(file_path, data)
        xml = File.open(file_path) { |f| Nokogiri::XML(f) }
        new(xml, data)
      end

      # @param [Nokogiri::XML::Document] doc
      # @param [Hash] data Additional CSL metadata
      def initialize(doc, data = {})
        unless doc.is_a? Nokogiri::XML::Document
          raise 'constructor arg must be a Nokogire::XML::Document'
        end
        doc.remove_namespaces!
        @_doc = doc
        custom.metadata_source = 'grobid'
        data.merge!({ title:, abstract:, author: })
        super(data)
      end

      def title
        @title || @_doc.xpath('//teiHeader/fileDesc/titleStmt/title/text()').to_s
      end

      def abstract
        @abstract || @_doc.xpath('//teiHeader/profileDesc/abstract/*').to_s.gsub(/<[^>]+>/, '')
      end

      # Returns a CSL compliant author field with additional affiliation information
      # @return [Array]
      def author
        return @author if @author

        author_nodes = @_doc.xpath('//teiHeader/fileDesc/sourceDesc/biblStruct/analytic/author')
        author_nodes.map do |author_node|
          Creator.new(author_node)
        end.compact
      end
    end
  end
end
