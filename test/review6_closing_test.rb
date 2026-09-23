# frozen_string_literal: true

require_relative "test_helper"

# Closing the fifth round (23 Sept 2026): the items the preflight for the
# sixth review had left open and that could be fixed without a design
# decision. Each test is an answer that was refused or wrong before.
class Review6ClosingTest < Minitest::Test
  def setup
    @x, @a, @b = %i[x a b].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  # ---- solve: powers of one base --------------------------------------------

  # 4**x is (2**x)**2, so this is t**2 - 3*t + 2 in t = 2**x; it was refused.
  def test_powers_of_one_base_are_a_polynomial_in_it
    assert_equal [n(0), n(1)], RCAS.solve(4**@x - 3 * 2**@x + 2, @x, domain: RCAS::RR)
    assert_equal [n(0), n(1)], RCAS.solve(9**@x - 4 * 3**@x + 3, @x, domain: RCAS::RR)
    assert_equal [n(0), n(1)], RCAS.solve(2**(2 * @x) - 3 * 2**@x + 2, @x, domain: RCAS::RR)
    assert_equal [n(1)], RCAS.solve(4**(@x / 2r) + 2**@x - 4, @x, domain: RCAS::RR)
    assert_equal [n(0)], RCAS.solve(n(1/2r)**@x - 2**@x, @x, domain: RCAS::RR)
    assert_equal [], RCAS.solve(4**@x + 2**@x + 1, @x, domain: RCAS::RR)
  end

  # Complete over CC, as decision 3 asks: every member solves the equation.
  def test_powers_of_one_base_are_complete_over_cc
    families = RCAS.solve(4**@x - 3 * 2**@x + 2, @x)
    assert_equal 2, families.size
    families.each do |family|
      assert_kind_of RCAS::ImageSet, family
      (-2..2).each do |k|
        value = (4**@x - 3 * 2**@x + 2).subs(x: family.at(k)).evalf
        assert_in_delta 0, value.abs, 1e-9
      end
    end
  end

  # ---- Decide: logs of rationals --------------------------------------------

  # The logs of distinct primes are independent over QQ, so writing each
  # log of a rational over its primes proves these zero; they had been
  # undecided, and an undecided constant pivot counts as non-zero.
  def test_logs_of_rationals_are_decided_over_their_primes
    l = ->(v) { RCAS.log(n(v)) }
    assert_equal true, RCAS::Decide.zero?(l[6] - l[2] - l[3])
    assert_equal true, RCAS::Decide.zero?(l[12] - 2 * l[2] - l[3])
    assert_equal true, RCAS::Decide.zero?(l[3/4r] + 2 * l[2] - l[3])
    assert_equal false, RCAS::Decide.zero?(l[6] - l[2] - l[5])
    solution = RCAS.solve([(l[6] - l[2] - l[3]) * @x + RCAS::Var.new(:y) - 1, @x + RCAS::Var.new(:y) - 2], %i[x y])
    assert_equal [{ @x => n(1), RCAS::Var.new(:y) => n(1) }], solution
  end

  # ---- nsolve ---------------------------------------------------------------

  # The expanded ninth power is Float noise for |x - 1| < 0.05, and the
  # bisection followed the noise to 0.985; exact signs put it back at 1.
  def test_nsolve_is_not_led_by_float_noise
    f = RCAS.expand((@x - 1)**9)
    [0..3, 0.5..1.2, 0.9..1.3, -2..5].each do |range|
      assert_in_delta 1.0, RCAS.nsolve(f, x: range), 1e-12, range.inspect
    end
  end

  # Two values of 1e-165 multiply to 0, and that "sign change" made the
  # bisection stop at 0.9999 and call the root a jump.
  def test_nsolve_finds_a_root_of_high_order
    [41, 301].each do |k|
      assert_in_delta 1.0, RCAS.nsolve((@x - 1)**k, x: 0..3), 1e-12, k.to_s
    end
  end

  # ---- special parameter values ---------------------------------------------

  # b - a and a + b are denominators in two parameters: a = b and a = -b
  # are branches, each with the special value b = 0 of its own.
  def test_special_values_in_two_parameters
    f = RCAS.sin(@a * @x) * RCAS.cos(@b * @x)
    found = RCAS.integrate(f, @x)
    assert_kind_of RCAS::Piecewise, found
    [[1, 1], [1, -1], [0, 0], [2, 3], [0, 2], [-3, 3]].each do |a, b|
      antiderivative = found.subs(a: a, b: b)
      derivative = RCAS.diff(antiderivative, @x).subs(x: n(7/10r)).evalf
      assert_in_delta Math.sin(a * 0.7) * Math.cos(b * 0.7), derivative, 1e-10, [a, b].inspect
    end
    assert_equal "piecewise(a.eq(-1 - b) => log(x), :else => x**(1 + a + b)/(1 + a + b))",
                 RCAS.integrate(@x**(@a + @b), @x).to_s
  end

  # cos(a*x) over 0..pi is sin(pi*a)/a, which has no value at a = 0.
  def test_special_values_of_a_definite_integral
    assert_equal "piecewise(a.eq(0) => pi, :else => sin(pi*a)/a)",
                 RCAS.integrate(RCAS.cos(@a * @x), @x, 0, RCAS::PI).to_s
    assert_equal "piecewise(a.eq(0) => 1, :else => -1/a + exp(a)/a)",
                 RCAS.integrate(RCAS.exp(@a * @x), x: 0..1).to_s
    assert_equal "piecewise(a.eq(-1) => log(2), :else => -1/(1 + a) + 2*2**a/(1 + a))",
                 RCAS.integrate(@x**@a, @x, 1, 2).to_s
    assert_equal "sin(pi*a)/a", RCAS.integrate(RCAS.cos(@a * @x), @x, 0, RCAS::PI, generic: true).to_s
  end
end
