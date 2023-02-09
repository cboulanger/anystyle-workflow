require 'logger'

# replace with https://github.com/TwP/logging
#require 'logging'

$logger = Logger.new('tmp/logfile.log')
$logger.formatter = proc do |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
end
$logger.level = Logger::DEBUG