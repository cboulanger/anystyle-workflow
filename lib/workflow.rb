# frozen_string_literal: true

require './lib/bootstap'
require 'ruby-progressbar'
require 'json'
require 'csv'

class Workflow
  @datasources = %w[crossref dimensions openalex]

  class << self
    def progress_defaults
      {
        format: "%t %b\u{15E7}%i %p%% %c/%C %a %e",
        progress_mark: ' ',
        remainder_mark: "\u{FF65}"
      }
    end

    def text_glob
      File.join('data', '2-txt', '*.txt')
    end

    def refs_glob
      File.join('data', '3-csl', '*.json')
    end

    def metadata_dir
      File.join('data', '0-metadata')
    end

    def export_dir
      File.join('data', '5-export')
    end

    def create_gold_csl
      anystyle = Datamining::AnyStyle.new('./models/finder.mod', './models/parser.mod')
      files = Dir.glob('data/0-gold/*.xml').map(&:untaint)
      files.each do |file_path|
        file_name = File.basename file_path, '.xml'
        xml = File.read file_path
        csl = anystyle.xml_to_csl xml
        File.write("data/0-gold/#{file_name}.json", JSON.pretty_generate(csl))
      end
    end

    # Generates CSL metadata for all files from the given datasources, using
    # cached data it has been already retrieved
    # @param [Array<String (frozen)>] datasources
    def generate_csl_metadata(datasources: %w[crossref dimensions openalex], limit: nil, break_on_error: false)
      # load cached metadata
      cache = {}
      datasources.each do |ds|
        file_path = "data/0-metadata/#{ds}.json" # un-hardcode!
        cache[ds] = if File.exist? file_path
                      JSON.load_file(file_path)
                    else
                      {}
                    end
      end

      # iterate over all files and retrieve missing metadata
      files = Dir.glob(refs_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Fetching missing metadata for citing items:',
                                       total: files.length,
                                       **progress_defaults)
      counter = 0
      files.each do |file_path|
        progressbar.increment

        file_name = File.basename(file_path, '.json')
        datasources.each do |ds|
          next if cache[ds][file_name]

          doi = file_name.sub(/_/, '/') # relies on file names being DOIs
          begin
            meta = Datasource::Utils.fetch_metadata_by_identifier doi, datasources: [ds]
            cache[ds][file_name] = meta.first unless meta.empty?
            counter += 1
          rescue StandardError => e
            $logger.error "While querying #{ds} for #{doi}, encountered exception: #{e.inspect}"
            raise e if break_on_error
          end
        end
        break if limit && counter >= limit
      end

      # write cache files to disk
      datasources.each do |ds|
        metadata_path = "data/0-metadata/#{ds}.json"
        json = JSON.pretty_generate(cache[ds])
        File.write(metadata_path, json)
      end
    end

    def extract_text_from_pdf(source_dir, overwrite: true)
      anystyle = Datamining::AnyStyle.new('./models/finder.mod', './models/parser.mod')
      source_dir ||= 'data/1-pdf'
      files = Dir.glob("#{source_dir}/*.pdf").map(&:untaint)
      progressbar = ProgressBar.create(title: 'Extracting text from PDF:',
                                       total: files.length,
                                       **progress_defaults)
      files.each do |file_path|
        file_name = File.basename(file_path, '.pdf')
        outfile = File.join('data', '2-txt', "#{file_name}.txt")
        progressbar.increment
        next if !overwrite && File.exist?(outfile)

        text = anystyle.extract_text(file_path)
        File.write(outfile, text)
      end
    end

    def extract_refs_from_text(overwrite: false, output_intermediaries: false)
      anystyle = Datamining::AnyStyle.new('./models/finder.mod', './models/parser.mod')
      anystyle.output_intermediaries = output_intermediaries
      files = Dir.glob(text_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Extracting references from text:',
                                       total: files.length,
                                       **progress_defaults)
      files.each do |file_path|
        file_name = File.basename(file_path, '.txt')
        outfile = File.join('data', '3-csl', "#{file_name}.json")
        progressbar.increment
        next if !overwrite && File.exist?(outfile)

        csl = anystyle.extract_refs_as_csl(file_path)
        File.write outfile, JSON.pretty_generate(csl)
      end
    end

    def timestamp
      DateTime.now.strftime('%Y-%m-%d_%H-%M-%S')
    end

    def extraction_stats
      files = Dir.glob(refs_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Collecting extraction statistics:',
                                       total: files.length,
                                       **progress_defaults)
      outfile = File.join('data', '5-export', "extraction-stats-#{timestamp}.csv")
      stats = []
      columns = %w[file journal year a_all a_rejected a_potential a_valid gold]

      # vendor data
      vendors = %w[crossref dimensions openalex wos]
      columns += vendors
      vendor_cache = {}
      vendors.each do |vendor|
        vendor_path = "data/0-metadata/#{vendor}.json"
        vendor_cache[vendor] = (JSON.load_file vendor_path if File.exist? vendor_path)
      end
      crossref_meta = vendor_cache['crossref']
      raise 'CrossRef metadata is required' unless crossref_meta

      stats.append columns
      files.each do |file_path|
        progressbar.increment
        file_name = File.basename(file_path, '.json')
        begin
          year = crossref_meta[file_name]['issued']['date-parts'].first.first
          journal = case crossref_meta[file_name]['container-title']
                    when /^Zeitschrift/
                      'zfrsoz'
                    else
                      'jls'
                    end
        rescue StandardError
          $logger.error "Problem parsing year/journal for #{file_name}"
          next
        end
        row = [file_name, journal, year]
        # all found
        all = JSON.load_file(file_path)
        row.append(all.length)
        # rejected items
        rf_path = "data/3-csl-rejected/#{file_name}.json"
        row.append(File.exist?(rf_path) ? JSON.load_file(rf_path).length : nil)
        # all non-rejected are potential candidates
        potential = filter_cited_items(all)
        row.append(potential.length)
        # all valid
        row.append(filter_cited_items(all).length)
        # gold files
        gf_path = "data/0-gold/#{file_name}.json"
        row.append(File.exist?(gf_path) ? JSON.load_file(gf_path).length : nil)
        # vendor data
        vendors.each do |vendor|
          refs = vendor_cache.dig(vendor, file_name)
          refs = refs.first if refs.is_a? Array
          refs = refs['reference'] if refs.is_a? Hash
          row.append(refs.is_a?(Array) ? refs.length : 0)
        end

        # write row
        stats.append(row)
      end
      File.write(outfile, stats.map(&:to_csv).join)
      puts "Data written to #{outfile}..."
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
      files = Dir.glob(refs_glob).map(&:untaint)
      progressbar = ProgressBar.create(title: 'Exporting to WOS file:',
                                       total: files.length,
                                       **progress_defaults)
      metadata_file = File.join(metadata_dir, 'crossref.json')
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
                                       **progress_defaults)
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
