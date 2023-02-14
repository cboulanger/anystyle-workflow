require 'require_all'

# pycall gem to call python code from ruby
require 'pycall'
PyCall.sys.path.append('./pylib')

require 'ruby-progressbar'
require 'json'
require 'csv'

# refactor this with require_all
require './lib/env'
require './lib/utils'
require './lib/logger'
require './lib/datasource'
require './lib/format'
#require './lib/models'
require './lib/datamining/anystyle'
require './lib/matcher'
require './lib/export/wos'

require_all './lib/nlp/*.rb'
require_all './lib/workflow/*.rb'

# monkey-patch Hash to have deep_merge method from Rails
class ::Hash
  def deep_merge(second)
    merger = proc { |_, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2 }
    merge(second.to_h, &merger)
  end
end