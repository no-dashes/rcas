# frozen_string_literal: true

require_relative "test_helper"

class SimplifyTest < Minitest::Test
  def s(expr) = expr.simplify.to_s

  def test_identities
    assert_equal "x", s(:x + 0)
    assert_equal "x", s(:x * 1)
    assert_equal "0", s(:x * 0)
    assert_equal "x", s(:x**1)
    assert_equal "1", s(:x**0)
    assert_equal "1", s(:x / :x)
    assert_equal "0", s(:x - :x)
  end

  def test_like_terms_and_factors
    assert_equal "2*x", s(:x + :x)
    assert_equal "-2*x", s(3 * :x - 5 * :x)
    assert_equal "x**2", s(:x * :x)
    assert_equal "x**(2 + y)", s(:x**2 * :x**:y)
    assert_equal "x", s(RCAS.sqrt(:x) * RCAS.sqrt(:x))
    assert_equal "x", s((:x**Rational(1, 2))**2)
    assert_equal "8*x**3", s((2 * :x)**3)
    assert_equal "x*y**2", s((:x * :y)**2 / :x)
  end

  def test_exact_number_folding
    assert_equal "9 + x", s(2**3 + 1 + :x)
    assert_equal "x/2", s(2**-1 * :x)
    assert_equal "2.0*x", s(1.5 * :x + 0.5 * :x)
    assert_equal "2", s(RCAS.sqrt(4))
    assert_equal "2**(1/2)", s(RCAS.sqrt(2))
    assert_equal "x/3 - y/2", s(:x / 3 - :y / 2)
    assert_raises(ZeroDivisionError) { (:x / 0).simplify }
  end

  def test_canonical_ordering
    assert_equal "1 + 2*x + x**2", s(:x**2 + 2 * :x + 1)
    assert_equal "1 + 2*x + x**2", s(1 + :x * 2 + :x * :x)
    assert_equal "-x - y", s(-:x - :y)
    assert_equal "1 - x", s(-(:x - 1))
    assert_equal "2*x*exp(x**2)", s(RCAS.exp(:x**2) * :x * 2)
    assert_equal (:x + 1).simplify, (1 + :x).simplify
  end

  def test_function_folding
    assert_equal "x", s(RCAS.exp(RCAS.log(:x)))
    assert_equal "1", s(RCAS.cos(0))
    assert_equal "0.0", s(RCAS.sin(0.0))
    assert_equal "sin(x)", s(RCAS.sin(:x))
  end

  def test_expand
    assert_equal "1 - x**2", ((:x + 1) * (1 - :x)).expand.to_s
    assert_equal "x**2 + 2*x*y + y**2", ((:x + :y)**2).expand.to_s
    assert_equal "x**3 - 3*x**2*y + 3*x*y**2 - y**3", ((:x - :y)**3).expand.to_s
    assert_equal "0", (:x**2 + 2 * :x + 1 - (:x + 1)**2).expand.to_s
    assert_equal "1 + x/y", ((:x + :y) / :y).expand.to_s
  end
end
