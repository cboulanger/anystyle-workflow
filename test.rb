#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/bootstrap'

def test1
  datasources = %w[wos]
  datasources.each do |ds|
    provider = ::Datasource.by_id(ds)
    provider.verbose = true
    item = provider.import_items(['10.1111/1467-6478.00033']).first
    r = {}
    item.to_h.each do |k, v|
      v = case v
          when Array
            v[..3]
          else
            v
          end
      r[k] = v
    end
    puts(JSON.pretty_generate(r))
  end
end

def test3
  ids = Dir.glob(File.join(Workflow::Path.csl, '*.json')).map { |f| File.basename(f, '.json') }
  text_dir = '/mnt/c/Users/Boulanger/ownCloud/Langfristvorhaben/Legal-Theory-Graph/Data/FULLTEXTS/JLS/jls-txt'
  stopword_files = ['data/0-metadata/summarize-ignore.txt']
  authors_ignore_list = ['see']
  affiliation_ignore_list = ['108 Cowley Road']
  options = Workflow::Dataset::Options.new(
    verbose: false,
    text_dir:,
    stopword_files:,
    authors_ignore_list:,
    affiliation_ignore_list:,
    cache_file_prefix: 'test-'
  )
  limit = 1000
  dataset = Workflow::Dataset.new(options:)
  items = dataset.import(ids[..limit], limit:)
  File.write('tmp/test3.json', JSON.pretty_generate(items.map(&:to_h)))
  dataset.export(Export::WebOfScience.new('tmp/test3.txt'))
end

def test4
  iso4 = PyCall.import_module('iso4')
  puts iso4.abbreviate('Recent Advances in Studies on Cardiac Structure and Metabolism')
  puts iso4.abbreviate('Journal of the American Academy of Dermatology', periods: false)
end

def test5
  require 'neo4j-ruby-driver'
  url = 'bolt://172.31.240.1:7687' # ENV['NEO4J_URL']
  username = ENV['NEO4J_USERNAME']
  password = ENV['NEO4J_PASSWORD']
  auth = ::Neo4j::Driver::AuthTokens.basic(username, password)
  puts "Connecting to Neo4J on #{url}..." if @verbose
  @driver = ::Neo4j::Driver::GraphDatabase.driver(url, auth, encryption: false)
  begin
    result = @driver.session.read_transaction do |tx|
      result = tx.run('match (n) return count(n)')
      if result.has_next?
        result.single.first
      else
        'nil'
      end
    end
    puts(result)
  rescue StandardError => e
    puts "Cannot connect to server: #{e}".colorize(:red)
    exit(1)
  end
end

def test6
  require 'sqlite3'
  ext_dir = '/opt/sqlite-extensions' # or whereever you keep the extensions

  db = SQLite3::Database.new(':memory:')
  db.enable_load_extension(true)
  db.load_extension(File.join(ext_dir, 'spellfix.o'))
  db.execute('CREATE VIRTUAL TABLE demo USING spellfix1;')
  db.execute('CREATE TABLE mytable (id integer, description text)')
  db.execute('INSERT INTO mytable VALUES (1, "hello world, guys")')
  db.execute('INSERT INTO mytable VALUES (2, "hello there everybody")')
  result = db.execute('SELECT * FROM mytable WHERE editdist3(description, "hel o wrold guy") < 600')
  puts result
end

def test7
  item = Model::Zotero::Item.new({ title: 'Rechtssoziologie von Sinz', date: '2015' })
  results = Datasource::ZoteroSqlite
            .find_similar_items(item)
            .map { |i| i.to_h(compact: true) }
  puts "#{results.length} hits, first one is:"
  puts JSON.dump(results.first)
end

def test8
  item = Model::Zotero::Item.new({ title: 'Die Rechtssoziologfe von Hugo Sinzhelmer - eine Annäherung', date: '2015' })
  results = Datasource::ZoteroSqlite
            .find_similar_items(item, edit_distance: 600)
            .map { |i| i.to_h(compact: true) }
  puts "#{results.length} hits, first one is:"
  puts JSON.dump(results.first)
end

def test9
  data = { "author": [{ "family": 'Seifert' }], "title": 'Die Rechtssoziologie von Hugo Sinzheimer',
           "issued": { "date-parts": [[2015]] } }
  item = Format::CSL::Item.new(data)
  Datasource::ZoteroSqlite.verbose=true
  puts JSON.dump(Datasource::ZoteroSqlite.lookup(item))
end

test9
