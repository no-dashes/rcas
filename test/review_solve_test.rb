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
  rescue NotImplementedError, RCAS::Unsupported
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

  # nsolve stops on |f| < 1e-12 (numerics.rb:110, :124): (x - 3/10)/10**12
  # is -3e-13 at 0 and vanishes only at 3/10; exp(-50x)(x - 1/2) is 1e-22
  # at 1 and vanishes only at 1/2.
  def test_nsolve_answers_a_root_not_a_small_value
    assert_in_delta 0.3, RCAS.nsolve((@x - 3/10r) / 10**12, x: 0..1), 1e-9
    assert_in_delta 0.5, RCAS.nsolve(RCAS.exp(-50 * @x) * (@x - 1/2r), x: 0..1), 1e-9
  end

  # A step from -1 to 1 changes sign without vanishing anywhere, so there is
  # no root to report; pole? recognises only growth (numerics.rb:86).
  def test_nsolve_refuses_a_jump
    step = RCAS.piecewise(@x < n(1/2r) => -1, :else => 1)
    assert_raises(ArgumentError) { RCAS.nsolve(step, x: 0..1) }
    assert_raises(ArgumentError) { RCAS.nsolve((@x - 1/2r) / RCAS.abs(@x - 1/2r), x: 0..1) }
  end

  # f' = x**2*(x - a) with a = 10**-5 is negative on both sides of 0, so 0
  # is no extremum; sampling at +-10**-4 steps over a (analysis.rb:78).
  def test_an_extremum_needs_a_sign_change_of_the_derivative
    f = @x**4 / 4 - @x**3 / (3 * 10**5)
    refute RCAS.extrema(f, @x).any? { |p, _, kind| real(p) == 0.0 && kind != :saddle }
    refute RCAS.discuss(f, @x).extrema.any? { |p, _, kind| real(p) == 0.0 && kind != :saddle }
  end

  # critical_points / vertical_asymptotes turn "cannot solve" into []
  # (analysis.rb:42, :175). cos(x) + x**2/4 has a maximum at 0 (f''(0) =
  # -1/2); exp(x) - x - 2 changes sign on [1, 2] and [-2, -1], poles of 1/it.
  def test_unsolved_equations_are_not_reported_as_none
    refused_or { refute_empty RCAS.extrema(RCAS.cos(@x) + @x**2 / 4, @x) }
    refused_or { refute_empty RCAS.asymptotes(1 / (RCAS.exp(@x) - @x - 2), @x)[:vertical] }
  end

  # log(x) -> -oo as x -> 0+, so x = 0 is a vertical asymptote; only
  # denominators are searched (analysis.rb:196). Likewise log(x - 1) at 1.
  def test_a_logarithm_has_a_vertical_asymptote
    assert covers?(RCAS.asymptotes(RCAS.log(@x), @x)[:vertical], 0.0)
    assert covers?(RCAS.asymptotes(RCAS.log(@x - 1) / @x, @x)[:vertical], 1.0)
  end

  # f'' of sqrt(x)*(x - 3) vanishes only at x = -1, outside [0, oo): there
  # is no inflection, and certainly not the complex point (-1, -4*i).
  def test_reported_inflections_lie_in_the_domain
    points = RCAS.discuss(RCAS.sqrt(@x) * (@x - 3), @x).inflections
    assert points.all? { |p, _| (v = real(p)) && v >= 0 }, points.inspect
  end

  # x/a > 1: for a = 1 this is x > 1, for a = 0 it is meaningless; a case
  # split must not divide by zero on the way.
  def test_a_parametric_inequality_survives_a_zero_parameter
    cases = RCAS.solve(@x / @a > 1, @x)
    assert cases.at(1).include?(2)
  end

  # (x - 1)**3/(x - 1) is (x - 1)**2 off x = 1 and undefined at 1, so it has
  # no extremum at all; evaluating there divides by zero.
  def test_an_excluded_point_is_not_an_extremum
    assert_equal [], RCAS.extrema((@x - 1)**3 / (@x - 1), @x)
  end

  # The graph of sqrt(x) has a vertical tangent at 0, which y = m*x + c
  # cannot write: refusing with a message is right, ZeroDivisionError is not.
  def test_a_vertical_tangent_is_refused_with_a_message
    RCAS.tangent(RCAS.sqrt(@x), @x, 0)
  rescue ArgumentError, NotImplementedError, RCAS::Unsupported
    assert true
  end

  # tan(1) = 1.557 > tan(2) = -2.185, so tan is not increasing on (0, pi):
  # the chart merges across the pole at pi/2 (discussion.rb:362).
  def test_monotonicity_does_not_bridge_a_pole
    chart = RCAS.discuss(RCAS.tan(@x), @x).monotonicity
    refute chart.any? { |piece, _| piece.include?(Math::PI / 2) }, chart.inspect
  end

  # 1 + exp(-x) > 0 for real x: the logistic function has no gap, no
  # vertical asymptote. -log(-1) = -i*pi is complex (real_point?,
  # analysis.rb:60, counts an unevaluated log(-1) as real).
  def test_complex_points_are_not_gaps_of_a_real_function
    report = RCAS.discuss(1 / (1 + RCAS.exp(-@x)), @x)
    assert_empty report.gaps
    assert_empty report.asymptotes[:vertical]
  end

  # sin(x)/x vanishes at every k*pi, k != 0, and is not periodic, so the
  # principal zeros [pi] are a truncation (discussion.rb:291); -pi and 2*pi
  # are zeros too. "not determined" (nil) would be honest.
  def test_zeros_of_a_nonperiodic_function_are_not_truncated
    zeros = RCAS.discuss(RCAS.sin(@x) / @x, @x).zeros
    assert zeros.nil? || (covers?(zeros, -Math::PI) && covers?(zeros, 2 * Math::PI)), zeros.inspect
  end

  # A branch equal to the right-hand side everywhere contributes its piece;
  # solve now answers 0 = 0 with a RealSet, and Piecewises.solve still waits
  # for the old ArgumentError (piecewise.rb:401). Here x >= 0 is the answer.
  def test_a_constant_branch_contributes_its_whole_piece
    step = RCAS.piecewise(@x < 0 => 0, :else => 1)
    set = RCAS.solve(eq(step, 1), @x)
    assert set.include?(0) && set.include?(5) && !set.include?(-1)
  end

  # Piecewises.solve asks for principal solutions (piecewise.rb:400), so a
  # periodic branch keeps one period: sin(2*pi) = 0 with 2*pi > 0, and
  # cos(5*pi/3) = 1/2 with 5*pi/3 > 0.
  def test_a_periodic_branch_keeps_every_period
    pw = RCAS.piecewise(@x > 0 => RCAS.sin(@x), :else => @x + 1)
    assert covers?(RCAS.solve(pw, @x), 2 * Math::PI)
    pw = RCAS.piecewise(@x > 0 => RCAS.cos(@x), :else => n(5))
    assert covers?(RCAS.solve(eq(pw, 1/2r), @x), 5 * Math::PI / 3)
  end

  # README tells a library user to `include RCAS::Functions`; then :else
  # responds to simplify/subs (piecewise.rb:113-114) and every piecewise
  # with an :else raises. d/dx of a step is 0 away from the jump.
  def test_piecewise_survives_the_library_include
    lib = $LOAD_PATH.find { |dir| File.exist?(File.join(dir, 'rcas.rb')) }
    script = 'include RCAS::Functions; x = :x; ' \
             'puts diff(piecewise(x < 0 => 0, :else => 1), x).call(x: 1)'
    out, err, status = Open3.capture3(RbConfig.ruby, '-I', lib, '-rrcas', '-e', script)
    assert status.success?, err.lines.first
    assert_equal '0', out.strip
  end

  # sin(pi*x) = 0 exactly on ZZ; restricting to ZZ keeps ZZ, restricting to
  # RR keeps ZZ. rebuilt_family returns the NumberSet (solve.rb:258) and
  # restrict lifts it as a root.
  def test_a_family_that_is_the_integers_can_be_restricted
    [RCAS::ZZ, RCAS::RR].each do |domain|
      assert_equal [RCAS::ZZ], RCAS.solve(RCAS.sin(pi * @x), @x, domain: domain)
    end
  end

  # Squaring sqrt(x**2) = -x gives x**2 = x**2, which says nothing about the
  # original: |x| = -x holds for x <= 0 only, so x = 1 is no solution.
  def test_an_identity_after_squaring_is_not_a_verdict
    [[RCAS.sqrt(@x**2), -@x, -1, 1], [RCAS.sqrt(@x**2), @x, 1, -1]].each do |l, r, yes, no|
      refused_or do
        set = RCAS.solve(eq(l, r), @x)
        assert set.include?(yes) && !set.include?(no)
      end
    end
  end

  # exp(x) = -1 and sin(x) = 2 have no real solution (exp > 0, |sin| <= 1);
  # under domain: RR the answers log(-1) = i*pi and asin(2) + 2*pi*k are not real.
  def test_a_real_domain_drops_nonreal_answers
    assert_equal [], RCAS.solve(RCAS.exp(@x) + 1, @x, domain: RCAS::RR)
    assert_equal [], RCAS.solve(RCAS.sin(@x) - 2, @x, domain: RCAS::RR)
    assert_equal [], RCAS.solve(RCAS.cos(@x) - 2, @x, domain: RCAS::RR)
  end
end
