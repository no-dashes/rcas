# frozen_string_literal: true

require_relative "test_helper"

# The numbered results of a session: `_r[3]`, `_r[-1]`, `_r`.
class ResultsTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def setup
    RCAS::Results.clear
    RCAS.numbered = nil
  end

  def teardown
    RCAS::Results.clear
    RCAS.numbered = nil
  end

  def record(*values) = values.map { |v| RCAS::Results.record(v) }

  def test_numbers_start_at_one_and_count_up
    assert_equal [1, 2, 3], record(X + 1, 42, "text")
    assert_equal 3, RCAS::Results.index
    assert_equal "text", RCAS::Results.last
  end

  def test_lookup_forwards_and_backwards
    record(:a, :b, :c)
    r = RCAS.results
    assert_equal :a, r[1]
    assert_equal :c, r[3]
    assert_equal :c, r[-1]
    assert_equal :a, r[-3]
    assert_nil r[4]
    assert_nil r[-9]
  end

  def test_the_table_is_a_hash_that_prints_one_result_per_line
    assert_equal "(no results yet)", RCAS.results.inspect
    record(X + 1, 2)
    assert_equal "[1] x + 1\n[2] 2", RCAS.results.inspect
    assert_equal({ 1 => X + 1, 2 => 2 }, RCAS.results.to_h)
  end

  def test_clearing_starts_the_numbering_over
    record(1, 2)
    RCAS.results.clear
    assert_empty RCAS.results
    assert_equal 0, RCAS::Results.index
    assert_equal [1], record(7)
  end

  def test_the_table_itself_is_not_a_result
    record(1)
    assert_equal 1, RCAS::Results.record(RCAS.results)
    assert_equal 1, RCAS.results.size
    assert_nil RCAS::Results.mark
    record(2)
    assert_equal "=>", RCAS::Results.mark
    RCAS.numbered = true
    assert_equal "[2]", RCAS::Results.mark
  end

  def test_numbering_is_off_by_default_and_switchable
    refute_predicate RCAS, :numbered?
    record(1)
    assert_equal "=>", RCAS::Results.prefix
    assert_equal "plain", RCAS::Results.return_format("plain")
    RCAS.numbered = true
    assert_predicate RCAS, :numbered?
    assert_equal "[1]", RCAS::Results.prefix
    assert_equal "[1] %s\n", RCAS::Results.return_format("plain")
    RCAS.numbered = "off"
    refute_predicate RCAS, :numbered?
  end

  def test_the_environment_sets_the_default
    RCAS.numbered = nil
    ENV["RCAS_NUMBERED"] = "1"
    assert_predicate RCAS, :numbered?
  ensure
    ENV.delete("RCAS_NUMBERED")
  end

  def test_top_level_shorthand
    record(X**2)
    assert_same RCAS.results, RCAS._r
    assert_equal X**2, RCAS._r[-1]
  end
end
