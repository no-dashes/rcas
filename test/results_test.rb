# frozen_string_literal: true

require_relative "test_helper"

# The numbered lines of a session: `In[3]`, `Out[3]`, `Out[-1]`.
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

  # One finished line: its source and its result.
  def line(source, value, context = nil)
    RCAS::Results.record_input(source, context)
    RCAS::Results.record(value)
  end

  def record(*values) = values.map { |v| RCAS::Results.record(v) }

  def test_numbers_start_at_one_and_count_up
    assert_equal [1, 2, 3], record(X + 1, 42, "text")
    assert_equal 3, RCAS::Results.index
    assert_equal "text", RCAS::Results.last
  end

  def test_an_input_and_its_result_share_a_number
    assert_equal 1, line("x + 1", X + 1)
    assert_equal 2, line("2 + 2", 4)
    assert_equal X + 1, RCAS::Out[1]
    assert_equal 4, RCAS::Out[2]
    assert_equal X + 1, RCAS::In[1]
    assert_equal 2, RCAS::Results.index
  end

  def test_a_line_without_a_result_keeps_its_number
    RCAS::Results.record_input("e = x + 1")
    RCAS::Results.record_input("2 + 2")
    assert_equal 2, RCAS::Results.record(4)
    assert_nil RCAS::Out[1]
    assert_equal 4, RCAS::Out[2]
    assert_equal "e = x + 1", RCAS::In.fetch(1)
  end

  def test_lookup_forwards_and_backwards
    record(:a, :b, :c)
    assert_equal :a, RCAS::Out[1]
    assert_equal :c, RCAS::Out[3]
    assert_equal :c, RCAS::Out[-1]
    assert_equal :a, RCAS::Out[-3]
    assert_nil RCAS::Out[4]
    assert_nil RCAS::Out[-9]
  end

  def test_the_line_being_read_is_not_in_the_tables_yet
    line("1 + 1", 2)
    RCAS::Results.record_input("In[-1]") # being evaluated now
    assert_equal 2, RCAS::Results.pending
    assert_nil RCAS::In[2], "the line reading the table is not in it"
    assert_equal RCAS::Num.new(1) + 1, RCAS::In[-1], "the previous line is"
    assert_equal 2, RCAS::Out[-1]
  end

  # ---- held inputs -----------------------------------------------------------

  def test_an_input_comes_back_held
    line("1 + 2", 3)
    assert_equal RCAS::Num.new(1) + 2, RCAS::In[1]
    assert_equal 3, RCAS::In[1].simplify
  end

  def test_a_formal_function_stays_formal
    line("integrate(sin(x), x)", :whatever, binding_of_a_session)
    assert_equal "integral(sin(x), x)", RCAS::In[1].to_s
    assert_equal "-cos(x)", RCAS::In[1].doit.to_s
  end

  def test_names_are_read_in_the_binding_of_the_line
    context = binding_of_a_session
    context.local_variable_set(:e, X + 1)
    line("e*2", (X + 1) * 2, context)
    assert_equal "(x + 1)*2", RCAS::In[1].to_s
  end

  def test_a_line_that_cannot_be_held_comes_back_as_text
    line("x + )", nil)
    line("this is a sentence", nil)
    assert_equal "x + )", RCAS::In[1]
    assert_equal "this is a sentence", RCAS::In[2]
  end

  def test_a_line_that_reads_itself_comes_back_as_text
    line("In[-1]", nil)
    line("In[-1]", nil) # the second one holds the first, which holds ... itself
    assert_equal "In[-1]", RCAS::In[2]
  end

  # ---- the tables ------------------------------------------------------------

  def test_the_tables_print_one_line_per_line
    assert_equal "(no inputs yet)", RCAS::In.inspect
    assert_equal "(no results yet)", RCAS::Out.inspect
    line("x + 1", X + 1)
    line("2", 2)
    assert_equal "[1] x + 1\n[2] 2", RCAS::Out.inspect
    assert_equal "[1] x + 1\n[2] 2", RCAS::In.inspect # the lines as typed, unquoted
    assert_equal({ 1 => X + 1, 2 => 2 }, RCAS::Out.to_h)
  end

  def test_clearing_one_table_starts_the_session_over
    line("1", 1)
    RCAS::Out.clear
    assert_empty RCAS::Out
    assert_empty RCAS::In
    assert_equal 0, RCAS::Results.index
    assert_equal [1], record(7)
  end

  def test_a_table_itself_is_not_a_result
    record(1)
    assert_equal 1, RCAS::Results.record(RCAS::Out)
    assert_equal 1, RCAS::Results.record(RCAS::In)
    assert_equal 1, RCAS::Out.size
    assert_nil RCAS::Results.mark
    record(2)
    assert_equal "=>", RCAS::Results.mark
  end

  # ---- the prompt ------------------------------------------------------------

  def test_numbering_is_on_by_default_and_switchable
    assert_predicate RCAS, :numbered?
    record(1)
    assert_equal "rcas[2]> ", RCAS::Results.prompt("rcas> "), "the line to come, not the last one"
    assert_equal "[2]❯ ", RCAS::Results.prompt("❯ ")
    assert_nil RCAS::Results.prompt(nil) # no prompt without a terminal
    assert_equal "=>", RCAS::Results.mark, "the result keeps its arrow"
    assert_equal "plain", RCAS::Results.return_format("plain")
    RCAS.numbered = "off"
    refute_predicate RCAS, :numbered?
    assert_equal "rcas> ", RCAS::Results.prompt("rcas> ")
  end

  def test_the_environment_switches_it_off
    RCAS.numbered = nil
    ENV["RCAS_NUMBERED"] = "0"
    refute_predicate RCAS, :numbered?
  ensure
    ENV.delete("RCAS_NUMBERED")
  end

  def test_top_level_shorthand
    line("x**2", X**2)
    assert_same RCAS::Out, RCAS.outputs
    assert_same RCAS::In, RCAS.inputs
    assert_same RCAS::Out, RCAS::Constants::Out
    assert_equal X**2, RCAS.outputs[-1]
  end

  private

  # A binding like a session's: the functions and the constants in scope.
  def binding_of_a_session
    session = Object.new
    session.singleton_class.include(RCAS::Functions)
    session.singleton_class.class_eval("def __binding__ = binding")
    session.__binding__
  end
end
