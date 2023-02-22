class Cache

  CACHE_DIR = "tmp/cache"
  Dir.mkdir(CACHE_DIR, 0755) unless Dir.exist? CACHE_DIR

  def self.load(identifier, use_literal: false, prefix:'')
    p = cache_path(identifier, use_literal:, prefix:)
    return unless File.exist? p

    File.open(p) { |f| JSON.load_file f }
  end

  def self.save(identifier, data, use_literal: false, prefix:'')
    p = cache_path(identifier, use_literal:, prefix:)
    File.open(p, "w") { |f| JSON.dump data, f }
  end

  private

  def self.cache_path(identifier, use_literal: false, prefix: '')
    file_name = (use_literal && identifier.is_a?(String)) ? identifier : "#{prefix}#{Digest::MD5.hexdigest(identifier.to_s)}.json"
    File.join(CACHE_DIR, file_name)
  end

end