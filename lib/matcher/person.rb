require 'httpx'

module Matcher
  module PersonMatcher
    def lookup
      response = HTTPX.get("https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY")
      puts response.body if response.status == 200
    end
  end
end
