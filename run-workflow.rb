# frozen_string_literal: true

require './lib/libs'
require 'ruby-progressbar'
require 'json'

anystyle = Datamining::AnyStyle.new('./models/finder.mod', './models/parser.mod')


progress_defaults = {
  format: "%t %b\u{15E7}%i %p%% %c/%C %a %e",
  progress_mark: ' ',
  remainder_mark: "\u{FF65}"
}

# files = Dir.glob(File.join('data', '1-pdf', '*.pdf')).map(&:untaint)
# progressbar = ProgressBar.create(title: 'Extracting text from PDF:',
#                                  total: files.length,
#                                  **progress_defaults)
# files.each do |file_path|
#   file_name = File.basename(file_path, '.pdf')
#   outfile = File.join('data', '2-txt', "#{file_name}.txt")
#   progressbar.increment
#   next if File.exist? outfile
#
#   text = anystyle.extract_text(file_path)
#   File.write(outfile, text)
# end
#
# files = Dir.glob(File.join('data', '2-txt', '*.txt')).map(&:untaint)
# progressbar = ProgressBar.create(title: 'Extracting references from text:',
#                                  total: files.length,
#                                  **progress_defaults)
# files.each do |file_path|
#   file_name = File.basename(file_path, '.txt')
#   outfile = File.join('data', '3-csl', "#{file_name}.json")
#   progressbar.increment
#   next if File.exist? outfile
#
#   csl = anystyle.extract_refs_as_csl(file_path)
#   File.write outfile, JSON.pretty_generate(csl)
# end

files = Dir.glob(File.join('data', '3-csl', '*.json')).map(&:untaint)
progressbar = ProgressBar.create(title: 'Matching references:',
                                 total: files.length,
                                 **progress_defaults)
files.each do |file_path|
  file_name = File.basename(file_path, '.json')
  outfile = File.join('data', '4-csl-matched', "#{file_name}.json")
  progressbar.increment
  refs = JSON.load_file(file_path)
  identifiers = if File.exist? outfile
                  JSON.load_file(outfile)
                else
                  []
                end
  refs.each_with_index do |item, index|
    if identifiers[index].nil?
      identifiers[index] = Matcher::CslMatcher.lookup(item)
    end
  end
  File.write(outfile, JSON.pretty_generate(identifiers))
  break
end
