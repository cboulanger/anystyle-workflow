module Linking
  class Article
    def self.lookup(name, title, date)
      Datasource::Crossref.lookup(name, title, date)
    end
  end
end
