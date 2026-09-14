# frozen_string_literal: true

require_relative "test_helper"

# Systems of linear differential equations with constant coefficients.
class OdeSystemsTest < Minitest::Test
  T = RCAS::Var.new(:t)
  X = RCAS::Var.new(:x)
  Y = RCAS::Var.new(:y)

  def d(u) = RCAS::Derivative.new(u, T)
  def solve(equations) = RCAS.dsolve(equations, [X, Y], T)

  # Substituting the solution back into the system must leave nothing.
  def assert_solves(equations, solutions)
    values = solutions.to_h { |s| [s.lhs, s.rhs] }
    equations.each do |equation|
      residual = RCAS::Solve.to_zero(equation)
      residual = residual.subs(values.to_h { |u, expr| [d(u), expr.diff(:t)] }).subs(values)
      [0.3, 1.4].each do |point|
        value = residual.simplify.evalf(t: point, C1: 0.7, C2: -1.3)
        assert_in_delta 0.0, value, 1e-9, "#{solutions.map(&:to_s)} does not solve the system"
      end
    end
  end

  def test_a_rotation
    equations = [RCAS::Equation.new(d(X), Y), RCAS::Equation.new(d(Y), -X)]
    solutions = solve(equations)
    assert_equal ["x = C1*sin(t) + C2*cos(t)", "y = C1*cos(t) - C2*sin(t)"], solutions.map(&:to_s)
    assert_solves equations, solutions
  end

  def test_real_eigenvalues
    equations = [RCAS::Equation.new(d(X), X + 2 * Y), RCAS::Equation.new(d(Y), 3 * X + 2 * Y)]
    solutions = solve(equations)
    assert_equal ["x = 2*C1*exp(4*t)/3 - C2*exp(-t)", "y = C1*exp(4*t) + C2*exp(-t)"], solutions.map(&:to_s)
    assert_solves equations, solutions
  end

  def test_a_repeated_eigenvalue
    equations = [RCAS::Equation.new(d(X), X), RCAS::Equation.new(d(Y), X + Y)]
    solutions = solve(equations)
    assert_equal ["x = C2*exp(t)", "y = C1*exp(t) + C2*t*exp(t)"], solutions.map(&:to_s), "a Jordan chain gives the t*exp(t) term"
    assert_solves equations, solutions
  end

  def test_a_constant_forcing_term
    equations = [RCAS::Equation.new(d(X), -X + 1), RCAS::Equation.new(d(Y), X - Y)]
    solutions = solve(equations)
    assert_includes solutions.first.to_s, "1 +", "the steady state is added"
    assert_solves equations, solutions
  end

  def test_what_is_not_supported
    assert_raises(NotImplementedError) { solve([RCAS::Equation.new(d(X), T * X), RCAS::Equation.new(d(Y), Y)]) }
    assert_raises(NotImplementedError) { solve([RCAS::Equation.new(d(X), RCAS.exp(T)), RCAS::Equation.new(d(Y), Y)]) }
    assert_raises(ArgumentError) { RCAS.dsolve([RCAS::Equation.new(d(X), Y)], [X, Y], T) }
  end
end
