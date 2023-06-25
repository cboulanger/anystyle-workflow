# frozen_string_literal: true

require './lib/format/format'

module Format
  class Cypher < ::Format::Format

    @counter = 0

    def self.header
      [
        'CREATE CONSTRAINT work_id IF NOT EXISTS ON (w:Work) ASSERT w.id IS UNIQUE;',
        'CREATE CONSTRAINT institution_name IF NOT EXISTS ON (i:Institution) ASSERT i.name IS UNIQUE',
        'CREATE CONSTRAINT venue_id IF NOT EXISTS ON (v:Venue) ASSERT v.id IS UNIQUE',
        'CREATE INDEX work_title IF NOT EXISTS FOR (w:Work) ON (w.title)',
        'CREATE INDEX venue_name IF NOT EXISTS FOR (v:Venue) ON (v.name)',
        'CREATE INDEX author_display_name IF NOT EXISTS FOR (a:Author) ON (a.display_name)'
      # 'CALL db.awaitIndexes();'
      ]
    end

    def self.next_work_num
      @counter += 1
    end

    def serialize
      output = []
      # @type [Format::CSL::Item]
      @item = @item

      # works
      output.append(
        <<~CYPHER
          MERGE (w:Work {id: "#{@item.id}"})
              ON CREATE SET
                w.title = #{JSON.dump @item.title&.downcase || 'no_title'},
                w.year = #{@item.issued&.to_year || 0},
                w.type = "#{@item.type}",
                w.display_name = #{JSON.dump @item.to_s.downcase},
                w.container = #{JSON.dump @item.container_title&.downcase},
                w.url = "#{@item.url}",
                w.validatedBy = "#{@item.custom.validated_by&.keys&.join(",").to_s}"
      CYPHER
      )

      # authors
      @item.creators.each_with_index do |creator, index|
        a_var = "a#{index + 1}"
        family, given = creator.family_and_given.map(&:downcase)
        output.append(
          <<~CYPHER
            MERGE (#{a_var}:Author {family: #{JSON.dump family}, given:#{JSON.dump given}})
              ON CREATE SET
                #{a_var}.display_name = #{JSON.dump((creator.to_s)&.downcase)}
            MERGE (#{a_var})-[:CREATOR_OF]->(w)
        CYPHER
        )

        next if creator.x_affiliations.to_a.empty?

        # TO DO: remove duplicates, use only first affiliation for now
        affs = [creator.x_affiliations[0]]
        affs.each_with_index do |a, i_index|
          i_var = "i#{index + 1}_#{i_index + 1}"
          a.institution = a.institution.first if a.institution.is_a? Array
          institution = (a.institution || a.literal.to_s[..50] || 'unknown').downcase
          output.append(
            <<~CYPHER
              MERGE (#{i_var}:Institution {name: #{JSON.dump institution}})
              ON CREATE SET
                #{i_var}.country = #{JSON.dump a.country&.downcase.to_s},
                #{i_var}.ror = #{JSON.dump a.ror.to_s},
                #{i_var}.source = #{JSON.dump a.ror.to_s},
                #{i_var}.orig_aff = #{JSON.dump a.x_affiliation_source.to_s}
              MERGE (#{a_var})-[:AFFILIATED_WITH]->(#{i_var})
          CYPHER
          )
        end
      end

      # containers
      if @item.container_title
        abbr_cont_title = (if @item.type == ::Format::CSL::ARTICLE_JOURNAL && @item.journal_abbreviation
                            @item.journal_abbreviation
                          else
                            @item.custom.iso4_container_title || @item.container_title
                           end).downcase.gsub(/\p{P}/, '')
        output.append(
          <<~CYPHER
            MERGE (v:Venue {id: #{JSON.dump abbr_cont_title.downcase}})
              ON CREATE SET
                v.name = #{JSON.dump @item.container_title.downcase},
                v.issn = #{JSON.dump @item.issn&.first.to_s}
              MERGE (w)-[:PUBLISHED_IN]->(v)
        CYPHER
        )
      end

      # create relationship with citing item
      if @citing_item
        output.append(
          <<~CYPHER
            WITH w#{' '}
            MATCH (w2:Work {id:"#{@citing_item.id}"})
            MERGE (w2)-[:CITES]->(w)
        CYPHER
        )

      end

      output.append('RETURN "ok";')

      # references
      unless @item.x_references.empty?
        output.append("// #{'-' * 80}") if @pretty
        @item.x_references.each_with_index do |ref, _index|
          output.append Cypher.new(ref, citing_item: item, pretty: @pretty).serialize
        end
      end
      output.append("// #{(citing_item ? '-' : '*') * 80}") if @pretty
      output.map(&:strip).join("\n")
    end
  end
end
