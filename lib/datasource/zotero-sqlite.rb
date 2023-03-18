# frozen_string_literal: true

require 'sqlite3'
require 'date'

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

      # @return [Boolean]
      def enabled?
        (p = ENV['ZOTERO_SQLITE_PATH']) && File.exist?(p)
      end

      # @return [Boolean]
      def provides_metadata?
        true
      end

      # @return [Array<String>]
      def metadata_types
        [Format::CSL::ARTICLE_JOURNAL, Format::CSL::CHAPTER, Format::CSL::BOOK, Format::CSL::COLLECTION]
      end

      # @return [Boolean]
      def provides_citation_data?
        false
      end

      # @return [Boolean]
      def provides_affiliation_data?
        false
      end

      def connect
        return unless @db.nil?

        @db_path = ENV['ZOTERO_SQLITE_PATH']
        raise "Environment variable ZOTERO_SQLITE_PATH is not set" if @db_path.to_s.empty?
        raise "Sqlite database at #{@db_path} does not exist." unless File.exist?(@db_path)

        @db = SQLite3::Database.new(@db_path)
        return unless (ext_dir = ENV['SQLITE_EXTENSIONS_PATH'])

        begin
          @db.enable_load_extension(true)
          @db.load_extension(File.join(ext_dir, 'spellfix.o'))
          @db_has_spellfix = true
        rescue RunTimeError
          # Couldn't load extension
          @db_has_spellfix = false
        end

        # puts @db_has_spellfix ? 'Spellfix was loaded'.colorize(:green) : "Spellfix was not loaded".colorize(:red)
      end

      # @param [Format::CSL::Item] item
      # @return [Format::CSL::Item, nil]
      def lookup(item)
        raise 'Argument must be Format::CSL::Item' unless item.is_a?(::Format::CSL::Item)

        connect
        author, year, title = item.creator_year_title
        zot_search_item = ::Model::Zotero::Item.new({ date: year.to_i, title: })
        cache = Cache.new(zot_search_item.to_h, prefix: 'zot_sqlite_')
        if (data = cache.load).nil?
          data = find_similar_items(zot_search_item)
                 .map { |i| Item.new(i.to_h) }
                 .select { |i| i.creator_family_names.include? author }
                 .first.to_h
          cache.save(data)
        else
          puts "     - zotero-sqlite: cached data exists"  if @verbose
        end
        data.empty? ? nil : Format::CSL::Item.new(data)
      end

      # Given a Zotero Item object, find other items in Zotero that are similar, based on
      # the field-value pairs in the input object, i.e. only populate a few fields in the
      # passed object. Will match the field values using a `LIKE "%value%"` operator and expression.
      #
      # @param [Model::Zotero::Item] zotero_item
      # @return [Array<Model::Zotero::Item>]
      def find_similar_items(zotero_item, edit_distance: nil)
        raise 'edit_distance must be an integer' unless edit_distance.nil? || edit_distance.is_a?(Integer)

        connect
        # The following sql was constructed with the help of ChatGPT!
        zot_hash = zotero_item.to_h
        raise 'Item is empty' if zot_hash.empty?

        # construct SQL to find record (doesn't look at authors)
        sql1 = <<~SQL
          SELECT i."key"
          FROM items i
            JOIN itemData id ON i.itemID = id.itemID
            JOIN itemDataValues idv ON idv.valueID = id.valueID
            JOIN fields f ON f.fieldID = id.fieldID
          GROUP BY i.key
          HAVING COUNT(DISTINCT f.fieldName || idv.value) = ?
        SQL
        conditions = []
        vars = []
        # sql query to retrieve keys of similar items
        zot_hash.each do |k, v|
          next if k == 'creators'

          vars << k
          condition = 'f.fieldName = ? AND '
          if edit_distance && @db_has_spellfix && %w[title].include?(k)
            condition += "editdist3(idv.value, ?) < #{edit_distance}"
            vars << v
          else
            condition += ' idv.value like ?'
            vars << "%#{v}%"
          end
          conditions << condition
        end
        # add number of conditions
        vars << zot_hash.keys.length
        # insert where clause
        or_where = ["WHERE (#{conditions[0]})"] + conditions[1..].map { |c| ["  OR (#{c})"] }
        sql1 = sql1.split("\n").insert(5, *or_where).join("\n")
        # sql for querying item data based on the retrieved keys
        sql2 = <<~SQL
          SELECT 	json_object(
            'key', i."key",
            'library_id', i.libraryID,
            'creators', json_group_array(
              DISTINCT json_object(
                'lastName',     c.lastName,
                'firstName',    c.firstName,
                'creatorType',  cT.creatorType
              )
            ),
            'title',  MAX(CASE WHEN f.fieldName = 'title' THEN idv.value END),
            'date',   MAX(CASE WHEN f.fieldName = 'date'  THEN idv.value END),
            'ISBN',   MAX(CASE WHEN f.fieldName = 'ISBN'  THEN idv.value END),
            'DOI',    MAX(CASE WHEN f.fieldName = 'DOI'   THEN idv.value END)
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

        if @verbose
          puts sql1
          puts "vars:#{JSON.dump(vars)}"
          puts "query:#{zotero_item.to_json}"
          # puts "hash:" + JSON.dump(zot_hash)
        end

        # execute query
        result = []
        @db.execute sql1, vars do |row|
          @db.execute(sql2, [row.first]) do |json|
            result << Item.new(JSON.parse(json.first))
          end
        end
        result
      end
    end

    class Item < Format::CSL::Item
      def initialize(data)
        super
        custom.metadata_source = 'zotero'
      end

      def key=(key)
        custom.metadata_id = key
      end

      def library_id=(library_id)
        custom.metadata_id = "#{library_id}/#{custom.metadata_id}"
      end

      def creators=(creators)
        self.author = creators
                      .select { |c| c['creatorType'] == 'author' }
                      .map { |c| { 'given' => c['firstName'], 'family' => c['lastName'] } }
        self.editor = creators
                      .select { |c| c['creatorType'] == 'editor' }
                      .map { |c| { 'given' => c['firstName'], 'family' => c['lastName'] } }
      end

      def date=(date)
        self.issued = begin
                        DateTime.parse(date).year
                      rescue Date::Error
                        (date.match('\d\d\d\d') || [])[0]
                      end
      end
    end
  end
end

