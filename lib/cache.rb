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
  def initialize(identifier, use_literal: false, prefix: '', mode: MODE_JSON)
    @identifier = identifier
    @use_literal = use_literal
    @prefix = prefix
    @mode = mode
  end

  def load
    Cache.load(@identifier, use_literal: @use_literal, prefix: @prefix, mode: @mode)
  end

  def save(data)
    Cache.save(@identifier, data, use_literal: @use_literal, prefix: @prefix, mode: @mode)
  end

  def delete
    Cache.delete(@identifier, use_literal: @use_literal, prefix: @prefix, mode: @mode)
  end

  # @param [Object] identifier
  # @param [Boolean] use_literal
  # @param [String] prefix
  # @return [Object]
  def self.load(identifier, use_literal: false, prefix: '', mode: MODE_JSON)
    p = cache_path(identifier, use_literal:, prefix:, mode:)
    return unless File.exist? p

    File.open(p) do |f|
      begin
        case mode
        when MODE_JSON
          JSON.load_file f
        when MODE_MARSHAL
          Marshal.load f.read
        else
          raise "Invalid mode"
        end
      rescue JSON::ParserError => e
        puts "Could not load cached data from '#{p}': #{e.to_s}".colorize(:red)
        nil
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

  def self.delete(identifier, use_literal: false, prefix: '', mode: MODE_JSON)
    cp = cache_path(identifier, use_literal:, prefix:, mode:)
    if File.exist? cp
      File.delete(cp)
    else
      puts "Cache '#{cp}' does not exist".colorize(:red)
    end

  end

  # @param [Object] identifier
  # @param [Boolean] use_literal
  # @param [String] prefix
  # @return [String]
  def self.cache_path(identifier, use_literal: false, prefix: '', mode: MODE_JSON)
    file_name = prefix
    file_name += use_literal && identifier.is_a?(String) ? identifier.to_s : Digest::MD5.hexdigest(identifier.to_s)
    file_name += if mode == MODE_JSON
                   '.json'
                elsif mode == MODE_MARSHAL
                  '.bin'
                else
                  raise "Invalid mode"
                end
    File.join(CACHE_DIR, file_name)
  end
end
