class Cache

  Dir.mkdir(Workflow::Path.cache, 0755) unless Dir.exist? Workflow::Path.cache

  def self.load(identifier)
    return unless File.exist? cache_path(identifier)

    File.open(cache_path(identifier)) { |f| JSON.load_file f }
  end

  def self.save(identifier, data)
    File.open(cache_path(identifier), "w") { |f| JSON.dump data, f }
  end

  private

  def self.cache_path(identifier)
    File.join(Workflow::Path.cache, "#{Digest::MD5.hexdigest(identifier.to_s)}.json")
  end

end