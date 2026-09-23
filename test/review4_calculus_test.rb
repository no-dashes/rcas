# Verification round, calculus: defects found after the fixes of da72570..8c10e71.
# Each test states a mathematical expectation, derived independently.
require_relative 'test_helper'
require 'rcas'
require 'timeout'

class Review2CalculusTest < Minitest::Test
  # not a StandardError, so no rescue inside rcas swallows it
  class TooSlow < Exception; end

  def setup
    @x, @a = %i[x a].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  def value(e, at = {})
    e = RCAS::Expression.lift(e)
    e = e.subs(at.transform_values { |v| RCAS::Expression.lift(v) }) unless at.empty?
    v = e.evalf
    v = v.value if v.is_a?(RCAS::Num)
    v.is_a?(Numeric) ? v : nil
  end

  def formal?(e) = RCAS::Expression.lift(e).each_node.any? { |m| m.is_a?(RCAS::Integral) || m.is_a?(RCAS::Limit) }

  # A definite integral that is either left formal or right.
  def assert_integral(expected, result)
    return pass if formal?(result)
    v = value(result)
    assert v, "#{result} is not a number"
    assert_in_delta expected, v.real, 1e-9 * [1, expected.abs].max, "got #{result} = #{v}"
    assert_in_delta 0, v.imag, 1e-9, "got #{result} = #{v}" if v.is_a?(Complex)
  end

  # ImageSet#between counts members as base + k*step from at(0) and at(1),
  # which only an arithmetic family is. The kinks of |sin(x**2)| are
  # sqrt(k*pi); on 0..5 there are seven (sqrt(7*pi) = 4.69), and the count
  # stopped at three. With u = x**2: int_0^5 x|sin x**2| dx =
  # (1/2) int_0^25 |sin u| du = (1/2)(14 + 1 + cos 25) and
  # int_0^5 x sign(sin x**2) dx = (1/2)(pi - (25 - 7*pi)) = 4*pi - 25/2.
  def test_kinks_of_a_family_that_is_not_arithmetic_are_all_found
    s = RCAS.sin(@x**2)
    assert_integral((15 + Math.cos(25)) / 2, RCAS.integrate(@x * RCAS.abs(s), @x, 0, 5))
    assert_integral(4 * Math::PI - 12.5, RCAS.integrate(@x * RCAS.sign(s), @x, 0, 5))
  end

  # The same between() evaluates at(0) of 1/(2*pi*k) and log(2*pi*k): a
  # division by zero and a NaN. Old rcas answered the first one
  # (d/dx 1/sin(1/x) = cos(1/x)/(x**2 sin(1/x)**2), and sin(1/x) has no zero
  # for 1 <= 1/x <= 2) and left the second formal. With u = exp(x),
  # int_0^3 e^x |sin e^x| dx = int_1^{e^3} |sin u| du = 12 + cos(1) - cos(e**3),
  # since 6*pi < e**3 < 7*pi.
  def test_a_family_undefined_at_its_first_index_does_not_crash
    f = RCAS.cos(1 / @x) / (@x**2 * RCAS.sin(1 / @x)**2)
    assert_integral(1 / Math.sin(1) - 1 / Math.sin(2), RCAS.integrate(f, @x, Rational(1, 2), 1))
    g = RCAS.exp(@x) * RCAS.abs(RCAS.sin(RCAS.exp(@x)))
    assert_integral(12 + Math.cos(1) - Math.cos(Math.exp(3)), RCAS.integrate(g, @x, 0, 3))
  end

  # D3 made abs and sign refuse a series at their kink, and with it every
  # limit through that point - also of functions that are continuous there,
  # whose limit is the value: |x| -> 0, exp(-|x|) -> 1, x|x| -> 0, and
  # |x**3|/x**2 = |x| -> 0. Old rcas answered all four correctly.
  def test_a_continuous_function_has_its_value_as_limit_at_a_kink
    assert_equal n(0), RCAS.limit(RCAS.abs(@x), @x, 0)
    assert_equal n(1), RCAS.limit(RCAS.exp(-RCAS.abs(@x)), @x, 0)
    assert_equal n(0), RCAS.limit(@x * RCAS.abs(@x), @x, 0)
    assert_equal n(0), RCAS.limit(RCAS.abs(@x - 2), @x, 2)
    assert_equal n(0), RCAS.limit(RCAS.abs(@x**3) / @x**2, @x, 0)
  end

  # A declared sign has to reach the pole test: for a > 0 the pole -a of
  # 1/(x + a) lies left of 1..2, so the integral is log(2 + a) - log(1 + a)
  # (old rcas said so). possibly_inside? asks RCAS.sign_of(-a - 1), and
  # sign_of has no case for a negation: sign_of(-a) is nil under a > 0.
  def test_a_pole_outside_the_range_by_assumption_is_outside
    RCAS.assume(@a > 0) do
      r = RCAS.integrate(1 / (@x + @a), @x, 1, 2)
      refute formal?(r), "stays formal: #{r}"
      assert_in_delta Math.log(1.5), value(r, a: 1), 1e-12
      assert_equal :negative, RCAS.sign_of(-@a)
    end
  end

  # Si is entire: Si(x) = x - x**3/18 + x**5/600 - ... [AS64, 5.2.14]. The
  # refusal "has no Taylor series where its argument is 0" is false (the
  # derivative sin(x)/x has a removable singularity there, not a pole).
  def test_si_has_a_taylor_series_at_zero
    t = RCAS.taylor(RCAS::Fn.new(:Si, [@x]), @x, 0, 6)
    assert_in_delta 0.5 - 0.5**3 / 18.0 + 0.5**5 / 600.0, value(t, x: 0.5), 1e-12
  rescue RCAS::SeriesError => e
    refute_match(/no Taylor series/, e.message)
  end
end
