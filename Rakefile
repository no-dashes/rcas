# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

desc "Regenerate the table of contents in MANUAL.md"
task :toc do
  anchor = ->(title) { title.downcase.gsub(/[^[:word:]\s-]/, "").strip.tr(" ", "-") }
  %w[MANUAL.md].each do |path|
    next unless File.file?(path)
    lines = File.read(path).split("\n")
    start = lines.index("<!-- toc -->")
    stop = lines.index("<!-- /toc -->")
    abort "no <!-- toc --> markers in #{path}" unless start && stop
    toc = lines[stop..].filter_map do |l|
      next unless (m = l.match(/\A(\#{2,4}) (.*)\z/))
      indent = "  " * (m[1].size - 2)
      "#{indent}- [#{m[2]}](##{anchor.call(m[2])})"
    end
    lines[(start + 1)...stop] = toc
    File.write(path, lines.join("\n") + "\n")
    puts "#{path}: #{toc.size} entries"
  end
end
