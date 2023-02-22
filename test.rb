require './lib/bootstrap'


def test1
  datasources = %w[wos]
  datasources.each do |ds|
    provider = ::Datasource.get_provider_by_name(ds)
    provider.verbose = true
    item = provider.import_items(["10.1111/1467-6478.00033"]).first
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
  items = Workflow::Dataset.merge_and_validate(doi)
  File.write("tmp/test2.json", JSON.pretty_generate(items.to_h))
end

def test3
  ids = Dir.glob(File.join(Workflow::Path.csl, '*.json')).map { |f| File.basename(f, '.json') }
  text_dir = '/mnt/c/Users/Boulanger/ownCloud/Langfristvorhaben/Legal-Theory-Graph/Data/FULLTEXTS/JLS/jls-txt'
  remove_list = '"\\d,©,Blackwell Publishers Ltd"'.split(',')
  options = Workflow::Dataset::Options.new(verbose: true, text_dir:, remove_list:)
  limit = 10
  dataset = Workflow::Dataset.new(ids[..limit], options:)
  items = dataset.generate(limit:)
  File.write('tmp/test3.json', JSON.pretty_generate(items.map(&:to_h)))
  dataset.export(Export::WebOfScience.new("tmp/test3.txt"))
end

test3
