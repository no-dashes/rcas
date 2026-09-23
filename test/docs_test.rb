# frozen_string_literal: true

require_relative "test_helper"

class DocsTest < Minitest::Test
  def test_a_function
    d = RCAS.doc(:factor)
    assert_equal :function, d.kind
    assert_equal "factor(obj, extension: nil, recombination: nil)", d.signature
    assert_includes d.lines.first, "factor(x**2 - 1)"
    assert_equal "e.factor", d.also
    refute_empty d.sections, "the manual sections that cover it"
    assert_includes d.to_s, "manual:"
    assert_equal d.to_s, d.inspect
  end

  def test_names_of_every_shape
    assert_equal "subs(f, pattern, replacement = nil)", RCAS.doc(:subs).signature, "a function wins over the method of the same name"
    assert_equal :method, RCAS.doc(:variables).kind
    assert RCAS.doc(:variables).signature.start_with?("e."), "methods are shown as e.name"
    assert_equal :value, RCAS.doc("ZZ").kind
    assert_includes RCAS.doc("ZZ").lines.first, "NumberSet"
    assert_includes RCAS.doc("ZZ").lines.join(" "), "Membership is by value"
    assert_equal :class, RCAS.doc(:Polynomial).kind
    assert_includes RCAS.doc(:Polynomial).lines.join(" "), "exponent_vector"
    assert_includes RCAS.doc(:Polynomial).lines.last, "methods: "
    assert_equal RCAS.doc(:factor).signature, RCAS.doc("RCAS::factor").signature, "a qualified name works too"
  end

  def test_comments_are_found_for_every_definition_style
    assert_includes RCAS.doc(:sin).lines.join(" "), "fold", "define_method in a loop"
    assert_equal "sin(arg)", RCAS.doc(:sin).signature
    assert_includes RCAS.doc(:ldegree).lines.join(" "), "polynomial structure", "a comment shared by a group of defs"
    assert_equal "hold(&block)", RCAS.doc(:hold).signature
  end

  # The convention of CLAUDE.md: every top-level function carries a comment.
  def test_every_function_is_documented
    undocumented = RCAS::Functions.instance_methods(false).sort.reject { |m| !RCAS.doc(m).lines.empty? }
    assert_empty undocumented, "these top-level functions have no doc comment above their def"
  end

  def test_unknown_names
    error = assert_raises(RCAS::Docs::NotFound) { RCAS.doc("facter") }
    assert_includes error.message, "factor", "a near miss is suggested"
    assert_raises(RCAS::Docs::NotFound) { RCAS.doc("zzzz") }
    assert_includes RCAS::Docs.names, "integrate"
    assert_includes RCAS::Docs.names, "ZZ"
  end

  def test_manual_sections_are_real_headings
    headings = File.readlines(RCAS::Docs::MANUAL).select { |l| l.start_with?("##") }.map { |l| l.sub(/\A#+\s*/, "").strip }
    %w[factor integrate solve plot ttest].each do |name|
      RCAS.doc(name).sections.each { |s| assert_includes headings, s, "#{name} points at a real section" }
    end
    assert_empty RCAS.doc(:factor).sections.grep(/Reference|Sources|License/), "the tables are not sections to read"
  end
  def test_background_is_shown
    d = RCAS.doc(:integrate)
    assert_includes d.background[:maths], "antiderivative"
    assert_includes d.background[:method], "Hermite"
    assert_includes d.to_s, "maths:"
    assert_includes d.to_s, "method:"
    assert_nil RCAS.doc(:show).background, "plumbing needs no mathematics"
    assert_includes RCAS.doc(:show).to_s, "show"
    # an alias points at another entry
    assert_equal RCAS::Background[:gcd], RCAS::Background[:lcm]
    assert_equal RCAS.doc(:taylor).background, RCAS.doc(:series).background
  end

  def test_background_lines_are_wrapped
    lines = RCAS.doc(:solve).to_s.lines.map(&:chomp)
    maths = lines.index { |l| l.start_with?("  maths:") }
    refute_nil maths
    assert lines.all? { |l| l.size <= 78 }, "the help fits a terminal"
    assert lines[maths + 1].start_with?(" " * 9), "continuations line up under the text"
  end

  # Every entry names something that exists, and every source is in the bibliography.
  def test_background_entries_are_sound
    dead = RCAS::Background::ENTRIES.keys.reject do |name|
      RCAS.doc(name)
      true
    rescue RCAS::Docs::NotFound
      false
    end
    assert_empty dead, "background entries for names that do not exist"

    aliases = RCAS::Background::ENTRIES.select { |_, v| v.is_a?(Symbol) }
    aliases.each { |from, to| assert RCAS::Background::ENTRIES.key?(to), "#{from} points at the missing entry #{to}" }
    RCAS::Background::ENTRIES.each do |name, entry|
      next if entry.is_a?(Symbol)
      refute entry[:maths].to_s.empty?, "#{name} has no mathematics"
    end

    bibliography = File.read(RCAS::Docs::MANUAL).scan(/^- \[([A-Za-z]+\d+[a-z]?)\]/).flatten
    used = RCAS::Background::ENTRIES.values.reject { |v| v.is_a?(Symbol) }
                                   .flat_map { |e| e.values.join(" ").scan(/\[([A-Za-z]+\d+[a-z]?)(?:,[^\]]*)?\]/) }.flatten.uniq
    refute_empty used
    assert_empty used - bibliography, "sources cited in the background but missing from MANUAL.md"
  end
  def test_sources_are_expanded_from_the_bibliography
    d = RCAS.doc(:gcd)
    assert_equal 2, d.sources.size
    assert d.sources.first.start_with?("[Knu98] D. E. Knuth"), d.sources.first
    assert_includes d.sources.last, "Geddes"
    refute_includes d.sources.first, "*", "the markdown italics are stripped"
    assert_includes d.to_s, "sources: [Knu98]"
    assert_empty RCAS.doc(:expand).sources, "an entry that cites nothing"
    assert_empty RCAS.doc(:show).sources, "a name without background cites nothing"
    # every key that appears in a background text can be expanded
    keys = RCAS::Background::ENTRIES.keys.reject { |k| RCAS::Background::ENTRIES[k].is_a?(Symbol) }
    cited = keys.flat_map { |k| RCAS::Background[k].values.join(" ").scan(/\[([A-Za-z]+\d+[a-z]?)/) }.flatten.uniq
    assert_empty cited - RCAS::Docs.bibliography.keys
    assert RCAS::Docs.bibliography.size > 40, "the whole bibliography is read"
  end

  def test_reading_links
    links = RCAS.doc(:factor).reading
    assert_includes links, "https://en.wikipedia.org/wiki/Factorization_of_polynomials"
    assert_equal RCAS.doc(:gcd).reading, RCAS.doc(:lcm).reading, "an alias inherits the reading list"
    assert_includes RCAS.doc(:factor).to_s, "read: https://en.wikipedia.org/wiki/"
    assert_empty RCAS.doc(:show).reading
    # the titles are plain ASCII, so the links need no escaping
    RCAS::Background::READING.each do |name, titles|
      titles.each do |title|
        assert title.ascii_only?, "#{name}: #{title} is not ASCII"
        assert_equal title.strip, title
        refute_includes title, "_", "#{name}: write the title with spaces"
      end
    end
    RCAS::Background::READING.each_key do |name|
      RCAS.doc(name)
    rescue RCAS::Docs::NotFound
      flunk "reading list for the unknown name #{name}"
    end
  end
end
