# frozen_string_literal: true

require 'active_graph'

module Datasource
  class Neo4j
    class << self
      def connect
        # connect to Neo4j
        url      = ENV['NEO4J_URL']
        username = ENV['NEO4J_USERNAME']
        password = ENV['NEO4J_PASSWORD']
        auth = ::Neo4j::Driver::AuthTokens.basic(username, password)
        $logger.info "Connecting to Neo4J on #{url}..."
        ::ActiveGraph::Base.driver = ::Neo4j::Driver::GraphDatabase.driver(url, auth, encryption: false)
        setup_models
      end

      def setup_models
        ::ActiveGraph::Base.query('CREATE CONSTRAINT IF NOT EXISTS ON (w:Work) ASSERT w.uuid IS UNIQUE')
        ::ActiveGraph::Base.query('CREATE CONSTRAINT IF NOT EXISTS ON (c:EditedBook) ASSERT c.uuid IS UNIQUE')
        ::ActiveGraph::Base.query('CREATE CONSTRAINT IF NOT EXISTS ON (c:Journal) ASSERT c.uuid IS UNIQUE')
        ::ActiveGraph::Base.query('CREATE CONSTRAINT IF NOT EXISTS ON (cr:Creator) ASSERT cr.uuid IS UNIQUE')
      end

      def get_driver
        ::ActiveGraph::Base.driver
      end
    end
  end
end
