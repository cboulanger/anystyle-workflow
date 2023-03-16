module Model
  # Just an empty interface marker for the moment
  class Model
    def initialize(data)
      data.each do |k, v|
        method_name = "#{k}=".to_sym
        if respond_to? method_name
          public_send(method_name, v)
        else
          warn "#{self.class.name}: Ignoring unsupported attribute '#{method_name}' (from key '#{k}')".colorize(:red)
        end
      end
    end

    def to_h(compact: false)
      hash = {}
      instance_variables.each do |var|
        attr_name = var.to_s.delete('@')
        next if attr_name.start_with? '_'

        key = key_name(attr_name)
        value = instance_variable_get(var)
        hash[key] = case value
                    when Array
                      value.map { |i| i.is_a?(::Format::CSL::Model) ? i.to_h(compact:) : i }
                    when ::Format::CSL::Model
                      value.to_h(compact:)
                    else
                      value
                    end
      end
      return hash unless compact

      hash.delete_if do |_k, v|
        case v
        when Array
          v.empty?
        when String
          v.strip.empty?
        else
          v.nil?
        end
      end
    end

    alias to_hash to_h

    def to_json(opts = nil)
      JSON.pretty_generate to_hash, opts
    end

    def self.from_hash(properties)
      new(properties)
    end

    protected

    def accessor_name(key)
      key.to_sym
    end

    def key_name(attribute)
      attribute
    end
  end
end