# 第一引数からファイル名を取得
file_path = ARGV[0]

# ファイル名が指定されていない場合、エラーを表示して終了
if file_path.nil? || file_path.empty?
  puts "Usage: ruby count_lines.rb <file_name>"
  exit 1
end

# ファイルが存在するか確認
unless File.exist?(file_path)
  puts "Error: File '#{file_path}' does not exist."
  exit 1
end

# ERBファイルの行数をカウント
def count_erb_lines(file_path)
  File.readlines(file_path).count do |line|
    stripped_line = line.strip
    # 空行またはHTMLコメント行でない場合をカウント
    !stripped_line.empty? && !stripped_line.start_with?("<%#", "<!--")
  end
end

# ファイルの種類を判定して行数をカウント
erb_lines = count_erb_lines(file_path)
puts "ERB code lines (excluding comments): #{file_path} : #{erb_lines}"

