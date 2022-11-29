module Workflow
  class Export
    class << self


      def filter_cited_items(cited_items)
        cited_items.reject do |item|
          item['title'].nil? || item['issued'].nil? ||
            !(item['author'] || item['editor']) ||
            (item['author'] || item['editor']).any? { |c| c['given'] && (c['family'].nil? || c['family'].empty?) }
        end
      end

      def read_dimensions_data
        files = Dir.glob('data/0-metadata/Dimensions-*.csv').map(&:untaint)
        data = []
        files.each do |file_path|
        end
      end

      # given a unique, resolvable id (currently, DOI and ISBN), return cited items as CSL-JSON
      # from the sources available in this workflow
      def get_cited_items(unique_id)
        case unique_id
        when /^978/, /^isbn:/i
          nil
        when /^10\./, /^doi:/i
          # extracted refs
          file_path = "data/3-refs/#{unique_id.sub('/', '_')}"
          items = if File.exist? file_path
                    filter_cited_items(JSON.load_file(file_path))
                  else
                    {}
                  end

        end
      end

      def export_to_wos
        files = Dir.glob(::Workflow::Config.refs_glob).map(&:untaint)
        progressbar = ProgressBar.create(title: 'Exporting to WOS file:',
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)
        metadata_file = File.join('data/0-metadata', 'crossref.json')
        generate_csl_metadata unless File.exist? metadata_file
        metadata = JSON.load_file(metadata_file)
        wosexport_file_path = File.join('data', '5-export', "wos-export-#{timestamp}.txt")
        Export::Wos.write_header(wosexport_file_path)
        files.each do |file_path|
          progressbar.increment
          file_name = File.basename(file_path, '.json')
          item = metadata[file_name]
          next if item.nil?

          cited_items = get_cited_items(item['DOI'])
          Export::Wos.append_record(wosexport_file_path, item, cited_items)
        end
      end

      def export_to_neo4j
        Datasource::Neo4j.connect
        files = Dir.glob(File.join('data', '3-csl', '*.json')).map(&:untaint)
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