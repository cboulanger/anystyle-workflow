# sudo apt install libpq-dev
# bundle add pg
require 'pg'

module Datasource

  # Web of Science via a PostGreSQL database at the Kompetenzzentrum Bibliometrie (Karlsruhe)
  # (Restricted use)
  class WosKb < Datasource
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

      def lookup(item)

      end

      def connect
        @con = PG.connect(host: ENV['KB_HOST'],
                          dbname: ENV['KB_DB'],
                          port: ENV['KB_PORT'],
                          user: ENV['KB_USER'],
                          password: ENV['KB_PASS'])
      end

      def exec_params(sql, params, use_cache: true, is_json: false)
        cache = Cache.new(sql+params.to_s, prefix: "#{id}-")
        if !use_cache || (data = cache.load).nil?
          puts "  - #{id}: Executing query, please wait..." if verbose
          data = @con.exec_params(sql, params).values
          data = JSON.parse data.first.first if is_json
          cache.save(data) #if use_cache
        else
          puts "  - #{id}: Retrieved data from cache" if verbose
        end
        data
      end

      def items_by_autor(author_str)
        connect
        puts "  - #{id}: Searching for '#{author_str}'..." if verbose
        ids = exec_params( sql_find_by_author, [author_str])
                .map(&:first)
                .map { |id| id.include?('.') ? id.split('.')[0] : id }
                .map { |id| id.start_with?('WOS') ? id : "WOS:#{id}"}
        params = [PG::TextEncoder::Array.new.encode(ids)]
        puts "  - #{id}: Downloading entries of or citing '#{author_str}'..." if verbose
        exec_params(sql_get_csl_item_data, params, is_json: true)
          .map { |data| Format::CSL::Item.new data }
      end

      def sql_find_by_author
        <<~SQL
          select i.item_id
          from wos_b_202210.items i
          where i.first_author = $1
          union all
          select r.item_id_cited
          from wos_b_202210.refs r
          where $1 = any(r.ref_authors)
        SQL
      end

      def sql_get_csl_item_data
        <<~SQL
          select jsonb_agg( 
            json_build_object(
              'doi'::text, i.doi,
              'issued'::text, json_build_object('date-parts'::text, json_build_array(json_build_array(i.pubyear))),
              'title'::text, i.item_title,
              'author'::text, (
                select jsonb_agg(json_build_object(
                  'family'::text, ia.family_name,
                  'given'::text, ia.given_name,
                  'x_orcid'::text, ia.orcid,
                  'x_affiliations'::text, (
                      select jsonb_agg(distinct jsonb_build_object(
                        'institution'::text, ia2.organization,
                        'country'::text, ia2.country
                      ))  
                      from wos_b_202210.items_affiliations ia2
                      where ia2.item_id = ia.item_id
                      and ia2.aff_seq_nr = ia.author_seq_nr
                  )
                )
                order by ia.author_seq_nr) 
                from wos_b_202210.items_authors ia 
                where ia.item_id = i.item_id
              ),
              'x_references'::text, (
                select coalesce(jsonb_agg(json_build_object(
                  'doi'::text, r.ref_doi,
                  'issued'::text, json_build_object('date-parts'::text, json_build_array(json_build_array(r.ref_pubyear))),
                  'title'::text, r.ref_item_title,
                  'container_title'::text, r.ref_source_title,
                  'volume'::text, r.ref_volume,
                  'page'::text, r.ref_pages, 
                  'author'::text, json_build_array(
                      json_build_object(
                          'literal'::text, regexp_replace(r.ref_authors::text, '[{}"]', '', 'g')::text
                      )
                  ),
                  'custom'::text, json_build_object(
                    'metadata-id'::text, r.item_id_cited
                  )
                )), '[]'::jsonb)
                from wos_b_202210.refs r
                where i.item_id = r.item_id_citing
              ),
              'custom'::text, jsonb_build_object(
                'times_cited'::text, i.cit_all_years
              ) 
            ) 
          ) 
          from wos_b_202210.items i
          where i.item_id = any($1::text[])
        SQL
      end
    end
  end
end