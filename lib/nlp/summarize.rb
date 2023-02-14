# to install the summarize gem on Debian, sudo apt install libglib2.0-dev  libxml2-dev

require 'summarize'

module Nlp
  # @param [String] file_path
  # @param [String] language
  # @param [Integer] ratio
  # @param [Boolean] topics
  def summarize_file(file_path, language:'en', ratio: 50, topics: false, remove_list:[] )
    text = File.read(file_path, encoding:"utf-8")
    abstract, topics = text.summarize(:language => language, :ratio => ratio, :topics => topics)
    abstract = abstract.force_encoding("utf-8")
    topics = topics.force_encoding("utf-8").split(",")
    remove_list.each { |phrase | abstract.gsub!(/#{phrase}/,"")}
    while abstract.match(/\n|\s\s/)
      abstract.gsub!(/\p{Pd} ?\n/, "")
      abstract.gsub!(/\n|\s{2,}/, " ")
    end
    [abstract, topics]
  end
end