# Review round 4, calculus: each test pins one root cause found by the review.
require_relative 'test_helper'
require 'rcas'

class ReviewCalculusTest < Minitest::Test
  def setup
    @x, @a = %i[x a].map { |n| RCAS::Var.new(n) }
  end
  def teardown = RCAS.forget
  def n(v) = RCAS::Num.new(v)

  def value(e, **b)
    v = RCAS::Expression.lift(e).evalf(**b)
    v.is_a?(RCAS::Num) ? v.value : v
  end

  # F' by a central difference, so the check does not depend on how F is spelled.
  def assert_antiderivative(f, points)
    big_f = RCAS.integrate(f, @x)
    points.each do |p|
      h = 1e-6
      slope = (value(big_f, x: p + h) - value(big_f, x: p - h)) / (2 * h)
      assert_in_delta value(f, x: p), slope, 1e-5, "F = #{big_f} at x = #{p}"
    end
  end

  def formal?(e) = e.is_a?(RCAS::Expression) && e.each_node.any? { |m| m.is_a?(RCAS::Integral) || m.is_a?(RCAS::Limit) }

  def test_sqrt_of_quadratic_with_odd_linear_coefficient
    # d/dx log(x + 1/2 + sqrt(x^2 + x + 1)) = 1/sqrt(x^2 + x + 1); the 1/2 is b/(2a).
    assert_antiderivative(1 / RCAS.sqrt(@x**2 + @x + 1), [0.4, 1.7, 3.1])
  end

  def test_linear_factor_under_a_radical_keeps_its_rational_root
    # 1/((2x + 1)*sqrt(x^2 + 1)) is positive for x > 0, so its antiderivative is not 0.
    assert_antiderivative(1 / ((2 * @x + 1) * RCAS.sqrt(@x**2 + 1)), [0.4, 1.7])
  end

  def test_rational_atan_antiderivative_is_split_where_its_argument_has_a_pole
    # F = atan((x^2 - 1)/(sqrt(2)*x))/sqrt(2) jumps by pi/sqrt(2) at x = 0, where the
    # integrand is smooth; the integral of the positive integrand is 3.7532894344772...
    r = RCAS.integrate((@x**2 + 1) / (@x**4 + 1), @x, -3, 3)
    assert_in_delta 3.753289434477252, value(r), 1e-9
  end

  def test_weierstrass_antiderivative_is_split_where_tan_half_angle_vanishes
    # 1/(1 + sin(x)^2) >= 1/2, and the integral over -1..2 is 2.1413814824544...;
    # F has a break at x = 0 (tan(x/2) = 0 in the denominator of an atan argument).
    r = RCAS.integrate(1 / (1 + RCAS.sin(@x)**2), @x, -1, 2)
    assert_in_delta 2.1413814824544537, value(r), 1e-9
  end

  def test_atan_of_tan_in_the_integrand_is_not_unwound
    # atan(tan(x)) = x - pi on (pi/2, 3pi/2), so F'(2.3) = 2.3 - pi, not 2.3.
    assert_antiderivative(RCAS.atan(RCAS.tan(@x)), [0.4, 2.3])
  end

  def test_improper_integral_evaluates_on_the_checked_route
    # integral(x^(-3/2), x, 2, oo) = 2/sqrt(2) = sqrt(2). evalf turns oo into a Float
    # and lands on an unchecked Simpson rule (1.41419356..., and 23.03 for the
    # divergent integral(1/x, x, 1, oo)); refusing is fine, a wrong digit is not.
    v = begin
      RCAS::Integral.new(@x**n(Rational(-3, 2)), @x, n(2), RCAS::OO).evalf
    rescue ArgumentError
      return assert true
    end
    assert(v.is_a?(RCAS::Expression) || (v - Math.sqrt(2)).abs < 1e-12, "evalf gave #{v}")
  end

  def test_nintegrate_handles_an_interior_kink
    # integral of |x - 1| over 0..3 is 1/2 + 2 = 5/2.
    v = begin
      RCAS.nintegrate(RCAS.abs(@x - 1), x: 0..3)
    rescue ArgumentError => e
      flunk "nintegrate refused: #{e.message}"
    end
    assert_in_delta 2.5, v, 1e-9
  end

  def test_nintegrate_does_not_return_a_principal_value
    # 1/x is not integrable on -1..1; 0.0 is the Cauchy principal value, not the integral.
    assert_raises(ArgumentError) { RCAS.nintegrate(1 / @x, x: -1..1) }
  end

  def test_symbolic_pole_between_the_bounds_is_not_ignored
    # 1/(x - a)^2 > 0; for a = 1/2 the integral over 0..1 diverges, yet the generic
    # answer -1/(1 - a) - 1/a gives -4 there.
    r = RCAS.integrate(1 / (@x - @a)**2, @x, 0, 1)
    special = r.subs(a: Rational(1, 2)).simplify
    assert(formal?(r) || r.is_a?(RCAS::Piecewise) || special == RCAS::OO, "got #{r}, #{special} at a = 1/2")
  end

  def test_non_analytic_functions_have_no_taylor_series_at_their_kink
    # For x < 0, (|x| - x)/x = -2 identically, so the left limit is -2.
    r = RCAS.limit((RCAS.abs(@x) - @x) / @x, x: 0, dir: :left)
    assert(r.is_a?(RCAS::Limit) || r == n(-2), "got #{r}")
    r = RCAS.limit(RCAS.sign(@x), @x, 0)
    refute_equal n(0), r, 'sign(x) is 1 on the right and -1 on the left'
  end

  def test_erfc_tail_is_not_zero_against_exponential_growth
    # erfc(x) ~ exp(-x^2)/(x*sqrt(pi)), so x*exp(x^2)*erfc(x) -> 1/sqrt(pi) = 0.5641...
    r = RCAS.limit(RCAS.erfc(@x) * RCAS.exp(@x**2) * @x, @x, RCAS::OO)
    assert(r.is_a?(RCAS::Limit) || (value(r).is_a?(Numeric) && (value(r) - 0.5641895835477563).abs < 1e-12), "got #{r}")
  end

  def test_fps_keeps_the_index_where_the_recurrence_degenerates
    # x/(1 - x) = x + x^2 + ...; the recurrence (k - 1)*(a(k) - a(k - 1)) = 0 says
    # nothing at k = 1, and cancelling it away left the series 0.
    begin
      r = RCAS.fps(@x / (1 - @x), @x)
    rescue RCAS::SeriesError
      return assert true
    end
    refute_equal n(0), r
  end

  def test_series_order_term_claims_only_what_is_known
    # sqrt(x^2 + x) = x + 1/2 - 1/(8x) + O(1/x^2); at x = 40 the O(1/x^3) claim
    # leaves an error below 1e-4, while dropping the 1/2 leaves 0.497.
    f = RCAS.sqrt(@x**2 + @x)
    t = RCAS.taylor(f, @x, RCAS::OO, 3)
    assert_in_delta value(f, x: 40.0), value(t, x: 40.0), 1e-4, "taylor = #{t}"
  end

  def test_cosine_integral_is_not_real_on_the_negative_axis
    # Ci(-x) = Ci(x) +- i*pi for x > 0: a real float is wrong on either side of the cut.
    v = begin
      value(RCAS.Ci(-1.0))
    rescue ArgumentError
      return assert true
    end
    refute(v.is_a?(Float), "Ci(-1.0) = #{v}")
  end

  def test_binomial_node_evaluates_numerically
    # binomial(5, 2) = 10; evalf turns the arguments into floats and must still fold.
    v = value(RCAS::Fn.new(:binomial, [n(5), n(2)]))
    assert_kind_of Numeric, v
    assert_in_delta 10.0, v, 1e-12
  end
end
