# frozen_string_literal: true

module Workflow
  class Utils
    class << self

      def debug_message(str)
        caller_locations(1, 1).first.tap{|loc| puts "#{loc.path}:#{loc.lineno}:#{str}"}
      end

      def remove_whilespace_from_lines(file_path)
        File.write(file_path, File.read(file_path).split("\n").map(&:strip).join("\n"))
      end

      def titleize_if_uppercase(text)
        text.split(' ').map { |w| w.match(/^[\p{Lu}\p{P}]+$/) ? w.capitalize : w }.join(' ')
      end

      def initialize_given_name(given_name)
        given_name.scan(/\p{L}+/)&.map { |n| n[0] }&.join('')
      end

      # given a author name as a string, return what is probably the last name
      def author_name_family(name)
        n = Namae.parse(name).first
        return if n.nil?

        [n.particle, n.family].reject(&:nil?).join(' ')
      end

      def author_name_given(name)
        Namae.parse(name).first&.given
      end

      # @return [Array]
      def title_keywords(title, min_length = 4, max_number = 5)
        title.downcase
             .scan(/[[:alnum:]]+/)
             .reject { |w| w.length < min_length }
             .first(max_number)
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
