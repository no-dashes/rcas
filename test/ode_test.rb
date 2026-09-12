# frozen_string_literal: true

require_relative "test_helper"

class OdeTest < Minitest::Test
  X = RCAS::Var.new(:x)
  Y = RCAS::Var.new(:y)

  def d(n = 1) = RCAS::Derivative.new(Y, X, n)
  def dsolve(eq) = RCAS::ODE.dsolve(eq, :y, :x)

  # Substitute the solution back into the equation and check it vanishes.
  def assert_solves(equation, solutions)
    f = RCAS::Solve.to_zero(equation)
    solutions.each do |sol|
      assert_equal Y, sol.lhs
      y = sol.rhs
      residual = f.subs(d(2) => y.diff(:x, 2), d(1) => y.diff(:x), Y => y).expand
      if RCAS::Scalar.zero?(residual)
        pass
      else
        [0.3, 1.1].each do |p|
          assert_in_delta 0.0, residual.evalf(x: p, C1: 0.7, C2: -1.3), 1e-9, "#{sol} does not solve #{equation}"
        end
      end
    end
  end

  def test_separable
    eq = RCAS::Equation.new(d, 2 * X * Y)
    sols = dsolve(eq)
    assert_equal ["y = exp(C1 + x**2)"], sols.map(&:to_s)
    assert_solves eq, sols
    assert_equal ["y = exp(C1 + x)"], dsolve(d - Y).map(&:to_s)
    assert_equal ["y = C1 + x**2/2"], dsolve(d - X).map(&:to_s)
    assert_solves d - Y**2, dsolve(d - Y**2)
    assert_solves d - RCAS.sin(X) * Y, dsolve(d - RCAS.sin(X) * Y)
    sols = dsolve(d - X / Y)
    assert_equal ["y = -(2*C1 + x**2)**(1/2)", "y = (2*C1 + x**2)**(1/2)"], sols.map(&:to_s)
    assert_solves d - X / Y, sols
  end

  def test_first_order_linear
    eq = RCAS::Equation.new(d + 2 * Y, RCAS.exp(X))
    sols = dsolve(eq)
    assert_equal ["y = exp(-2*x)*(C1 + exp(3*x)/3)"], sols.map(&:to_s)
    assert_solves eq, sols
    eq = X * d + Y - X**2
    assert_equal ["y = (C1 + x**3/3)/x"], dsolve(eq).map(&:to_s)
    assert_solves eq, dsolve(eq)
  end

  def test_second_order_constant_coefficients
    eq = d(2) - 3 * d + 2 * Y
    assert_equal ["y = C1*exp(x) + C2*exp(2*x)"], dsolve(eq).map(&:to_s)
    assert_solves eq, dsolve(eq)
    eq = d(2) + Y
    assert_equal ["y = C1*cos(x) + C2*sin(x)"], dsolve(eq).map(&:to_s)
    assert_solves eq, dsolve(eq)
    eq = d(2) - 2 * d + Y
    assert_equal ["y = exp(x)*(C1 + C2*x)"], dsolve(eq).map(&:to_s)
    assert_solves eq, dsolve(eq)
    eq = d(2) + 2 * d + 5 * Y
    assert_equal ["y = exp(-x)*(C1*cos(2*x) + C2*sin(2*x))"], dsolve(eq).map(&:to_s)
    assert_solves eq, dsolve(eq)
  end

  def test_unsupported_cases_raise
    assert_raises(NotImplementedError) { dsolve(d(2) + Y - X) }
    assert_raises(NotImplementedError) { dsolve(d - RCAS.sin(X * Y)) }
    assert_raises(ArgumentError) { dsolve(Y - X) }
    assert_equal "D(y, x, 2)", d(2).to_s
    assert_equal d(3), d(2).diff(:x)
  end
end
