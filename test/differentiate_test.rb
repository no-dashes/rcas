# frozen_string_literal: true

require_relative "test_helper"

class DifferentiateTest < Minitest::Test
  def d(expr, var = :x, n = 1) = expr.to_expr.diff(var, n).to_s

  def test_polynomials
    assert_equal "1", d(:x)
    assert_equal "0", d(:y)
    assert_equal "3 + 4*x", d(2 * :x**2 + 3 * :x + 1)
    assert_equal "6*x", d(:x**3, :x, 2)
    assert_equal "-2*x", d((:x + 1) * (1 - :x))
  end

  def test_quotients_and_powers
    assert_equal "1/y", d(:x / :y)
    assert_equal "-x/y**2", d(:x / :y, :y)
    assert_equal "x**x*(1 + log(x))", d(:x**:x)
    assert_equal "2**x*log(2)", d(2**:x)
    assert_equal "1/(2*x**(1/2))", d(RCAS.sqrt(:x))
  end

  def test_functions_and_chain_rule
    assert_equal "cos(x)", d(RCAS.sin(:x))
    assert_equal "-sin(x)", d(RCAS.cos(:x))
    assert_equal "1/x", d(RCAS.log(:x))
    assert_equal "2*x*exp(x**2)", d(RCAS.exp(:x**2))
    assert_equal "2*cos(x)*sin(x)", d(RCAS.sin(:x)**2)
    assert_equal "cos(x)**2 - sin(x)**2", d(RCAS.sin(:x) * RCAS.cos(:x))
  end

  def test_requires_a_variable
    assert_raises(ArgumentError) { (:x**2).diff(2) }
  end

  # A definite integral is a number, but a number that still depends on the
  # parameters of its integrand. Only the integration variable is bound, and
  # looking at the bounds alone answered every such derivative with zero
  # (22 Sept 2026, from a review).
  def test_differentiating_under_the_integral_sign
    x = RCAS::Var.new(:x)
    t = RCAS::Var.new(:t)
    f = RCAS::Integral.new(x * t, t, RCAS::Num.new(0), RCAS::Num.new(1))
    assert_equal "integral(t, t, 0, 1)", f.diff(x).to_s
    assert_equal "1/2", f.diff(x).doit.to_s, "integral(x*t, t, 0, 1) is x/2"
    g = RCAS::Integral.new(RCAS.sin(x * t), t, RCAS::Num.new(0), RCAS::Num.new(1))
    assert_equal "integral(t*cos(t*x), t, 0, 1)", g.diff(x).to_s
    # integral(sin(x*t), t, 0, 1) is (1 - cos(x))/x, so the two agree
    assert_equal "0", (((1 - RCAS.cos(x)) / x).diff(x) - g.diff(x).doit).cancel.to_s
    assert_in_delta 0.3817732, g.diff(x).subs(x: RCAS::Num.new(1)).evalf, 1e-6
  end

  # The integration variable is bound: nothing that happens to be spelled
  # the same is free, and an integrand without the parameter gives zero.
  def test_a_bound_variable_is_not_a_parameter
    x = RCAS::Var.new(:x)
    t = RCAS::Var.new(:t)
    zero = RCAS::Integral.new(RCAS.sin(t), t, RCAS::Num.new(0), RCAS::Num.new(1))
    assert_equal "0", zero.diff(x).to_s, "no x in the integrand"
    assert_equal "0", zero.diff(t).to_s, "t is the bound variable"
    assert_equal "0", RCAS::Integral.new(x * t, t, RCAS::Num.new(0), RCAS::Num.new(1)).diff(t).to_s
  end

  # Bounds that move add Leibniz's two boundary terms to the integral of
  # the parameter derivative.
  def test_leibniz_rule_for_moving_bounds
    x = RCAS::Var.new(:x)
    t = RCAS::Var.new(:t)
    # d/dx int_0^x exp(-t**2) dt is the integrand at the upper bound
    assert_equal "exp(-x**2)", RCAS::Integral.new(RCAS.exp(-t**2), t, RCAS::Num.new(0), x).diff(x).to_s
    assert_equal "-exp(-x**2)", RCAS::Integral.new(RCAS.exp(-t**2), t, x, RCAS::Num.new(0)).diff(x).to_s
    # int_0^x x*t dt is x**3/2, so the derivative is 3*x**2/2
    both = RCAS::Integral.new(x * t, t, RCAS::Num.new(0), x).diff(x)
    assert_equal "integral(t, t, 0, x) + x**2", both.to_s
    assert_equal "3*x**2/2", both.doit.simplify.to_s
    # A name bound by the integral is not the free one outside it, however
    # it is spelled: integral(sin(x), x, 0, x) is integral(sin(t), t, 0, x)
    # after renaming, and its derivative is sin(x) (22 Sept 2026, the
    # second review - rcas used to refuse this as ambiguous).
    assert_equal "sin(x)", RCAS::Integral.new(RCAS.sin(x), x, RCAS::Num.new(0), x).diff(x).to_s
    assert_equal "sin(x)", RCAS::Integral.new(RCAS.sin(t), t, RCAS::Num.new(0), x).diff(x).to_s
    assert_equal "x**2", RCAS::Integral.new(x**2, x, RCAS::Num.new(0), x).diff(x).to_s
    # int_{x-1}^{x} t dt = x - 1/2, so the derivative is 1
    assert_equal "1", RCAS::Integral.new(x, x, x - 1, x).diff(x).to_s
  end

  # An indefinite integral keeps its old two rules, with the new integrand
  # simplified on the way in (an Integral is an atom to Simplify).
  def test_indefinite_integrals_are_unchanged
    x = RCAS::Var.new(:x)
    t = RCAS::Var.new(:t)
    assert_equal "sin(x)", RCAS::Integral.new(RCAS.sin(x), x).diff(x).to_s
    assert_equal "integral(t*cos(t*x), t)", RCAS::Integral.new(RCAS.sin(x * t), t).diff(x).to_s
  end
end
