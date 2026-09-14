# frozen_string_literal: true

require_relative "test_helper"

# Rationalizing substitutions: square roots of quadratics, roots of linear
# forms, exponentials and the Weierstrass substitution.
class IntegrateSubstitutionsTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def sqrt(e) = RCAS.sqrt(e)
  def exp(e) = RCAS.exp(e)
  def sin(e) = RCAS.sin(e)
  def cos(e) = RCAS.cos(e)

  # Free of Integral nodes, and the derivative agrees numerically with the
  # integrand at points where both are real.
  def antiderivative(f, points)
    f = RCAS::Expression.lift(f)
    result = f.integrate(:x)
    assert RCAS::Integrate.complete?(result), "unevaluated: #{result}"
    d = result.diff(:x)
    points.each do |p|
      assert_in_delta f.evalf(x: p), d.evalf(x: p), 1e-8, "d/dx #{result} != #{f} at #{p}"
    end
    result
  end

  INSIDE = [0.2, 0.5, 0.8].freeze   # inside (-1, 1)
  OUTSIDE = [1.3, 2.1, 3.7].freeze  # beyond 1

  def test_square_root_of_quadratic
    cases = {
      sqrt(X**2 + 1) => ["log((1 + x**2)**(1/2) + x)/2 + x*(1 + x**2)**(1/2)/2", OUTSIDE],
      1 / sqrt(X**2 + 1) => ["log((1 + x**2)**(1/2) + x)", OUTSIDE],
      sqrt(1 - X**2) => ["asin(x)/2 + x*(1 - x**2)**(1/2)/2", INSIDE],
      1 / sqrt(1 - X**2) => ["asin(x)", INSIDE],
      1 / sqrt(4 - X**2) => ["asin(x/2)", INSIDE],
      X**2 * sqrt(1 - X**2) => ["asin(x)/8 + (-x/8 + x**3/4)*(1 - x**2)**(1/2)", INSIDE],
      sqrt(X**2 - 1) => ["-log((-1 + x**2)**(1/2) + x)/2 + x*(-1 + x**2)**(1/2)/2", OUTSIDE],
      sqrt(X**2 + 2 * X + 5) => ["2*log(1 + (5 + 2*x + x**2)**(1/2) + x) + (1/2 + x/2)*(5 + 2*x + x**2)**(1/2)", OUTSIDE],
      1 / sqrt(X**2 + 2 * X + 5) => ["log(1 + (5 + 2*x + x**2)**(1/2) + x)", OUTSIDE],
      X**3 / sqrt(X**2 + 1) => ["(1 + x**2)**(3/2)/3 - (1 + x**2)**(1/2)", OUTSIDE],
      sqrt(2 * X**2 + 3) => ["3*2**(1/2)*log(2*x + 2**(1/2)*(3 + 2*x**2)**(1/2))/4 + x*(3 + 2*x**2)**(1/2)/2", OUTSIDE]
    }
    cases.each do |f, (expected, points)|
      assert_equal expected, antiderivative(f, points).to_s
    end
  end

  def test_linear_denominators_under_the_root
    cases = {
      1 / (X * sqrt(X**2 - 1)) => ["atan((-1 + x**2)**(1/2))", OUTSIDE],
      sqrt(1 - X**2) / X**2 => ["-(1 - x**2)**(1/2)/x - asin(x)", INSIDE],
      1 / (X**2 * sqrt(1 + X**2)) => ["-(1 + x**2)**(1/2)/x", OUTSIDE],
      1 / (X * sqrt(1 - X**2)) => ["log(-1 + (1 - x**2)**(1/2))/2 - log(1 + (1 - x**2)**(1/2))/2", INSIDE]
    }
    cases.each do |f, (expected, points)|
      assert_equal expected, antiderivative(f, points).to_s
    end
    # a shifted linear factor: x - alpha = 1/t, valid on both sides of alpha
    antiderivative(1 / ((X + 1) * sqrt(X**2 + 1)), OUTSIDE + [-2.5, -0.5])
  end

  def test_definite_integrals_with_roots
    assert_equal "pi/2", RCAS.integrate(sqrt(1 - X**2), :x, -1, 1).to_s
    assert_equal "pi/2", RCAS.integrate(1 / sqrt(1 - X**2), :x, 0, 1).to_s
    assert_equal "pi/4", RCAS.integrate(1 / sqrt(1 - X**2), :x, 0, RCAS.sqrt(2) / 2).to_s
  end

  def test_root_of_linear_form
    assert_equal "-2*atan(x**(1/2)) + 2*x**(1/2)", antiderivative(sqrt(X) / (1 + X), OUTSIDE).to_s
    assert_equal "-2*log(1 + x**(1/2)) + 2*log(x**(1/2))", antiderivative(1 / (X * sqrt(X) + X), OUTSIDE).to_s
    assert_equal "log(-1 + (1 + x)**(1/2)) - log(1 + (1 + x)**(1/2))", antiderivative(1 / (X * sqrt(X + 1)), OUTSIDE).to_s
    assert_equal "2*(1 + x)**(1/2) - 2*log(1 + (1 + x)**(1/2))", antiderivative(1 / (1 + sqrt(X + 1)), OUTSIDE).to_s
  end

  def test_rational_in_exponentials
    assert_equal "-log(1 + exp(x)) + x", antiderivative(1 / (1 + exp(X)), OUTSIDE).to_s
    assert_equal "atan(exp(x))", antiderivative(1 / (exp(X) + exp(-X)), OUTSIDE).to_s
    assert_equal "exp(x) - log(1 + exp(x))", antiderivative(exp(2 * X) / (1 + exp(X)), OUTSIDE).to_s
    assert_equal "-2*log(1 + exp(x/2)) + x", antiderivative(1 / (exp(X / 2) + 1), OUTSIDE).to_s
    assert_equal "log(-1 + exp(x)) - x", antiderivative(1 / (exp(X) - 1), OUTSIDE).to_s
    assert_equal "atan(sinh(x))", antiderivative(1 / RCAS.cosh(X), OUTSIDE).to_s
    assert_equal "log(1 + cosh(x))", antiderivative(RCAS.sinh(X) / (1 + RCAS.cosh(X)), OUTSIDE).to_s
  end

  def test_rational_in_sine_and_cosine
    assert_equal "log((1 + sin(x))/cos(x))", antiderivative(1 / cos(X), INSIDE).to_s
    assert_equal "log((1 - cos(x))/sin(x))", antiderivative(1 / sin(X), INSIDE).to_s
    assert_equal "log((1 + sin(x))/cos(x)) - sin(x)", antiderivative(sin(X)**2 / cos(X), INSIDE).to_s
    assert_equal "cos(x) + log((1 - cos(x))/sin(x))", antiderivative(cos(X)**2 / sin(X), INSIDE).to_s
    assert_equal "2*3**(1/2)*atan(3**(1/2)*tan(x/2)/3)/3", antiderivative(1 / (2 + cos(X)), INSIDE).to_s
    assert_equal "-2/(1 + tan(x/2))", antiderivative(1 / (1 + sin(X)), INSIDE).to_s
    assert_equal "-log(-2 + tan(x/2))/4 + log(2 + tan(x/2))/4", antiderivative(1 / (3 + 5 * cos(X)), INSIDE).to_s
    assert_equal "tan(x) - x", antiderivative(RCAS.tan(X)**2, INSIDE).to_s
  end

  def test_negative_exact_values
    assert_equal "-pi/6", RCAS.asin(Rational(-1, 2)).to_s
    assert_equal "-pi/2", RCAS.asin(-1).to_s
    assert_equal "pi", RCAS.acos(-1).to_s
    assert_equal "-pi/4", RCAS.atan(-1).to_s
    assert_equal "2*pi/3", RCAS.acos(Rational(-1, 2)).to_s
  end

  def test_out_of_scope_stays_formal
    # an irreducible quadratic denominator under the root, a quartic radicand
    [1 / ((X**2 + 1) * sqrt(X**2 + 2)), 1 / sqrt(X**4 + 1), sqrt(X) * sqrt(X + 1)].each do |f|
      refute RCAS::Integrate.complete?(f.integrate(:x))
    end
  end
end
