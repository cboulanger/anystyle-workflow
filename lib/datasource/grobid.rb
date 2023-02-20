# frozen_string_literal: true

require 'nokogiri'

module Datasource
  class Grobid
    CSL_CUSTOM_FIELDS = [
      AUTHOR_AFFILIATIONS = 'grobid-author-affiliations'
    ].freeze

    class << self
      attr_accessor :verbose

      def import_items_by_doi(dois, include_references:false, include_abstract:false)
        dois.map do |doi|
          file_name = doi.sub('/', '_')
          file_path = File.join(Workflow::Path.grobid_tei, "#{file_name}.tei.xml")
          data = {
            "DOI": doi
          }
          Item.from_tei_file(file_path, data)
        end
      end
    end

    class Item < Format::CSL::Item

      def self.from_tei_file(file_path, data)
        xml = File.open(file_path) { |f| Nokogiri::XML(f) }
        new(xml, data)
      end

      # @param [Nokogiri::XML::Document] doc
      # @param [Hash] data Additional CSL metadata
      def initialize(doc, data={})
        unless doc.is_a? Nokogiri::XML::Document
          raise "constructor arg must be a Nokogire::XML::Document"
        end
        doc.remove_namespaces!
        @_doc = doc
        custom.metadata_source = "grobid"
        data.merge!({ title:, abstract:, author: })
        super(data)
      end


      def title
        @title || @_doc.xpath('//teiHeader/fileDesc/titleStmt/title/text()').to_s
      end

      def abstract
        @abstract || @_doc.xpath('//teiHeader/profileDesc/abstract/*').to_s.gsub(/<[^>]+>/,"")
      end

      # Returns a CSL compliant author field with additional affiliation information
      # in the 'grobid-author-affiliations' field
      # @return [Array]
      def author
        return @author if @author

        author_nodes = @_doc.xpath('//teiHeader/fileDesc/sourceDesc/biblStruct/analytic/author')
        author_nodes.map do |author_node|
          family = author_node.xpath('persName/surname/text()').to_s
          given = author_node.xpath('persName/forename/text()').to_s
          author_data = if family.empty?
                          {}
                        else
                          { family:, given: }
                        end
          # affiliation
          unless author_node.xpath('affiliation').empty?
            aff_data = {}
            aff_string = author_node.xpath('affiliation/note/text()').to_s.strip
            aff_data['literal'] = aff_string unless aff_string.empty?
            # organization
            unless author_node.xpath('affiliation/orgName').empty?
              %w[department laboratory institution].each do |type|
                text = author_node.xpath("affiliation/orgName[@type='#{type}']/text()").to_s
                aff_data[type] = text unless text.empty?
              end
            end
            # address
            unless author_node.xpath('affiliation/address').empty?
              aff_data['address'] = {}
              %w[addrLine postCode settlement country].each do |part|
                text = author_node.xpath("affiliation/address/#{part}/text()").to_s
                aff_data['address'][part] = text unless text.empty?
              end
              unless (country = author_node.xpath('affiliation/address/country')).empty?
                aff_data['address']['country_code'] = country[0]['key']
              end
            end
            author_data['x_affiliations'] = [aff_data] unless aff_data.empty?
          end
          author_data
        end.compact
      end
    end
  end
end
