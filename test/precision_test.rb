# frozen_string_literal: true

require_relative "test_helper"

class PrecisionTest < Minitest::Test
  include RCAS::Constants

  X = RCAS::Var.new(:x)

  # The first fifty significant digits of pi, and thirty of three others.
  PI50 = "3.1415926535897932384626433832795028841971693993751"
  E30 = "2.71828182845904523536028747135"
  LOG2_30 = "0.693147180559945309417232121458"
  SQRT2_30 = "1.41421356237309504880168872421"

  def test_the_constants
    assert_equal PI50, RCAS.evalf(PI, 50).to_s
    assert_equal E30, RCAS.evalf(RCAS.exp(1), 30).to_s
    assert_equal LOG2_30, RCAS.evalf(RCAS.log(2), 30).to_s
    assert_equal SQRT2_30, RCAS.evalf(RCAS.sqrt(2), 30).to_s
    assert_equal PI50, RCAS.evalf(4 * RCAS.atan(1), 50).to_s, "Machin's constant the long way round"
  end

  def test_the_digits_are_rounded_not_truncated
    assert_equal "3.1415926535897932385", RCAS.evalf(PI, 20).to_s
    assert_equal "3.1416", RCAS.evalf(PI, 5).to_s
    assert_equal "3.0", RCAS.evalf(PI, 1).to_s
    assert_equal 50, RCAS.evalf(PI, 50).digits
  end

  def test_both_spellings_and_bindings
    assert_equal RCAS.evalf(PI, 30), RCAS.evalf(PI, digits: 30)
    assert_equal RCAS.evalf(PI, 30), PI.evalf(30)
    assert_equal "10.0", RCAS.evalf(X**2 + 1, x: 3, digits: 20).to_s
    assert_equal "1.73205080756887729352744634151", RCAS.evalf(RCAS.sqrt(X), x: 3, digits: 30).to_s
  end

  def test_identities_come_out_exactly
    assert_equal "1.0", RCAS.evalf(RCAS.sin(1)**2 + RCAS.cos(1)**2, 40).to_s
    assert_equal "2.0", RCAS.evalf(RCAS.exp(RCAS.log(2)), 40).to_s
    assert_equal "0.0", RCAS.evalf(RCAS.sin(PI), 40).to_s
    assert_equal "0.5", RCAS.evalf(RCAS.sin(PI / 6), 40).to_s, "folded to 1/2 before it ever got here"
    assert_equal "1.0", RCAS.evalf(RCAS.tan(PI / 4), 30).to_s
  end

  def test_exact_input_stays_exact
    assert_equal "0.3333333333333333333333333", RCAS.evalf(Rational(1, 3), 25).to_s
    assert_equal "0.333", RCAS.evalf(Rational(1, 3), 3).to_s
    assert_equal "2.0", RCAS.evalf(2, 5).to_s
    assert_equal "1.0e-20", RCAS.evalf(Rational(1, 10**20), 20).to_s
    assert_equal "-1.0e-20", RCAS.evalf(Rational(-1, 10**20), 20).to_s
  end

  # A Float knows sixteen digits; asking for fifty does not invent more.
  def test_a_float_limits_the_answer
    value = RCAS.evalf(0.1 * PI, 50)
    assert_equal 16, value.digits
    assert_equal "0.3141592653589793", value.to_s
    assert_equal 16, RCAS.evalf(X * PI, x: 0.5, digits: 40).digits
    assert_equal 40, RCAS.evalf(X * PI, x: Rational(1, 2), digits: 40).digits, "a rational does not"
  end

  def test_roots_and_powers
    assert_equal "1.2599210498948731647672106073", RCAS.evalf(RCAS.root(2, 3), 29).to_s
    assert_equal "-2.0", RCAS.evalf(RCAS::Pow.new(RCAS::Num.new(-8), RCAS::Num.new(Rational(1, 3))), 20).to_s
    assert_equal "8.0", RCAS.evalf(2**RCAS::Num.new(3), 20).to_s
    assert_equal "0.125", RCAS.evalf(RCAS::Pow.new(RCAS::Num.new(2), RCAS::Num.new(-3)), 20).to_s
    assert_equal "8.824977827076287623856429604208", RCAS.evalf(2**PI, 31).to_s
  end

  # A real RootOf is refined from its Float value by Newton's method.
  def test_an_algebraic_number
    root = RCAS.solve(X**5 - X - 1, :x).first
    assert_kind_of RCAS::RootOf, root
    assert_equal "1.167303978261418684256045899854842180721", RCAS.evalf(root, 40).to_s
    residual = RCAS.evalf(root**5 - root - 1, 30)
    assert residual.abs < RCAS.evalf(Rational(1, 10**25), 30), "the root really is one: #{residual}"
    assert_equal "1.4142135623730950488016887242", RCAS.evalf(RCAS.solve(X**2 - 2, :x).last, 29).to_s
  end

  def test_a_finite_sum
    assert_equal "1.64393456668156", RCAS.evalf(RCAS.sum(1 / X**2, x: 1..1000), 16).to_s, "a trailing zero is not printed"
    assert_equal E30, RCAS.evalf(RCAS.sum(1 / RCAS.factorial(X), x: 0..30), 30).to_s, "thirty terms of the series for e"
  end

  def test_what_has_no_arbitrary_precision_says_so
    error = assert_raises(RCAS::Precision::Unsupported) { RCAS.evalf(RCAS::Fn.new(:u, [X]), 30, x: 1) }
    assert_includes error.message, "double-precision"
    # an integral with no bounds is not a number
    assert_raises(RCAS::Precision::Unsupported) { RCAS.evalf(RCAS::Integral.new(RCAS.exp(-X**4), X), 30) }
    assert_raises(RCAS::Precision::Unsupported) { RCAS.evalf(RCAS.log(-2), 30) }
    assert_raises(RCAS::Precision::Unsupported) { RCAS.evalf(RCAS.sqrt(-1), 30) }
    assert_raises(RCAS::Precision::Unsupported) { RCAS.evalf(RCAS::Fn.new(:zeta, [RCAS::Num.new(Rational(3, 2))]), 30) }
    assert_raises(RCAS::Precision::Unsupported) { RCAS.evalf(RCAS.exp(10**9), 30) }
    # a series whose cancellation would eat more digits than it can make up
    assert_raises(RCAS::Precision::Unsupported) { RCAS.evalf(RCAS::Fn.new(:Si, [RCAS::Num.new(10_000)]), 30) }
  end

  # The functions BigMath does not have, each to thirty digits.
  def test_the_special_functions
    assert_equal "0.842700792949714869341220635083", RCAS.evalf(RCAS.erf(1), 30).to_s
    assert_equal "0.157299207050285130658779364917", RCAS.evalf(RCAS.erfc(1), 30).to_s
    assert_equal "0.946083070367183014941353313823", RCAS.evalf(RCAS::Fn.new(:Si, [RCAS::Num.new(1)]), 30).to_s
    assert_equal "0.337403922900968134662646203889", RCAS.evalf(RCAS::Fn.new(:Ci, [RCAS::Num.new(1)]), 30).to_s
    assert_equal "1.89511781635593675546652093433", RCAS.evalf(RCAS::Fn.new(:Ei, [RCAS::Num.new(1)]), 30).to_s
    assert_equal "1.04516378011749278484458888919", RCAS.evalf(RCAS::Fn.new(:li, [RCAS::Num.new(2)]), 30).to_s
    assert_equal "1.20205690315959428539973816151", RCAS.evalf(RCAS.zeta(3), 30).to_s, "Apery's constant"
    assert_equal RCAS.evalf(PI**2 / 6, 30), RCAS.evalf(RCAS.zeta(2), 30), "the even ones go through pi"
    # Euler's constant, which Ci and Ei are built on
    assert_equal "0.57721566490153286060651209008240243104215933593992",
                 RCAS::Precision.euler_gamma(60).mult(1, 50).to_s("F")
  end

  # The series and the quadrature are different methods; where they meet is
  # the check that either of them is right.
  def test_the_series_agree_with_the_integrals_that_define_them
    t = RCAS::Var.new(:t)
    digits = 25
    pairs = {
      "Si(1)" => [RCAS::Fn.new(:Si, [RCAS::Num.new(1)]), RCAS::Integral.new(RCAS.sin(t) / t, t, RCAS::Num.new(0), RCAS::Num.new(1))],
      "erf(1)" => [RCAS.erf(1), 2 / RCAS.sqrt(PI) * RCAS::Integral.new(RCAS.exp(-t**2), t, RCAS::Num.new(0), RCAS::Num.new(1))],
      "-Ei(-1)" => [-RCAS::Fn.new(:Ei, [RCAS::Num.new(-1)]), RCAS::Integral.new(RCAS.exp(-t) / t, t, RCAS::Num.new(1), RCAS::OO)],
      "zeta(3)" => [RCAS.zeta(3), RCAS::Integral.new(t**2 / (RCAS.exp(t) - 1), t, RCAS::Num.new(0), RCAS::OO) / 2]
    }
    pairs.each do |name, (series, integral)|
      difference = RCAS.evalf(series, digits) - RCAS.evalf(integral, digits)
      assert difference.abs < RCAS.evalf(Rational(1, 10**(digits - 2)), digits),
             "#{name}: the series and the integral differ by #{difference}"
    end
  end

  def test_quadrature_to_thirty_digits
    assert_equal "0.78539816339744830961566084582", RCAS.nintegrate(1 / (1 + X**2), x: 0..1, digits: 30).to_s
    assert_equal "2.0", RCAS.nintegrate(1 / RCAS.sqrt(X), x: 0..1, digits: 30).to_s, "a singular endpoint"
    assert_equal "-1.0", RCAS.nintegrate(RCAS.log(X), x: 0..1, digits: 30).to_s
    assert_equal "0.886226925452758013649083741671", RCAS.nintegrate(RCAS.exp(-X**2), x: 0..RCAS::OO, digits: 30).to_s
    assert_equal RCAS.evalf(PI, 30), RCAS.nintegrate(1 / (1 + X**2), x: -RCAS::OO..RCAS::OO, digits: 30)
    assert_instance_of Float, RCAS.nintegrate(1 / (1 + X**2), x: 0..1), "without digits nothing changes"
  end

  def test_roots_to_forty_digits
    root = RCAS.nsolve(RCAS.cos(X) - X, x: 0..1, digits: 40)
    assert_equal "0.7390851332151606416553120876738734040134", root.to_s
    assert RCAS.evalf(RCAS.cos(X) - X, 40, x: root).abs < RCAS.evalf(Rational(1, 10**38), 40)
    assert_equal "1.25992104989487316476721060727822835057", RCAS.nsolve(X**3 - 2, x: 1..2, digits: 40).to_s
    assert_instance_of Float, RCAS.nsolve(X**3 - 2, x: 1..2), "without digits nothing changes"
  end

  def test_arguments_are_checked
    assert_raises(ArgumentError) { RCAS.evalf(PI, 0) }
    assert_raises(ArgumentError) { RCAS.evalf(PI, -5) }
    error = assert_raises(ArgumentError) { RCAS.evalf(X + 1, 20) }
    assert_includes error.message, "x has no value"
    assert_raises(ZeroDivisionError) { RCAS.evalf(1 / (X - 2), x: 2, digits: 20) }
  end

  def test_the_decimal_is_a_number
    d = RCAS.evalf(PI, 30)
    assert_kind_of Numeric, d
    assert_equal "4.14159265358979323846264338328", (d + 1).to_s
    assert_equal "6.28318530717958647692528676656", (2 * d).to_s, "coercion from the left"
    assert_equal "1.04719755119659774615421446109", (d / 3).to_s
    assert_equal "0.0", (d - d).to_s
    assert d > 3
    assert d < Rational(22, 7)
    assert_in_delta Math::PI, d.to_f, 1e-15
    assert_equal 16, (d + 0.5).digits, "a Float drags it down"
    assert_equal RCAS::RR, RCAS::NumberSet.of(d)
    assert_equal "3.14159265358979323846264338328", RCAS::LaTeX.of(d)
  end

  def test_a_decimal_goes_back_into_an_expression
    d = RCAS.evalf(PI, 30)
    e = (RCAS::Num.new(d) * X).simplify
    assert_equal "3.14159265358979323846264338328*x", e.to_s
    assert_equal "6.28318530717958647692528676656", e.call(x: 2).to_s
    assert_equal "-3.14159265358979323846264338328", RCAS::Num.new(-d).to_s
  end
  # keep = digits - (integer digits) counted only the part before the point,
  # so the zeros after it ate the budget: evalf(1/3000, 20) had 17 digits.
  def test_a_number_below_one_keeps_all_its_digits
    assert_equal "0.00033333333333333333333", RCAS.evalf(RCAS::Num.new(Rational(1, 3000)), 20).to_s
    assert_equal "0.000031415926535897932385", RCAS.evalf(PI / 100_000, 20).to_s
    assert_equal "0.33333333333333333333", RCAS.evalf(RCAS::Num.new(Rational(1, 3)), 20).to_s
    assert_equal "-0.00033333333333333333333", RCAS.evalf(RCAS::Num.new(Rational(-1, 3000)), 20).to_s
    # and the last digit is rounded, not cut off
    assert_equal "0.66667", RCAS.evalf(RCAS::Num.new(Rational(2, 3)), 5).to_s
    assert_equal "1.0", RCAS.evalf(RCAS::Num.new(Rational(99_999, 100_000)), 4).to_s
  end

end
