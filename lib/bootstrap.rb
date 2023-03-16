require 'require_all'

require 'dotenv'
Dotenv.load('./.env')

# if ENV['SSL_BYPASS_CERTIFICATE_VERIFICATION']
#   # this is to work around WSL2 SSL issues
#   require 'openssl'
#   OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
# end

# pycall gem to call python code from ruby
require 'pycall'
PyCall.sys.path.append('./pylib')

require 'ruby-progressbar'
require 'json'
require 'csv'
require 'colorize'

require './lib/cache'
require './lib/logger'
require_all './lib/utils/*.rb'
require_all './lib/model/*.rb'
require_all './lib/format/*.rb'
require_all './lib/datasource/*.rb'
require_all './lib/datamining/*.rb'
require_all './lib/export/*.rb'
require_all './lib/linking/*.rb'
require_all './lib/workflow/*.rb'
