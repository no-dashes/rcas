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

  def test_evalf_keeps_integer_exponents
    assert_equal "1.0 + x**2", (:x**2 + 1).evalf.to_s
    assert_equal "3.141592653589793 + x**0.5", (:x**(1 / 2r) + RCAS::PI).evalf.to_s
    assert_equal "0.5*x**3", (:x**3 / 2).evalf.to_s
    assert_in_delta 1.7320508, (:x**2 + 1).evalf(x: Math.sqrt(2)) - 1.2679492, 1e-6
  end
  # The hash is computed in the constructor, before the node is frozen; a
  # node class that does not set it falls back to the walk. Either way it
  # has to agree with eql?.
  def test_hashes_are_computed_once_and_agree_with_eql
    x = RCAS::Var.new(:x)
    a = (x + 1) * RCAS.sin(x) - 2
    b = (RCAS::Var.new(:x) + RCAS::Num.new(1)) * RCAS.sin(RCAS::Var.new(:x)) - RCAS::Num.new(2)
    assert_equal a.hash, b.hash
    assert a.eql?(b)
    assert_equal 1, { a => 1 }[b]
    refute_equal RCAS::Num.new(1).hash, RCAS::Num.new(1.0).hash, "eql? tells them apart, so the hash must too"
    refute_equal (x + 1).hash, (x - 1).hash
    formal = RCAS::Integral.new(x, x) # a node class that sets no @hash
    assert_equal formal.hash, RCAS::Integral.new(RCAS::Var.new(:x), RCAS::Var.new(:x)).hash
  end

  # constant? stops at the first Var instead of collecting them all.
  def test_constant
    x = RCAS::Var.new(:x)
    assert RCAS::Num.new(3).constant?
    assert (RCAS.sin(1) + RCAS::PI).constant?
    refute (RCAS.sin(x) + 1).constant?
    refute x.constant?
    assert_equal (RCAS.sin(x) + 1).variables.empty?, (RCAS.sin(x) + 1).constant?
  end

end
