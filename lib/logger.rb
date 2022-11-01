require 'logger'

$logger = Logger.new('tmp/logfile.log')
$logger.formatter = proc do |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
end
$logger.level = Logger::DEBUG