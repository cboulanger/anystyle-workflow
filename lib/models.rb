require 'active_graph'
require './lib/models/work'
require './lib/models/creator'


class CreatorOf
  include ActiveGraph::Relationship
  property :role # this contains an array of roles
  from_class :Creator
  to_class :Work
  type :CREATOR_OF
  creates_unique :all
end

class Citation
  include ActiveGraph::Relationship
  property :numCitations # this contains an array of roles
  from_class :Work
  to_class :Work
  type :CITES
  creates_unique :all
end

class SameAs
  include ActiveGraph::Relationship
  from_class :any
  to_class :any
  type :SAME_AS
  creates_unique :all
end

class ContainedIn
  include ActiveGraph::Relationship
  from_class :Work
  to_class :any
  type :CONTAINED_IN
  creates_unique :all
end

#end