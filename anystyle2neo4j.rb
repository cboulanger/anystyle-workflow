# frozen_string_literal: true

require './lib/libs'
# todo turn into module
logger = $logger

# loop over all files in the corpus
corpus = Datasource::Corpus.new(ENV['CORPUS_DIR'].untaint, ENV['CORPUS_GLOB_PATTERN'])
files = corpus.files(ENV['CORPUS_FILTER'])

files.each do |file_path|
  # get metadata of citing document from its filename
  file_name = File.basename(file_path, '.pdf')
  logger.debug "Analyzing #{file_name}"
  work = Corpus.get_metadata_from_filename(file_name, true) # returns a Work or {family, date, title,doi}
  next if work.nil?

  # create citing item
  #begin
  if (work.is_a? Work) && work.imported
    logger.info "#'{family} (#{date}) #{title[0, 30]}' has alread been imported"
    next
  else
    # create an entry with only date and title
    citing_work = Work.find_or_create_by({ date: work.date, title: work.title })
  end
  logger.debug "Created/retrieved #{family} #{title}, #{date}"

  # save DOI
  unless work.doi.nil?
    citing_work.doi = work.doi
    citing_work.save
  end

  #
  citing_creator = Creator.find_or_create_by(family: work.family)
  CreatorOf.new(from_node: citing_creator, to_node: citing_work, role: :author)
  citing_work.save # adds author to display_name
  
  logger.info '======================================================================='
  logger.info "Citing work #{citing_work.display_name}:"
  #  rescue StandardError => e
  #logger.warn "Could not create #{family} #{title} #{date}: #{e.message}"
  #next
  # end
  #
  # extract references from PDF
  #
  refs = Datamining::AnyStyle.extract_references(file_path)
  # remove low quality refs and false positives
  refs = refs.reject { |w| (w['author'].nil? && w['editor'].nil?) || w['title'].nil? || w['issued'].nil? }
  # iterate over extracted reference data
  logger.info "Found #{refs.length} references. "

  next

  refs.each do |w|
    # AnyStyle extraction data as a hash, lots of false positives
    #logger.debug { w.pretty_inspect }
    author = w[:author]
    editor = w[:editor]
    title = w[:title]&.first
    date = w[:date]&.first
    type = w[:type]

    if type.nil?
      logger.debug 'No type, skipping...'
      next
    end

    if (author.nil? && editor.nil?) || title.nil? || date.nil?
      logger.debug 'No author/editor, title or date, skipping...'
      next
    end

    # lookup cited item:  match item with author last name, date and the longest two words in the title, using
    name = author&.first&.[](:family) || author&.first&.[](:literal) #||
    #editor&.first&.[](:family) || editor&.first&.[](:literal)
    if name.nil?
      logger.warn "Could not find author for #{title[0, 30]} #{date}"
      next
    end
    # matches = Matcher::BibliographicItem.lookup(name, title, date)
    # if matches.length == 0
    #   logger.warn "Could not find match for #{name} #{title[0, 30]} #{date}"
    #   next
    # end
    # m = matches.first
    # logger.debug "====================================================================="
    # logger.debug "First matdch is"
    # logger.debug m
    # logger.debug "====================================================================="
    #
    # creators = m['creators']
    # title = m['title'].first
    # date = m['date'].first
    # type = m['type'].last
    # ISBN = m['ISBN']&.join(' ')

    creators = author

    # create cited item
    #begin
    cited_work = Work.find_or_create_by(title:, date:)
    #cited_work.ISBN = ISBN
    citing_work.note = w.to_json
    cited_work.type = type
    cited_work.save
    Citation.create(from_node: citing_work, to_node: cited_work)
    logger.info "Linked cited work #{cited_work.display_name}"
    #rescue StandardError => e
    #logger.warn "Could not create #{title} #{title}: #{e.message}"
    #next
    #end
    # link authors
    creators&.each do |c|
      family = c[:family]
      given = c[:given]
      unless family.nil?
        # todo save full creator metadata
        cited_creator = Creator.find_or_create_by(family:, given:)
        CreatorOf.create(from_node: cited_creator, to_node: cited_work, role: :author)
        logger.info "Linked cited author #{cited_creator.display_name}"
      end
    end
    # link container/journal
    book = nil
    journal = nil
    container_title = w[:'container-title']&.first
    unless container_title.nil?
      if w[:type] == 'article-journal'
        journal = Journal.find_or_create_by(title: container_title)
        ContainedIn.create(from_node: cited_work, to_node: journal)
        logger.info "Linked journal #{journal.title}"
      else
        book = EditedBook.find_or_create_by(title: container_title, date:, type: 'book')
        ContainedIn.create(from_node: cited_work, to_node: book)
        logger.info "Linked edited book #{book.title}"
      end
    end
    # link editors to work
    next unless journal.nil?
    w[:editor]&.each do |e|
      citing_creator = Creator.find_or_create_by(family: e[:family], given: e[:given])
      citing_creator.save
      if book.nil?
        CreatorOf.create(from_node: citing_creator, to_node: cited_work, role: :editor)
        logger.info "Linked editor #{citing_creator.display_name} to work #{cited_work.display_name}"
      else
        CreatorOf.create(from_node: citing_creator, to_node: book, role: :editor)
        logger.info "Linked editor #{citing_creator.display_name} to container #{cited_work.display_name}"
      end
    end
  end
  # all refs have been imported
  #citing_work.imported = true
  #citing_work.save
end
