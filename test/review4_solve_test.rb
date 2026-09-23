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
    rescue NotImplementedError
      nil
    end
    refute r.include?(n(1)), "domain RR: #{r} contains the pole 1" if r
    r = begin
      RCAS.assume(x: RCAS::ZZ) { RCAS.solve(f, @x) }
    rescue NotImplementedError
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
end
