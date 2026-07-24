def count_js_code_lines(file_path)
  unless File.exist?(file_path)
    puts "File does not exist: #{file_path}"
    return
  end

  code_lines = 0
  in_multiline_comment = false

  File.foreach(file_path) do |line|
    stripped_line = line.strip

    if in_multiline_comment
      in_multiline_comment = !stripped_line.end_with?('*/')
      next
    elsif stripped_line.start_with?('/*')
      in_multiline_comment = !stripped_line.end_with?('*/')
      next
    end

    unless stripped_line.empty? || stripped_line.start_with?('//')
      code_lines += 1
    end
  end

  code_lines
end

if ARGV.empty?
  puts "Usage: ruby #{__FILE__} <file_path>"
  exit 1
end

file_path = ARGV[0]
lines = count_js_code_lines(file_path)
puts "Number of lines excluding comments and empty lines: #{file_path} : #{lines}"
