require './lib/bootstrap'

datasources = %w[crossref openalex anystyle grobid dimensions]
datasources.each do |ds|
  provider = Datasource::Utils.get_provider_by_name(ds)
  provider.verbose = true
  item = provider.import_items_by_doi(["10.1111/1467-6478.00033"]).first
  r = {}
  item.to_h.each do |k, v|
    v = case v
        when Array
          v[..3]
        else
          v
        end
    r[k] = v
  end
  puts(JSON.pretty_generate(r))
end

