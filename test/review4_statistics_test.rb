# Verification round of the statistics/numerics fixes (after 8c10e71): each
# test states a mathematical fact that rcas still gets wrong, or got right
# before the fixes and gets wrong now. Reference values are derived in the
# test from definitions, exact sums or Ruby's own Math.erfc.
require_relative 'test_helper'
require 'rcas'
require 'bigdecimal'
require 'bigdecimal/math'

class Review2StatisticsTest < Minitest::Test
  N = RCAS::Distributions

  def setup
    @x, @k, @a, @b = %i[x k a b].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget
  def n(v) = RCAS::Num.new(v)

  def float(e)
    v = e.is_a?(RCAS::Expression) ? e.evalf : e
    v = v.value if v.is_a?(RCAS::Num)
    v.to_f
  end

  def assert_relative(expected, actual, tolerance, message = nil)
    assert (actual - expected).abs <= tolerance * expected.abs,
           "#{message} got #{actual}, expected #{expected} (relative #{((actual - expected) / expected).abs})"
  end

  # Data on a picometre scale has a spread: [1, 2, 3]*1e-12 has mean 2e-12,
  # s = 1e-12 and t = 2*sqrt(3) = 3.4641 against mu = 0, as at any other
  # scale. Before the fixes this was computed; now Scalar.zero? calls the
  # standard error (5.8e-13) zero because Decide leaves it undecided and
  # undecided below 1e-12 counts as zero (scalar.rb vanishes?).
  def test_a_small_scale_sample_has_a_spread
    result = RCAS.ttest([1.0e-12, 2.0e-12, 3.0e-12], mu: 0)
    assert_in_delta 2 * Math.sqrt(3), float(result.statistic), 1e-9
  end

  # A continuous function that changes sign has a root there, however
  # steep: the real cube root sign(u)*|u|**(1/3) of u = x - 3/10 vanishes
  # at 3/10. Before the fixes nsolve found it; now it is refused as "a
  # jump, not a root" (numerics.rb jump!: |f| is 5e-6 one ulp away).
  def test_a_steep_root_is_not_a_jump
    root = RCAS.nsolve(RCAS.sign(@x - 3/10r) * RCAS.abs(@x - 3/10r)**(1/3r), x: 0..1)
    assert_in_delta 0.3, root, 1e-12
  end

  # 1/(x - 1) = 10**13 has the root 1 + 1e-13, bracketed by 1 + 1e-14..2,
  # where the function is continuous; the pole at 1 is outside. nsolve
  # calls the root "a pole".
  def test_a_root_near_a_pole_is_a_root
    root = RCAS.nsolve(1 / (@x - 1) - 10**13, x: (1 + 1e-14)..2)
    assert_in_delta 1e-13, root - 1, 1e-15
  end

  # Binomial with a Float p goes through lgamma now: C(10, 5)/2**10 is
  # exactly 0.24609375 = 252/1024 and printed as 0.24609375000000067, and
  # C(100, 50)/2**100 = 0.0795892373871787615 lost two digits. Before the
  # fixes both were right to the last place.
  def test_a_float_binomial_pmf_keeps_its_digits
    assert_in_delta 0.24609375, float(N::Binomial.new(10, 0.5).pdf(5)), 1e-16
    assert_relative 0.07958923738717876, float(N::Binomial.new(100, 0.5).pdf(50)), 2e-15
  end

  # Certified digits must not certify a zero that is a deep cancellation:
  # exp(x) - 1 at 1e-60 is x + x**2/2 + ... = 1e-60, 1 - cos(x) at 1e-25 is
  # x**2/2 = 5e-51, erfc(12) = 1.356e-64 (Math.erfc is accurate there),
  # Ei(-700) = -E1(700) = -1.40651876623403e-307 (continued fraction for E1
  # at 80 digits). Two working precisions that both cancel to 0 "agree" on
  # 0 (precision.rb agree?/the value.zero? rule). A refusal is acceptable.
  def test_certified_digits_do_not_certify_a_cancelled_zero
    cases = [
      [RCAS.exp(@x) - 1, { x: 10r**-60 }, 1.0e-60],
      [1 - RCAS.cos(@x), { x: 10r**-25 }, 5.0e-51],
      [RCAS.erfc(@x), { x: 12 }, Math.erfc(12.0)],
      [RCAS.Ei(@x), { x: -700 }, -1.4065187662340329e-307]
    ]
    cases.each do |e, bindings, truth|
      begin
        v = e.evalf(20, **bindings)
      rescue RCAS::Precision::Unsupported, NotImplementedError
        next
      end
      assert_relative truth, v.to_f, 1e-12, "#{e} at #{bindings}:"
    end
  end

  # P(9 <= Z <= 10) = (erfc(9/sqrt 2) - erfc(10/sqrt 2))/2 = 1.12851e-19;
  # cdf(10) - cdf(9) as (1 + erf)/2 cancels to 0. The mirrored interval
  # -10..-9 is right, which is how the survival fix was tested.
  def test_an_upper_tail_interval_does_not_cancel_to_zero
    truth = (Math.erfc(9 / Math.sqrt(2)) - Math.erfc(10 / Math.sqrt(2))) / 2
    assert_relative truth, float(N::Normal.new(0, 1).probability(9..10)), 1e-9
  end

  # The Cauchy tail: P(T > t) = atan(1/t)/pi = 3.1831e-18 at t = 1e17, and for
  # nu = 2 the two-sided p-value is 1 - t/sqrt(2 + t**2) = 2/(s*(s + t)) with
  # s = sqrt(2 + t**2). survival falls back on 1 - cdf for nu = 1 and 2.
  def test_student_tails_with_one_and_two_degrees_of_freedom
    assert_relative Math.atan(1e-17) / Math::PI, float(N::StudentT.new(1).probability(@x > 1.0e17)), 1e-9
    data = [1.0, 1.0 + 1e-9, 1.0 - 1e-9]
    result = RCAS.ttest(data, mu: -1)
    t = float(result.statistic)
    s = Math.sqrt(2 + t * t)
    assert_relative 2 / (s * (s + t)), float(result.pvalue), 1e-6, "ttest df = 2:"
  end

  # A probability is never negative. P(X > 95) for Binomial(100, 1/2) is
  # sum_{k=96}^{100} C(100, k)/2**100 = 3.2248e-24, and for Poisson(2)
  # P(X > 30) = e**-2 * sum_{k>30} 2**k/k! = 3.5e-26; the discrete survival
  # is 1 - cdf, which cancels (and with the lgamma pmf goes below zero).
  def test_discrete_upper_tails_are_positive_and_accurate
    binomial = (96..100).sum { |j| Rational((1..100).reduce(:*), (1..j).reduce(:*) * (1..(100 - j)).reduce(1, :*)) } / 2r**100
    v = float(N::Binomial.new(100, 0.5).probability(@x > 95))
    assert v >= 0, "P(X > 95) = #{v} is negative"
    assert_relative binomial.to_f, v, 1e-6
    tail = (31..90).sum { |j| Rational(2**j, (1..j).reduce(:*)) }
    poisson = BigMath.exp(BigDecimal(-2), 40) * BigDecimal(tail.numerator).div(tail.denominator, 40)
    assert_relative poisson.to_f, float(N::Poisson.new(2).probability(@x > 30)), 1e-6
  end

  # I_x(nu/2, 1/2) with x = nu/(nu + t**2) near 1 loses the digits for a
  # large nu: t with 10**12 degrees of freedom is the normal to within
  # 1e-12, so cdf(1) = Phi(1) = 0.841344746068543. It printed 0.84128,
  # silently (beta_i has no non-convergence signal, unlike gamma_p now).
  def test_student_cdf_with_many_degrees_of_freedom
    phi = (1 + Math.erf(1 / Math.sqrt(2))) / 2
    assert_in_delta phi, float(N::StudentT.new(10**12).cdf(1.0)), 1e-9
  end

  # The median of a symmetric distribution is its centre: quantile(1/2) of
  # a t distribution is 0, and cdf(1e-9) of t_5 is 1/2 + 3.796e-10.
  def test_student_quantile_at_one_half_is_zero
    assert_in_delta 0.0, float(N::StudentT.new(5).quantile(0.5)), 1e-12
    assert_in_delta 0.5 + 0.3796066898224944e-9, float(N::StudentT.new(5).cdf(1e-9)), 1e-15
  end

  # Quantiles in the upper tail: for p = 1 - 1e-15 (the Float; its tail is
  # 9.992e-16) the normal quantile is 7.9414444874, found by bisection on
  # Math.erfc; ChiSquare(2) has the closed form -2*log(1 - p). Bisection on
  # the cdf near 1 only sees steps of 1.1e-16 and gave 7.9364 and 55.26198.
  def test_upper_tail_quantiles_use_the_tail
    tail = 1 - (1 - 1e-15)
    lo, hi = 7.0, 9.0
    200.times { m = (lo + hi) / 2; Math.erfc(m / Math.sqrt(2)) / 2 > tail ? lo = m : hi = m }
    assert_in_delta lo, float(N::Normal.new(0, 1).quantile(1 - 1e-15)), 1e-6
    p = 1 - 1e-12
    assert_in_delta(-2 * Math.log(1 - p), float(N::ChiSquare.new(2).quantile(p)), 1e-6)
  end

  # A discrete quantile is the least k with cdf(k) >= p, decided exactly:
  # Binomial(3, 1/2) has cdf(0) = 1/8 < 1/8 + 1e-14 <= cdf(1) = 1/2, and
  # Poisson(1) has P(X > 15) = 1.9e-14 > 1e-14 >= P(X > 16) = 1.1e-15, so
  # quantile(1 - 1e-14) is 16. A 1e-12 slack answered 0 and 14.
  def test_discrete_quantiles_have_no_slack
    assert_equal n(1), N::Binomial.new(3, 1/2r).quantile(1/8r + 10r**-14)
    assert_equal n(16), N::Poisson.new(1).quantile(1 - 10r**-14)
  end

  # The variance of t_2 and the kurtosis of t_4 are infinite (the
  # integrals diverge), which the new moment_exists answers with oo - but
  # the formula nu/(nu - 2) is evaluated first and divides by zero.
  def test_moments_at_the_boundary_of_existence
    assert_equal RCAS::OO, N::StudentT.new(2).variance
    assert_equal RCAS::OO, N::StudentT.new(4).kurtosis
  end

  # The exponential quantile at p = 1 is oo (or a refusal), never a bare
  # ZeroDivisionError; and 2*sqrt(2) or pi is no probability, although only
  # a Num was checked: the answers were 2*sqrt(2) and log(1/(1 - pi)).
  def test_quantile_arguments_outside_zero_one
    begin
      q = N::Exponential.new(1).quantile(1)
      assert_equal RCAS::OO, q
    rescue ArgumentError, NotImplementedError
      pass
    end
    assert_raises(ArgumentError) { N::Uniform.new(0, 1).quantile(2 * RCAS.sqrt(2)) }
    assert_raises(ArgumentError) { N::Exponential.new(1).quantile(RCAS::PI) }
  end

  # The discrete twin of T6: a symbolic point keeps no support, so after a
  # substitution the cdf of a die is 3/2 at 9 and -1/3 at -2, and it counts
  # 5.5 as 5.5 values (11/12); the Binomial pmf at 5/2 is not 0.
  def test_discrete_cdf_at_a_symbolic_point_keeps_its_support
    die = N::DiscreteUniform.new(1, 6).cdf(@k)
    assert_equal n(1), die.subs(k: 9).simplify
    assert_equal n(0), die.subs(k: -2).simplify
    assert_equal n(5/6r), die.subs(k: 11/2r).simplify
    assert_equal n(0), N::Binomial.new(10, 1/2r).pdf(@k).subs(k: 5/2r).simplify
  end

  # P(a <= X <= b) is 0 for a > b: the symbolic event came back as
  # cdf(b) - cdf(a), which is -1/2 for Uniform(0, 1) at a = 2, b = 1/2.
  def test_a_symbolic_range_that_turns_out_reversed_is_empty
    p = N::Uniform.new(0, 1).probability(@a..@b).subs(a: 2, b: 1/2r).simplify
    assert_equal n(0), p
  end
end
