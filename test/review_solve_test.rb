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

  # The root substitution t = x**(1/2) leaves every other x in place
  # (solve.rb:636). sqrt(x) = sqrt(2 - x) iff x = 2 - x iff x = 1;
  # sqrt(1)*log(1) = 0; sqrt(pi/2)*cos(pi/2) = 0.
  def test_root_substitution_replaces_every_occurrence
    roots = RCAS.solve(eq(RCAS.sqrt(@x), RCAS.sqrt(2 - @x)), @x)
    assert roots.all? { |r| RCAS::Expression.lift(r).variables.empty? }, "a solution may not contain x: #{roots.inspect}"
    assert_equal [1.0], roots.map { |r| real(r) }
    assert covers?(RCAS.solve(RCAS.sqrt(@x) * RCAS.log(@x), @x), 1.0)
    assert covers?(RCAS.solve(RCAS.sqrt(@x) * RCAS.cos(@x), @x), Math::PI / 2)
  end

  # (x**2 - 1)/(x - 1) = x + 1 holds wherever the left side is defined, i.e.
  # for every x != 1; the cleared numerator is the zero polynomial, which
  # polynomial_roots answers with [] (solve.rb:500).
  def test_rational_identity_holds_off_its_pole
    set = RCAS.solve(eq((@x**2 - 1) / (@x - 1), @x + 1), @x)
    assert_kind_of RCAS::RealSet, set
    assert set.include?(0) && set.include?(2) && !set.include?(1)
    set = RCAS.solve(eq(@x / (@x + 1) + 1 / (@x + 1), 1), @x)
    assert_kind_of RCAS::RealSet, set
    assert set.include?(0) && !set.include?(-1)
    # the same expression minus 1 is zero wherever defined: "!= 0" is empty
    assert RCAS.solve(RCAS::Inequality.new(@x / (@x + 1) + 1 / (@x + 1) - 1, :!=, 0), @x).none? { true }
  end

  # invert answers [] for a function it has no inverse for (solve.rb:910,
  # :920). 2**2 = 4, erf(0) = 0, gamma(1) = gamma(2) = 1, floor(2.5) = 2:
  # each has a solution, so [] is false; refusing is fine.
  def test_an_uninvertible_equation_is_refused_not_empty
    [[eq(@x**@x, 4), 2.0], [RCAS.erf(@x), 0.0], [eq(RCAS.gamma(@x), 1), 1.0],
     [@x**@x - 1, 1.0]].each do |equation, root|
      refused_or { assert covers?(RCAS.solve(equation, @x), root), "#{equation.inspect} misses #{root}" }
    end
    refused_or { refute_empty RCAS.solve(eq(RCAS.floor(@x), 2), @x) }
  end

  # solve and the inequality solver simplify before looking at the domain
  # (solve.rb:166, inequalities.rb:151), so a cancelled factor's zero comes
  # back. Each expression below is undefined at the point tested.
  def test_cancelled_denominators_still_exclude_their_zeros
    refute RCAS.solve(eq((@x - 1) / (@x - 1), 1), @x).include?(1)
    refute RCAS.solve(eq(@x / @x, 1), @x).include?(0)
    assert_equal [], RCAS.solve(@x**2 / @x, @x)
    assert_equal [], RCAS.solve((@x - 1)**2 / (@x - 1), @x)
    assert_equal [], RCAS.solve(@x + 1 / @x - 1 / @x, @x)
    refute RCAS.solve(@x / @x > 0, @x).include?(0)
    refute RCAS.solve((@x - 1)**2 / (@x - 1) >= 0, @x).include?(1)
    refute RCAS.solve(@x**2 / @x >= 0, @x).include?(0)
  end

  # (x - 1)(x - 1 - 10**-15) < 0 exactly on (1, 1 + 10**-15), which contains
  # 1 + 10**-15/2; roots are deduplicated by round(12) (inequalities.rb:310).
  def test_nearby_roots_bound_a_nonempty_interval
    eps = 1/10**15r
    inside = 1 + eps / 2
    assert RCAS.solve((@x - 1) * (@x - 1 - eps) < 0, @x).include?(n(inside))
    refute RCAS.solve((@x - 1) * (@x - 1 - eps) > 0, @x).include?(n(inside))
    assert RCAS.solve((@x - 1) / (@x - 1 - eps) <= 0, @x).include?(1)
  end

  # (x - 1)**2 + 10**-26 > 0 for every real x: its roots 1 +- 10**-13*i are
  # not real, but |Im| < 1e-12 promotes them to the float 1.0 (inequalities.rb:327).
  def test_nonreal_roots_are_not_boundary_points
    f = (@x - 1)**2 + 1/10**26r
    assert RCAS.solve(f <= 0, @x).none? { true }
    assert RCAS.solve(f > 0, @x).include?(1)
  end

  # |x|/x is 1 for x > 0 and -1 for x < 0, so |x|/x > 0 is (0, oo); the abs
  # split evaluates f at x = 0 (inequalities.rb:297) and divides by zero.
  def test_an_abs_split_point_may_be_a_pole
    set = RCAS.solve(RCAS.abs(@x) / @x > 0, @x)
    assert set.include?(1) && !set.include?(-1) && !set.include?(0)
  end
end
