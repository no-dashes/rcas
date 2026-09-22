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
end
