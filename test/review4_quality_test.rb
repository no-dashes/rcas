# Review round 4, quality and fast paths: each test states a property that
# the fixes of da72570..8c10e71 still violate, derived independently.
require_relative 'test_helper'
require 'rcas'

class Review2QualityTest < Minitest::Test
  def setup
    @x, @a = %i[x a].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  # For 1 < x < 2 the principal asin(x) = pi/2 - i*acosh(x), so the integrand
  # |asin(x)| = sqrt(pi**2/4 + acosh(x)**2) is real and smooth; a midpoint
  # rule with 200000 panels gives 1.8317342920790718 (the tree evaluation
  # of da72570 gave the same). Numerics.compile answers nil for asin out of
  # [-1, 1] and caller_for never falls back to the tree.
  def test_a_real_integrand_with_complex_intermediate_values_is_integrated
    v = RCAS.nintegrate(RCAS.abs(RCAS.asin(@x)), x: 1..2)
    assert_in_delta 1.8317342920790718, v, 1e-8
  end

  # |sqrt(x)| = sqrt(-x) for x < 0, so the integral over -1..0 is 2/3.
  def test_the_modulus_of_a_principal_root_is_integrated
    v = RCAS.nintegrate(RCAS.abs(RCAS.sqrt(@x)), x: -1..0)
    assert_in_delta 2.0 / 3, v, 1e-8
  end

  # |asin(x)| = 1.9 at x = cosh(sqrt(1.9**2 - pi**2/4)) = 1.627811245442231;
  # the function is real and continuous on 1..2 (see above).
  def test_nsolve_through_complex_intermediate_values
    root = RCAS.nsolve(RCAS.abs(RCAS.asin(@x)) - 1.9, x: 1..2)
    assert_in_delta 1.627811245442231, root, 1e-9
  end

  # 10**400*x/10**401 is x/10, whose integral over 0..1 is 1/20; evalf of
  # the same tree at a point gives 0.05 (its `wide` fallback), while the
  # integrator's caller floats 10**400 to Infinity and reports that the
  # integrand "has no numeric value".
  def test_an_integrand_with_huge_exact_constants_is_evaluated
    f = n(10**400) * @x / n(10**401)
    assert_in_delta 0.05, RCAS.nintegrate(f, x: 0..1), 1e-12
  end

  # c = sqrt(1 + exp(-400)) - 1 = exp(-400)/2 - ... = 9.5758e-175 (evaluated
  # at 400 digits). It is not zero, so c*x = 1 has one root, and diag(c, 1)
  # has rank 2. Decide.zero? says true: at 30 and at 60 digits both values
  # are 0, which it reads as "shrinks with the precision".
  def test_a_constant_below_the_working_precision_is_not_zero
    c = RCAS.sqrt(1 + RCAS.exp(-400)) - 1
    refute_equal true, RCAS::Decide.zero?(c), 'a value of 9.6e-175 is not a proven zero'
    assert_equal 2, RCAS.matrix([[c, 0], [0, 1]]).rank
    assert_equal 1, RCAS.solve(c * @x - 1, @x).size
  end

  # d = (1 + e**-200)(1 - e**-200) - 1 + e**-400 is exactly 0 (expand says
  # so). Decide.sign(d) is :positive: at 30 and 60 digits the product
  # rounds to 1 and both levels agree on the lone e**-400. The rank of
  # diag(d, 1) must agree with its determinant, which rcas computes as 0.
  def test_an_exact_zero_with_tiny_terms_has_no_sign
    e = RCAS.exp(-200)
    d = (1 + e) * (1 - e) - 1 + RCAS.exp(-400)
    assert_equal n(0), d.expand
    refute_includes %i[positive negative], RCAS::Decide.sign(d)
    m = RCAS.matrix([[d, 0], [0, 1]])
    assert_equal n(0), m.det
    assert_equal 1, m.rank
  end
end
