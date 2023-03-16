# frozen_string_literal: true
require 'httpx'
require 'erb'

module Datasource
  class ZoteroLocal
    class << self

      # @return [String]
      def id
        'zotero-local'
      end

      # @return [String]
      def name
        'Data from querying the local http API of Zotero'
      end

    end
  end
end