# frozen_string_literal: true
module Linking
  class Openurl
    def initialize(base_url)
      @base_url = base_url
      @config = {}
    end

    # @param [::Format::CSL::Item] item
    def lookup(item)
      raise 'Argument must be Format::CSL::Item' unless item.is_a? ::Format::CSL::Item

      if (title = item.title.to_s)
        @config['rft.atitle'] = title
      end
      if item.type == ::Format::CSL::ARTICLE_JOURNAL && (jtitle = item.container_title)
        @config['rft.jtitle'] = jtitle
      end
      author = item.creators.first
      if (aulast = author&.family)
        @config['rft.aulast'] = aulast
      end
      if (auinit = author&.initial)
        @config['rft.auinit'] = auinit
      end
      if (date = item.year)
        @config['rft.date'] = date
      end
      url = "#{@base_url}?#{@config.join('&')}"
      puts url
    end
  end
end
