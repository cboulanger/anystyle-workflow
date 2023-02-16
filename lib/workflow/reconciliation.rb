module Workflow
  class Reconciliation



    class << self

      def metadata_file_path(datasource, outfile_suffix)
        File.join(Path.metadata, "#{datasource}#{outfile_suffix ? '-' : ''}#{outfile_suffix||''}.json")
      end

      # Generates CSL metadata for all files from the given datasources, using
      # cached data if it has been already retrieved
      # @param [Array<String (frozen)>] datasources
      def generate_csl_metadata(datasources: %w[crossref dimensions openalex],
                                source_dir:Path.anystyle_json,
                                outfile_suffix:,
                                limit:,
                                break_on_error: true,
                                verbose: false)

        # load cached metadata
        cache = {}
        datasources.each do |ds|
          file_path = metadata_file_path(ds, outfile_suffix)
          cache[ds] = if File.exist? file_path
                        JSON.load_file(file_path)
                      else
                        {}
                      end
        end

        # iterate over all files and retrieve missing metadata
        files = Dir.glob(File.join(source_dir || Path.csl, '*.json'))
        progressbar = ProgressBar.create(title: 'Fetching missing metadata for citing items:',
                                         total: files.length,
                                         **Config.progress_defaults) unless verbose
        counter = 0
        total = [files.length, limit || files.length].min
        files.each do |file_path|
          progressbar.increment unless verbose

          file_name = File.basename(file_path, File.extname(file_path))
          doi = file_name.sub(/_/, '/') # relies on file names being DOIs

          datasources.each do |ds|
            if cache[ds][file_name]
              puts "#{doi}: Already imported from #{ds}"
              next
            end
            puts "Importing #{doi} from #{ds} #{counter+1}/#{total}..."

            begin
              meta = Datasource::Utils.fetch_metadata_by_identifier(doi, datasources: [ds], verbose:)
              cache[ds][file_name] = meta.first if meta.length.positive?
              counter += 1
            rescue StandardError => e
              puts "While querying #{ds} for #{doi}, encountered exception: #{e.inspect}"
              raise e if break_on_error
            end
          end

          # save cache to disk every five records or at the last iteration
          if counter % 5 == 0 || counter == total
            datasources.each do |ds|
              metadata_path = metadata_file_path(ds, outfile_suffix)
              json = JSON.pretty_generate(cache[ds])
              File.write(metadata_path, json)
              puts "Saved #{ds} metadata to #{metadata_path}"
            end
          end

          break if counter >= total
        end
      end
    end
  end
end