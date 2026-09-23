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
end
