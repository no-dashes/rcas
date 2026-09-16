# frozen_string_literal: true

require_relative "test_helper"

class CombinatoricsTest < Minitest::Test
  include RCAS::Constants

  def fact(e) = RCAS.factorial(e)

  def test_values
    assert_equal 120, fact(5)
    assert_equal 1, fact(0)
    assert_equal "pi**(1/2)/2", fact(Rational(1, 2)).to_s
    assert_equal 24, RCAS.gamma(5)
    assert_equal "pi**(1/2)", RCAS.gamma(Rational(1, 2)).to_s
    assert_equal "3*pi**(1/2)/4", RCAS.gamma(Rational(5, 2)).to_s
    assert_equal "-2*pi**(1/2)", RCAS.gamma(Rational(-1, 2)).to_s
    assert_in_delta Math.sqrt(Math::PI), RCAS.gamma(0.5).to_f, 1e-12
    assert_equal 10, RCAS.binomial(5, 2)
    assert_equal 0, RCAS.binomial(5, 7)
    assert_equal "binomial(n, 2)", RCAS.binomial(:n, 2).to_s
    assert_equal 1, RCAS.binomial(:n, 0)
    assert_equal "n", RCAS.binomial(:n, 1).to_s
    # a number at the top too: the falling factorial over k!, which is what
    # the binomial series of sqrt(1 + x) is made of
    assert_equal "1/16", RCAS.binomial(Rational(1, 2), 3).to_s
    assert_equal "-5/16", RCAS.binomial(Rational(-1, 2), 3).to_s
    assert_in_delta 0.0625, RCAS.binomial(0.5, 3).to_f, 1e-12
    assert_equal "n!", fact(:n).to_s
    assert_equal "(n + 1)!", fact(:n + 1).to_s
    assert_equal 90, (fact(10) / fact(8)).simplify
  end

  def test_factorial_cancellation
    assert_equal "1 + k", (fact(:k + 1) / fact(:k)).simplify.to_s
    assert_equal "(1 + k)*(2 + k)", (fact(:k + 2) / fact(:k)).simplify.to_s
    assert_equal "1/(1 + k)", (fact(:k) / fact(:k + 1)).simplify.to_s
    ratio = RCAS::Combinatorics.to_factorials(RCAS.binomial(:n, :k + 1) / RCAS.binomial(:n, :k)).simplify
    assert_equal "(-k + n)/(1 + k)", ratio.to_s
  end

  def test_classical_series
    k = :k
    assert_equal "exp(x)", RCAS.sum(:x**k / fact(k), k: 0..).to_s
    assert_equal "e", RCAS.sum(1 / fact(k), k: 0..).to_s
    assert_equal "-2 + e", RCAS.sum(1 / fact(k), k: 2..).to_s
    assert_equal "exp(2)", RCAS.sum(2**k / fact(k), k: 0..).to_s
    assert_equal "cos(x)", RCAS.sum((-1)**k * :x**(2 * k) / fact(2 * k), k: 0..).to_s
    assert_equal "sin(x)", RCAS.sum((-1)**k * :x**(2 * k + 1) / fact(2 * k + 1), k: 0..).to_s
    assert_equal "cosh(x)", RCAS.sum(:x**(2 * k) / fact(2 * k), k: 0..).to_s
    assert_equal "sinh(x)", RCAS.sum(:x**(2 * k + 1) / fact(2 * k + 1), k: 0..).to_s
    assert_equal "log(1 + x)", RCAS.sum((-1)**(k + 1) * :x**k / k, k: 1..).to_s
    assert_equal "pi/4", RCAS.sum((-1)**k / (2 * k + 1), k: 0..).to_s
    assert_equal "atan(x)", RCAS.sum((-1)**k * :x**(2 * k + 1) / (2 * k + 1), k: 0..).to_s
    assert_equal "(1 + x)**n", RCAS.sum(RCAS.binomial(:n, k) * :x**k, k: 0..:n).to_s
    assert_equal "2**n", RCAS.sum(RCAS.binomial(:n, k), k: 0..:n).to_s
    assert_equal "2**n*n/2", RCAS.sum(k * RCAS.binomial(:n, k), k: 0..:n).to_s
    assert_equal 1, RCAS.sum(k / fact(k + 1), k: 1..)
    assert_equal "-1 + (1 + n)!", RCAS.sum(k * fact(k), k: 1..:n).to_s
    assert_equal 153, RCAS.sum(fact(k), k: 1..5)
    assert_equal "sum(1/k, k, 1, oo)", RCAS.sum(1 / k, k: 1..).to_s, "harmonic series is not log(0)"
  end
end
