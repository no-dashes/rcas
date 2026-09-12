# frozen_string_literal: true

require_relative "test_helper"

class DifferentiateTest < Minitest::Test
  def d(expr, var = :x, n = 1) = expr.to_expr.diff(var, n).to_s

  def test_polynomials
    assert_equal "1", d(:x)
    assert_equal "0", d(:y)
    assert_equal "3 + 4*x", d(2 * :x**2 + 3 * :x + 1)
    assert_equal "6*x", d(:x**3, :x, 2)
    assert_equal "-2*x", d((:x + 1) * (1 - :x))
  end

  def test_quotients_and_powers
    assert_equal "1/y", d(:x / :y)
    assert_equal "-x/y**2", d(:x / :y, :y)
    assert_equal "x**x*(1 + log(x))", d(:x**:x)
    assert_equal "2**x*log(2)", d(2**:x)
    assert_equal "1/(2*x**(1/2))", d(RCAS.sqrt(:x))
  end

  def test_functions_and_chain_rule
    assert_equal "cos(x)", d(RCAS.sin(:x))
    assert_equal "-sin(x)", d(RCAS.cos(:x))
    assert_equal "1/x", d(RCAS.log(:x))
    assert_equal "2*x*exp(x**2)", d(RCAS.exp(:x**2))
    assert_equal "2*cos(x)*sin(x)", d(RCAS.sin(:x)**2)
    assert_equal "cos(x)**2 - sin(x)**2", d(RCAS.sin(:x) * RCAS.cos(:x))
  end

  def test_requires_a_variable
    assert_raises(ArgumentError) { (:x**2).diff(2) }
  end
end
