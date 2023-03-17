# frozen_string_literal: true

module Workflow
  module Statistics
    module_function

    # @param [Array<String>] ids
    # @param [Boolean] verbose
    # @param [String] type
    # @param [String] text_dir
    # @param [Workflow::Dataset] dataset
    # @param [Integer] limit
    def generate(ids,
                 verbose: false,
                 type: 'reference',
                 outfile: nil,
                 text_dir: nil,
                 dataset: nil,
                 limit: nil)
      unless verbose
        progressbar = ProgressBar.create(title: "Collecting statistics on #{type}s:",
                                         total: ids.length,
                                         **::Workflow::Config.progress_defaults)
      end
      outfile ||= File.join(Path.stats, "#{type}-stats-#{Utils.timestamp}.csv")
      stats = []
      columns = %w[id journal year]
      columns.append('fulltext') if text_dir
      case type
      when 'reference'
        columns += %w[a_all a_rejected a_potential]
      when 'affiliation', 'abstract'
        # pass
      else
        raise "Invalid stat type '#{type}'"
      end

      # vendor data
      datasource_ids = %w[grobid openalex crossref dimensions wos]
      columns += datasource_ids

      # dataset
      columns.append(dataset.name || 'dataset') if dataset

      # columns row
      stats.append columns

      # iterate over files
      puts "Analysing #{ids.length} metadata records..." if verbose

      ids.each_with_index do |id, index|
        break if limit && index >= limit

        if verbose
          puts " - #{id}".colorize(:green)
        else
          progressbar.increment unless verbose
        end

        crossref_item = Datasource::Crossref.import_items([id]).first

        if crossref_item.nil?
          puts "   No metadata".colorize(:red) if verbose
          next
        end

        puts "   => #{crossref_item.creator_year_title.join(" ")}".colorize(:green) if verbose

        # dataset
        dataset_item = dataset.item_by_id(id) if dataset

        year = crossref_item.year
        journal_abbrv = crossref_item.container_title.to_s.scan(/\S+/).map { |w| w[0] }.join
        row = [id, journal_abbrv, year]
        file_name = Utils.to_filename(id)

        # fulltext available?
        row.append File.exist?(File.join(text_dir, "#{file_name}.txt")) ? 1 : 0 if text_dir

        case type
        when 'reference'

          # ##############
          # Reference Data
          # ##############

          # all found from anystyle json
          csl_json_path = File.join Path.csl, "#{file_name}.json"
          all = if File.exist? csl_json_path
                  JSON.load_file csl_json_path
                else
                  []
                end
          row.append(all.length)

          # rejected csl items
          rf_path = File.join Path.csl_rejected, "#{file_name}.json"
          row.append(File.exist?(rf_path) ? JSON.load_file(rf_path).length : nil)

          # potential csl items
          pf_path = File.join Path.csl, "#{file_name}.json"
          row.append(File.exist?(pf_path) ? JSON.load_file(pf_path).length : nil)

          # reference data from other datasources
          datasource_ids.each do |datasource_id|
            refs = Datasource.by_id(datasource_id).import_items([id]).first&.x_references
            row.append(refs.is_a?(Array) ? refs.length : 0)
          end

          # dataset
          row.append dataset_item&.x_references&.length if dataset

        when 'affiliation'
          # #################
          # Affiliation data
          # #################

          # count affiliations
          row += datasource_ids.map do |datasource_id|
            item = Datasource.by_id(datasource_id).import_items([id]).first
            puts "   #{datasource_id}:" if verbose
            item&.creators&.reduce(0) do |sum, c|
              aff = c.x_affiliations || []
              puts "    #{c.to_s}: #{aff.map(&:to_h)}" if verbose
              sum + aff.length
            end
          end

          # dataset
          if dataset
            puts "   #{dataset.name}:" if verbose
            row.append(dataset_item&.creators&.reduce(0) do |sum, c|
              aff = c.x_affiliations || []
              puts "    #{c.to_s}: #{aff.map(&:to_h)}" if verbose
              sum + aff.length
            end)
          end
        when 'abstract'
          # #################
          # Abstract data
          # #################

          # count abstracts
          row += datasource_ids.map do |datasource_id|
            Datasource.by_id(datasource_id).import_items([id]).first&.abstract.to_s.empty? ? 0 : 1
          end

          # dataset
          if dataset
            dataset_item.abstract.to_s.empty? ? 0 : 1
          end

        end
        # write row
        stats.append(row)
      end
      File.write(outfile, stats.map(&:to_csv).join)
      puts "Data written to #{outfile}..."
    end
  end
end
