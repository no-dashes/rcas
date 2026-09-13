# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

desc "Regenerate the table of contents in MANUAL.md (between <!-- toc --> markers)"
task :toc do
  path = "MANUAL.md"
  lines = File.read(path).split("\n")
  start = lines.index("<!-- toc -->")
  stop = lines.index("<!-- /toc -->")
  abort "no <!-- toc --> markers in #{path}" unless start && stop
  anchor = ->(title) { title.downcase.gsub(/[^\w\s-]/, "").strip.tr(" ", "-") }
  toc = lines[stop..].filter_map do |l|
    next unless (m = l.match(/\A(\#{2,4}) (.*)\z/))
    indent = "  " * (m[1].size - 2)
    "#{indent}- [#{m[2]}](##{anchor.call(m[2])})"
  end
  lines[(start + 1)...stop] = toc
  File.write(path, lines.join("\n") + "\n")
  puts "#{toc.size} entries"
end
