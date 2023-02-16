# frozen_string_literal: true

require 'pathname'

# Code adapted from AnyStyle::CLI::Commands::Base and AnyStyle::CLI::Commands::Check
module Workflow
  class Check
    class << self
      def walk(input, extension = nil)
        path = Pathname(input).expand_path
        raise ArgumentError, "path does not exist: #{input}" unless path.exist?

        if path.directory?
          path.each_child do |file|
            yield file, path unless file.directory? || (extension && file.extname != extension)
          rescue StandardError => e
            report e, file.relative_path_from(path)
          end
        else
          begin
            yield path, path.dirname
          rescue StandardError => e
            report_error e, path.basename
          end
        end
      end

      def report_error(error, file)
        warn "Error processing `#{file}'"
        warn "  #{error.message}"
        warn "  #{error.backtrace[0]}"
        warn "  #{error.backtrace[1]}"
        warn '  ...'
      end

      def run(path_to_gold, outfile_name: nil)
        rows = []
        columns = %w[file seq_count seq_err seq_rate tok_count tok_err tok_rate]
        rows.append columns
        walk path_to_gold do |path|
          stats = check path
          unless stats.nil?
            seq_count = stats[:sequence][:count]
            seq_errors = stats[:sequence][:errors]
            seq_rate = stats[:sequence][:rate]
            tok_count = stats[:token][:count]
            tok_errors = stats[:token][:errors]
            tok_rate = stats[:token][:rate]
            rows.append [path.basename, seq_count, seq_errors, seq_rate, tok_count, tok_errors, tok_rate]
          end
        end
        count = rows.length
        if count > 1
          sums = Array.new(columns.length-1, 0)
          rows[1..count].each do |row|
            row[1..row.length].each_with_index do |v, i|
              sums[i] += v
            end
          end
          rows.append ['Sum', *sums]
          rows.append ['Mean', *sums.map { |v| (v / count).to_f }]
        end
        outfile_name ||= "check-stats-#{Utils.timestamp}"
        outfile_path = "#{File.join(Path.export, outfile_name)}.csv"
        File.write(outfile_path, rows.map(&:to_csv).join)
        puts "Data written to #{outfile_path}..."
      end

      def check(path)
        case path.extname
        when '.ttx'
          AnyStyle.finder.check path.to_s
        when '.xml'
          AnyStyle.parser.check path.to_s
        end
      end

      # takes a filepath (string) to a gold standard file and returns the labeled result as XML or ttx,
      def relabel(path)
        case File.extname(path)
        when '.ttx'
          AnyStyle.finder.label(AnyStyle.finder.prepare(path, tagged: true)).to_s(tagged:true)
        when '.xml'
          AnyStyle.parser.label(AnyStyle.parser.prepare(path, tagged: true)).to_xml
        end
      end
    end
  end
end
