# frozen_string_literal: true

require './lib/linking/openurl'

module Linking
  class CrossrefOpenurl < Openurl
    def initialize
      super('https://doi.crossref.org/openurl')
      @config.merge!({
                       url_ver: 'Z39.88-2004',
                       rft_val_fmt: 'info:ofi/fmt:kev:mtx:journal',
                       pid: ENV['API_EMAIL'],
                       nodirect: 'true',
                       format: 'json'
                     })
    end
  end
end
