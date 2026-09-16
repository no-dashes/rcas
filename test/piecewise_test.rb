# frozen_string_literal: true

require_relative "test_helper"

class PiecewiseTest < Minitest::Test
  include RCAS::Constants

  X = RCAS::Var.new(:x)

  def pw(*args, **rest) = RCAS.piecewise(*args, **rest)
  def abs_like = pw(X < 0 => -X, :else => X)
  def step = pw(X < 0 => 0, :else => 1)

  def test_building_and_printing
    f = pw(X < 0 => -X, :else => X**2)
    assert_equal "piecewise(x < 0 => -x, :else => x**2)", f.to_s
    assert_equal [:x], f.variables
    assert_equal f, pw([[X < 0, -X], [:else, X**2]]), "an array of pairs builds the same node"
    assert_equal "piecewise(interval(0, 1) => x)", pw(RCAS.interval(0, 1) => X).to_s
    assert_equal "piecewise(x.eq(0) => 1, :else => 0)", pw(RCAS.eq(X, 0) => 1, :else => 0).to_s
    assert_raises(ArgumentError) { pw }
    assert_raises(ArgumentError) { pw("x < 0" => 1) }
  end

  def test_construction_does_not_choose
    f = abs_like
    assert_equal "piecewise(5 < 0 => -5, :else => 5)", f.subs(x: 5).to_s, "subs keeps the structure"
    assert_equal 5, f.call(x: 5)
    assert_equal 3, f.call(x: -3)
    assert_equal 2.5, f.evalf(x: -2.5)
  end

  def test_first_match_wins
    f = pw(X < 1 => 1, X < 2 => 2, :else => 3)
    assert_equal 1, f.call(x: 0)
    assert_equal 2, f.call(x: 1.5)
    assert_equal 3, f.call(x: 7)
    assert_equal ["(-oo, 1)", "[1, 2)", "[2, oo)"], f.sets.map { |set, _| set.to_s }
  end

  def test_uncovered_point
    f = pw(X < 0 => 1 / X, 0 < X => X)
    assert_equal(-Rational(1, 2), f.call(x: -2))
    assert_raises(RCAS::DomainError, "no branch covers 0") { f.call(x: 0) }
  end

  def test_breakpoints_and_continuity
    assert_equal [0], abs_like.breakpoints.map(&:to_s).map(&:to_i)
    assert_empty abs_like.discontinuities
    assert_equal [0], abs_like.kinks.map { |p| p.call }
    refute abs_like.differentiable?
    assert abs_like.continuous?
    assert_equal [0], step.discontinuities.map { |p| p.call }
    refute step.continuous?
    smooth = pw(X < 0 => X, :else => X)
    assert smooth.differentiable?
  end

  def test_diff
    assert_equal "piecewise(x < 0 => -1, :else => 2*x)", RCAS.diff(pw(X < 0 => -X, :else => X**2), :x).to_s
    assert_equal 1, RCAS.diff(abs_like, :x).call(x: 3)
    assert_equal(-1, RCAS.diff(abs_like, :x).call(x: -3))
  end

  def test_antiderivative_is_continuous
    f = pw(X < 1 => 1, :else => X)
    antiderivative = RCAS.integrate(f, :x)
    assert_equal "piecewise(x < 1 => x, :else => 1/2 + x**2/2)", antiderivative.to_s
    assert_equal 1, antiderivative.call(x: 1), "the pieces meet at the breakpoint"
    left = RCAS::Limits.limit(antiderivative, :x, 1, :left)
    right = RCAS::Limits.limit(antiderivative, :x, 1, :right)
    assert RCAS::Scalar.zero?(left - right), "no jump at the breakpoint: #{left} vs #{right}"
    # d/dx of the antiderivative is the function again
    assert_equal 1, RCAS.diff(antiderivative, :x).call(x: 0.5)
    assert_equal 2, RCAS.diff(antiderivative, :x).call(x: 2)
  end

  def test_definite_integral_across_breakpoints
    f = pw(X < 0 => -X, :else => X**2)
    assert_equal 11, RCAS.integrate(f, x: -2..3)
    assert_equal 2, RCAS.integrate(f, x: -2..0)
    assert_equal 9, RCAS.integrate(f, x: 0..3)
    assert_equal(-11, RCAS.integrate(f, x: 3..-2), "orientation")
    assert_equal Rational(1, 2), RCAS.integrate(step, x: -1..Rational(1, 2))
    u = pw(X <= 0 => RCAS.exp(X), :else => RCAS.cos(X))
    assert_in_delta 1 - Math.exp(-1) + Math.sin(1), RCAS.integrate(u, x: -1..1).evalf, 1e-12
  end

  def test_limits
    assert_equal 0, RCAS.limit(abs_like, :x, 0)
    assert_equal 0, RCAS.limit(step, :x, 0, :left)
    assert_equal 1, RCAS.limit(step, :x, 0, :right)
    assert_kind_of RCAS::Limit, RCAS.limit(step, :x, 0), "the sides disagree"
    assert_equal 4, RCAS.limit(pw(X < 0 => -X, :else => X**2), :x, 2)
  end

  def test_solve
    f = pw(X < 0 => -X, :else => X**2)
    assert_equal [-4, 2], RCAS.solve(RCAS.eq(f, 4), :x)
    assert_empty RCAS.solve(RCAS.eq(step, 5), :x)
    assert_equal [0], RCAS.solve(RCAS.eq(f, 0), :x), "a root on the boundary belongs to one branch only"
  end

  def test_latex_and_domain
    f = pw(X < 0 => -X, :else => X**2)
    assert_equal "\\begin{cases} -x & x < 0 \\\\ x^{2} & \\text{otherwise} \\end{cases}", RCAS::LaTeX.of(f)
    assert_equal RCAS::RR, RCAS::Infer.domain(pw(X < 0 => 1, :else => RCAS.sqrt(2)))
  end

  def test_hold_keeps_the_branches
    f = RCAS.hold { RCAS.piecewise(:x < 0 => -:x, :else => :x**2) }
    assert_equal "piecewise(x < 0 => -x, :else => x**2)", f.to_s
  end
end
