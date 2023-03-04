# frozen_string_literal: true

require './lib/export/exporter'
require 'neo4j-ruby-driver'


module Export
  class Neo4j < Exporter
    def name
      'Neo4j exporter'
    end

    def start
      @data = []
      url = ENV['NEO4J_URL']
      username = ENV['NEO4J_USERNAME']
      password = ENV['NEO4J_PASSWORD']
      auth = ::Neo4j::Driver::AuthTokens.basic(username, password)
      puts "Connecting to Neo4J on #{url}..." if @verbose
      @driver = ::Neo4j::Driver::GraphDatabase.driver(url, auth, encryption: false)
      begin
        @driver.session do |session|
          session.write_transaction do |tx|
            ::Format::Cypher.header.each { |stmt| tx.run(stmt) }
          end
        end
      rescue StandardError => e
        puts "Cannot connect to server: #{e}".colorize(:red)
        exit(1)
      end
    end

    # @param [Format::CSL::Item] item
    def add_item(item)
      @driver.session do |session|
        session.write_transaction do |tx|
          cypher_stmts = Format::Cypher.new(item, pretty: @pretty).serialize.split(";\n")
          cypher_stmts.each { |stmt| tx.run(stmt) }
        end
      end
    end

    def finish
      @driver.close
    end
  end
end
