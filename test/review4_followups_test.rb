# frozen_string_literal: true

# Fixes made on the way through the fourth review (23 Sept 2026) that its
# own tests do not pin, and one positive control per refusal site of its
# section 2.2: the refusal is right where it is, and the decision next to
# it is made. Each assertion is the mathematics.
require_relative "test_helper"

class Review4FollowupsTest < Minitest::Test
  def setup
    @x, @y, @z, @a, @k, @n = %i[x y z a k n].map { |s| RCAS::Var.new(s) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  def refused
    yield
    false
  rescue NotImplementedError, RCAS::Unsupported, ArgumentError
    true
  end

  # ---- Decide ---------------------------------------------------------------

  # Three radicals are beyond Algebraic.exact; the annihilating polynomial
  # and a root separation bound prove the zero, and prove a near miss
  # non-zero.
  def test_an_algebraic_zero_is_proved_by_root_separation
    s2, s3 = RCAS.sqrt(2), RCAS.sqrt(3)
    assert_equal :zero, RCAS::Decide.sign(s2 * s3 - RCAS.sqrt(6))
    assert_equal false, RCAS::Decide.zero?(s2 * s3 - RCAS.sqrt(6) + n(10r**-200))
    assert_equal false, RCAS::Decide.zero?(s2 + s3 - RCAS.sqrt(5))
  end

  # A value above the rounding of its largest term is decided at the
  # precision that sees it; one below it at 120 digits is not decided.
  def test_a_sign_is_measured_against_the_cancelled_terms
    assert_equal :positive, RCAS::Decide.sign(RCAS.exp(n(10)**-100) - 1)
    assert_equal :negative, RCAS::Decide.sign(RCAS.cos(n(10)**-50) - 1)
    assert_nil RCAS::Decide.zero?(RCAS.sqrt(1 + RCAS.exp(-400)) - 1)
    assert_equal :negative, RCAS::Decide.sign(RCAS.exp(RCAS::PI * RCAS.sqrt(163)) - 640_320**3 - 744)
  end

  # Certified digits: an exact 0 at two guards is a cancellation, not a zero.
  def test_certified_evalf_rises_past_a_cancelled_zero
    assert_in_delta 1e-60, (RCAS.exp(@x) - 1).evalf(20, x: 10r**-60).to_f, 1e-72
    assert_equal 0.0, RCAS::Precision.evalf(RCAS::Sub.new(RCAS::PI, RCAS::PI), 20).to_f
    # the positional bindings and the keyword form both work
    assert_equal 2.0, RCAS::Precision.evalf(@x + 1, 20, x: 1).to_f
    assert_equal 2.0, RCAS::Precision.evalf(@x + 1, 20, { x: 1 }).to_f
  end

  # ---- signs and domains ------------------------------------------------------

  def test_signs_of_negations_differences_and_quotients
    RCAS.assume(@a > 0) do
      assert_equal :negative, RCAS.sign_of(-@a)
      assert_equal :negative, RCAS.sign_of(-@a - 1)
      assert_equal :positive, RCAS.sign_of(1 / @a)
      assert_equal :negative, RCAS.sign_of((-@a)**3)
      assert_equal :positive, RCAS.sign_of((-@a)**2)
    end
    assert_nil RCAS.sign_of(@a - 1)
  end

  # sqrt(pi**2) = pi and sqrt(1/pi**2) = 1/pi, as sqrt(4*pi**2) was 2*pi.
  def test_a_root_of_a_power_of_a_positive_constant
    assert_equal RCAS::PI, RCAS.sqrt(RCAS::PI**2)
    assert_equal (1 / RCAS::PI).simplify, RCAS.sqrt(1 / RCAS::PI**2)
    assert_equal "(x**2)**(1/2)", RCAS.sqrt(@x**2).to_s # x may be negative or complex
  end

  # Control for Inequalities.real?: a root of a positive constant is real,
  # a root of a negative one is not.
  def test_roots_of_constants_are_real_by_the_sign_of_the_radicand
    assert RCAS::Inequalities.real?(RCAS.sqrt(RCAS::PI))
    assert RCAS::Inequalities.real?(RCAS.sqrt(7 - 4 * RCAS.sqrt(3)))
    refute RCAS::Inequalities.real?(RCAS.sqrt(-RCAS::PI))
  end

  # real_domain of d != 0 when d is not a polynomial: the zeros solve names.
  def test_a_domain_condition_off_the_zeros_of_a_logarithm
    d = RCAS.real_domain(1 / RCAS.log(@x), @x)
    assert d.include?(n(2)) && d.include?(n(1r / 2))
    refute d.include?(n(1))
    refute d.include?(n(0))
  end

  # Control for Infer.log_domain: log of a square that may be 0 is complex
  # (a matrix of it can be built), and log(n) for n in NN still makes no
  # claim.
  def test_log_domains_near_zero
    RCAS.assume(x: RCAS::RR) { assert_equal RCAS::CC, RCAS.log(@x**2).domain }
    RCAS.assume(n: RCAS::NN) { assert_nil RCAS.log(@n).domain }
    RCAS.assume(n: RCAS::NN) { assert_equal RCAS::QQ, (1 / (@n + 1)).domain }
  end

  # ---- limits at a kink ---------------------------------------------------------

  # Control for Series.non_analytic!: one-sided limits through the kink,
  # and the two sides compared - sign(x) and |x|/x differ, so their limit
  # at 0 stays formal; the series of |x| at 0 is still refused.
  def test_one_sided_limits_at_a_kink
    assert_kind_of RCAS::Limit, RCAS.limit(RCAS.sign(@x), @x, 0)
    assert_kind_of RCAS::Limit, RCAS.limit(RCAS.abs(@x) / @x, @x, 0)
    assert_equal n(1), RCAS.limit(RCAS.abs(@x) / @x, @x, 0, :right)
    assert_equal n(-1), RCAS.limit(RCAS.abs(@x) / @x, @x, 0, :left)
    assert_raises(RCAS::SeriesError) { RCAS.series(RCAS.abs(@x), @x, 0) }
    RCAS.assume(@a > 0) { assert_equal @a, RCAS.limit(RCAS.abs(@x + @a), @x, 0) }
  end

  # A Taylor coefficient at a removable hole of a derivative is its limit;
  # at a pole there is none.
  def test_taylor_coefficients_at_a_hole_and_at_a_pole
    t = RCAS.taylor(RCAS::Fn.new(:Si, [@x]), @x, 0, 6)
    assert_equal "x - x**3/18 + x**5/600", t.to_s
    assert_raises(RCAS::SeriesError) { RCAS.series(RCAS.asin(1 - @x), @x, 0) }
  end

  # ---- families -------------------------------------------------------------------

  # between counts a family that is not arithmetic by its crossings, keeps
  # to the parameter's own domain, and says nil for infinitely many.
  def test_members_of_a_family_between_two_bounds
    root = RCAS::ImageSet.new(RCAS.sqrt(RCAS::PI * @k), [@k])
    assert_equal 8, root.between(0.0, 5.0).size # k = 0..7
    natural = RCAS::ImageSet.new(RCAS::PI * (1 + @k), [@k], RCAS::NN)
    assert_equal [RCAS::PI], natural.between(-10.0, 4.0)
    crowded = RCAS::ImageSet.new(1 / (2 * RCAS::PI * @k), [@k])
    assert_nil crowded.between(0.0, 1.0)
    assert_equal [], crowded.between(0.5, 1.0)
  end

  # ---- summation and recurrences ------------------------------------------------------

  # The antidifference has no removable pole left: the closed form has a
  # value at every n.
  def test_an_antidifference_without_removable_poles
    closed = RCAS.sum(RCAS.binomial(@k, 2) * n(2)**@k, @k, 0, @n)
    brute = ->(m) { (0..m).sum { |j| j * (j - 1) / 2 * 2**j } }
    (0..6).each { |m| assert_equal n(brute.call(m)), closed.subs(n: m).simplify }
  end

  # Control for the start index: a recurrence whose leading coefficient
  # vanishes before the start still refuses an initial value there.
  def test_an_initial_value_before_a_singular_start_is_refused
    u = ->(arg) { RCAS::Fn.new(:u, [RCAS::Expression.lift(arg)]) }
    assert refused { RCAS.rsolve(RCAS.eq(u.(@n + 1), (@n - 3) * u.(@n)), :u, @n, init: { 0 => 1 }) }
  end

  # Control for independent?: a genuinely dependent pair is still refused.
  def test_dependent_hypergeometric_terms_do_not_span
    terms = [RCAS.factorial(@n), 2 * RCAS.factorial(@n)]
    refute RCAS::Recurrence.independent?(terms, @n, 2, 0)
    assert RCAS::Recurrence.independent?([RCAS.factorial(@n), @a**@n * RCAS.factorial(@n)], @n, 2, 0)
  end

  # Control for vanishes_past_upper?: a factor with a pole past n keeps the
  # bound.
  def test_a_pole_past_the_upper_bound_keeps_it
    assert RCAS::Summation.vanishes_past_upper?(RCAS.binomial(@n, @k) * RCAS.binomial(@k, 2), @k, @n)
    refute RCAS::Summation.vanishes_past_upper?(RCAS.binomial(@n, @k) / (@n - @k + 1), @k, @n)
  end

  # ---- vector calculus --------------------------------------------------------------------

  # Control for regular_on!: a square around the singularity is refused, a
  # square beside it is not; the vortex has no potential on its domain.
  def test_the_vortex_near_and_away_from_its_singularity
    r2 = @x**2 + @y**2
    vortex = [-@y / r2, @x / r2]
    assert refused { RCAS.green(vortex, x: -1..1, y: -1..1) }
    assert_equal n(0), RCAS.green(vortex, x: 1..2, y: 1..2)
    assert refused { RCAS.potential(vortex) }
    assert refused { RCAS.conservative?(vortex) }
  end

  # Control for proven_sign in norm: a base that changes sign on the box
  # keeps its abs, a sum of squares loses it.
  def test_a_root_of_a_square_keeps_its_abs_only_where_the_sign_changes
    box = [[@x, 0, 1], [@y, 0, 1]]
    assert_kind_of RCAS::Fn, RCAS::VectorCalculus.root_factor(@x + @y - n(1r / 10), box) # abs(...)
    assert_equal (@x**2 + @y**2).to_s, RCAS::VectorCalculus.root_factor(@x**2 + @y**2, box).to_s
  end

  # Sturm's count decides which numeric roots are real.
  def test_numeric_roots_are_real_by_sturm
    roots = RCAS.solve(@x**5 - @x - 1, @x).map(&:evalf)
    assert_equal 1, roots.count { |r| r.is_a?(Float) }
    assert_in_delta 1.1673039782614187, roots.find { |r| r.is_a?(Float) }, 1e-15
    assert_equal 3, RCAS.solve(@x**5 - 3 * @x + 1, @x).count { |r| r.evalf.is_a?(Float) }
  end

  # A point the family already says is not said again.
  def test_a_point_inside_a_family_is_not_listed_twice
    assert_equal ["{pi*k | k in ZZ}"], RCAS.solve(@x * RCAS.sin(@x), @x).map(&:to_s)
    assert_equal [RCAS::ZZ], RCAS.solve((@x - 1) * RCAS.sin(RCAS::PI * @x), @x)
  end

  # An equation holds with Floats within their rounding, and exactly for
  # exact values.
  def test_an_equation_holds_within_its_rounding
    eq = RCAS::Equation.new(@x**2, 2)
    assert eq.holds?(x: RCAS.sqrt(2))
    assert eq.holds?(x: 2**0.5)
    refute eq.holds?(x: 1.4142)
  end

  # grad(1/r) in space is conservative on its domain: its potential is 1/r.
  def test_the_gradient_of_one_over_r_has_its_potential
    r = RCAS.sqrt(@x**2 + @y**2 + @z**2)
    field = [@x, @y, @z].map { |c| (1 / r).diff(c) }
    assert RCAS.conservative?(field)
    assert_equal (1 / r).simplify, RCAS.potential(field)
  end

  # Interval arithmetic on a box is a proof of a sign, and says nothing when
  # the box straddles a zero.
  def test_signs_on_a_box
    assert_equal :positive, RCAS::Analysis.sign_on_box(@x**2 + @y**2, [[@x, 1, 2], [@y, 1, 2]])
    assert_nil RCAS::Analysis.sign_on_box(@x + @y - n(1r / 10), [[@x, 0, 1], [@y, 0, 1]])
    assert_equal :nonnegative, RCAS::Analysis.sign_on_box(4 * @x**2 + 4 * @y**2, [[@x, 0, 1], [@y, 0, 1]])
    # nested: y from x to 3 with x from 1 to 2 keeps y in [1, 3]
    assert_equal :positive, RCAS::Analysis.sign_on_box(@y - n(1r / 2), [[@y, @x, 3], [@x, 1, 2]])
    # an enclosure forgets that y <= x, so x - y + 1 (at least 1) is only
    # shown not negative: [0, 3]
    assert_equal :nonnegative, RCAS::Analysis.sign_on_box(@x - @y + 1, [[@y, 0, @x], [@x, 1, 2]])
  end

  # ---- integration -----------------------------------------------------------------------

  # sqrt of a quadratic with real constant coefficients, by completing the
  # square: checked by differentiating.
  def test_a_radical_with_constant_coefficients
    [RCAS.sqrt(1 + 4 * RCAS::PI**2 * @x**2), 1 / RCAS.sqrt(3 - 2 * RCAS.sqrt(2) * @x - RCAS::PI * @x**2)].each do |f|
      r = RCAS.integrate(f, @x)
      refute_kind_of RCAS::Integral, r
      [0.1, 0.3].each { |p| assert_in_delta 0, (r.diff(@x) - f).evalf(x: p).abs, 1e-12 }
    end
  end

  # ---- numerics ---------------------------------------------------------------------------

  # Controls for nsolve's crossing test: a jump and a pole are still
  # refused; a steep root and a root beside a pole are found.
  def test_nsolve_tells_roots_from_jumps_and_poles
    assert refused { RCAS.nsolve(RCAS.floor(@x) - n(1r / 2), x: 0..2) }
    assert refused { RCAS.nsolve(1 / @x, x: -1..1) }
    assert refused { RCAS.nsolve(RCAS.tan(@x), x: 1..2) }
    assert_in_delta Math::PI, RCAS.nsolve(RCAS.tan(@x), x: 3..3.5), 1e-12
  end

  # Control for the compiled integrand: an integrand with no real value on
  # the range is still refused.
  def test_an_integrand_with_no_real_value_is_refused
    assert refused { RCAS.nintegrate(RCAS.log(@x), x: -2..-1) }
  end

  # ---- limits and asymptotes ------------------------------------------------------------

  # The logistic function and its relatives, through u = exp(x); 1/log(x)
  # through u = log(x).
  def test_limits_through_an_exponential_or_a_logarithm
    e = RCAS.exp(@x)
    assert_equal n(1), RCAS.limit(e / (1 + e), @x, RCAS::OO)
    assert_equal n(0), RCAS.limit(e / (1 + e), @x, -RCAS::OO)
    assert_equal n(1), RCAS.limit(1 / (1 + RCAS.exp(-@x)), @x, RCAS::OO)
    assert_equal RCAS::OO, RCAS.limit(RCAS.exp(@x / 2) / (RCAS.exp(@x / 3) + 1), @x, RCAS::OO)
    assert_equal n(0), RCAS.limit(1 / RCAS.log(@x), @x, 0, :right)
    assert_equal n(1), RCAS.limit(RCAS.log(@x) / (1 + RCAS.log(@x)), @x, RCAS::OO)
  end

  # An asymptote row is "not determined" rather than "none" when a limit
  # is not taken; a periodic function has no horizontal asymptote at all.
  def test_discuss_says_when_an_asymptote_is_not_determined
    report = RCAS.discuss(RCAS.exp(@x) / (1 + RCAS.exp(@x)), @x)
    assert_equal [n(0), n(1)].sort_by(&:to_s), report.asymptotes[:horizontal].sort_by(&:to_s)
    report = RCAS.discuss(RCAS.tan(@x), @x)
    assert_equal [], report.asymptotes[:horizontal]
    assert_equal ["{pi/2 + pi*k | k in ZZ}"], report.asymptotes[:vertical].map(&:to_s)
    assert_raises(NotImplementedError, RCAS::Unsupported) { RCAS::Analysis.horizontal_asymptotes(RCAS.exp(@x) / (@x * (1 + RCAS.exp(@x))) + RCAS.sin(@x), @x) }
  end

  # ---- declared domains for families -----------------------------------------------------

  # a + b*k meets ZZ on a residue class, and NN or a sign cut it to a side.
  def test_a_rational_family_under_a_declared_domain
    k = @k
    assert_equal [RCAS::ZZ], RCAS::Solve.restrict([RCAS::ImageSet.new(k / 2, [k])], @x, RCAS::ZZ)
    assert_equal [], RCAS::Solve.restrict([RCAS::ImageSet.new(n(1r / 2) + k, [k])], @x, RCAS::ZZ)
    assert_equal ["{1 + 3*k | k in ZZ}"], RCAS::Solve.restrict([RCAS::ImageSet.new(1 + 3 * k / 2, [k])], @x, RCAS::ZZ).map(&:to_s)
    assert_equal ["{1 + 3*k | k in NN}"], RCAS::Solve.restrict([RCAS::ImageSet.new(1 + 3 * k / 2, [k])], @x, RCAS::NN).map(&:to_s)
    assert_equal [RCAS::NN], RCAS::Solve.restrict([RCAS::ImageSet.new(k / 2, [k])], @x, RCAS::NN)
  end

  # A removable pole cancels out of the sign chart without being sampled.
  def test_a_sign_chart_across_a_removable_pole
    assert_equal "[1, oo)", RCAS.solve((@x**2 - @x) / @x >= 0, @x).to_s
    assert_equal "(-oo, -1)", RCAS.solve((@x**2 + @x) / @x < 0, @x).to_s
  end

  # ---- the Float route of Decide -----------------------------------------------------------

  # A running error bound: a quotient cancels nothing (sqrt(2)/92160 is
  # plainly not 0), a difference of close terms carries their errors, and a
  # function of a large argument inherits the argument's error.
  def test_a_float_is_believed_well_above_its_error_bound
    assert RCAS::Decide.float_nonzero?(RCAS.sqrt(2) / 92_160)
    refute RCAS::Decide.float_nonzero?(RCAS.sqrt(2) * RCAS.sqrt(3) - RCAS.sqrt(6))
    refute RCAS::Decide.float_nonzero?(RCAS.sin(n(10)**20))
    refute RCAS::Decide.float_nonzero?(n(10)**30 * (RCAS.sqrt(2)**2 - 2))
    assert RCAS::Decide.float_nonzero?(RCAS.asin(n(2))) # complex, clear of 0
  end

  # sign(u)*|u|**e is u**e for an odd e.
  def test_a_sign_times_a_modulus
    assert_equal (1 / @x).simplify, (RCAS.sign(@x) / RCAS.abs(@x)).simplify
    assert_equal @x, (RCAS.sign(@x) * RCAS.abs(@x)).simplify
    assert_equal "abs(x)**2*sign(x)", (RCAS.sign(@x) * RCAS.abs(@x)**2).simplify.to_s # even: unchanged
  end

  # The antiderivative through t = 1/(x - alpha) holds on both sides of
  # alpha: checked by differentiating left and right of -1/2.
  def test_a_linear_factor_under_a_radical_on_both_sides
    f = 1 / ((2 * @x + 1) * RCAS.sqrt(@x**2 + 1))
    r = RCAS.integrate(f, @x)
    [-2.0, -0.7, 0.3, 2.0].each { |p| assert_in_delta 0, (r.diff(@x) - f).evalf(x: p), 1e-12 }
  end

  # erf(u) at infinity through erfc: the tail that exp(x**2) multiplies back.
  def test_limits_of_erf_at_infinity
    assert_equal n(1), RCAS.limit(RCAS.erf(@x), @x, RCAS::OO)
    assert_equal n(-1), RCAS.limit(RCAS.erf(@x), @x, -RCAS::OO)
    assert_equal n(0), RCAS.limit(RCAS.erf(@x) / @x, @x, RCAS::OO)
  end

  # Products: a factor with a pole makes an undefined product, a bound that
  # is no integer is refused, a zero past the start keeps the product formal.
  def test_products_with_poles_zeros_and_fractional_bounds
    assert_equal RCAS::UNDEFINED, RCAS.product(1 / @k, @k, 0, 3)
    assert_equal n(1r / 6), RCAS.product(1 / @k, @k, 1, 3)
    assert refused { RCAS.product(@k, @k, 1, 5r / 2) }
    assert_kind_of RCAS::Product, RCAS.product(@k - 3, @k, 1, @n)
    assert_equal n(0), RCAS.product(@k - 3, @k, 1, 5)
  end

  # A fixed pole past the start leaves a sum with a symbolic bound formal;
  # a pole before the start does not.
  def test_a_sum_past_a_fixed_pole
    assert_kind_of RCAS::Sum, RCAS.sum(1 / ((@k - 3) * (@k - 2)), @k, 0, @n)
    assert_equal (@n / (1 + @n)).simplify, RCAS.sum(1 / (@k * (@k + 1)), @k, 1, @n)
  end

  # ---- evaluation ---------------------------------------------------------------------------

  # A Float that lost its digits to cancellation is taken again in
  # arbitrary precision: 1 - cdf(30) of Poisson(2) is 3.77e-26, and an
  # exact zero comes out as 0.0 rather than rounding noise.
  def test_evalf_does_not_hand_back_a_cancelled_float
    tail = 1 - RCAS::Distributions::Poisson.new(2).cdf(30)
    assert_in_delta 3.7695528553257976e-26, tail.evalf, 1e-36
    assert_equal 0.0, (RCAS.sqrt(2) * RCAS.sqrt(3) - RCAS.sqrt(6)).evalf
  end

  # E1 and erfc by continued fractions: no series to cancel.
  def test_continued_fractions_for_the_far_tails
    assert_in_delta(-1.4065187662340329e-307, RCAS.Ei(@x).evalf(20, x: -700).to_f, 1e-320)
    assert_in_delta(-0.0011482955912753258, RCAS.Ei(@x).evalf(20, x: -5).to_f, 1e-18)
    assert_in_delta Math.erfc(12.0), RCAS.erfc(@x).evalf(20, x: 12).to_f, 1e-76
  end

  # A piecewise condition is decided exactly, and k in ZZ is one.
  def test_piecewise_conditions_are_decided
    pw = RCAS::Piecewise.new([[RCAS::Membership.new(@k, RCAS::ZZ), @k**2], [RCAS::Piecewise::OTHERWISE, n(0)]])
    assert_equal n(0), pw.subs(k: 5r / 2).simplify
    assert_equal n(9), pw.subs(k: 3).simplify
    tiny = RCAS::Piecewise.new([[RCAS::Inequality.new(RCAS.cos(n(10)**-30) - 1, :<, 0), n(1)], [RCAS::Piecewise::OTHERWISE, n(2)]])
    assert_equal n(1), tiny.simplify
  end

  # ---- distributions ------------------------------------------------------------------------

  # The t distribution's tails in closed form for 1 and 2 degrees of
  # freedom, its centre, and the normal limit for a huge nu.
  def test_student_t_tails_and_centre
    t = RCAS::Distributions::StudentT
    assert_equal "atan(1/5)/pi", t.new(1).survival(5).to_s
    assert_in_delta 0.5 - 5 / (2 * Math.sqrt(27)), t.new(2).survival(5).evalf, 1e-15
    assert_equal n(0), t.new(7).quantile(1r / 2)
    assert_in_delta 0.8413447460685429, t.new(10**9).cdf(1.0).value, 1e-9
  end

  # Discrete quantiles exactly, Float upper tails summed from the top.
  def test_discrete_quantiles_and_tails
    b = RCAS::Distributions::Binomial
    assert_equal n(0), b.new(3, 1r / 2).quantile(1r / 8)
    assert_equal n(1), b.new(3, 1r / 2).quantile(1r / 8 + 10r**-30)
    assert_in_delta 3.2248444478817708e-24, b.new(100, 0.5).probability(@x > 95).value, 1e-30
    assert_equal n(1000), b.new(2000, 1r / 2).quantile(0.5)
  end

  # A symbolic range that turns out reversed is empty; p = 1 is the top
  # of an exponential, and no constant outside [0, 1] is a probability.
  def test_ranges_and_quantile_arguments
    pr = RCAS::Distributions::Exponential.new(1).probability(@a..@z)
    assert_equal n(0), pr.subs(a: 3, z: 1).simplify
    assert_equal RCAS::OO, RCAS::Distributions::Exponential.new(2).quantile(1)
    assert refused { RCAS::Distributions::Normal.new(0, 1).quantile(RCAS.sqrt(2)) }
  end

  # ---- smaller findings of the fourth review --------------------------------------------------

  # atan has no value at i; erf has one at 1 + i (the series, |z| <= 3).
  def test_complex_values_of_atan_and_erf
    assert_equal RCAS::UNDEFINED, RCAS.atan(@x).evalf(x: Complex(0, 1))
    v = RCAS.erf(@x).evalf(x: Complex(1, 1))
    assert_in_delta 1.3161512816979477, v.real, 1e-14
    assert_in_delta 0.19045346923783471, v.imaginary, 1e-14
  end

  # A factor free of t is a constant of the Laplace transform (L7).
  def test_laplace_of_a_parameter_times_a_function
    t, s, b = %i[t s b].map { |v| RCAS::Var.new(v) }
    assert_equal (@a / (1 + s**2)).simplify, RCAS.laplace(@a * RCAS.sin(t), t, s)
    assert_equal (@a * s / (b**2 + s**2)).simplify, RCAS.laplace(@a * RCAS.cos(b * t), t, s)
  end

  # 0 is an inflection of a*x**3 + x**5 for every a: the order of vanishing
  # of f'' is 1 or 3, odd either way (S22); for a*x**3 + x**4 it is 1 or 2.
  def test_an_inflection_whose_parity_does_not_depend_on_the_parameter
    assert RCAS::Analysis.inflection_at?((@a * @x**3 + @x**5).diff(@x, 2), @x, n(0), [])
    assert refused { RCAS::Analysis.inflection_at?((@a * @x**3 + @x**4).diff(@x, 2), @x, n(0), []) }
  end

  # Poisson pmf in Floats keeps its digits too: e**-2 * 2**3/3!.
  def test_a_float_poisson_pmf_keeps_its_digits
    assert_in_delta Math.exp(-2) * 8 / 6, RCAS::Distributions::Poisson.new(2.0).pdf(3).value, 1e-17
  end
end
