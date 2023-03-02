# frozen_string_literal: true
# To do: rewrite & move into Utils module
class Cache
  CACHE_DIR = 'tmp/cache'
  MODE_JSON = 'json'
  MODE_MARSHAL = 'marshal'

  Dir.mkdir(CACHE_DIR, 0o755) unless Dir.exist? CACHE_DIR

  # @param [Object] identifier
  # @param [Object] data
  # @param [Boolean] use_literal
  # @param [String] prefix
  def initialize(identifier, use_literal: false, prefix: '')
    @identifier = identifier
    @use_literal = use_literal
    @prefix = prefix
  end

  def load
    Cache.load(@identifier, use_literal: @use_literal, prefix: @prefix)
  end

  def save(data)
    Cache.save(@identifier, data, use_literal: @use_literal, prefix: @prefix)
  end

  def delete
    Cache.delete(@identifier, data, use_literal: @use_literal, prefix: @prefix)
  end

  # @param [Object] identifier
  # @param [Boolean] use_literal
  # @param [String] prefix
  # @return [Object]
  def self.load(identifier, use_literal: false, prefix: '', mode: MODE_JSON)
    p = cache_path(identifier, use_literal:, prefix:, mode:)
    return unless File.exist? p

    # puts "Loading cache from #{p}"
    File.open(p) do |f|
      case mode
      when MODE_JSON
        JSON.load_file f
      when MODE_MARSHAL
        Marshal.load f.read
      else
        raise "Invalid mode"
      end
    end
  end

  # @param [Object] identifier
  # @param [Object] data
  # @param [Boolean] use_literal
  # @param [String] prefix
  # @return [Object] returns the data
  def self.save(identifier, data, use_literal: false, prefix: '', mode: MODE_JSON)
    p = cache_path(identifier, use_literal:, prefix:, mode:)
    File.open(p, 'w') do |f|
      case mode
      when MODE_JSON
        JSON.dump data, f
      when MODE_MARSHAL
        f.write(Marshal.dump data)
      else
        raise "Invalid mode"
      end
    end
    # puts "saved cache to #{p}..."
    data
  end

  def self.delete(identifier, data, use_literal: false, prefix: '', mode: MODE_JSON)
    File.delete(cache_path(identifier, use_literal:, prefix:, mode:))
  end

  # @param [Object] identifier
  # @param [Boolean] use_literal
  # @param [String] prefix
  # @return [String]
  def self.cache_path(identifier, use_literal: false, prefix: '', mode: MODE_JSON)
    file_name = if use_literal && identifier.is_a?(String)
                  identifier.to_s
                elsif mode == MODE_JSON
                  "#{prefix}#{Digest::MD5.hexdigest(identifier.to_s)}.json"
                elsif mode == MODE_MARSHAL
                  "#{prefix}#{Digest::MD5.hexdigest(identifier.to_s)}.bin"
                else
                  raise "Invalid mode"
                end
    File.join(CACHE_DIR, file_name)
  end
end
