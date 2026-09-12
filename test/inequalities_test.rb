# frozen_string_literal: true

require_relative "test_helper"

class InequalitiesTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def s(*a) = RCAS.solve(*a).to_s

  def test_building
    assert_equal "x < 2", (X < 2).to_s
    assert_equal "x >= 1", (:x >= 1).to_s
    assert_equal "2 > x", (X < 2).swap.to_s
    assert (X**2 < 4).holds?(x: 1)
    refute (X**2 < 4).holds?(x: 3)
    assert_equal true, :a < :b, "symbol comparison keeps Ruby's meaning"
  end

  def test_polynomial_and_rational
    assert_equal "(-2, 2)", s(X**2 < 4, X)
    assert_equal "(-oo, -2] ∪ [2, oo)", s(X**2 >= 4, X)
    assert_equal "(-oo, 0) ∪ (0, oo)", s(X**2 > 0, X)
    assert_equal "{0}", s(X**2 <= 0, X)
    assert_equal "{}", s(X**2 + 1 < 0, X)
    assert_equal "(-oo, oo)", s(X**2 + 1 > 0, X)
    assert_equal "(-oo, -1) ∪ [1, oo)", s((X - 1) / (X + 1) >= 0, X)
    assert_equal "(-oo, 0) ∪ (1, oo)", s(1 / X < 1, X)
    assert_equal "(-2**(1/2), 2**(1/2))", s(X**2 - 2 < 0, X)
    assert_equal "(-1, 0) ∪ (1, oo)", s(X**3 - X > 0, X)
    assert_equal "(-oo, 3]", s(2 * X + 1 <= 7)
  end

  def test_absolute_values
    assert_equal "[-1, 3]", s(RCAS.abs(X - 1) <= 2, X)
    assert_equal "(-oo, -3) ∪ (3, oo)", s(RCAS.abs(X) > 3, X)
    assert_equal "(-1, -1/3)", s(RCAS.abs(2 * X + 1) < RCAS.abs(X), X)
    assert_equal 3, RCAS.abs(-3)
    assert_equal "abs(x)", RCAS.abs(-X).simplify.to_s
    assert_equal "sign(x)", RCAS.abs(X).diff(:x).to_s
    assert_equal(-1, RCAS.sign(-2))
  end

  def test_results_typeset_in_the_chat_ui
    require "rcas/chat"
    ui = RCAS::Chat::UI.new(out: StringIO.new, mode: :latex)
    assert ui.typesettable?(X**2 < 4)
    assert ui.typesettable?(RCAS.solve(X**2 < 4, X))
    assert ui.typesettable?(RCAS.GF(7).call(3))
    assert ui.typesettable?(RCAS.GF(8).gen)
    assert_equal "a^{2} + 1", RCAS::LaTeX.of(RCAS.GF(8).gen**2 + 1).sub(/\A1 \+ a\^\{2\}\z/, "a^{2} + 1")
    assert_equal "x^{2} < 4", RCAS::LaTeX.of(X**2 < 4)
  end

  def test_parameters_give_cases
    a = RCAS::Var.new(:a)
    c = RCAS.solve(X**2 - a >= 0, X)
    assert_kind_of RCAS::Cases, c
    assert_equal "a <= 0: (-oo, oo)\na > 0:  (-oo, -a**(1/2)] ∪ [a**(1/2), oo)", c.to_s
    assert_equal "(-oo, oo)", c.at(-1).to_s
    assert_equal "(-oo, -a**(1/2)] ∪ [a**(1/2), oo)", c.at(4).to_s
    assert_equal "a < 1: (a, 1)\na = 1: {}\na > 1: (1, a)", RCAS.solve((X - a) * (X - 1) < 0, X).to_s
    assert_equal "a < 0: (-oo, 1/a)\na = 0: {}\na > 0: (1/a, oo)", RCAS.solve(a * X - 1 > 0, X).to_s
    assert_equal "a < 0: (-oo, -(-a)**(1/2)) ∪ ((-a)**(1/2), oo)\na = 0: (-oo, 0) ∪ (0, oo)\na > 0: (-oo, oo)", RCAS.solve(X**2 + a > 0, X).to_s
    assert_equal "[-1 + a, 1 + a]", RCAS.solve(X**2 - 2 * a * X + a**2 - 1 <= 0, X).to_s, "no case split when the structure is uniform"
    assert_equal "(-oo, oo)", RCAS.solve(X**2 + a**2 + 1 > 0, X).to_s
    assert_match(/\\begin\{cases\}.*\\text\{if \} a \\le 0/, c.to_latex)
    assert_raises(NotImplementedError) { RCAS.solve(X**2 - a * RCAS::Var.new(:b) >= 0, X) }
    assert_equal [1, "a"], RCAS.solve((X - a) * (X - 1), X).map(&:to_s).map { |s| s == "1" ? 1 : s }
    assert_equal "2*a**(1/2)", RCAS.sqrt(4 * a).simplify.to_s
    assert_equal "a**(1/2)/2", RCAS.sqrt(a / 4).simplify.to_s
  end

  def test_systems_and_sets
    assert_equal "(1, 3)", s([X > 1, X < 3], X)
    assert_equal "{}", s([X > 3, X < 1], X)
    set = RCAS.solve(X**2 < 4, X)
    assert set.include?(0)
    refute set.include?(2)
    assert_equal "\\left(-\\infty, -2\\right] \\cup \\left[2, \\infty\\right)", RCAS.solve(X**2 >= 4, X).to_latex
    assert_raises(NotImplementedError) { RCAS.solve(RCAS.sin(X) > 0, X) }
  end
end
