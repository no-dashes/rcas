# Review of solve / inequalities / piecewise / real_domain / Analysis /
# discuss / nsolve: mathematical expectations, each derived independently.
require_relative 'test_helper'
require 'rcas'
require 'open3'
require 'rbconfig'

class ReviewSolveTest < Minitest::Test
  def setup
    @x, @t, @a = %i[x t a].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)
  def eq(l, r) = RCAS::Equation.new(l, r)
  def pi = RCAS::PI

  # A number, or nil when e does not evaluate to a finite real.
  def real(e)
    v = RCAS::Expression.lift(e).evalf
    v = v.value if v.is_a?(RCAS::Num)
    return nil unless v.is_a?(Numeric)
    v = v.real if v.is_a?(Complex) && v.imaginary.abs < 1e-12
    v.is_a?(Complex) || !v.finite? ? nil : v.to_f
  rescue StandardError, Math::DomainError
    nil
  end

  # f(var = v) as a Float, nil when undefined, complex or not a number.
  def value_at(f, var, v)
    real(RCAS::Expression.lift(f).subs(var.name => RCAS::Expression.lift(v)))
  end

  # The members of a solution list: points, and families at k = -3..3.
  def members(solutions, ks = -3..3)
    solutions.flat_map do |s|
      s.is_a?(RCAS::ImageSet) ? ks.map { |k| s.at(k) } : [s]
    end
  end

  def covers?(solutions, target, ks = -6..6)
    members(solutions, ks).any? { |m| (v = real(m)) && (v - target).abs < 1e-9 }
  end

  def refused_or
    yield
  rescue NotImplementedError
    assert true
  end

  # verify substitutes `x:` literally (solve.rb:957), so for any other name
  # the roots invented by squaring and by the abs case split are kept.
  # sqrt(1) = 1 != -1; |(-1) - 1| = 2 != -2; sqrt(1) = 1 != -1.
  def test_extraneous_roots_are_rejected_for_any_unknown_name
    assert_equal [2.0], RCAS.solve(eq(RCAS.sqrt(@t + 2), @t), @t).map { |r| real(r) }
    assert_equal [1/3r], RCAS.solve(eq(RCAS.abs(@t - 1), 2 * @t), @t).map { |r| RCAS::Expression.lift(r).value }
    assert_equal [], RCAS.solve(eq(@t**n(1/2r), -1), @t)
  end
end
