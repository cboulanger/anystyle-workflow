# frozen_string_literal: true

module Datasource
  class Wos < Datasource


    class << self
      def import_items(ids)
        @cache ||= ::Datasource.get_vendor_data(['wos'])['wos']
        ids.map do |id|
          data = @cache[id] || @cache[id.sub('/', '_')]
          data && Item.new(data)
        end
      end
    end

    class Creator < Format::CSL::Creator

      def orcid=(orcid)
        self.x_orcid = orcid
      end
    end

    class Item < Format::CSL::Item
      def initialize(data)
        super(fix_legacy_data(data))
        custom.metadata_source = 'wos'
        custom.reference_data_source = 'wos'
        if container_title && title.nil?
          self.title = container_title
        end
        self.type ||= Item.guess_type(self)
      end

      def reference=(refs)
        self.x_references = refs.map { |r| Item.new(r.compact) }
      end


      private

      def creator_factory(data)
        Creator.new(data)
      end

      def fix_legacy_data(data)
        # fix malformed legacy format
        if data['issued'].is_a? Array
          data['issued'] = {
            'date-parts': [[data['issued'].first['date-parts'].first]]
          }
        end
        if data['custom']['wos-id']
          data['custom']['metadata_id'] = data['custom']['wos-id']
          data['custom'].delete('wos-id')
        end
        if data['custom']['wos-times-cited']
          data['custom']['times_cited'] = data['custom']['wos-times-cited']
          data['custom'].delete('wos-times-cited')
        end
        if (affiliations = data['custom']['wos-item-authors-affiliations'])
          data['custom'].delete('wos-item-authors-affiliations')
        end
        data['custom'] = data['custom'].compact

        data['author'].map! do |author|
          author.delete('email')
          if affiliations&.length&.positive?
            aff = affiliations.shift
            institution = aff['organization']
            institution = institution.first if institution.is_a? Array
            author['x_affiliations'] = [{ 'institution': institution, 'country': aff['country'] }]
          end
          author.compact
        end
        data.compact
      end
    end
  end
end
