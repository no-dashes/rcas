# frozen_string_literal: true

require_relative "test_helper"

class ExpressionTest < Minitest::Test
  def test_symbols_build_expressions
    e = :x + 1
    assert_kind_of RCAS::Add, e
    assert_equal [:add, :x, 1], e.to_sexp
  end

  def test_numbers_on_the_left_coerce
    assert_equal [:sub, 1, :x], (1 - :x).to_sexp
    assert_equal [:mul, 2, :x], (2 * :x).to_sexp
    assert_equal [:div, 1, [:add, :x, 1]], (1 / (:x + 1)).to_sexp
  end

  def test_structure_is_preserved
    e = (:x + 1) * (1 - :x)
    assert_equal [:mul, [:add, :x, 1], [:sub, 1, :x]], e.to_sexp
    assert_equal "(x + 1)*(1 - x)", e.to_s
    assert_equal e.to_s, e.inspect
  end

  def test_printing_uses_minimal_parentheses
    assert_equal "x + y + z", (:x + :y + :z).to_s
    assert_equal "x - (y - 1)", (:x - (:y - 1)).to_s
    assert_equal "x/(y*z)", (:x / (:y * :z)).to_s
    assert_equal "x*y/z", (:x * :y / :z).to_s
    assert_equal "(x**2)**3", ((:x**2)**3).to_s
    assert_equal "x**(y + 1)", (:x**(:y + 1)).to_s
    assert_equal "x**(-1)", (:x**-1).to_s
    assert_equal "2*(-x)", (2 * -:x).to_s
    assert_equal "-x**2", (-(:x**2)).to_s
    assert_equal "-(x + 1)", (-(:x + 1)).to_s
    assert_equal "x/2", (:x * Rational(1, 2)).simplify.to_s
    assert_equal "sin(x + 1)", RCAS.sin(:x + 1).to_s
  end

  def test_equality_and_hashing
    assert_equal :x + 1, :x + 1
    refute_equal :x + 1, 1 + :x
    assert_equal({ (:x + 1) => :found }[:x + 1], :found)
    assert_equal RCAS::Var.new(:x), :x
    assert_equal 0, (:x - :x).simplify
    assert_equal (:x - :x).simplify, 0
  end

  def test_variables
    assert_equal %i[x y], ((:y + 1) * :x).variables
    assert_empty (RCAS::Num.new(2) + 3).variables
  end

  def test_subs_and_call
    assert_equal "2 + y", (:x + :y).subs(x: 2).simplify.to_s
    assert_equal "z + x", (:x**2 + :x).subs(:x**2 => :z).to_s
    assert_equal 10, (:x**2 + :y).call(x: 3, y: 1)
    assert_equal "9 + y", (:x**2 + :y).call(x: 3).to_s
    assert_equal [1, 4, 9], [1, 2, 3].map(&(:x**2))
  end

  def test_lift_rejects_junk
    assert_raises(TypeError) { :x + "1" }
  end
end
