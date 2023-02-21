class Cache

  CACHE_DIR = "tmp/cache"
  Dir.mkdir(CACHE_DIR, 0755) unless Dir.exist? CACHE_DIR

  def self.load(identifier, use_literal: false)
    return unless File.exist? cache_path(identifier, use_literal:)

    File.open(cache_path(identifier, use_literal:)) { |f| JSON.load_file f }
  end

  def self.save(identifier, data, use_literal: false)
    File.open(cache_path(identifier, use_literal:), "w") { |f| JSON.dump data, f }
  end

  private

  def self.cache_path(identifier, use_literal: false)
    file_name = (use_literal && identifier.is_a?(String)) ? identifier : "#{Digest::MD5.hexdigest(identifier.to_s)}.json"
    File.join(CACHE_DIR, file_name)
  end

end