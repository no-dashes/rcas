# Review of statistics and numerics: each test states a mathematical fact
# that rcas currently gets wrong. Reference values are derived independently.
require_relative 'test_helper'
require 'rcas'

class ReviewStatisticsTest < Minitest::Test
  def setup
    @x = RCAS::Var.new(:x)
  end
  def n(v) = RCAS::Num.new(v)

  # A finite real number is the one answer that must not come back.
  def finite_number?(value)
    v = value.is_a?(RCAS::Expression) ? value.evalf : value
    v = v.value if v.is_a?(RCAS::Num)
    v.is_a?(Numeric) && !v.is_a?(Complex) && v.to_f.finite?
  rescue StandardError
    false
  end

  # The value (a Decimal from evalf(..., digits)) agrees with the truth in
  # every digit it claims.
  def assert_digits(expected, decimal)
    truth = BigDecimal(expected)
    allowed = truth.abs * BigDecimal("1e-#{decimal.digits - 1}")
    assert (decimal.value - truth).abs <= allowed,
           "rcas printed #{decimal} (#{decimal.digits} digits), the value is #{expected}"
  end

  def test_standard_normal_cdf_at_two_standard_deviations
    # Phi(-2) = erfc(sqrt(2))/2 = 0.0227501319481792 (any normal table);
    # P(-2 <= Z <= 2) = erf(sqrt(2)) = 0.9544997361036416.
    z = RCAS.Normal(0, 1)
    assert_in_delta 0.0227501319481792, z.cdf(-2).evalf, 1e-12
    assert_in_delta 0.9544997361036416, z.probability(-2..2).evalf, 1e-12
    assert_in_delta 0.0227501319481792, RCAS.Normal(1, 1).cdf(-1).evalf, 1e-12
  end

  def test_integral_of_an_unknown_function_has_no_numeric_value
    # f is unknown and a is a free parameter: the integrals are not numbers,
    # least of all 0.
    f = RCAS::Fn.new(:f, [@x])
    a = RCAS::Var.new(:a)
    [-> { RCAS.nintegrate(f * @x, x: 0..2) },
     -> { RCAS.nintegrate(f + 1, x: 0..1, digits: 20) },
     -> { RCAS.nintegrate(a * @x, x: 0..1) },
     -> { RCAS::Integral.new(f, @x, n(0), n(1)).evalf }].each do |call|
      result = begin
        call.call
      rescue StandardError
        nil
      end
      refute finite_number?(result), "an integral of an unknown integrand came back as #{result.inspect}"
    end
  end

  def test_integral_across_an_odd_pole_diverges
    # int_{-1}^{1} dx/x and dx/x**3 and int_0^1 dx/(x - 1/2) do not exist
    # (only a Cauchy principal value would be 0). A refusal is fine, 0.0 is not.
    [-> { RCAS.nintegrate(1 / @x, x: -1..1) },
     -> { RCAS.nintegrate(1 / @x**3, x: -1..1) },
     -> { RCAS.nintegrate(1 / (@x - Rational(1, 2)), x: 0..1) },
     -> { RCAS.nintegrate(1 / @x, x: -1..1, digits: 20) }].each do |call|
      result = begin
        call.call
      rescue StandardError
        nil
      end
      refute finite_number?(result), "a divergent integral came back as #{result.inspect}"
    end
  end

  def test_float_evalf_of_an_exact_expression_with_large_parts
    # Poisson(200) pmf at 200 = exp(200 log 200 - 200 - lgamma(201)) = 0.0281977276859;
    # 200!/199! = 200; the median of Poisson(200) is 200; qchisq(0.95, 300) =
    # 341.3951121 (bisection on the regularized gamma P(150, x/2)).
    assert_in_delta 0.0281977276859, RCAS.Poisson(200).pdf(200).evalf, 1e-10
    assert_in_delta 200.0, (RCAS.factorial(200) / RCAS.factorial(199)).evalf, 1e-9
    assert_equal n(200), RCAS.Poisson(200).quantile(0.5)
    assert_in_delta 341.3951121, RCAS.ChiSquare(300).quantile(0.95).evalf, 1e-5
    RCAS.random = 1
    RCAS.Poisson(200).sample(3).each { |k| assert_in_delta 200, k, 60 }
  end

  def test_binomial_pmf_with_a_float_probability
    # C(1100, 550)/2**1100 = exp(lgamma(1101) - 2 lgamma(551) - 1100 log 2) = 0.0240516577682;
    # the median of Binomial(2000, 0.3) is np = 600.
    assert_in_delta 0.0240516577682, RCAS.Binomial(1100, 0.5).pdf(550).evalf, 1e-10
    assert_equal n(600), RCAS.Binomial(2000, 0.3).quantile(0.5)
  end

  def test_regularized_gamma_for_a_large_parameter
    # P(10000, 10000) = 0.50132980833995520 (the series summed in 60-digit BigDecimal);
    # P(a, a) = 1/2 + 1/(3 sqrt(2 pi a)) + O(1/a) gives 0.500188 for chi-square(10**6 + 1).
    assert_in_delta 0.50132980833995520, RCAS::Special.gamma_p(10_000, 10_000), 1e-10
    assert_in_delta 0.500188, RCAS.ChiSquare(10**6 + 1).cdf(10**6 + 1).evalf, 1e-4
  end

  def test_quantile_outside_the_search_bracket
    # Cauchy: F^-1(p) = tan(pi (p - 1/2)); F(1, 1) is the square of a Cauchy
    # variable, so its quantile at p is tan(pi p/2)**2.
    cauchy = 1 / Math.tan(Math::PI * 1e-5)
    assert_in_delta 1.0, RCAS.StudentT(1).quantile(0.99999).evalf / cauchy, 1e-8
    f11 = Math.tan(Math::PI * 0.9999 / 2)**2
    assert_in_delta 1.0, RCAS.FRatio(1, 1).quantile(0.9999).evalf / f11, 1e-6
  end

  def test_moments_that_do_not_exist
    # The Cauchy distribution (t with 1 degree of freedom) has no mean and no
    # variance; t(3) has infinite kurtosis; F(d1, d2) has a mean only for
    # d2 > 2 and a variance only for d2 > 4. None of these is a finite number.
    {
      "StudentT(1).mean" => -> { RCAS.StudentT(1).mean },
      "StudentT(1).variance" => -> { RCAS.StudentT(1).variance },
      "StudentT(3).kurtosis" => -> { RCAS.StudentT(3).kurtosis },
      "FRatio(3, 1).mean" => -> { RCAS.FRatio(3, 1).mean },
      "FRatio(3, 3).variance" => -> { RCAS.FRatio(3, 3).variance }
    }.each do |name, call|
      result = begin
        call.call
      rescue StandardError
        nil
      end
      refute finite_number?(result), "#{name} does not exist, rcas answered #{result.inspect}"
    end
  end

  def test_exclusive_range_of_a_discrete_distribution
    # Binomial(10, 1/2): P(2 <= X < 4) = (45 + 120)/1024 and
    # P(2 <= X < 9/2) = (45 + 120 + 210)/1024.
    b = RCAS.Binomial(10, Rational(1, 2))
    assert_equal n(Rational(165, 1024)), b.probability(2...4)
    assert_equal n(Rational(375, 1024)), b.probability(2...Rational(9, 2))
  end

  def test_discrete_event_with_irrational_ends
    # x**2 < 5 means X in {0, 1, 2} for a variable on 0..10:
    # (1 + 10 + 45)/1024 = 7/128.
    b = RCAS.Binomial(10, Rational(1, 2))
    assert_equal n(Rational(7, 128)), b.probability(@x**2 < 5)
  end

  def test_normal_lower_tail_without_cancellation
    # Phi(-8) = erfc(8/sqrt(2))/2 = 6.22096057427178e-16 (Math.erfc);
    # qnorm(1e-20) = -9.262340089798408 (R).
    z = RCAS.Normal(0, 1)
    assert_in_delta 1.0, z.cdf(-8).evalf / 6.22096057427178e-16, 1e-9
    assert_in_delta(-9.262340089798408, z.quantile(1e-20).evalf, 1e-6)
  end

  def test_p_value_of_an_extreme_statistic_is_not_zero
    # z = 10: p = erfc(10/sqrt(2)) = 1.5239706048321e-23. Chi-square 300 on 3 df:
    # Q = erfc(sqrt(150)) + sqrt(600/pi) exp(-150) = 9.94875834632771e-65.
    p = RCAS.ztest([10], sigma: 1, mu: 0).pvalue.evalf
    assert_in_delta 1.0, p / 1.5239706048321e-23, 1e-6
    q = RCAS.chisquare_test([100, 0, 0, 0]).pvalue.evalf
    assert_in_delta 1.0, q / 9.94875834632771e-65, 1e-6
  end

  def test_exact_binomial_test_compares_exact_probabilities
    # Under p = 1/2, only k = 0 and k = 1100 are as improbable as k = 0,
    # so the two-sided p value is exactly 2/2**1100.
    assert_equal n(Rational(2, 2**1100)), RCAS.binomial_test(0, 1100).pvalue
  end

  def test_quantile_argument_must_be_a_probability
    # A quantile function is defined on [0, 1] only.
    assert_raises(ArgumentError) { RCAS.Exponential(1).quantile(Rational(3, 2)) }
    assert_raises(ArgumentError) { RCAS.Uniform(0, 1).quantile(2) }
  end

  def test_range_from_minus_infinity_to_a_number
    # int_{-oo}^{0} exp(x) dx = 1; 0..oo and -oo..oo are accepted, -oo..0 must be too.
    assert_equal n(1), RCAS.integrate(RCAS.exp(@x), x: (-RCAS::OO)..0)
  end

  def test_discrete_uniform_needs_whole_ends
    # DiscreteUniform(3/2, 4) is either refused or uniform on {2, 3, 4}.
    d = begin
      RCAS.DiscreteUniform(Rational(3, 2), 4)
    rescue ArgumentError
      return assert true
    end
    assert_equal n(Rational(1, 3)), d.pdf(2)
  end

  def test_discrete_uniform_with_symbolic_ends_does_not_crash
    # For a <= 3 <= b the cdf is (4 - a)/(b - a + 1); a formal answer is fine too.
    d = RCAS.DiscreteUniform(RCAS::Var.new(:a), RCAS::Var.new(:b))
    begin
      d.cdf(3)
    rescue NoMethodError => e
      flunk "cdf crashed: #{e.message}"
    rescue ArgumentError
      assert true
    end
  end

  def test_chisquare_goodness_of_fit_rejects_inconsistent_expectations
    # Expected probabilities summing to 1.1, expected counts summing to 50 for
    # 100 observations, and an unknown alternative are all input errors (R refuses the first two).
    observed = [18, 22, 20, 25, 15]
    assert_raises(ArgumentError) { RCAS.chisquare_test(observed, expected: [0.3, 0.2, 0.2, 0.2, 0.2]) }
    assert_raises(ArgumentError) { RCAS.chisquare_test(observed, expected: [10, 10, 10, 10, 10]) }
    assert_raises(ArgumentError) { RCAS.chisquare_test(observed, alternative: :bogus) }
  end

  def test_evalf_digits_survive_cancellation
    # Taylor: exp(h) - 1 = h + h**2/2, log(1 + h) = h - h**2/2, cosh(h) - 1 = h**2/2,
    # acos(1 - h) = sqrt(2h)(1 + h/12), cot(h) = 1/h - h/3; sin(k*pi) = 0.
    tiny = Rational(1, 10**30)
    assert_digits "1e-30", RCAS.evalf(RCAS.exp(@x) - 1, 20, x: tiny)
    assert_digits "1e-30", RCAS.evalf(RCAS.log(@x), 20, x: 1 + tiny)
    assert_digits "5e-31", RCAS.evalf(RCAS.cosh(@x) - 1, 20, x: Rational(1, 10**15))
    assert_digits "1.4142135623730950488e-20", RCAS.evalf(RCAS.acos(@x), 20, x: 1 - Rational(1, 10**40))
    assert_digits "1e30", RCAS.evalf(RCAS.tan(@x), 20, x: RCAS::PI / 2 - tiny)
    value = RCAS.evalf(RCAS::Mul.new(RCAS::PI, n(10**15)).then { |u| RCAS::Fn.new(:sin, [u]) }, 20)
    assert value.value.abs < BigDecimal("1e-25"), "sin(pi*10**15) is 0, rcas printed #{value}"
  end

  def test_erfc_is_accurate_where_erf_is_one
    # erfc(10) = 2.0884875837625447570e-45 [AS64, 7.1]; Math.erfc(10) agrees to 16 digits.
    value = RCAS.evalf(RCAS.erfc(10), 20)
    assert_in_delta 1.0, value.to_f / 2.0884875837625447570e-45, 1e-14, "rcas printed #{value}"
  end

  def test_exponential_integral_of_a_large_negative_argument
    # Ei(-50) = -E1(50) = -3.7832640295504590187e-24 (rcas's own series at 80 digits;
    # scipy.special.exp1(50) = 3.783264029550459e-24).
    assert_digits "-3.7832640295504590187e-24", RCAS.evalf(RCAS.Ei(-50), 20)
  end

  def test_nsolve_digits_at_a_double_root
    # (x - 1)**2 has the root 1, exactly; 30 digits were asked for.
    root = RCAS.nsolve(@x**2 - 2 * @x + 1, @x, 0.9, digits: 30)
    assert_digits "1", root
  end

  def test_nsolve_stops_at_the_root_not_where_the_value_is_small
    # exp(-x) = 1e-20 at x = 20 log 10 = 46.051701859880914; 1e-20 (x - 1) and
    # (x - 1)**3 vanish at 1 only; x exp(-x) vanishes at 0 only.
    assert_in_delta 46.051701859880914, RCAS.nsolve(RCAS.exp(-@x) - Rational(1, 10**20), x: 0..100), 1e-9
    assert_in_delta 1.0, RCAS.nsolve(Rational(1, 10**20) * (@x - 1), x: 0..3), 1e-9
    assert_in_delta 1.0, RCAS.nsolve((@x - 1)**3, x: 0..3), 1e-9
    root = begin
      RCAS.nsolve(@x * RCAS.exp(-@x), @x, 5)
    rescue ArgumentError
      0.0 # refusing is acceptable
    end
    assert_in_delta 0.0, root, 1e-9
  end

  def test_nsolve_brackets_without_a_derivative
    # x + floor(x) = 5/2 at x = 3/2 (floor = 1), and nowhere else in 0..3.
    assert_in_delta 1.5, RCAS.nsolve(@x + RCAS.floor(@x) - Rational(5, 2), x: 0..3), 1e-9
  end

  def test_median_of_exact_values_closer_than_a_float_can_tell
    # Sorted, the data is 1 < 1 + 10**-20 < 1 + 2*10**-20; type-7 quantile at 1/4
    # is halfway between the first two.
    data = [1 + Rational(2, 10**20), 1, 1 + Rational(1, 10**20)]
    assert_equal n(1 + Rational(1, 10**20)), RCAS.median(data)
    assert_equal n(1 + Rational(1, 2 * 10**20)), RCAS.quantile(data, Rational(1, 4))
  end
end
