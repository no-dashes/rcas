# frozen_string_literal: true

require_relative "test_helper"

class HoldTest < Minitest::Test
  # in? decides membership; inside hold it is kept as the statement, the way
  # == is kept as an equation.
  def test_membership_is_held_as_a_statement
    x = RCAS::Var.new(:x)
    statement = RCAS.hold { x.in?(RCAS::ZZ) }
    assert_kind_of RCAS::Membership, statement
    assert_equal "x in ZZ", statement.to_s
    assert_equal "x \\in \\mathbb{Z}", statement.to_latex
    refute statement.holds?, "x is not declared an integer"
    assert statement.subs(x => RCAS::Num.new(3)).holds?
    assert_equal false, x.in?(RCAS::ZZ), "the bare call still answers"
    assert_equal "x + 1 in QQ", RCAS.hold { (x + 1).in?(RCAS::QQ) }.to_s
  end

  def test_numbers_stay_symbolic
    e = RCAS.hold { 1 + 2 }
    assert_equal [:add, 1, 2], e.to_sexp
    assert_equal "1 + 2", e.to_s
    assert_equal 3, e.simplify
    assert_equal "1/2", RCAS.hold { 1 / 2 }.to_s
    assert_equal RCAS.hold { 1 / 2 }.simplify, Rational(1, 2)
    assert_equal "2**10", RCAS.hold { 2**10 }.to_s
    assert_equal "-(-1)", RCAS.hold { - -1 }.to_s
  end

  def test_identifiers_symbols_and_locals
    a = 5
    assert_equal "2*x**2/2", RCAS.hold { 2 * x**2 / 2 }.to_s
    assert_equal [:sub, [:mul, 5, :x], :y], RCAS.hold { a * x - :y }.to_sexp
    x = :t
    assert_equal "t + 1", RCAS.hold { x + 1 }.to_s
  end

  def test_unicode_identifiers
    assert_equal "α + β₁**2", RCAS.hold { α + β₁**2 }.to_s
    assert_equal [:α, :β₁], RCAS.hold { α + β₁**2 }.variables
    assert_equal "pi", RCAS.π.to_s
    assert_equal "oo", RCAS.∞.to_s
    assert_match RCAS::IDENTIFIER, "α₁"
    assert_match RCAS::IDENTIFIER, "∞"
    refute_match RCAS::IDENTIFIER, "Foo"
    refute_match RCAS::IDENTIFIER, "foo?"
  end

  def test_kernel_printer_names_are_indeterminates
    assert_equal "p**2 + 1", RCAS.hold { p**2 + 1 }.to_s
  end

  def test_functions_and_constants
    assert_equal "sin(0) + 4**(1/2)", RCAS.hold { sin(0) + sqrt(4) }.to_s
    assert_equal "2", RCAS.hold { sin(0) + sqrt(4) }.simplify.to_s
    assert_equal "2 + sin(1)", RCAS.hold { sin(1) + sqrt(4) }.simplify.to_s
    e = RCAS.hold { Math::PI * x }
    assert_equal [:mul, Math::PI, :x], e.to_sexp
    assert_equal [:mul, 3, :x], RCAS.hold { RCAS.hold { 3 } * x }.to_sexp
  end

  def test_method_calls_run_on_held_arguments
    assert_equal "D(x + 1, x)", RCAS.hold { (x + 1).diff(x) }.to_s
    assert_equal 1, RCAS.hold { (x + 1).diff(x) }.evaluate
    assert_equal "x**3/3", RCAS.hold { integrate(x**2, x) }.evaluate.to_s
    assert_equal "(x + 1)**2", RCAS.hold { (x + 1)**2 }.to_s
    assert_equal "1 + 2*x + x**2", RCAS.hold { (x + 1)**2 }.expand.to_s
    assert_equal "-x", RCAS.hold { -x }.to_s
  end

  def test_equations_and_inequalities
    e = RCAS.hold { x**2 - 3 == 0 }
    assert_kind_of RCAS::Equation, e
    assert_equal "x**2 - 3 = 0", e.to_s
    assert_equal ["-3**(1/2)", "3**(1/2)"], e.solve.map(&:to_s)
    assert_equal "x**2 < 4", RCAS.hold { x**2 < 4 }.to_s
    ne = RCAS.hold { x**2 - 3 != 0 }
    assert_equal "x**2 - 3 != 0", ne.to_s
    assert_equal "(-oo, -3**(1/2)) ∪ (-3**(1/2), 3**(1/2)) ∪ (3**(1/2), oo)", ne.solve(:x).to_s
    assert ne.holds?(x: 1)
    refute ne.holds?(x: RCAS.sqrt(3)), "exact root"
    assert ne.holds?(x: Math.sqrt(3)), "a float is not exactly the root"
    assert_equal "(-oo, 0) ∪ (0, oo)", RCAS.solve(RCAS::Inequality.new(1 / :x, :!=, 0), :x).to_s, "undefined points are excluded"
    assert_equal "x^{2} \\ne 0", RCAS::Inequality.new(:x**2, :!=, 0).to_latex
    assert_equal "(-2, 2)", RCAS.solve(RCAS.hold { x**2 < 4 }, :x).to_s
  end

  def test_formal_operators
    e = RCAS.hold { (sin(x)**2).integrate(x) }
    assert_kind_of RCAS::Integral, e
    assert_equal "integral(sin(x)**2, x)", e.to_s
    assert_equal "x/2 - cos(x)*sin(x)/2", e.evaluate.to_s
    assert_equal "integral(x**2, x, 0, 1)", RCAS.hold { integrate(x**2, x: 0..1) }.to_s
    assert_equal Rational(1, 3), RCAS.hold { integrate(x**2, x: 0..1) }.evaluate
    assert_equal "D(x**3, x, 2)", RCAS.hold { diff(x**3, x, 2) }.to_s
    assert_equal "6*x", RCAS.hold { (x**3).diff(x, 2) }.evaluate.to_s
    assert_equal "sum(1/n**2, n, 1, oo)", RCAS.hold { sum(1/n**2, n: 1..) }.to_s
    assert_equal "pi**2/6", RCAS.hold { sum(1/n**2, n: 1..) }.unhold.to_s
    assert_equal "limit(sin(x)/x, x, 0)", RCAS.hold { limit(sin(x)/x, x: 0) }.to_s
    assert_equal 1, RCAS.hold { limit(sin(x)/x, x, 0) }.evaluate
    assert_equal 1, RCAS.hold { limit(sin(x)/x, x, 0) }.doit, "alias"
    assert_equal "1 + integral(x, x)", RCAS.hold { 1 + integrate(x, x) }.to_s
    assert_equal "1 + x**2/2", RCAS.hold { 1 + integrate(x, x) }.evaluate.to_s
    assert_equal "D(y, x)", RCAS.hold { diff(y, x) }.evaluate.to_s, "unknown functions stay formal"
  end

  def test_blocks_from_eval
    e = eval("RCAS.hold { 1 + 2 }") # rubocop:disable Style/EvalWithLocation
    assert_equal "1 + 2", e.to_s
    e = eval("RCAS.hold { (RCAS.sin(:x)**2).integrate(:x) }")
    assert_equal "integral(sin(x)**2, x)", e.to_s
    assert_equal "x/2 - cos(x)*sin(x)/2", e.evaluate.to_s
  end

  def test_available_in_irb
    require "open3"
    out, _err, status = Open3.capture3(File.expand_path("../bin/rcas", __dir__), stdin_data: "hold { 1 + 2 }\nhold { 1/2 }.simplify\n")
    assert status.success?, out
    lines = out.lines.map(&:chomp)
    assert_includes lines, "1 + 2"
    assert_includes lines, "1/2"
  end
end
