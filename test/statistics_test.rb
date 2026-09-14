# frozen_string_literal: true

require_relative "test_helper"

class StatisticsTest < Minitest::Test
  DATA = [2, 4, 4, 4, 5, 5, 7, 9].freeze

  def test_location
    assert_equal "5", RCAS.mean(DATA).to_s
    assert_equal "9/2", RCAS.median(DATA).to_s
    assert_equal "2", RCAS.median([3, 1, 2]).to_s
    assert_equal "4", RCAS.mode(DATA).to_s
    assert_equal "[2, 3]", RCAS.mode([1, 2, 2, 3, 3]).to_s
    assert_equal "4", RCAS.geometric_mean([2, 8]).to_s
    assert_equal "12/7", RCAS.harmonic_mean([1, 2, 4]).to_s
    assert_equal({ RCAS::Num.new(1) => 1, RCAS::Num.new(2) => 1, RCAS::Num.new(3) => 3 }, RCAS.frequencies([3, 1, 3, 2, 3]))
    assert_equal "5/2", RCAS.mean(1..4).to_s
  end

  def test_spread_and_shape
    assert_equal "32/7", RCAS.variance(DATA).to_s
    assert_equal "4", RCAS.variance(DATA, sample: false).to_s
    assert_equal "2", RCAS.stdev(DATA, sample: false).to_s
    assert_equal "1", RCAS.stdev([1, 2, 3]).to_s
    assert_equal "15/2", RCAS.moment([1, 2, 3, 4], 2, central: false).to_s
    assert_equal "5/4", RCAS.moment([1, 2, 3, 4], 2).to_s
    assert_equal "18*2**(1/2)/25", RCAS.skewness([1, 2, 3, 10]).to_s
    assert_equal "0", RCAS.skewness([1, 2, 3]).to_s
    assert_equal "41/25", RCAS.kurtosis([1, 2, 3, 4]).to_s
    assert_raises(ArgumentError) { RCAS.variance([1]) }
  end

  def test_quantiles_type_7
    assert_equal "7/4", RCAS.quantile([1, 2, 3, 4], Rational(1, 4)).to_s
    assert_equal "4", RCAS.quantile(DATA, Rational(1, 4)).to_s
    assert_equal ["11/4", "9/2", "25/4"], RCAS.quartiles([1, 2, 3, 4, 5, 6, 7, 8]).map(&:to_s)
    assert_equal "7/2", RCAS.iqr([1, 2, 3, 4, 5, 6, 7, 8]).to_s
    assert_equal "1", RCAS.quantile([3, 1, 2], 0).to_s
    assert_equal "3", RCAS.quantile([3, 1, 2], 1).to_s
    assert_in_delta 2.5, RCAS.quantile([1, 2, 3, 4], 0.5).value, 1e-12
    assert_equal RCAS.median(DATA), RCAS.quantile(DATA, Rational(1, 2))
    assert_raises(ArgumentError) { RCAS.quantile([1, 2], 2) }
    assert_raises(ArgumentError) { RCAS.median([:a, :b]) }
  end

  def test_symbolic_data
    assert_equal "a/3 + b/3 + c/3", RCAS.mean(%i[a b c]).to_s
    assert_equal "a**2/2 - a*b + b**2/2", RCAS.variance(%i[a b]).to_s
    assert_equal "0", RCAS.variance([:a, :a, :a]).to_s
    assert_equal "(a*b)**(1/2)", RCAS.geometric_mean(%i[a b]).to_s
  end

  def test_two_variables
    xs = [1, 2, 3]
    ys = [2, 4, 7]
    assert_equal "5/2", RCAS.covariance(xs, ys).to_s
    assert_equal "5/3", RCAS.covariance(xs, ys, sample: false).to_s
    assert_equal "1", RCAS.correlation(xs, [2, 4, 6]).to_s
    assert_equal "-1", RCAS.correlation(xs, [6, 4, 2]).to_s
    assert_in_delta 0.9933992677987828, RCAS.correlation(xs, ys).evalf, 1e-12
    line = RCAS.linreg(xs, ys, :x)
    assert_equal "-2/3 + 5*x/2", line.to_s
    # least squares: the residuals sum to zero and are orthogonal to x
    residuals = xs.zip(ys).map { |x, y| y - line.call(x: x) }
    assert_equal 0, residuals.sum
    assert_equal 0, xs.zip(residuals).sum { |x, r| x * r }
    assert_equal "11*x/10", RCAS.linreg([1, 2, 3, 4], [1, 3, 2, 5]).to_s
    assert_raises(ArgumentError) { RCAS.linreg([1, 1], [2, 3]) }
    assert_raises(ArgumentError) { RCAS.covariance([1, 2], [1]) }
  end
end
