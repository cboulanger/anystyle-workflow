# frozen_string_literal: true

# to install the summarize gem on Debian, sudo apt install libglib2.0-dev  libxml2-dev

require 'summarize'
require 'scylla'

module Utils
  module NLP
    # Languages supported by summarize
    LANGUAGES = {
      'bg' => 'bulgarian',
      'ca' => 'catalan',
      'cs' => 'czech',
      'cy' => 'welsh',
      'da' => 'danish',
      'de' => 'german',
      'el' => 'greek',
      'en' => 'english',
      'eo' => 'esperanto',
      'es' => 'spanish',
      'et' => 'creole',
      'eu' => 'basque',
      'fi' => 'finnish',
      'fr' => 'french',
      'ga' => 'irish',
      'gl' => 'galician',
      'he' => 'hebrew',
      'hu' => 'hungarian',
      'ia' => 'interlingua',
      'id' => 'indonesian',
      'is' => 'icelandic',
      'it' => 'italian',
      'lv' => 'latvian',
      'mi' => 'maori',
      'ms' => 'malay',
      'mt' => 'maltese',
      'nl' => 'dutch',
      'nn' => 'norwegian',
      'pl' => 'polish',
      'pt' => 'portuguese',
      'ro' => 'romanian',
      'ru' => 'russian',
      'sv' => 'swedish',
      'tl' => 'tagalog',
      'tr' => 'turkish',
      'uk' => 'ukrainian',
      'yi' => 'yiddish'
    }.freeze

    # @param [String] text
    # @param [Integer] ratio
    # @param [Boolean] topics
    # @param [Array] stopword_files
    # @return [Array<String, Array, String>] An array of [abstract, keywords, language]
    def summarize(text, ratio: 50, topics: false, stopword_files: [])
      skylla_lang = text.language
      language = LANGUAGES.invert[skylla_lang]
      raise "Language '#{skylla_lang}' is not supported by the auto-summarizer" if language.nil?

      # remove literal phrases or those which match a regular expressions
      stopword_files.each do |file_path|
        File.readlines(file_path).each do |line|
          if line.start_with? '/'
            # interpret as regular expression
            text.gsub!(/#{line.strip.gsub(%r{^/|/$}, '')}/, '')
          else
            text.gsub!(line.strip, '')
          end
        end
      end
      abstract, topics = text.summarize(language:, ratio:, topics:)
      abstract = abstract.force_encoding('utf-8')
      topics = topics.force_encoding('utf-8').split(',').compact.reject(&:empty?)
      # remove line breaks from abstract
      while abstract.match(/\n|\r|\s\s/)
        abstract.gsub!(/\p{Pd} ?\n/, '')
        abstract.gsub!(/\n|\r|\s{2,}/, ' ')
      end
      [abstract, topics, language]
    end
  end
end
