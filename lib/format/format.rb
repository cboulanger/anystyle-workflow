module Format
  class Format

    attr_reader :item, :citing_item

    # @param [::Format::CSL::Item] item A model item
    # @param [::Format::CSL::Item] citing_item Optional citing item if the format supports expressing the relationship
    def initialize(item, citing_item: nil, pretty:false)
      raise 'Arguments must be a subclasses of Format::CSL::Item' \
          unless item.is_a?(::Format::CSL::Item) && (citing_item.nil? || citing_item.is_a?(::Format::CSL::Item))

      @citing_item = citing_item
      @pretty = pretty
      @item = item
    end

    # @return [String]
    def serialize
      raise 'must be implemented by subclass'
    end

    # @param [String] input
    # @return [::Format::CSL::Item]
    def self.parse
      raise 'must be implemented by subclass'
    end
  end
end