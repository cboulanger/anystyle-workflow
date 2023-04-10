module Service
  class Base

    include Constants

    attr_accessor :verbose

    class << self
      TYPES = [
        OCR = "ocr"
      ]
      # Returns the type of the service
      # @return [String]
      def type
        raise METHOD_NOT_IMPLEMENTED_ERROR
      end
    end
  end
end