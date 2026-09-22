# Implementation-quality review: correctness defects behind uncertified
# floats, a missing normal form, a rebound variable, and global state.
require_relative 'test_helper'
require 'rcas'
require 'timeout'

class ReviewQualityTest < Minitest::Test
  def setup
    @x, @y, @a, @k, @n = %i[x y a k n].map { |name| RCAS::Var.new(name) }
  end
  def teardown = RCAS.forget
  def n(v) = RCAS::Num.new(v)

  def float_of(value)
    value = RCAS::Expression.lift(value).evalf
    value = value.value if value.is_a?(RCAS::Num)
    value.is_a?(Numeric) ? value : nil
  end

  # w = (a**2 - 1)/(a - 1) - a - 1 is the zero rational function (w.cancel is 0).
  def disguised_zero = (@a**2 - 1) / (@a - 1) - @a - 1

  def test_the_latex_module_can_be_a_hash_key
    # Module#hash takes no argument; LaTeX.hash(table) replaced it on the
    # module object, so any Hash keyed by the module raised.
    table = begin
      { RCAS::LaTeX => 1 }
    rescue ArgumentError => e
      flunk "hashing RCAS::LaTeX raised: #{e.message}"
    end
    assert_equal 1, table[RCAS::LaTeX]
  end

  def test_a_sign_assumption_does_not_hide_the_domain_assumption
    # x in ZZ and x > 0 are both in effect, so both statements are listed.
    RCAS.assume(@x > 0, x: RCAS::ZZ) do
      listed = RCAS.assumptions.values.map(&:to_s)
      assert listed.any? { |s| s.include?('ZZ') }, "the domain is missing: #{listed.inspect}"
      assert listed.any? { |s| s.include?('>') }, "the sign is missing: #{listed.inspect}"
    end
  end

  def test_a_rejected_assumption_changes_nothing
    # assume(x: ZZ, y: 3) raises for y; a statement refused as a whole must
    # not leave half of itself in effect.
    assert_raises(TypeError) { RCAS.assume(x: RCAS::ZZ, y: 3) }
    assert_nil RCAS.assumption(:x)
  end

  def test_an_exact_root_survives_a_residual_that_is_only_rounding
    # exp(x) = 10**10 has the single real root 10*log(10) = 23.0258...; the
    # float residual at that root is 4e-5, which is rounding at magnitude 1e10.
    roots = RCAS.solve(RCAS.exp(@x) - 10**10, @x)
    assert roots.any? { |r| (v = float_of(r)) && (v - 10 * Math.log(10)).abs < 1e-9 },
           "the root 10*log(10) was dropped: #{roots.inspect}"
  end

  def test_a_root_inside_the_domain_survives_the_domain_check
    # log(x)*(x - 10**-12) = 0: x = 10**-12 > 0 is inside the domain of log,
    # so the roots are 10**-12 and 1.
    roots = RCAS.solve(RCAS.log(@x) * (@x - Rational(1, 10**12)), @x)
    assert_includes roots, n(Rational(1, 10**12))
  end

  def test_a_binomial_sum_keeps_its_upper_bound
    # sum_{k=0}^{5} k**2*binomial(5, k) = 5*6*2**3 = 240, a finite sum of
    # six numbers; and the symbolic sum n*(n + 1)*2**(n - 2) is over 0..n,
    # so if it stays formal its upper bound is n, not oo.
    assert_equal n(240), RCAS.sum(@k**2 * RCAS.binomial(5, @k), @k, 0, 5)
    symbolic = RCAS.sum(@k**2 * RCAS.binomial(@n, @k), @k, 0, @n)
    if symbolic.is_a?(RCAS::Sum)
      refute_match(/oo/, symbolic.to_s)
    else
      assert_equal n(240), symbolic.subs(n: 5).simplify
    end
  end

  def test_a_radicand_negative_everywhere_has_an_empty_real_domain
    # -(x - 1)**2 - 10**-26 <= -10**-26 < 0 for every real x, so
    # sqrt of it is real nowhere.
    domain = RCAS.real_domain(RCAS.sqrt(-(@x - 1)**2 - Rational(1, 10**26)), @x)
    assert_equal RCAS::RealSet.empty, domain
  end

  def test_rank_agrees_with_singularity_for_a_disguised_zero_entry
    # [[1, 1], [1, 1 + w]] with w = 0 has two equal rows: rank 1, and the
    # same matrix is reported singular by inverse.
    RCAS.assume(a: RCAS::RR) do
      assert_equal 1, RCAS::RR.matrix([[1, 1], [1, 1 + disguised_zero]]).rank
    end
  end

  def test_a_linear_system_with_a_disguised_zero_coefficient_keeps_its_free_unknown
    # x + y = 1 and x + (1 + w)*y = 1 are the same equation, so y is free and
    # x = 1 - y; {x=1, y=0} alone drops the whole line. Refusing is acceptable.
    begin
      solutions = RCAS.solve([@x + @y - 1, @x + (1 + disguised_zero) * @y - 1], [@x, @y])
    rescue NotImplementedError
      return assert true
    end
    refute_empty solutions
    solutions.each do |s|
      refute s.key?(@y), "y should stay free: #{solutions.inspect}"
      assert_equal n(-6), s[@x].subs(y: 7).simplify.cancel
    end
  end

  # Performance regression, not a correctness property: expand_trig peels one
  # multiple of x at a time and expands sin and cos of the rest separately, so
  # sin(n*x) costs 2**n; sin(16*x) took 9 s. The bound is generous.
  def test_performance_expand_trig_of_a_multiple_angle_is_not_exponential
    result = Timeout.timeout(1.5) { RCAS.expand_trig(RCAS.sin(16 * @x)) }
    refute_nil result
  rescue Timeout::Error
    flunk 'expand_trig(sin(16*x)) took more than 1.5 s'
  end

  def test_complex_zeros_are_not_reported_as_real_zeros
    # (x - 1)**2 + 10**-26 > 0 for every real x; its zeros 1 +- 10**-13*i are
    # not real, so the discussion of the real function has no zeros.
    assert_empty RCAS.discuss((@x - 1)**2 + Rational(1, 10**26), @x).zeros
  end

  def test_the_argument_of_a_nearly_real_number_is_decided_with_enough_digits
    # r = exp(pi*sqrt(163)) - 640320**3 - 744 = -7.4993e-13, so r + i lies just
    # left of the imaginary axis and arg(r + i) = pi/2 + 7.5e-13. A value that
    # stays unevaluated is honest; a number must be close to pi/2.
    r = RCAS.exp(RCAS::PI * RCAS.sqrt(163)) - 640320**3 - 744
    result = RCAS.arg(r + RCAS::I)
    value = result.is_a?(Numeric) ? result : (result.is_a?(RCAS::Num) ? result.value : nil)
    assert_in_delta Math::PI / 2, value, 1e-9 if value
  end
end
