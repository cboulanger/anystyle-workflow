require 'logger'

# replace with https://github.com/TwP/logging, integrate with Feedback module
#require 'logging'

$logger = Logger.new('tmp/logfile.log')
$logger.formatter = proc do |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
end
$logger.level = Logger::DEBUG