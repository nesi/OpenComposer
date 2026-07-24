#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "time"
require "zlib"
require "optparse"

DEFAULT_LOG_ROOT = "/var/log/ondemand-nginx"

# Extract only Open Composer "Submit job" log lines from OnDemand nginx logs.
#
# Supported log format:
# App 622195 output: [2026-04-27 15:23:31 +0900] [Open Composer] Submit job :
#   scheduler=Slurm : cluster=Prepost : job_ids=["578572"] :
#   app_dir=Slurm : app_name=Job script for Prepost

OPEN_COMPOSER_SUBMIT_LOG_PATTERN = %r{
  ^
  App\ \d+\ output:\s+
  \[
    (?<timestamp>[^\]]+)
  \]
  \s+\[Open\ Composer\]\s+
  Submit\ job
  \s+:\s+
  scheduler=(?<scheduler>[^:]+)
  \s+:\s+
  cluster=(?<cluster>[^:]+)
  \s+:\s+
  job_ids=(?<job_ids>\[[^\]]*\])
  \s+:\s+
  app_dir=(?<app_dir>[^:]+)
  \s+:\s+
  app_name=(?<app_name>.+)
  $
}x.freeze

def parse_submit_log_line(line)
  match = OPEN_COMPOSER_SUBMIT_LOG_PATTERN.match(line)
  return nil unless match

  {
    timestamp: match[:timestamp],
    scheduler: match[:scheduler].strip,
    cluster: match[:cluster].strip,
    job_ids: match[:job_ids].strip,
    app_dir: match[:app_dir].strip,
    app_name: match[:app_name].strip
  }
end

def target_log_paths(username: nil)
  pattern =
    if username
      File.join(DEFAULT_LOG_ROOT, username, "error.log*")
    else
      File.join(DEFAULT_LOG_ROOT, "*", "error.log*")
    end

  Dir.glob(pattern).sort
end

def each_log_line(path)
  if path.end_with?(".gz")
    Zlib::GzipReader.open(path) do |gz|
      gz.each_line do |line|
        yield line
      end
    end
  else
    File.foreach(path) do |line|
      yield line
    end
  end
end

def show_progress(current, total, path)
  percent = total.zero? ? 100.0 : (current.to_f / total * 100)
  message = format("Progress: %6.2f%% (%d/%d) %s", percent, current, total, path)
  $stderr.print("\r#{message}")
  $stderr.print("\n") if current == total
end

def load_submit_log_entries(username: nil)
  paths = target_log_paths(username: username)

  paths.each_with_index.each_with_object([]) do |(path, index), entries|
    show_progress(index + 1, paths.length, path)
    entry_username = username || path.sub("#{DEFAULT_LOG_ROOT}/", "").split("/").first
    each_log_line(path) do |line|
      parsed = parse_submit_log_line(line)
      next if parsed.nil?

      entries << parsed.merge(
        username: entry_username,
        source_log_file: path
      )
    end
  end
end

RAW_SUBMISSION_HEADERS = %w[
  username
  timestamp
  scheduler
  cluster
  app_dir
  app_name
  job_ids
  source_log_file
].freeze

def month_key(timestamp)
  Time.parse(timestamp.to_s).strftime("%Y-%m")
rescue ArgumentError
  "unknown"
end

def count_by(entries)
  entries.each_with_object(Hash.new(0)) do |entry, counts|
    counts[yield(entry)] += 1
  end
end

def report_suffix(username)
  username ? "_#{username}" : "_all"
end

def suffixed_csv_path(output_dir, base_name, username)
  File.join(output_dir, "#{base_name}#{report_suffix(username)}.csv")
end

def write_summary_csv(output_path, headers, rows)
  CSV.open(output_path, "w", write_headers: true, headers: headers) do |csv|
    rows.each do |row|
      csv << row
    end
  end
end

def write_summary_by_user_csv(entries, output_dir, username)
  counts = count_by(entries) { |entry| entry[:username].to_s }
  rows = counts.sort_by { |username, _count| username }
  write_summary_csv(suffixed_csv_path(output_dir, "summary_by_user", username), %w[username submit_count], rows)
end

def write_summary_by_app_csv(entries, output_dir, username)
  counts = count_by(entries) { |entry| entry[:app_name].to_s }
  rows = counts.sort_by { |app_name, _count| app_name }
  write_summary_csv(suffixed_csv_path(output_dir, "summary_by_app", username), %w[app_name submit_count], rows)
end

def write_summary_by_user_app_csv(entries, output_dir, username)
  counts = count_by(entries) { |entry| [entry[:username].to_s, entry[:app_name].to_s] }
  rows = counts.sort_by { |(username, app_name), _count| [username, app_name] }.map(&:flatten)
  write_summary_csv(suffixed_csv_path(output_dir, "summary_by_user_app", username), %w[username app_name submit_count], rows)
end

def write_summary_by_month_csv(entries, output_dir, username)
  counts = count_by(entries) { |entry| month_key(entry[:timestamp]) }
  rows = counts.sort_by { |month, _count| month }
  write_summary_csv(suffixed_csv_path(output_dir, "summary_by_month", username), %w[month submit_count], rows)
end

def write_entries_csv(entries, output_path)
  CSV.open(output_path, "w", write_headers: true, headers: RAW_SUBMISSION_HEADERS) do |csv|
    entries.each do |entry|
      csv << RAW_SUBMISSION_HEADERS.map { |header| entry[header.to_sym] }
    end
  end
end

def output_paths(output_path, username)
  output_dir = File.dirname(File.expand_path(output_path))
  output_base = File.basename(output_path, File.extname(output_path))

  {
    raw: File.join(output_dir, "#{output_base}#{report_suffix(username)}.csv"),
    summary_by_user: suffixed_csv_path(output_dir, "summary_by_user", username),
    summary_by_app: suffixed_csv_path(output_dir, "summary_by_app", username),
    summary_by_user_app: suffixed_csv_path(output_dir, "summary_by_user_app", username),
    summary_by_month: suffixed_csv_path(output_dir, "summary_by_month", username)
  }
end

def write_report_csvs(output_path, username: nil)
  paths = output_paths(output_path, username)
  entries = load_submit_log_entries(username: username)

  write_entries_csv(entries, paths[:raw])
  write_summary_by_user_csv(entries, File.dirname(paths[:summary_by_user]), username)
  write_summary_by_app_csv(entries, File.dirname(paths[:summary_by_app]), username)
  write_summary_by_user_app_csv(entries, File.dirname(paths[:summary_by_user_app]), username)
  write_summary_by_month_csv(entries, File.dirname(paths[:summary_by_month]), username)

  paths
end

if $PROGRAM_NAME == __FILE__
  options = {
    output: "raw_submissions.csv"
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby misc/create_report.rb [options]"

    opts.on("-o", "--output PATH", "Raw CSV output path (default: raw_submissions.csv)") do |value|
      options[:output] = value
    end

    opts.on("--user USERNAME", "Filter by username") do |value|
      options[:username] = value
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end

  parser.parse!(ARGV)

  unless Dir.exist?(DEFAULT_LOG_ROOT)
    warn "Directory not found: #{DEFAULT_LOG_ROOT}"
    exit 1
  end

  output_path = options[:output]
  paths = write_report_csvs(
    output_path,
    username: options[:username]
  )
  puts "Wrote #{paths[:raw]}"
  puts "Wrote #{paths[:summary_by_user]}"
  puts "Wrote #{paths[:summary_by_app]}"
  puts "Wrote #{paths[:summary_by_user_app]}"
  puts "Wrote #{paths[:summary_by_month]}"
end
