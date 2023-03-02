# frozen_string_literal: true
require './lib/format/format'

module Format
  class Cypher < ::Format::Format

    def self.header
      [
        'CREATE CONSTRAINT work_id IF NOT EXISTS ON (w:Work) ASSERT w.id IS UNIQUE;',
        'CREATE INDEX author_family IF NOT EXISTS FOR (a:Author) ON (a.family)',
        'CREATE INDEX author_given IF NOT EXISTS FOR (a:Author) ON (a.given)',
      #'CALL db.awaitIndexes();'
      ]
    end

    def serialize
      # @type [Format::CSL::Item]
      @item = @item

      output = []

      # works
      output.append(
        <<~CYPHER
          MERGE (w:Work {id: "#{@item.id}"})
              ON CREATE SET
                w.title = #{JSON.dump @item.title||"NO TITLE"},
                w.year = #{@item.issued&.to_year||0},
                w.type = "#{@item.type}"
      CYPHER
      )

      # authors
      @item.creators.each_with_index do |creator, index|
        a_var = "a#{(index + 1).to_s}"
        output.append(
          <<~CYPHER
            MERGE (#{a_var}:Author {family: #{JSON.dump creator.family.to_s}, given:#{JSON.dump creator.given.to_s}})
            MERGE (#{a_var})-[:CREATOR_OF]->(w)
        CYPHER
        )

        creator.x_affiliations&.each_with_index do |affiliation, i_index|
          i_var = "i#{(index + 1).to_s}#{(i_index + 1).to_s}"
          output.append(
            <<~CYPHER
              MERGE (#{i_var}:Institution {name: #{JSON.dump affiliation.to_s}})
              MERGE (#{a_var})-[:AFFILIATED_WITH]->(#{i_var})
          CYPHER
          )
        end
      end

      # containers
      if @item.container_title
        output.append(
          <<~CYPHER
            MERGE (v:Venue {name: #{JSON.dump @item.container_title}})
              ON CREATE SET
                v.issn = #{JSON.dump @item.issn&.first.to_s}
              MERGE (w)-[:PUBLISHED_IN]->(v)
        CYPHER
        )
      end

      # create relationship with citing item
      if @citing_item
        output.append(
          <<~CYPHER
            WITH w 
            MATCH (w2:Work {id:"#{@citing_item.id}"})
            MERGE (w2)-[:CITES]->(w)
        CYPHER
        )

      end

      output.append('RETURN *;')

      # references
      unless @item.x_references.empty?
        output.append("// #{'-' * 80}") if @pretty
        @item.x_references.each_with_index do |ref, index|
          output.append Cypher.new(ref, citing_item: item, pretty:@pretty).serialize
        end
      end

      output.append("// #{(citing_item ? '-' : '*') * 80}") if @pretty
      output.map(&:strip).join("\n")
    end
  end
end
