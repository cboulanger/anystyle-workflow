# frozen_string_literal: true

require 'nokogiri'

module Datasource
  class Grobid
    CSL_CUSTOM_FIELDS = [
      AUTHOR_AFFILIATIONS = 'grobid-author-affiliations'
    ].freeze

    class << self
      attr_accessor :verbose

      def import_items_by_doi(dois, include_references:, include_abstract:)
        dois.map do |doi|
          file_name = doi.sub('/', '_')
          file_path = File.join(Workflow::Path.grobid_tei, "#{file_name}.tei.xml")
          CSL_Document.from_tei_file(file_path).to_h
        end
      end
    end

    class CSL_Document
      def self.from_tei_file(file_path)
        new(File.open(file_path) { |f| Nokogiri::XML(f) })
      end

      # @param [Nokogiri::XML::Document] doc
      def initialize(doc)
        doc.remove_namespaces!
        @doc = doc
      end

      def to_h
        {
          author:,
          title:,
          abstract:,
        }
      end

      def title
        @doc.xpath('//teiHeader/fileDesc/titleStmt/title/text()').to_s
      end

      def abstract
        @doc.xpath('//teiHeader/profileDesc/abstract/*').to_s
      end

      # Returns a CSL compliant author field with additional affiliation information
      # in the 'grobid-author-affiliations' field
      # @return [Array]
      def author
        author_nodes = @doc.xpath('//teiHeader/fileDesc/sourceDesc/biblStruct/analytic/author')
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
            author_data[AUTHOR_AFFILIATIONS] = aff_data unless aff_data.empty?
          end
          author_data
        end.compact
      end
    end
  end
end
