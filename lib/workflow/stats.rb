module Workflow
  module Statistics

    extend self
    def compile(verbose: false, type: 'reference')
      files = Dir.glob(File.join(Path.anystyle_json, '*.json'))
      unless verbose
        progressbar = ProgressBar.create(title: "Collecting statistics on #{type}s:",
                                         total: files.length,
                                         **::Workflow::Config.progress_defaults)
      end
      outfile = File.join(Path.stats, "#{type}-stats-#{Utils.timestamp}.csv")
      stats = []
      case type
      when 'reference'
        columns = %w[file journal year a_all a_rejected a_potential]
      when 'affiliation'
        columns = %w[file journal year]
      else
        raise "Type must be 'reference' or 'affiliation'"
      end

      # vendor data
      vendors = Workflow::Utils.datasource_ids
      columns += vendors

      # columns row
      stats.append columns

      # iterate over files
      puts "Analysing #{files.length} files..." if verbose
      files.each do |file_path|
        file_name = File.basename(file_path, '.json')
        doi = file_name.sub('_', '/')

        if verbose
          puts " - #{file_name}"
        else
          progressbar.increment unless verbose
        end

        crossref_item = Datasource::Crossref.import_items([doi]).first
        raise "No metadata for #{file_name}" if crossref_item.nil?

        year = crossref_item.year
        journal_abbrv = crossref_item.container_title.scan(/\S+/).map { |w| w[0] }.join
        row = [file_name, journal_abbrv, year]

        case type
        when 'reference'
          # ##############
          # Reference Data
          # ##############
          # all found from anystyle json
          all = JSON.load_file(file_path)
          row.append(all.length)
          # rejected csl items
          rf_path = File.join Path.csl_rejected, "#{file_name}.json"
          row.append(File.exist?(rf_path) ? JSON.load_file(rf_path).length : nil)
          # potential csl items
          pf_path = File.join Path.csl, "#{file_name}.json"
          row.append(File.exist?(pf_path) ? JSON.load_file(pf_path).length : nil)
          # vendor data
          vendors.each do |vendor|
            vendor_refs = Datasource.by_id(vendor).import_items([doi]).first&.x_references
            row.append(vendor_refs.is_a?(Array) ? vendor_refs.length : 0)
          end
        else
          # #################
          # Affiliation data
          # #################
          vendors.each do |vendor|
            # @type [Format::CSL::Item]
            vendor_item = Datasource.by_id(vendor).import_items([doi]).first
            return 0 if vendor_item.nil?

            num_aff = vendor_item.creators.reduce(0) {|sum, c| sum + c.x_affiliations&.length || 0 }
            row.append(num_aff)
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
