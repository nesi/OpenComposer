def count_code_lines(file_path)
  unless File.exist?(file_path)
    puts "No found file: #{file_path}"
    return
  end

  code_lines = 0

  File.foreach(file_path) do |line|
    stripped_line = line.strip
    unless stripped_line.empty? || stripped_line.start_with?('#')
      code_lines += 1
    end
  end

  code_lines
end

if ARGV.empty?
  puts "ruby #{__FILE__} <file path>"
  exit 1
end

file_path = ARGV[0]
lines = count_code_lines(file_path)
puts "Number of lines excluding comments and empty lines: #{file_path} : #{lines}"

