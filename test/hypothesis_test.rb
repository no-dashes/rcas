# frozen_string_literal: true

require_relative "test_helper"

# The expected numbers are the textbook ones and agree with R's t.test,
# chisq.test, var.test, binom.test and prop.test to the digits shown.
class HypothesisTest < Minitest::Test
  SAMPLE = [5.1, 4.9, 5.6, 5.2, 5.0].freeze
  XS = [12, 15, 14, 16, 13].freeze
  YS = [10, 11, 9, 12, 10].freeze

  def test_one_sample_t
    r = RCAS.ttest([1, 2, 3, 4, 5], mu: 1)
    assert_equal "one-sample t test: t = 2.82843, df = 4, p = 0.0474207 (two-sided)", r.to_s
    assert_in_delta 2.8284271247, r.statistic.evalf, 1e-9
    assert_in_delta 0.04742066, r.pvalue.evalf, 1e-8
    assert r.reject?(0.05)
    refute r.reject?(0.01)
    assert_equal 4, r.parameters[:df]
    assert_in_delta 0.02371033, RCAS.ttest([1, 2, 3, 4, 5], mu: 1, alternative: :greater).pvalue.evalf, 1e-8
    assert_in_delta 0.97628967, RCAS.ttest([1, 2, 3, 4, 5], mu: 1, alternative: :less).pvalue.evalf, 1e-8
    assert_raises(ArgumentError) { RCAS.ttest([1], mu: 0) }
    assert_raises(ArgumentError) { RCAS.ttest([1, 1, 1], mu: 0) }
    assert_raises(ArgumentError) { RCAS.ttest(SAMPLE, alternative: :bigger) }
  end

  def test_two_sample_t
    welch = RCAS.ttest(XS, YS)
    assert_equal "Welch t test", welch.name
    assert_in_delta 4.1294832, welch.statistic.evalf, 1e-7
    assert_in_delta 7.2745592, welch.parameters[:df].evalf, 1e-6, "Welch-Satterthwaite degrees of freedom"
    assert_in_delta 0.0040545, welch.pvalue.evalf, 1e-7
    pooled = RCAS.ttest(XS, YS, equal_variance: true)
    assert_equal 8, pooled.parameters[:df].value
    assert_in_delta 0.0033008, pooled.pvalue.evalf, 1e-7
    paired = RCAS.ttest(XS, YS, paired: true)
    assert_equal "paired t test", paired.name
    assert_in_delta 7.0601809, paired.statistic.evalf, 1e-7
    assert_in_delta 0.0021229, paired.pvalue.evalf, 1e-7
    assert_raises(ArgumentError) { RCAS.ttest(XS, [1, 2], paired: true) }
  end

  def test_z_test
    r = RCAS.ztest([101, 99, 104, 98, 103], sigma: 2, mu: 100)
    assert_in_delta 1.1180340, r.statistic.evalf, 1e-7
    assert_in_delta 0.2635524, r.pvalue.evalf, 1e-7
    refute r.reject?
    assert_in_delta 0.1317762, RCAS.ztest([101, 99, 104, 98, 103], sigma: 2, mu: 100, alternative: :greater).pvalue.evalf, 1e-7
  end

  def test_chisquare_goodness_of_fit
    r = RCAS.chisquare_test([18, 22, 20, 25, 15])
    assert_equal "29/10", r.statistic.to_s, "the statistic is exact"
    assert_equal 4, r.parameters[:df]
    assert_in_delta 0.5746973, r.pvalue.evalf, 1e-7
    assert_equal "2", RCAS.chisquare_test([20, 30], expected: [Rational(1, 2), Rational(1, 2)]).statistic.to_s
    assert_equal "2", RCAS.chisquare_test([20, 30], expected: [25, 25]).statistic.to_s
    assert_in_delta 0.1572992, RCAS.chisquare_test([20, 30]).pvalue.evalf, 1e-7
    assert_equal 2, RCAS.chisquare_test([18, 22, 20, 25, 15], df: 2).parameters[:df]
    assert_raises(ArgumentError) { RCAS.chisquare_test([1, 2, 3], expected: [1, 2]) }
    assert_raises(ArgumentError) { RCAS.chisquare_test([1, 2], expected: [0, 3]) }
  end

  def test_chisquare_independence
    r = RCAS.chisquare_test([[30, 20], [15, 35]])
    assert_equal "chi-square test of independence", r.name
    assert_equal "100/11", r.statistic.to_s
    assert_equal 1, r.parameters[:df]
    assert_in_delta 0.0025688, r.pvalue.evalf, 1e-7
    assert r.reject?(0.01)
    # a table with no association gives a zero statistic
    assert_equal "0", RCAS.chisquare_test([[10, 20], [20, 40]]).statistic.to_s
    big = RCAS.chisquare_test([[10, 20, 30], [15, 25, 20]])
    assert_equal 2, big.parameters[:df]
    assert_equal RCAS.chisquare_test(RCAS.matrix([[30, 20], [15, 35]])).statistic, r.statistic, "a Matrix works too"
    assert_raises(ArgumentError) { RCAS.chisquare_test([[1, 2], [3]]) }
  end

  def test_f_test
    r = RCAS.ftest(XS, YS)
    assert_equal "25/13", r.statistic.to_s
    assert_equal [4, 4], [r.parameters[:df1], r.parameters[:df2]]
    assert_in_delta 0.5420615, r.pvalue.evalf, 1e-6
    refute r.reject?
    assert_in_delta 0.2710308, RCAS.ftest(XS, YS, alternative: :greater).pvalue.evalf, 1e-6
  end

  def test_exact_binomial
    r = RCAS.binomial_test(9, 10)
    assert_equal "11/512", r.pvalue.to_s, "exact, not a float"
    assert_in_delta 0.021484375, r.pvalue.evalf, 1e-12
    assert r.reject?(0.05)
    assert_equal "11/1024", RCAS.binomial_test(9, 10, alternative: :greater).pvalue.to_s
    assert_equal "1023/1024", RCAS.binomial_test(9, 10, alternative: :less).pvalue.to_s
    assert_equal "1", RCAS.binomial_test(5, 10).pvalue.to_s
    assert_in_delta 0.0568879, RCAS.binomial_test(60, 100).pvalue.evalf, 1e-6
    # P(X <= 3) for Binomial(10, 3/5) is also the incomplete beta I_0.4(7, 4) checked below
    assert_in_delta 0.0547618816, RCAS.binomial_test(3, 10, p: Rational(3, 5), alternative: :less).pvalue.evalf, 1e-9
    assert_raises(ArgumentError) { RCAS.binomial_test(11, 10) }
  end

  def test_confidence_intervals
    ci = RCAS.confidence_interval(SAMPLE)
    assert_in_delta 4.8245209, ci.low.evalf, 1e-7
    assert_in_delta 5.4954791, ci.high.evalf, 1e-7
    assert ci.include?(5.16), "the interval is centred on the sample mean"
    wider = RCAS.confidence_interval(SAMPLE, level: 0.99)
    assert wider.low.evalf < ci.low.evalf && wider.high.evalf > ci.high.evalf
    z = RCAS.confidence_interval(SAMPLE, sigma: 0.3)
    assert_in_delta 4.8970432, z.low.evalf, 1e-7
    assert_in_delta 5.4229568, z.high.evalf, 1e-7
    v = RCAS.confidence_interval(SAMPLE, parameter: :variance)
    assert_in_delta 0.0262041, v.low.evalf, 1e-7
    assert_in_delta 0.6027845, v.high.evalf, 1e-7
    s = RCAS.confidence_interval(SAMPLE, parameter: :stdev)
    assert_in_delta Math.sqrt(v.low.evalf), s.low.evalf, 1e-9
    w = RCAS.proportion_interval(41, 100)
    assert_in_delta 0.3186731, w.low.evalf, 1e-7
    assert_in_delta 0.5079857, w.high.evalf, 1e-7
    assert_equal 0.0, RCAS.proportion_interval(0, 10).low.evalf
    assert_raises(ArgumentError) { RCAS.confidence_interval(SAMPLE, level: 1.5) }
    assert_raises(ArgumentError) { RCAS.confidence_interval(SAMPLE, parameter: :median) }
    assert_raises(ArgumentError) { RCAS.proportion_interval(11, 10) }
  end

  def test_sampling_distributions
    assert_equal "3/4", RCAS.StudentT(1).cdf(1).to_s, "nu = 1 is the Cauchy distribution"
    assert_equal "1/2 + 3**(1/2)/6", RCAS.StudentT(2).cdf(1).to_s
    assert_in_delta 2.7764451, RCAS.StudentT(4).quantile(0.975).value, 1e-7
    assert_in_delta 1.9599640, RCAS.Normal(0, 1).quantile(0.975).value, 1e-7
    assert_equal "5/3", RCAS.StudentT(5).variance.to_s
    assert_equal "1 - exp(-x/2)", RCAS.ChiSquare(2).cdf(RCAS::Var.new(:x)).to_s, "even k is exact"
    assert_equal "1 - exp(-x/2)*(1 + x/2)", RCAS.ChiSquare(4).cdf(RCAS::Var.new(:x)).to_s
    assert_in_delta 7.8147279, RCAS.ChiSquare(3).quantile(0.95).value, 1e-6
    assert_equal ["5", "10"], [RCAS.ChiSquare(5).mean, RCAS.ChiSquare(5).variance].map(&:to_s)
    assert_in_delta 3.7082648, RCAS.FRatio(3, 10).quantile(0.95).value, 1e-6
    assert_equal "d2/(-2 + d2)", RCAS.FRatio(:d1, :d2).mean.to_s
    # the CDFs are consistent with the chi-square / F relationship
    assert_in_delta RCAS.ChiSquare(4).cdf(5.2).evalf, RCAS::Special.gamma_p(2.0, 2.6), 1e-12
    values = RCAS.ChiSquare(6).sample(4000, random: Random.new(11))
    assert_in_delta 6.0, values.sum / values.size, 0.2
  end

  def test_special_functions
    assert_in_delta 1 - Math.exp(-1), RCAS::Special.gamma_p(1, 1), 1e-14
    assert_in_delta Math.erf(Math.sqrt(0.5)), RCAS::Special.gamma_p(0.5, 0.5), 1e-14
    assert_in_delta 1.0, RCAS::Special.gamma_p(3, 2) + RCAS::Special.gamma_q(3, 2), 1e-15
    assert_in_delta 0.5, RCAS::Special.beta_i(0.5, 1, 1), 1e-15
    # I_x(k, n - k + 1) is the upper binomial tail
    n, k, x = 10, 7, 0.4
    tail = (k..n).sum { |j| RCAS.binomial(n, j).value * x**j * (1 - x)**(n - j) }
    assert_in_delta tail, RCAS::Special.beta_i(x, k, n - k + 1), 1e-12
    assert_raises(ArgumentError) { RCAS::Special.gamma_p(-1, 1) }
  end
end
