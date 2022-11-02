require './lib/datasource/corpus'
require './lib/datasource/crossref'
require './lib/datasource/neo4j'
require './lib/datasource/lobid'
require './lib/datasource/openlibrary'

module Datasource
  class Utils
    class << self
      def title_keywords(title, min_length = 4, max_number = 5)
        title.downcase
             .scan(/[[:alnum:]]+/)
             .reject { |w| w.length < min_length }
             .first(max_number)
      end

      def author_lastname(name)
        name.gsub(/[^\p{L}\s]/, '').split(' ').reject { |w| w.length < 3 }.join(' ')
      end

      def get_metadata_from_filename(file_name, query_neo4j=false)
        logger = $logger
        if file_name.start_with? '10.'
          # is it a DOI-like string?
          begin
            doi = file_name.sub(/_/, '/')
            if query_neo4j
              logger.debug "Looking up doi #{doi} in Neo4J..."
              work = Work.find_by(doi:)
              return work unless work.nil?
            end
            return Datasource::Crossref.items_by_doi([doi])[0]
          rescue StandardError
            logger.warn "Cannot find crossref data for #{file_name}"
            return nil
          end
        else
          # otherwise, expect "Lastname (Year) Title words" pattern
          logger.debug "Using filename #{file_name}"
          m = file_name.match(/^(?:\d{1,3} )?(.+?)[ -(]+(\d{4})[ -)]+(.+)$/)
          family, date, title = m.to_a.slice(1, 3).map &:strip
          if m.nil?
            logger.warn "Cannot parse file name #{file_name}"
            return nil
          end
        end
        {
          family:,
          date:,
          title:,
          doi:
        }
      end
    end
  end
end