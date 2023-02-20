require 'require_all'

require 'dotenv'
Dotenv.load('./.env')

if ENV['SSL_BYPASS_CERTIFICATE_VERIFICATION']
  # this is to work around WSL2 SSL issues
  require 'openssl'
  OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
end

# pycall gem to call python code from ruby
require 'pycall'
PyCall.sys.path.append('./pylib')

require 'ruby-progressbar'
require 'json'
require 'csv'

# refactor this with require_all
require './lib/utils'
require './lib/logger'
require './lib/format'
require './lib/datasource'
#require './lib/models'
require './lib/datamining/anystyle'
require './lib/matcher'
require './lib/export/wos'

require_all './lib/nlp/*.rb'
require_all './lib/workflow/*.rb'

require './lib/cache'