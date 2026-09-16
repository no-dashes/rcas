# frozen_string_literal: true

require_relative "test_helper"

class IntegralFunctionsTest < Minitest::Test
  include RCAS::Constants

  X = RCAS::Var.new(:x)

  def test_the_antiderivatives_that_have_names
    assert_equal "Si(x)", RCAS.integrate(RCAS.sin(X) / X, :x).to_s
    assert_equal "Ci(x)", RCAS.integrate(RCAS.cos(X) / X, :x).to_s
    assert_equal "Ei(x)", RCAS.integrate(RCAS.exp(X) / X, :x).to_s
    assert_equal "li(x)", RCAS.integrate(1 / RCAS.log(X), :x).to_s
    assert_equal "Si(3*x)", RCAS.integrate(RCAS.sin(3 * X) / X, :x).to_s
    assert_equal "Ei(2*x)/2", RCAS.integrate(RCAS.exp(2 * X) / (2 * X), :x).to_s
  end

  def test_a_shifted_denominator
    r = RCAS.integrate(RCAS.exp(X) / (X + 1), :x)
    assert_equal "Ei(1 + x)/e", r.to_s
    assert_equal 0, (r.diff(:x) - RCAS.exp(X) / (X + 1)).simplify.cancel
  end

  def test_the_derivatives_are_the_integrands
    assert_equal RCAS.sin(X) / X, RCAS.diff(RCAS::Fn.new(:Si, [X]), :x)
    assert_equal RCAS.cos(X) / X, RCAS.diff(RCAS::Fn.new(:Ci, [X]), :x)
    assert_equal RCAS.exp(X) / X, RCAS.diff(RCAS::Fn.new(:Ei, [X]), :x)
    assert_equal 1 / RCAS.log(X), RCAS.diff(RCAS::Fn.new(:li, [X]), :x)
    assert_equal "2*sin(x**2)/x", RCAS.diff(RCAS::Fn.new(:Si, [X**2]), :x).to_s, "the chain rule"
  end

  def test_exact_values
    assert_equal 0, RCAS::Fn.new(:Si, [RCAS::Num.new(0)]).simplify
    assert_equal "pi/2", RCAS.limit(RCAS::Fn.new(:Si, [X]), :x, OO).to_s
    assert_equal 0, RCAS.limit(RCAS::Fn.new(:Ci, [X]), :x, OO)
    assert_equal 0, RCAS.limit(RCAS::Fn.new(:Ei, [X]), :x, -OO)
    assert_equal "-oo", RCAS::Fn.new(:Ci, [RCAS::Num.new(0)]).simplify.to_s
    assert_equal 0, RCAS::Fn.new(:li, [RCAS::Num.new(0)]).simplify
  end

  def test_definite_integrals
    assert_equal "pi/2", RCAS.integrate(RCAS.sin(X) / X, x: 0..RCAS::OO).to_s, "the Dirichlet integral"
    assert_equal "Si(1)", RCAS.integrate(RCAS.sin(X) / X, x: 0..1).to_s
    assert_in_delta 0.9460830703671830, RCAS.integrate(RCAS.sin(X) / X, x: 0..1).evalf, 1e-12
  end

  def test_numbers
    assert_in_delta 1.8951178163559368, RCAS::IntegralFunctions.ei(1.0), 1e-12
    assert_in_delta(-0.21938393439552029, RCAS::IntegralFunctions.ei(-1.0), 1e-12)
    assert_in_delta 0.9460830703671830, RCAS::IntegralFunctions.si(1.0), 1e-12
    assert_in_delta 1.6583475942188740, RCAS::IntegralFunctions.si(10.0), 1e-10, "the continued fraction"
    assert_in_delta 0.3374039229009681, RCAS::IntegralFunctions.ci(1.0), 1e-12
    assert_in_delta(-0.04545643300445537, RCAS::IntegralFunctions.ci(10.0), 1e-10)
    assert_in_delta 1.0451637801174927, RCAS::IntegralFunctions.li(2.0), 1e-12
    assert_in_delta 30.126141584079644, RCAS::IntegralFunctions.li(100.0), 1e-9, "li(100), against 25 primes below 100"
    assert_in_delta 177.6096579901522, RCAS::IntegralFunctions.li(1000.0), 1e-9
    assert_in_delta(-RCAS::IntegralFunctions.si(2.0), RCAS::IntegralFunctions.si(-2.0), 1e-12, "Si is odd")
  end

  def test_evalf_and_printing
    assert_in_delta 0.9460830703671830, RCAS.evalf(RCAS::Fn.new(:Si, [RCAS::Num.new(1)])), 1e-12
    assert_equal "Si(x)", RCAS::Fn.new(:Si, [X]).to_s
    assert_equal "\\operatorname{Si} x", RCAS::LaTeX.of(RCAS::Fn.new(:Si, [X]))
    assert_equal RCAS::RR, RCAS::Infer.domain(RCAS::Fn.new(:Si, [RCAS::Num.new(2)]))
  end

  def test_a_second_order_ode_that_needs_them
    y = RCAS::Var.new(:y)
    eq = RCAS::Equation.new(RCAS::Derivative.new(y, X, 2) + y, 1 / X)
    assert_equal ["y = C1*cos(x) + C2*sin(x) + Ci(x)*sin(x) - Si(x)*cos(x)"], RCAS.dsolve(eq, :y, :x).map(&:to_s)
  end
end
