# frozen_string_literal: true

require_relative "test_helper"

# Formal power series: the general coefficient, not the first few terms.
class FPSTest < Minitest::Test
  X = RCAS::Var.new(:x)
  A = RCAS::Var.new(:a)

  # The expansion prints as expected, and its terms are the Taylor
  # coefficients: the sums are written out and compared with taylor degree by
  # degree, which is a check on the assembled answer, not only on the ratio.
  def assert_expansion(f, expected, degree: 6, point: 0, values: {})
    f = RCAS::Expression.lift(f)
    result = RCAS.fps(f, X, point)
    assert_equal expected, result.to_s
    series = shifted(written_out(result, degree).subs(values), point)
    reference = shifted(RCAS::Limits.taylor(f.subs(values), X, point, degree + 1), point)
    (0..degree).each do |d|
      difference = (RCAS::Coefficients.coeff(series, X, d) - RCAS::Coefficients.coeff(reference, X, d)).expand
      assert RCAS::Scalar.zero?(difference), "coefficient of x**#{d} in #{result}: #{difference}"
    end
  end

  # Every sum replaced by its first terms.
  def written_out(expr, degree)
    expr = expr.map_children { |child| written_out(child, degree) }
    return expr unless expr.is_a?(RCAS::Sum)
    (expr.from.value..degree).reduce(RCAS::Num.new(0)) { |acc, i| acc + expr.term.subs(expr.var => RCAS::Num.new(i)) }.simplify
  end

  def shifted(expr, point) = RCAS::Scalar.zero?(RCAS::Expression.lift(point)) ? expr.expand : expr.subs(X => X + point).expand

  def test_the_exponential_and_the_trigonometric_series
    assert_expansion RCAS.exp(X), "sum(x**k/k!, k, 0, oo)"
    assert_expansion RCAS.exp(2 * X), "sum(2**k*x**k/k!, k, 0, oo)"
    assert_expansion RCAS.exp(X**2), "sum(x**(2*k)/k!, k, 0, oo)"
    assert_expansion RCAS.sin(X), "sum((-1)**k*x**(1 + 2*k)/(1 + 2*k)!, k, 0, oo)"
    assert_expansion RCAS.cos(X), "sum((-1)**k*x**(2*k)/(2*k)!, k, 0, oo)"
    assert_expansion RCAS.sinh(X), "sum(x**(1 + 2*k)/(1 + 2*k)!, k, 0, oo)"
    assert_expansion RCAS.sin(X) / X, "sum((-1)**k*x**(2*k)/(1 + 2*k)!, k, 0, oo)"
  end

  def test_the_logarithmic_and_inverse_trigonometric_series
    assert_expansion RCAS.log(1 + X), "sum(-((-1)**k*x**k)/k, k, 1, oo)"
    assert_expansion RCAS.log(1 - X), "sum(-x**k/k, k, 1, oo)"
    assert_expansion RCAS.atan(X), "sum((-1)**k*x**(1 + 2*k)/(1 + 2*k), k, 0, oo)"
    assert_expansion RCAS.asin(X), "sum((1/4)**k*x**(1 + 2*k)*(2*k)!/(k!**2*(1 + 2*k)), k, 0, oo)"
    assert_expansion RCAS.erf(X), "sum(2*(-1)**k*x**(1 + 2*k)/(pi**(1/2)*k!*(1 + 2*k)), k, 0, oo)"
  end

  # The binomial series, with a parameter and at two half-integer exponents.
  def test_the_binomial_series
    assert_expansion (1 + X)**A, "sum(x**k*binomial(a, k), k, 0, oo)", values: { a: Rational(1, 3) }
    assert_expansion RCAS.sqrt(1 + X), "sum(x**k*binomial(1/2, k), k, 0, oo)"
    assert_expansion 1 / RCAS.sqrt(1 - 4 * X), "sum(x**k*(2*k)!/k!**2, k, 0, oo)"
    assert_expansion 1 / (1 - X), "sum(x**k, k, 0, oo)"
    assert_expansion 1 / (1 - X)**2, "sum(x**k*(1 + k), k, 0, oo)"
  end

  # A class whose first coefficients come before the recurrence takes hold is
  # written out in front of the sum.
  def test_the_terms_before_the_first_index
    assert_expansion RCAS.cos(X)**2, "1 + sum((-4)**k*x**(2*k)/(2*(2*k)!), k, 1, oo)"
    assert_expansion X * RCAS.exp(X), "sum(x**k/(-1 + k)!, k, 1, oo)"
  end

  def test_other_expansion_points
    assert_expansion RCAS.exp(X), "sum((x - 1)**k*e/k!, k, 0, oo)", point: 1
    assert_expansion RCAS.log(X), "sum(-((-1)**k*(x - 1)**k)/k, k, 1, oo)", point: 1
    assert_expansion 1 / X, "sum((-1/2)**k*(x - 2)**k/2, k, 0, oo)", point: 2
  end

  def test_a_polynomial_is_its_own_power_series
    assert_equal "2*x + x**3", RCAS.fps(X**3 + 2 * X, X).to_s
    assert_equal "5", RCAS.fps(5, X).to_s
  end

  def test_the_keyword_form_and_the_option_on_series
    assert_equal RCAS.fps(RCAS.sin(X), X).to_s, RCAS.fps(RCAS.sin(X), x: 0).to_s
    assert_equal RCAS.fps(RCAS.sin(X), X).to_s, RCAS.series(RCAS.sin(X), X, formal: true).to_s
    assert_equal RCAS.fps(RCAS.exp(X), X, 1).to_s, RCAS.fps(RCAS.exp(X), x: 1).to_s
  end

  # tan has Bernoulli numbers in its coefficients, exp(sin(x)) is not
  # holonomic of low order, and the Fibonacci numbers obey a three-term
  # recurrence: none of them is hypergeometric, and saying so is the answer.
  def test_coefficients_that_are_not_hypergeometric
    assert_raises(RCAS::SeriesError) { RCAS.fps(RCAS.tan(X), X) }
    assert_raises(RCAS::SeriesError) { RCAS.fps(RCAS.exp(RCAS.sin(X)), X) }
    assert_nil RCAS::FPS.expansion(X / (1 - X - X**2), X, 0, max_order: 2)
    assert_nil RCAS::FPS.expansion(RCAS.exp(X) / (1 - X), X, 0, max_order: 2)
  end

  def test_the_message_points_at_series
    message = assert_raises(RCAS::SeriesError) { RCAS.fps(RCAS.tan(X), X) }.message
    assert_includes message, "series(f, x)"
  end
end

# Step one of the algorithm: a differential equation with polynomial
# coefficients, sum_j p_j(x)*f^(j)(x) = 0.
class HolonomicEquationTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def equation(f) = RCAS::FPS.differential_equation(f, X)

  def test_the_equations_of_the_elementary_functions
    assert_equal ["-1", "1"], equation(RCAS.exp(X)).map(&:to_s)             # f' = f
    assert_equal ["1", "0", "1"], equation(RCAS.sin(X)).map(&:to_s)         # f'' + f = 0
    assert_equal ["0", "x", "-1 + x**2"], equation(RCAS.asin(X)).map(&:to_s)
    assert_equal ["0", "1", "1 + x"], equation(RCAS.log(1 + X)).map(&:to_s)
  end

  # The equation holds: at a few points, and away from the singularities.
  def test_the_equation_annihilates_the_function
    [RCAS.asin(X), RCAS.atan(X), RCAS.exp(X) * RCAS.sin(X), 1 / (1 - X)].each do |f|
      ps = equation(f)
      refute_nil ps, "no equation for #{f}"
      total = ps.each_with_index.reduce(RCAS::Num.new(0)) { |acc, (p, j)| acc + p * f.diff(X, j) }
      [0.3, -0.4, 0.7].each do |point|
        assert_in_delta 0.0, total.evalf(x: point).to_f, 1e-9, "#{ps.map(&:to_s)} at x = #{point}"
      end
    end
  end

  def test_no_equation_of_low_order
    assert_nil RCAS::FPS.differential_equation(RCAS.exp(RCAS.sin(X)), X, max_order: 2)
  end
end
