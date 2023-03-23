# sudo apt install libpq-dev
# bundle add pg

module Datasource

  # Web of Science via a PostGreSQL database at the Kompetenzzentrum Bibliometrie (Karlsruhe)
  # (Restricted use)
  class WosKb
    class << self

      # @return [String]
      def id
        'wos-kb'
      end

      # @return [String]
      def label
        'Data from WOD data in a postgresql query at fiz-karlsruhe.de'
      end

      # @return [Boolean]
      def enabled?
        false
      end

      # @return [Boolean]
      def provides_metadata?
        false #
      end

      # @return [Array<String>]
      def metadata_types
        []
      end

      # @return [Boolean]
      def provides_citation_data?
        true
      end

      # @return [Boolean]
      def provides_affiliation_data?
        true
      end

      def import_items(ids)

      end

      def sql_query
        <<~SQL
          select json_object_agg(replace(i.doi, '/','_')::text, 
            json_build_object(
              'doi'::text, i.doi,
              'issued'::text, json_build_array(json_build_object('date-parts'::text, json_build_array(i.pubyear))),
              'title'::text, i.item_title,
              'author'::text, (
                select jsonb_agg(json_build_object(
                  'family'::text, ia.family_name,
                  'given'::text, ia.given_name,
                  'email'::text, ia.email,
                  'orcid'::text, ia.orcid 
                ) order by ia.author_seq_nr) 
                from wos_b_202210.items_authors ia 
                where ia.item_id = i.item_id
              ),
              'reference'::text, (
                select coalesce(jsonb_agg(json_build_object(
                  'doi'::text, r.ref_doi,
                  'issued'::text, json_build_array(json_build_object('date-parts'::text, json_build_array(r.ref_pubyear))),
                  'title'::text, r.ref_item_title,
                  'container-title'::text, r.ref_source_title,
                  'volume'::text, r.ref_volume,
                  'page'::text, r.ref_pages, 
                  'author'::text, json_build_array(json_build_object(
                    'literal'::text, regexp_replace(r.ref_authors::text, '[{}"]', '', 'g')::text)),
                  'custom'::text, json_build_object(
                    'wos-id'::text, r.item_id,
                    'wos-item-authors-affiliations'::text, (
                      select jsonb_agg(json_build_object(
                        'organization'::text, ia2.organization,
                        'country'::text, ia2.country --,
                        --'vendor-org-id'::text, ia2.vendor_org_id
                      ) order by ia2.aff_seq_nr) 
                      from wos_b_202210.items_affiliations ia2
                      where ia2.item_id = i.item_id
                    )
                  )
                )), '[]'::jsonb)
                from mpgcboulanger.wos_jls_citing r
                where i.item_id = r.item_id_citing
              ),
              'custom'::text, jsonb_build_object(
                'wos-times-cited'::text, (
                  select count(*) 
                  from mpgcboulanger.wos_jls_cited r
                  where i.item_id = r.item_id_cited
                ),
                'wos-item-authors-affiliations'::text, (
                  select jsonb_agg(json_build_object(
                    'organization'::text, ia2.organization,
                    'country'::text, ia2.country --,
                    --'vendor-org-id'::text, ia2.vendor_org_id
                  ) order by ia2.aff_seq_nr) 
                  from wos_b_202210.items_affiliations ia2
                  where ia2.item_id = i.item_id
                )
              ) 
            ) 
          ) 
          from mpgcboulanger.wos_jls_items i 
          where i.doi is not null;
        SQL
      end

    end
  end
end