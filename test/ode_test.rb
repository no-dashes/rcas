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
      pattern = { Y => y }
      (1..4).each { |k| pattern[d(k)] = y.diff(:x, k) }
      residual = f.subs(pattern).expand
      if RCAS::Scalar.zero?(residual)
        pass
      else
        [0.3, 1.1].each do |p|
          assert_in_delta 0.0, residual.evalf(x: p, C1: 0.7, C2: -1.3, C3: 0.4, C4: 2.1), 1e-9, "#{sol} does not solve #{equation}"
        end
      end
    end
  end

  def test_separable
    eq = RCAS::Equation.new(d, 2 * X * Y)
    sols = dsolve(eq)
    # linear, so the linear rule answers: C1*exp(x**2) includes y = 0 and
    # the negative solutions, which exp(C1 + x**2) missed (third review)
    assert_equal ["y = C1*exp(x**2)"], sols.map(&:to_s)
    assert_solves eq, sols
    assert_equal ["y = C1*exp(x)"], dsolve(d - Y).map(&:to_s)
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

  def test_symbolic_coefficients
    k = RCAS::Var.new(:k)
    eq = d(2) - k**2 * Y
    assert_equal ["y = C1*exp(-(k*x)) + C2*exp(k*x)"], dsolve(eq).map(&:to_s)
    a = RCAS::Var.new(:a)
    assert_equal ["y = C1 + C2*exp(-(a*x))"], dsolve(d(2) + a * d).map(&:to_s)
  end

  def test_higher_order
    eq = d(3) - d
    assert_equal ["y = C1 + C2*exp(-x) + C3*exp(x)"], dsolve(eq).map(&:to_s)
    assert_solves eq, dsolve(eq)
    eq = d(4) - 2 * d(2) + Y
    assert_equal ["y = exp(-x)*(C1 + C2*x) + exp(x)*(C3 + C4*x)"], dsolve(eq).map(&:to_s)
    assert_solves eq, dsolve(eq)
    eq = d(4) + Y # roots (+-1 +- i)/sqrt(2)
    sols = dsolve(eq)
    assert_equal ["y = exp(-(2**(1/2)*x)/2)*(C1*cos(2**(1/2)*x/2) + C2*sin(2**(1/2)*x/2)) + " \
                  "exp(2**(1/2)*x/2)*(C3*cos(2**(1/2)*x/2) + C4*sin(2**(1/2)*x/2))"], sols.map(&:to_s)
    assert_solves eq, sols
    eq = d(3) + d(2) + d + Y
    assert_solves eq, dsolve(eq)
  end

  def test_undetermined_coefficients
    cases = {
      RCAS::Equation.new(d(2) + Y, X) => "y = x + C1*cos(x) + C2*sin(x)",
      RCAS::Equation.new(d(2) - Y, RCAS.exp(X)) => "y = C1*exp(-x) + C2*exp(x) + x*exp(x)/2", # resonance
      RCAS::Equation.new(d(2) + Y, X * RCAS.exp(X)) => "y = exp(x)*(-1/2 + x/2) + C1*cos(x) + C2*sin(x)",
      RCAS::Equation.new(d(2) + 4 * Y, RCAS.cos(2 * X)) => "y = C1*cos(2*x) + C2*sin(2*x) + x*sin(2*x)/4", # resonance
      RCAS::Equation.new(d(2) + 3 * d + 2 * Y, 1) => "y = 1/2 + C1*exp(-2*x) + C2*exp(-x)",
      RCAS::Equation.new(d(2), X) => "y = C1 + C2*x + x**3/6",
      RCAS::Equation.new(d(2) - Y, RCAS.exp(X + 1)) => "y = C1*exp(-x) + C2*exp(x) + x*exp(1 + x)/2",
      RCAS::Equation.new(d(2) + Y, RCAS.exp(X) * RCAS.sin(X) + X**2) =>
        "y = -2 + exp(x)*(-2*cos(x)/5 + sin(x)/5) + C1*cos(x) + C2*sin(x) + x**2",
      RCAS::Equation.new(d(3) - Y, X) => "y = -x + C3*exp(x) + exp(-x/2)*(C1*cos(3**(1/2)*x/2) + C2*sin(3**(1/2)*x/2))"
    }
    cases.each do |eq, expected|
      sols = dsolve(eq)
      assert_equal [expected], sols.map(&:to_s)
      assert_solves eq, sols
    end
    a = RCAS::Var.new(:a)
    eq = RCAS::Equation.new(d(2) + Y, a * RCAS.sin(3 * X))
    assert_equal ["y = C1*cos(x) + C2*sin(x) - a*sin(3*x)/8"], dsolve(eq).map(&:to_s)
  end

  def test_variation_of_parameters
    eq = RCAS::Equation.new(d(2) - 2 * d + Y, RCAS.exp(X) / X)
    sols = dsolve(eq)
    assert_equal ["y = -(x*exp(x)) + exp(x)*(C1 + C2*x) + x*exp(x)*log(x)"], sols.map(&:to_s)
    assert_solves eq, sols
    eq = RCAS::Equation.new(d(2) + Y, 1 / RCAS.cos(X))
    sols = dsolve(eq)
    assert_equal ["y = C1*cos(x) + C2*sin(x) + cos(x)*log(cos(x)) + x*sin(x)"], sols.map(&:to_s)
    assert_solves eq, sols
    # 1/x needs the sine and cosine integrals, and gets them.
    sols = dsolve(RCAS::Equation.new(d(2) + Y, 1 / X))
    assert_equal ["y = C1*cos(x) + C2*sin(x) + Ci(x)*sin(x) - Si(x)*cos(x)"], sols.map(&:to_s)
    # Integrals rcas cannot do stay formal instead of being dropped.
    sols = dsolve(RCAS::Equation.new(d(2) + Y, 1 / RCAS.log(X)))
    assert_includes sols.first.to_s, "integral("
  end

  def test_unsupported_cases_raise
    assert_raises(NotImplementedError) { dsolve(d(2) + Y * d) }
    assert_raises(NotImplementedError) { dsolve(d(2) + X * Y) }
    assert_raises(NotImplementedError) { dsolve(RCAS::Equation.new(d(3) + Y, 1 / X)) }
    assert_raises(NotImplementedError) { dsolve(d - RCAS.sin(X * Y)) }
    assert_raises(ArgumentError) { dsolve(Y - X) }
    assert_equal "D(y, x, 2)", d(2).to_s
    assert_equal d(3), d(2).diff(:x)
  end
end
