# frozen_string_literal: true

module Workflow
  class Import
    class << self
      def metadata_file_path(datasource, outfile_suffix)
        File.join(Path.metadata, "#{datasource}#{outfile_suffix ? '-' : ''}#{outfile_suffix || ''}.json")
      end

      # Generates CSL metadata for all files from the given datasources, using
      # cached data if it has been already retrieved
      # @param [Array<String (frozen)>] datasources
      def generate_csl_metadata(outfile_suffix:, limit:, datasources:,
                                source_dir: Path.anystyle_json,
                                break_on_error: true,
                                verbose: false,
                                use_cache: true)

        if !datasources.is_a?(Array) || datasources.empty?
          raise "datasources must be non-empty array"
        end

        # load cached metadata
        cache = {}
        datasources.each do |ds|
          file_path = metadata_file_path(ds, outfile_suffix)
          cache[ds] = if use_cache && File.exist?(file_path)
                        JSON.load_file(file_path)
                      else
                        {}
                      end
        end

        # iterate over all files and retrieve missing metadata
        files = Dir.glob(File.join(source_dir || Path.csl, '*.json'))
        unless verbose
          progressbar = ProgressBar.create(title: 'Fetching missing metadata:',
                                           total: files.length,
                                           **Config.progress_defaults)
        end

        counter = 0
        imported = 0
        total = [files.length, limit || files.length].min

        # iterate over all files
        files.each do |file_path|
          progressbar.increment unless verbose

          file_name = File.basename(file_path, File.extname(file_path))
          doi = file_name.sub(/_/, '/') # relies on file names being DOIs

          datasources.each do |ds|
            counter += 1
            if cache[ds][file_name]
              puts "#{doi}: Already imported from #{ds}" if verbose
              next
            end
            puts "Importing #{doi} from #{ds} #{counter}/#{total}..." if verbose

            begin
              meta = Datasource::Utils.import_by_identifier(doi, datasources: [ds], verbose:)
              if meta.length.positive?
                cache[ds][file_name] = meta.first
                imported += 1
              end

            rescue StandardError => e
              puts "While querying #{ds} for #{doi}, encountered exception: #{e.inspect}"
              raise e if break_on_error
            end
          end

          # save cache to disk after importing five records or at the last iteration
          if (imported > 0 && (imported % 5).zero?) || counter == total
            datasources.each do |ds|
              metadata_path = metadata_file_path(ds, outfile_suffix)
              json = JSON.pretty_generate(cache[ds])
              File.write(metadata_path, json)
              puts "Saved #{ds} metadata to #{metadata_path}" if verbose
            end
          end

          break if counter >= total
        end
      end
    end
  end
end
