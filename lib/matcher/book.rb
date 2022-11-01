# frozen_string_literal: true

module Matcher
  class Book
    def self.lookup(name, title, date)
      Datasource::Lobid.lookup(name, title, date)
    end
  end
end
