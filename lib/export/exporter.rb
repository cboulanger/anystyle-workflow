module Export
  class Exporter

    def initialize(*)
      super()
    end

    def name
      raise "Must be implemented by subclass"
    end

    def start; end

    # @param [Format::CSL::Item] item
    def add_item(item)
      raise "Must be implemented by subclass"
    end

    def finish; end
  end
end