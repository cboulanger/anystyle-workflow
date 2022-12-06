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
#require './lib/models'
require './lib/datamining/anystyle'
require './lib/matcher'
require './lib/export/wos'

# workflow
require_all './lib/workflow/*.rb'