module Datasource
  class Corpus
    def initialize(corpus_dir, glob_pattern)
      @corpus_dir = corpus_dir
      @corpus_files = Dir.glob(File.join(corpus_dir, glob_pattern)).map(&:untaint).shuffle
    end

    def files(filter = nil)
      if filter
        @corpus_files.filter { |f| f.match(filter) }
      else
        @corpus_files
      end
    end
  end

  def self.get_metadata_from_filename(file_name, query_neo4j=false)
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
        logger.debug "Looking up doi #{doi} in crossref..."
        item = Datasource::Crossref.item_by_doi doi
        logger.debug item
        family = item[:family]
        date = item[:date]
        title = item[:title]
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