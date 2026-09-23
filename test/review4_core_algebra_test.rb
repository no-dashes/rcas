# Second review round, core and algebra: properties the fixes of the third
# review still violate, each derived independently.
require_relative 'test_helper'
require 'rcas'

class Review2CoreAlgebraTest < Minitest::Test
  def setup
    @x, @y = %i[x y].map { |n| RCAS::Var.new(n) }
  end
  def teardown = RCAS.forget
  def n(v) = RCAS::Num.new(v)
  def l(v) = RCAS::Expression.lift(v)

  def value(e)
    v = RCAS::Expression.lift(e).evalf
    v = v.value if v.is_a?(RCAS::Num)
    v.is_a?(Numeric) ? Complex(v) : nil
  end

  def assert_value(expected, e, msg = nil)
    v = value(e)
    refute_nil v, "#{e} did not evaluate to a number #{msg}"
    assert_in_delta 0, (v - expected).abs, 1e-9 * (1 + expected.abs), "#{e} = #{v}, expected #{expected} #{msg}"
  end

  # exp(u) - 1 = u + u**2/2 + ... > 0 for u = 10**-100, and 1 - cos(u) =
  # u**2/2 - ... > 0 for u = 10**-50. Two evaluations that both round to 0
  # are not a proof of zero: Decide returns :zero when the 30- and 60-digit
  # values are both exactly 0 (decide.rb, precise_sign), so t*x = 1 has "no
  # solution" and diag(t, 1) is singular.
  def test_a_constant_below_the_working_precision_is_not_zero
    t = RCAS.exp(l(10)**-100) - 1
    refute_equal true, RCAS::Decide.zero?(t), 'exp(10**-100) - 1 is about 1e-100, not 0'
    refute_equal :zero, RCAS::Decide.sign(RCAS.cos(l(10)**-50) - 1), '1 - cos(1e-50) is about 5e-101'
    refute RCAS::Scalar.zero?(t)
    assert_equal 1, RCAS.solve(t * @x - 1, @x).size, 'x = 1/(exp(10**-100) - 1) solves t*x = 1'
    assert_equal 2, RCAS.matrix([[t, 0], [0, 1]]).rank
  end

  # Decide.zero? says nil (undecided) for gamma(1/3) - gamma(1/3)*(1 + 10**-30)
  # = -gamma(1/3)/10**30, and Scalar.vanishes? turns nil into true - the
  # undecided-counts-as-zero bias the review named, still in scalar.rb. The
  # equation w*x = 1 has the solution x = 1/w.
  def test_an_undecided_constant_is_not_taken_for_zero
    g = RCAS.gamma(l(1) / 3)
    w = g - g * (1 + l(10)**-30)
    refute RCAS::Scalar.zero?(w), 'gamma(1/3)/10**30 is not 0'
    refute_empty RCAS.solve(w * @x - 1, @x)
  end

  # arg of a positive real number is 0. exp(10**-100) - 1 is positive, and
  # arg answered undefined - the value of arg(0) - because Decide took it
  # for zero (complex_parts.rb, arg). The old revision gave 0.0.
  def test_the_argument_of_a_tiny_positive_number_is_zero
    t = RCAS.exp(l(10)**-100) - 1
    refute_equal RCAS::UNDEFINED, RCAS.arg(t)
    assert_value 0, RCAS.arg(t)
    assert_value Math::PI / 2, RCAS.arg(RCAS::I * t)
  end

  # |a**z| = a**re(z) for a > 0, so |2**i| = 1 and |2**(1 + i)| = 2, and
  # sign(2**i) = 2**i/|2**i| = 2**i, not 1. expression_sign calls any power
  # of a positive base positive, whatever the exponent (domains.rb,
  # expression_sign, Pow) - the even-power fix (C1) left the other branch.
  def test_a_positive_base_with_a_complex_exponent_is_not_positive
    assert_value 1, RCAS.abs(l(2)**RCAS::I).simplify
    assert_value 2, RCAS.abs(l(2)**(1 + RCAS::I)).simplify
    RCAS.assume(@x > 0) do
      assert_value 1, RCAS.abs(@x**RCAS::I).simplify.subs(x: 2)
      refute_equal n(1), RCAS.sign(@x**RCAS::I).simplify, 'sign(x**i) is x**i, of modulus 1, not 1'
    end
    # an undeclared exponent may be complex too: |2**y| at y = i is 1, not 2**i
    assert_value 1, RCAS.abs(l(2)**@y).simplify.subs(y: RCAS::I)
  end

  # For x in NN the value x = 0 is allowed, where 1/x and x**(-1/2) have no
  # value - the reason log(x) is no longer inferred real there (C5). The
  # powers still are: 1/x is inferred QQ and x**(-1/2) RR.
  def test_a_negative_power_of_a_natural_number_has_no_value_at_zero
    RCAS.assume(x: RCAS::NN) do
      d = (@x**(-1 / 2r)).domain
      refute d && d <= RCAS::RR, "x**(-1/2) for x in NN inferred as #{d}"
      d = (1 / @x).domain
      refute d && d <= RCAS::QQ, "1/x for x in NN inferred as #{d}"
    end
  end

  # cos(10**-30) - 1 = -5e-61 < 0 and sin(1) - sin(1 + 10**-20) =
  # -cos(1)*10**-20 + ... < 0, so c*x -> -oo as x -> oo. Limits read the
  # sign of the leading coefficient off a Float (series.rb, signed_infinity:
  # `c.evalf`), which is 0.0 or noise here - a private Float decision the
  # Decide policy was meant to end. (Outside core; found on the way.)
  def test_the_sign_of_a_tiny_leading_coefficient_is_decided
    [RCAS.cos(l(10)**-30) - 1, RCAS.sin(l(1)) - RCAS.sin(1 + l(10)**-20)].each do |c|
      r = begin
        RCAS.limit(c * @x, @x, RCAS::OO)
      rescue RCAS::SeriesError, NotImplementedError
        :refused
      end
      assert(r == :refused || r.is_a?(RCAS::Limit) || r == (-RCAS::OO).simplify, "limit(#{c}*x, x, oo) = #{r.inspect}")
    end
  end
end
