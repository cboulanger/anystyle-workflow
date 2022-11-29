module Workflow
  class Reconciliation
    class << self
      # Generates CSL metadata for all files from the given datasources, using
      # cached data if it has been already retrieved
      # @param [Array<String (frozen)>] datasources
      def generate_csl_metadata(datasources: %w[crossref dimensions openalex], limit: nil, break_on_error: false)
        # load cached metadata
        cache = {}
        datasources.each do |ds|
          file_path = File.join(Path.metadata, "#{ds}.json")
          cache[ds] = if File.exist? file_path
                        JSON.load_file(file_path)
                      else
                        {}
                      end
        end

        # iterate over all files and retrieve missing metadata
        files = Dir.glob(::Workflow::Config.refs_glob).map(&:untaint)
        progressbar = ProgressBar.create(title: 'Fetching missing metadata for citing items:',
                                         total: files.length,
                                         **Config.progress_defaults)
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
          metadata_path = File.join(Path.metadata, "#{ds}.json")
          json = JSON.pretty_generate(cache[ds])
          File.write(metadata_path, json)
        end
      end

      def match_references
        files = Dir.glob(::Workflow::Config.refs_glob).map(&:untaint)
        progressbar = ProgressBar.create(title: 'Matching references:',
                                         total: files.length,
                                         **Config.progress_defaults)
        files.each do |file_path|
          file_name = File.basename(file_path, '.json')
          outfile = File.join(Path.csl_matched, "#{file_name}.json")
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

    end
  end
end