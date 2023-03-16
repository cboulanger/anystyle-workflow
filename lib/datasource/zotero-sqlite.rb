# frozen_string_literal: true

require 'sqlite3'

module Datasource
  # this class allows you to query all of the data in your local Zotero application by directly accessing the
  # zotero.sqlite file. Accessing this file while Zotero is running is not possible. You either need to stop
  # Zotero or use a copy.
  class ZoteroSqlite < Datasource
    class << self
      # @return [String]
      def id
        'zotero-sqlite'
      end

      # @return [String]
      def name
        'Data from querying zotero.sqlite'
      end

      def connect
        return unless @db.nil?

        @db = SQLite3::Database.new(ENV['ZOTERO_SQLITE_PATH'] || raise('ZOTERO_SQLITE_PATH not set.'))
      end

      # @param [::Format::CSL::Item] item
      # @return [::Format::CSL::Item | nil]
      def lookup(item)
        raise 'Argument must be Format::CSL::Item' unless item.is_a? ::Format::CSL::Item

        connect
        author, year, title = item.creator_year_title
        container_title = item.container_title
      end

      # @param [Model::Zotero::Item] zotero_item
      def findSimilar(zotero_item)
        connect
        # The following sql was constructed with the help of ChatGPT!
        z = zotero_item.to_h
        n = z.keys.length
        sql1 = <<~SQL
          SELECT i."key"
          FROM items i
            JOIN itemData id ON i.itemID = id.itemID
            JOIN itemDataValues idv ON idv.valueID = id.valueID
            JOIN fields f ON f.fieldID = id.fieldID
          WHERE (f.fieldName = ? AND idv.value like ?)
          GROUP BY i.key
          HAVING COUNT(DISTINCT f.fieldName || idv.value) = ?
        SQL
        if n > 1
          or_where = ['  OR (f.fieldName = ? AND idv.value like ?)'] * (n - 1)
          sql1 = sql1.split("\n").insert(6, *or_where).join("\n")
        end
        vars1 = z.reduce([]) { |a, (k, v)| a + [k, "%#{v}%"] } + [n]
        sql2 = <<~SQL
          SELECT 	json_object(
            'key', i."key",
            'creators', json_group_array(
              DISTINCT json_object(
                'lastName', c.lastName,
                'firstName', c.firstName,
                'creatorType', cT.creatorType
              )
            ),
            'title',  MAX(CASE WHEN f.fieldName = 'title' THEN idv.value END),
            'date',   MAX(CASE WHEN f.fieldName = 'date' THEN idv.value END),
            'ISBN',   MAX(CASE WHEN f.fieldName = 'ISBN' THEN idv.value END),
            'DOI',    MAX(CASE WHEN f.fieldName = 'DOI' THEN idv.value END)
          )
          FROM items i
          JOIN itemData id ON i.itemID = id.itemID
          JOIN itemDataValues idv ON idv.valueID = id.valueID
          JOIN fields f ON f.fieldID = id.fieldID
          JOIN itemCreators iC on i.itemID = iC.itemID
          JOIN creators c on iC.creatorID = c.creatorID
          JOIN creatorTypes cT on iC.creatorTypeID = cT.creatorTypeID
          WHERE i."key" = ?
          GROUP BY i."key";
        SQL
        result = []
        @db.execute sql1, vars1 do |row|
          @db.execute(sql2, [row.first]) do |json|
            result.append JSON.load(json.first)
          end
        end
        result
      end
    end
  end
end
