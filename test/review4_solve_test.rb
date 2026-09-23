# Second verification round (solve / inequalities / analysis / discuss):
# defects found after the fixes of the third review, each derived
# independently. Every test fails on 8c10e71 for the reason stated.
require_relative 'test_helper'
require 'rcas'
require 'timeout'

class Review2SolveTest < Minitest::Test
  def setup
    @x, @a = %i[x a].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)
  def eq(l, r) = RCAS::Equation.new(l, r)
  def pi = RCAS::PI

  # A finite real Float, or nil.
  def real(e)
    v = RCAS::Expression.lift(e).evalf
    v = v.value if v.is_a?(RCAS::Num)
    return nil unless v.is_a?(Numeric)
    v = v.real if v.is_a?(Complex) && v.imaginary.abs < 1e-12
    v.is_a?(Complex) || !v.finite? ? nil : v.to_f
  rescue StandardError, Math::DomainError
    nil
  end

  # The members of a solution list: points, and each family over its OWN
  # parameter domain (k in -5..5 over ZZ, 0..10 over NN).
  def members(solutions)
    solutions.flat_map do |s|
      next [s] unless s.is_a?(RCAS::ImageSet)
      ks = s.domain == RCAS::NN ? (0..10) : (-5..5)
      ks.map { |k| s.at(k) }
    end.map { |m| real(m) }
  end

  def includes?(set, v) = set.include?(v)

  # x**2 < pi is -sqrt(pi) < x < sqrt(pi), and (x - 1)*(x - sqrt(2)) < 0 is
  # 1 < x < sqrt(2): the roots are real, since pi and 2 are positive. The
  # reviewed revision answered both; 8c10e71 cannot decide that sqrt(pi) is
  # real (Inequalities.real? asks ComplexParts.im, which leaves
  # im(pi**(1/2)) unevaluated, and Infer calls pi**(1/2) complex).
  def test_roots_under_a_radical_of_a_positive_constant_are_real
    s = RCAS.solve(@x**2 < pi, @x)
    assert includes?(s, n(Rational(17, 10))), "#{s} misses 1.7 (1.7**2 = 2.89 < pi)"
    refute includes?(s, n(Rational(18, 10))), "#{s} contains 1.8 (1.8**2 = 3.24 > pi)"
    s = RCAS.solve((@x - 1) * (@x - RCAS.sqrt(2)) < 0, @x)
    assert includes?(s, n(Rational(6, 5))), "#{s} misses 1.2"
    refute includes?(s, n(Rational(3, 2))), "#{s} contains 1.5 > sqrt(2)"
    d = RCAS.real_domain(RCAS.sqrt(pi - @x**2), @x)
    assert includes?(d, n(Rational(17, 10))), "real_domain #{d} misses 1.7"
  end

  # (x**2 - 1)/(x - 1) = x + 1 holds for every x but 1, where the left side
  # has no value - over RR and over ZZ alike. `everywhere` returns a
  # declared domain as it is, before the poles are taken out.
  def test_an_identity_over_a_declared_domain_keeps_out_the_poles
    f = eq((@x**2 - 1) / (@x - 1), @x + 1)
    r = begin
      RCAS.solve(f, @x, domain: RCAS::RR)
    rescue NotImplementedError, RCAS::Unsupported
      nil
    end
    refute r.include?(n(1)), "domain RR: #{r} contains the pole 1" if r
    r = begin
      RCAS.assume(x: RCAS::ZZ) { RCAS.solve(f, @x) }
    rescue NotImplementedError, RCAS::Unsupported
      nil
    end
    refute r.include?(n(1)), "x in ZZ: #{r} contains the pole 1" if r
  end

  # log(x)/log(x) = 1 wherever log(x) is defined and non-zero: never at 0
  # (log(0) has no value) nor at 1. The identity set only takes out the
  # zeros of the denominator, not the points where it is undefined.
  def test_an_identity_keeps_out_points_where_the_equation_is_undefined
    s = RCAS.solve(eq(RCAS.log(@x) / RCAS.log(@x), 1), @x)
    refute s.include?(n(0)), "#{s} contains 0, where log(0) is undefined"
    s = RCAS.solve(eq(RCAS.log(@x + 1) / RCAS.log(@x + 1), 1), @x)
    refute s.include?(n(-1)), "#{s} contains -1, where log(0) is undefined"
  end

  # The surface of revolution of sin(2*pi*x) over 0..1 took 0.09 s on
  # da72570 (a formal integral); on 8c10e71 it runs for minutes, because
  # split_at_kinks now splits |sin(2*pi*x)| at its zeros and each piece goes
  # to the Risch-Norman heuristic, whose rref over rational functions swells
  # (integrate.rb:134-142 -> 1085 -> matrix.rb:408). Performance regression
  # test: 2 s is twenty times the old time.
  def test_performance_surface_of_revolution_of_a_periodic_radius
    th = Thread.new { RCAS.revolution_surface(RCAS.sin(2 * pi * @x), x: 0..1) }
    finished = th.join(2)
    th.kill
    assert finished, 'revolution_surface(sin(2*pi*x), x: 0..1) took more than 2 s'
  end

  # sin(x)/(x**2 - pi**2) vanishes at k*pi for every integer k except +-1,
  # where the denominator vanishes too. The two isolated poles fall in the
  # same residue class; the second split (solve.rb split_at) only matches a
  # family over ZZ and leaves -pi inside a half-family over NN.
  def test_every_isolated_pole_is_taken_out_of_a_family
    [[RCAS.sin(@x) / (@x**2 - pi**2), [Math::PI, -Math::PI]],
     [RCAS.sin(@x) / (@x**2 - 4 * pi**2), [2 * Math::PI, -2 * Math::PI]]].each do |f, poles|
      got = members(RCAS.solve(f, @x)).compact
      poles.each do |p|
        refute got.any? { |m| (m - p).abs < 1e-9 }, "#{f}: the pole #{p} is listed as a zero"
      end
      assert got.any? { |m| m.abs < 1e-9 }, "#{f}: 0 is a zero"
    end
  end

  # 1/abs(x) runs to oo at 0 and to 0 at both infinities; 1/log(x) tends to
  # 0 as x -> oo. rcas cannot take those limits, and asymptotes reads the
  # unevaluated Limit as "no asymptote" (analysis.rb horizontal_asymptotes,
  # runs_away?) - the "cannot is not none" policy. Refusing is fine.
  def test_an_undetermined_limit_is_not_reported_as_no_asymptote
    [[1 / RCAS.abs(@x), :vertical, 0], [1 / RCAS.abs(@x), :horizontal, 0],
     [1 / RCAS.log(@x), :horizontal, 0]].each do |f, kind, value|
      got = begin
        RCAS.asymptotes(f, @x)[kind]
      rescue NotImplementedError, RCAS::Unsupported
        next
      end
      assert got.any? { |v| (real(v) || Float::NAN) == value }, "#{f}: #{kind} #{got.inspect} misses #{value}"
    end
  end

  # |x| = x holds exactly for x >= 0. The case split knows it and says so -
  # in the message of an ArgumentError, where a set was the answer.
  def test_an_abs_identity_on_a_half_line_is_a_set
    s = begin
      RCAS.solve(eq(RCAS.abs(@x), @x), @x)
    rescue NotImplementedError, RCAS::Unsupported
      return pass
    end
    assert s.include?(n(0)) && s.include?(n(5)), "#{s}"
    refute s.include?(n(-1)), "#{s}"
    s = RCAS.solve(eq(RCAS.abs(@x - 1) + RCAS.abs(@x + 1), 2), @x)
    assert s.include?(n(0)) && !s.include?(n(2)), "#{s}"
  end

  # sin(2*pi*x) = 0 means x = k/2; over the integers that is every integer.
  # The family {k/2} is kept whole, so 1/2 is offered as an integer solution.
  def test_an_integer_domain_keeps_only_integers
    s = begin
      RCAS.solve(RCAS.sin(2 * pi * @x), @x, domain: RCAS::ZZ)
    rescue NotImplementedError, RCAS::Unsupported
      return pass
    end
    return pass if s == RCAS::ZZ || s == [RCAS::ZZ]
    members(s).compact.each { |m| assert_in_delta m.round, m, 1e-12, "#{s} offers the non-integer #{m}" }
  end

  # f = sin(x) + g(x)/10**6 with g vanishing at the four sample points and
  # at their shifts by 2*pi: f(x + 2*pi) = f(x) at exactly those points,
  # which is all Discussion.periodic? looks at. f -> oo at both ends, so it
  # has no period at all.
  def test_a_period_is_not_decided_by_four_samples
    g = [Rational(3, 10), Rational(11, 10), Rational(12, 5), Rational(-7, 10)].map { |p| (@x - p) * (@x - p - 2 * pi) }.reduce(:*)
    report = RCAS.discuss(RCAS.sin(@x) + g / 10**6, @x)
    assert_nil report.period, "a function that tends to oo was given the period #{report.period}"
  end

  # |x| has a corner at 0: no tangent line. d/dx abs(x) at 0 is sign(0) = 0,
  # and tangent answered y = 0. A refusal (as for a vertical tangent) is right.
  def test_no_tangent_at_a_corner
    t = begin
      RCAS.tangent(RCAS.abs(@x), @x, 0)
    rescue ArgumentError, NotImplementedError, RCAS::Unsupported
      return pass
    end
    flunk "tangent(abs(x), x, 0) = #{t}, but abs has a corner at 0"
  end

  # sin(2*x)/sin(x) is 2*cos(x) off the multiples of pi: period 2*pi, zeros
  # pi/2 and 3*pi/2 in each period. discuss lists the zeros of one period
  # and got them from solve(principal: true), whose period is the one of
  # sin(2*x) (pi), not the function's - so 3*pi/2 is lost. Likewise
  # sin(3*x)/sin(x) = 3 - 4*sin(x)**2 (period pi) loses 2*pi/3.
  def test_discuss_lists_every_zero_of_its_period
    [[RCAS.sin(2 * @x) / RCAS.sin(@x), [Math::PI / 2, 3 * Math::PI / 2]],
     [RCAS.sin(3 * @x) / RCAS.sin(@x), [Math::PI / 3, 2 * Math::PI / 3]]].each do |f, wanted|
      report = RCAS.discuss(f, @x)
      period = real(report.period)
      next if report.zeros.nil? || period.nil?
      got = members(report.zeros).compact.map { |z| z % period }
      wanted.each do |w|
        assert got.any? { |z| (z - w % period).abs < 1e-9 || (z - w % period).abs > period - 1e-9 },
               "discuss(#{f}): zeros #{report.zeros.inspect} (period #{report.period}) miss #{w}"
      end
    end
  end
end
