module Datasource
  class Anystyle

    class << self

      def get_references_by_doi(doi)
        file_path = File.join(::Workflow::Path.csl, "#{doi.sub('/', '_')}.json")
        if File.exist?(file_path)
          JSON.load_file(file_path)
        else
          nil
        end
      end
    end
  end
end