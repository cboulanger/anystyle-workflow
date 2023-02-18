# frozen_string_literal: true

module Datasource
  class Wos
    CSL_CUSTOM_FIELDS = [
      TIMES_CITED = 'wos-times-cited',
      AUTHORS_AFFILIATIONS = 'wos-item-authors-affiliations'
    ].freeze

    class << self
      attr_accessor :verbose
    end
  end
end
