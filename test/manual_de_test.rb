# frozen_string_literal: true

require_relative "test_helper"

# MANUAL-de.md is the German translation of MANUAL.md. The prose is
# translated, everything else has to stay in step: this test is what keeps
# the two files from drifting apart.
class ManualDeTest < Minitest::Test
  ENGLISH = File.expand_path("../MANUAL.md", __dir__)
  GERMAN = File.expand_path("../MANUAL-de.md", __dir__)

  def english = @english ||= File.read(ENGLISH)
  def german = @german ||= File.read(GERMAN)
  def blocks(text) = text.scan(/^```\n.*?^```\n/m)
  def headings(text) = text.lines.select { |l| l.start_with?("#") }.map(&:chomp)

  def test_the_transcripts_are_the_same
    mine = blocks(german)
    theirs = blocks(english)
    assert_equal theirs.size, mine.size, "the two manuals have a different number of code blocks"
    theirs.zip(mine).each_with_index do |(a, b), i|
      assert_equal a, b, "code block #{i + 1} differs; the German manual must copy the English one verbatim"
    end
  end

  def test_the_structure_is_the_same
    mine = headings(german)
    theirs = headings(english)
    assert_equal theirs.size, mine.size, "the two manuals have a different number of headings"
    levels = ->(list) { list.map { |h| h[/\A#+/] } }
    assert_equal levels.call(theirs), levels.call(mine), "the heading levels do not line up"
    # the numbering of the sections is the same, so cross references carry over
    numbers = ->(list) { list.filter_map { |h| h[/\A#+\s+(\d+(?:\.\d+)?)\./, 1] || h[/\A#+\s+(\d+\.\d+)\s/, 1] } }
    assert_equal numbers.call(theirs), numbers.call(mine)
  end

  def test_the_german_manual_is_translated
    refute_includes german, "# rcas manual", "the title is translated"
    assert_includes german, "# rcas Handbuch"
    prose = german.gsub(/^```\n.*?^```\n/m, "").lines
    %w[Ausdrücke Unbestimmte Gleichung Ableitung Grenzwert Matrix].each do |word|
      assert prose.any? { |l| l.include?(word) }, "the German manual should speak German (#{word})"
    end
    assert_includes german, "Dies ist die Übersetzung von MANUAL.md"
  end

  def test_both_have_a_table_of_contents
    [english, german].each do |text|
      assert_includes text, "<!-- toc -->"
      assert_includes text, "<!-- /toc -->"
      entries = text[/<!-- toc -->\n(.*?)<!-- \/toc -->/m, 1].to_s.lines
      assert entries.size > 50, "run `ruby -S rake toc`"
      assert entries.all? { |l| l.match?(/\A\s*- \[.+\]\(#.+\)\n\z/) }
    end
    assert_equal english[/<!-- toc -->\n(.*?)<!-- \/toc -->/m, 1].to_s.lines.size,
                 german[/<!-- toc -->\n(.*?)<!-- \/toc -->/m, 1].to_s.lines.size
  end

  # The German file carries the same citations, in the language of the works.
  def test_the_bibliography_is_shared
    entries = ->(text) { text.scan(/^- \[([A-Za-z]+\d+[a-z]?)\]/).flatten }
    assert_equal entries.call(english), entries.call(german)
    refute_empty entries.call(german)
  end
end
