module Datasource
  class Corpus
    def initialize(corpus_dir, glob_pattern)
      @corpus_dir = corpus_dir
      @corpus_files = Dir.glob(File.join(corpus_dir, glob_pattern)).shuffle
    end

    def files(filter = nil)
      if filter
        @corpus_files.filter { |f| f.match(filter) }
      else
        @corpus_files
      end
    end
  end


end