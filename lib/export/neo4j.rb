module Export
  class Neo4j
    class << self
      def to_neo4j
        Datasource::Neo4j.connect
        files = Dir.glob(File.join('data', '3-csl', '*.json'))
        progressbar = ProgressBar.create(title: 'Matching references:',
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)
        files.each do |file_path|
          progressbar.increment
          file_name = File.basename(file_path, '.json')
          # work = Datasource::Utils.fetch_metadata_by_identifier(file_name, datasources: ['neo4j']) # returns a Work or {family, date, title,doi}
          case work
          when Work
            family = work.first_creator_name
            title = work.title
            date = work.date
          when Hash
            family = work[:family]
            title = work[:title]
            date = work[:date]
          else
            $logger.warn("Cannot find metadata for #{file_name}")
            next
          end

          if (work.is_a? Work) && work.imported
            logger.info "#'{family} (#{date}) #{title[0, 30]}' has alread been imported"
            next
          end

          # create an entry with only date and title
          citing_work = Work.find_or_create_by({ date:, title: })
          logger.info "#{family} (#{date}): #{title}:"

          # save creator
          citing_creator = Creator.find_or_create_by(family:)
          CreatorOf.new(from_node: citing_creator, to_node: citing_work, role: :author)
          citing_work.save

          # save references
          refs = JSON.load_file(file_path)
          refs.each do |w|
            creator = if w['editor'].length.positive?
                        w['editor']
                      else
                        w['author']
                      end
            title = w['title']
            date = w['date']
            type = w['type']
            name = creator.first['family'] || creator.first['literal']
            logger.warn "  => #{name}, #{title[0, 30]} #{date}: "
            if name.nil?
              logger.warn '    - Could not find author, skipping'
              next
            end

            # create cited item
            cited_work = Work.find_or_create_by(title:, date:)
            cited_work.note = w.to_json
            cited_work.type = type
            cited_work.save
            Citation.create(from_node: citing_work, to_node: cited_work)

            # link authors
            creator.each do |c|
              family = c['family']
              given = c['given']
              next if family.nil?

              cited_creator = Creator.find_or_create_by(family:, given:)
              CreatorOf.create(from_node: cited_creator, to_node: cited_work, role: :author)
              logger.info "    - Linked cited author #{cited_creator.display_name}"
            end

            # link container/journal
            book = nil
            journal = nil
            container_title = w['container-title']&.first
            unless container_title.nil?
              if w['type'] == 'article-journal'
                journal = Journal.find_or_create_by(title: container_title)
                ContainedIn.create(from_node: cited_work, to_node: journal)
                logger.info "    - Linked journal #{journal.title}"
              else
                book = EditedBook.find_or_create_by(title: container_title, date:, type: 'book')
                ContainedIn.create(from_node: cited_work, to_node: book)
                logger.info "    - Linked edited book #{book.title}"
              end
            end
            next unless journal.nil?

            # link editors to work
            w['editor']&.each do |e|
              citing_creator = Creator.find_or_create_by(family: e['family'], given: e['given'])
              citing_creator.save
              if book.nil?
                CreatorOf.create(from_node: citing_creator, to_node: cited_work, role: :editor)
                logger.info "    - Linked editor #{citing_creator.display_name} to work #{cited_work.display_name}"
              else
                CreatorOf.create(from_node: citing_creator, to_node: book, role: :editor)
                logger.info "    - Linked editor #{citing_creator.display_name} to container #{cited_work.display_name}"
              end
            end
          end
          citing_work.imported = true
          citing_work.save
          # break
        end
      end
    end
  end
end