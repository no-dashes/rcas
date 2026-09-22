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
end
