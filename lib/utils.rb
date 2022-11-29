
module Workflow
  class Utils
    class << self
      def remove_whilespace_from_lines(file_path)
        File.write(file_path, File.read(file_path).split("\n").map(&:strip).join("\n"))
      end

      def timestamp
        DateTime.now.strftime('%Y-%m-%d_%H-%M-%S')
      end
    end
  end
end
