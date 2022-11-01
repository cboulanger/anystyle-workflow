require 'active_graph'

module Datasource
  class Neo4j
    def self. connect
      # connect to Neo4j
      url      = ENV['NEO4J_URL']
      username = ENV['NEO4J_USERNAME']
      password = ENV['NEO4J_PASSWORD']
      auth = Neo4j::Driver::AuthTokens.basic(username, password)
      $logger.info "Connecting to Neo4J on #{url}..."
      ActiveGraph::Base.driver = Neo4j::Driver::GraphDatabase.driver(url, auth, encryption: false)
      get_driver
    end

    def self.get_driver
      ActiveGraph::Base.driver
    end
  end
end



