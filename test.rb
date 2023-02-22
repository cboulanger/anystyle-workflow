require './lib/bootstrap'


def test1
  datasources = %w[wos]
  datasources.each do |ds|
    provider = ::Datasource.get_provider_by_name(ds)
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
end

def test2
  doi = "10.1111/1467-6478.00033"
  items = Workflow::Dataset.merge_and_validate(doi, verbose: true)
  File.write("tmp/test2.json", JSON.pretty_generate(items.to_h))
end

test2
