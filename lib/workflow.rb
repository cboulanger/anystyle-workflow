# frozen_string_literal: true

require './lib/libs'
require 'ruby-progressbar'
require 'json'

class Workflow
  class << self
    def progress_defaults
      {
        format: "%t %b\u{15E7}%i %p%% %c/%C %a %e",
        progress_mark: ' ',
        remainder_mark: "\u{FF65}"
      }
    end

    def pdf_glob
      File.join('data', '1-pdf', '*.pdf')
    end

    def text_glob
      File.join('data', '2-txt', '*.txt')
    end

    def refs_glob
      File.join('data', '3-csl', '*.json')
    end

    def metadata_file_path
      File.join('data', '5-export', 'metadata.json')
    end

    def wosexport_file_path
      File.join('data', '5-export', 'export.wos')
    end

    def extract_text_from_pdf
      files = Dir.glob(pdf_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Extracting text from PDF:',
                                       total: files.length,
                                       **progress_defaults)
      files.each do |file_path|
        file_name = File.basename(file_path, '.pdf')
        outfile = File.join('data', '2-txt', "#{file_name}.txt")
        progressbar.increment
        next if File.exist? outfile

        text = anystyle.extract_text(file_path)
        File.write(outfile, text)
      end
    end

    def extract_refs_from_txt
      anystyle = Datamining::AnyStyle.new('./models/finder.mod', './models/parser.mod')
      files = Dir.glob(text_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Extracting references from text:',
                                       total: files.length,
                                       **progress_defaults)
      files.each do |file_path|
        file_name = File.basename(file_path, '.txt')
        outfile = File.join('data', '3-csl', "#{file_name}.json")
        progressbar.increment
        next if File.exist? outfile

        csl = anystyle.extract_refs_as_csl(file_path)
        File.write outfile, JSON.pretty_generate(csl)
      end
    end

    def match_references
      files = Dir.glob(refs_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Matching references:',
                                       total: files.length,
                                       **progress_defaults)
      files.each do |file_path|
        file_name = File.basename(file_path, '.json')
        outfile = File.join('data', '4-csl-matched', "#{file_name}.json")
        progressbar.increment
        refs = JSON.load_file(file_path)
        identifiers = if File.exist? outfile
                        JSON.load_file(outfile)
                      else
                        []
                      end
        refs.each_with_index do |item, index|
          identifiers[index] = Matcher::CslMatcher.lookup(item) if identifiers[index].nil?
        end
        File.write(outfile, JSON.pretty_generate(identifiers))
      end
    end

    def export_citing_items
      files = Dir.glob(refs_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Fetching metadata for citing items:',
                                       total: files.length,
                                       **progress_defaults)
      outfile = metadata_file_path
      result = if File.exist? outfile
                 JSON.load_file(outfile)
               else
                 {}
               end

      files.each do |file_path|
        progressbar.increment
        file_name = File.basename(file_path, '.json')
        next unless result[file_name].nil?
        begin
          result[file_name] = Datasource::Utils.get_metadata_from_filename(file_name)
        rescue StandardError => e
          puts "Encountered exception: #{e.inspect}, skipping #{file_name}..."
        end
      end

      text = JSON.pretty_generate(result)
      File.write(outfile, text)
    end

    def export_to_wos
      files = Dir.glob(refs_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Exporting to WOS file:',
                                       total: files.length,
                                       **progress_defaults)
      export_citing_items unless File.exist? metadata_file_path
      metadata = JSON.load_file(metadata_file_path)
      Export::Wos.write_header(wosexport_file_path)
      files.each do |file_path|
        progressbar.increment
        file_name = File.basename(file_path, '.json')
        item = metadata[file_name]
        next if item.nil?
        cited_items = JSON.load_file(file_path)
        Export::Wos.append_record(wosexport_file_path, item, cited_items)
      end
    end

    def export_to_neo4j
      Datasource::Neo4j.connect
      files = Dir.glob(File.join('data', '3-csl', '*.json')).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Matching references:',
                                       total: files.length,
                                       **progress_defaults)
      files.each do |file_path|
        progressbar.increment
        file_name = File.basename(file_path, '.json')
        work = Datasource::Utils.get_metadata_from_filename(file_name, true) # returns a Work or {family, date, title,doi}
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
