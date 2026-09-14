# frozen_string_literal: true

require_relative "test_helper"

class SeriesTest < Minitest::Test
  include RCAS::Constants

  def sin(e) = RCAS.sin(e)
  def cos(e) = RCAS.cos(e)
  def exp(e) = RCAS.exp(e)
  def log(e) = RCAS.log(e)

  def test_taylor_and_series
    assert_equal "x - x**3/6 + x**5/120 - x**7/5040 + O(x**8)", RCAS.series(sin(:x), :x, 0, 8).to_s
    assert_equal "1 + x + x**2/2 + x**3/6 + x**4/24 + x**5/120", RCAS.taylor(exp(:x), :x).to_s
    assert_equal "x - x**2/2 + x**3/3 - x**4/4 + x**5/5 + O(x**6)", RCAS.series(log(1 + :x), :x).to_s
    assert_equal "1 + x + x**2 + x**3 + x**4 + x**5", RCAS.taylor(1 / (1 - :x), :x).to_s
    assert_equal "x + x**3/3 + 2*x**5/15 + O(x**7)", RCAS.series(RCAS.tan(:x), :x, 0, 7).to_s
    assert_equal "x - x**3/3 + x**5/5", RCAS.taylor(RCAS.atan(:x), :x, 0, 7).to_s
    assert_equal "1 + x/2 - x**2/8 + x**3/16 + O(x**4)", RCAS.series(RCAS.sqrt(1 + :x), :x, 0, 4).to_s
    assert_equal "1 + a*x + a*x**2*(-1 + a)/2", RCAS.taylor((1 + :x)**:a, :x, 0, 3).to_s
  end

  def test_laurent_puiseux_and_other_points
    assert_equal "1/x + x/6 + 7*x**3/360 + O(x**4)", RCAS.series(1 / sin(:x), :x, 0, 4).to_s
    assert_equal "1/x**2 + 1/x + 1/2 + x/6 + O(x**2)", RCAS.series(exp(:x) / :x**2, :x, 0, 2).to_s
    assert_equal "x*log(x) + O(x**3)", RCAS.series(:x * log(:x), :x, 0, 3).to_s
    assert_equal "1/x**2 - 1/x + 1 + O(1/x**3)", RCAS.series(:x / (:x + 1), :x, OO, 3).to_s
    s = RCAS.taylor(cos(:x), :x, PI / 2, 4)
    assert_in_delta Math.cos(1.6), s.evalf(x: 1.6), 1e-4
    assert_equal "1 + x/4 - (-4 + x)**2/64 + O((-4 + x)**3)", RCAS.series(RCAS.sqrt(:x), :x, 4, 3).to_s
  end

  def test_limits_at_finite_points
    assert_equal 1, RCAS.limit(sin(:x) / :x, :x, 0)
    assert_equal Rational(1, 2), RCAS.limit((1 - cos(:x)) / :x**2, :x, 0)
    assert_equal 1, RCAS.limit((exp(:x) - 1) / :x, :x, 0)
    assert_equal Rational(-1, 6), RCAS.limit((sin(:x) - :x) / :x**3, :x, 0)
    assert_equal 2, RCAS.limit((:x**2 - 1) / (:x - 1), :x, 1)
    assert_equal 0, RCAS.limit(:x * log(:x), :x, 0, :right)
    assert_equal 1, RCAS.limit(:x**:x, :x, 0, :right)
    assert_equal "-oo", RCAS.limit(log(:x), :x, 0, :right).to_s
    assert_equal "oo", RCAS.limit(1 / :x, :x, 0, :right).to_s
    assert_equal "-oo", RCAS.limit(1 / :x, :x, 0, :left).to_s
    assert_equal "oo", RCAS.limit(1 / :x**2, :x, 0).to_s
    assert_kind_of RCAS::Limit, RCAS.limit(1 / :x, :x, 0), "two-sided limit does not exist"
    assert_equal "oo", RCAS.limit(RCAS.tan(:x), :x, PI / 2, :left).to_s
  end

  def test_limits_at_infinity
    assert_equal "e", RCAS.limit((1 + 1 / :x)**:x, :x, OO).to_s
    assert_equal "exp(a)", RCAS.limit((1 + :a / :x)**:x, :x, OO).to_s
    assert_equal 1, RCAS.limit(:x / (:x + 1), :x, OO)
    assert_equal Rational(3, 2), RCAS.limit((3 * :x**2 + 1) / (2 * :x**2 - :x), :x, OO)
    assert_equal Rational(1, 2), RCAS.limit(RCAS.sqrt(:x**2 + :x) - :x, :x, OO)
    assert_equal 0, RCAS.limit(log(:x) / :x, :x, OO)
    assert_equal "oo", RCAS.limit(:x**2 - :x, :x, OO).to_s
    assert_equal "-oo", RCAS.limit(-:x**3, :x, OO).to_s
    assert_equal 0, RCAS.limit(exp(-:x), :x, OO)
    assert_equal 0, RCAS.limit(:x**3 * exp(-:x), :x, OO)
    assert_equal "oo", RCAS.limit(exp(:x) / :x**5, :x, OO).to_s
    assert_equal 0, RCAS.limit(exp(1 / :x), :x, 0, :left)
    assert_kind_of RCAS::Limit, RCAS.limit(sin(:x) / :x, :x, OO), "bounded oscillation is beyond the series method"
  end

  def test_polynomial_sums
    assert_equal "n/2 + n**2/2", RCAS.sum(:k, :k, 1, :n).to_s
    assert_equal "n/6 + n**2/2 + n**3/3", RCAS.sum(:k**2, :k, 1, :n).to_s
    assert_equal 3025, RCAS.sum(:k**3, :k, 1, 10)
    assert_equal "n**2", RCAS.sum(2 * :k - 1, :k, 1, :n).to_s
    assert_equal "5*n", RCAS.sum(5, :k, 1, :n).to_s
    assert_equal (1..20).sum { |k| k**4 }, RCAS.sum(:k**4, :k, 1, :n).call(n: 20)
  end

  def test_gosper_sums
    assert_equal "-1 + 2*2**n", RCAS.sum(2**:k, :k, 0, :n).to_s
    assert_equal "-1/(-1 + x) + x**(1 + n)/(-1 + x)", RCAS.sum(:x**:k, :k, 0, :n).to_s
    assert_equal "2 + 2*2**n*(-1 + n)", RCAS.sum(:k * 2**:k, :k, 1, :n).to_s
    assert_equal "n/(1 + n)", RCAS.sum(1 / (:k * (:k + 1)), :k, 1, :n).to_s
    assert_equal "1/2 + (-1)**n/2", RCAS.sum((-1)**:k, :k, 0, :n).to_s
    s = RCAS.sum(1 / (:k * (:k + 1) * (:k + 2)), :k, 1, :n)
    assert_in_delta (1..9).sum { |k| 1.0 / (k * (k + 1) * (k + 2)) }, s.evalf(n: 9), 1e-12
    s = RCAS.sum(1 / (:k**2 - 1), :k, 2, :n)
    assert_in_delta (2..9).sum { |k| 1.0 / (k * k - 1) }, s.evalf(n: 9), 1e-12
    assert_equal (0..7).sum { |k| k * k * 2**k }, RCAS.sum(:k**2 * 2**:k, :k, 0, :n).call(n: 7)
  end

  def test_infinite_sums
    assert_equal 1, RCAS.sum(1 / (:k * (:k + 1)), :k, 1, OO)
    assert_equal 2, RCAS.sum(Rational(1, 2)**:k, :k, 0, OO)
    assert_equal 2, RCAS.sum(:k / 2**:k, :k, 1, OO)
    assert_equal Rational(1, 4), RCAS.sum(1 / (:k * (:k + 1) * (:k + 2)), :k, 1, OO)
    assert_equal "-1/(-1 + x)", RCAS.sum(:x**:k, :k, 0, OO).to_s, "symbolic ratio: convergence assumed"
    assert_raises(ArgumentError) { RCAS.sum(2**:k, :k, 0, OO) }
    assert_equal "harmonic(n)", RCAS.sum(1 / :k, :k, 1, :n).to_s
    assert_equal "sum(1/k, k, 1, oo)", RCAS.sum(1 / :k, :k, 1, OO).to_s
  end

  def test_range_syntax_and_zeta
    assert_equal "pi**2/6", RCAS.sum(1 / :n**2, n: 1..).to_s
    assert_equal "pi**4/90", RCAS.sum(1 / :n**4, n: 1..).to_s
    assert_equal "-5/4 + pi**2/6", RCAS.sum(1 / :n**2, n: 3..).to_s
    assert_equal "zeta(3)", RCAS.sum(1 / :n**3, n: 1..).to_s
    assert_in_delta 1.2020569031595942, RCAS.zeta(3).evalf, 1e-11
    assert_equal (1..100).sum { |n| Rational(1, n * n) }, RCAS.sum(1 / :n**2, n: 1..100)
    assert_equal "-n/2 + n**2/2", RCAS.sum(:k, k: 1...:n).to_s
    assert_equal 2, RCAS.sum(1 / 2**:k, k: 0..Float::INFINITY)
    assert_equal "oo", RCAS.zeta(1).to_s
    assert_raises(ArgumentError) { RCAS.sum(:k, k: ..5) }
    assert_raises(ArgumentError) { RCAS.sum(:k, k: 1..5, j: 1..2) }
  end

  def test_definite_integrals
    assert_equal Rational(1, 3), RCAS.integrate(:x**2, x: 0..1)
    assert_equal 2, RCAS.integrate(sin(:x), x: 0..PI)
    assert_equal 1, RCAS.integrate(exp(-:x), x: 0..)
    assert_equal 1, RCAS.integrate(1 / :x**2, x: 1..)
    assert_equal 2, RCAS.integrate(1 / RCAS.sqrt(:x), x: 0..1)
    assert_equal(-1, RCAS.integrate(log(:x), x: 0..1))
    assert_equal "pi", RCAS.integrate(1 / (1 + :x**2), x: -Float::INFINITY..Float::INFINITY).to_s
    assert_equal 4, (:x**3).to_expr.integrate(x: 0..2)
    assert_equal Rational(1, 3), RCAS.integrate(:x**2, :x, 0, 1)
    assert_equal "pi**(1/2)*erf(1)/2", RCAS.integrate(exp(-:x**2), x: 0..1).to_s
    assert_equal 0, RCAS.integrate(exp(-:x**2), x: 0..1).diff(:x)
    assert_equal 1, RCAS.limit(sin(:x) / :x, x: 0)
    assert_equal "oo", RCAS.limit(1 / :x, x: 0, dir: :right).to_s
    assert_equal "1 - x**2/2 + O(x**4)", RCAS.series(cos(:x), x: 0, n: 4).to_s
  end
end
