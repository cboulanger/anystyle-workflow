# frozen_string_literal: true

module Workflow
  class Utils
    class << self
      def remove_whilespace_from_lines(file_path)
        File.write(file_path, File.read(file_path).split("\n").map(&:strip).join("\n"))
      end

      def timestamp
        DateTime.now.strftime('%Y-%m-%d_%H-%M-%S')
      end

      def py_to_rb(value)
        case value
        when PyCall::Dict
          value = value.to_h
          value.each do |k, v|
            value[k] = py_to_rb v
          end
        when PyCall::List
          value = value.to_a
          value.map do |v|
            py_to_rb v
          end
        else
          value
        end
      end
    end
  end
end
