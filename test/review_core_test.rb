# Core review: invariants of the expression layer, each derived independently.
require_relative 'test_helper'
require 'rcas'

class ReviewCoreTest < Minitest::Test
  def setup
    @x, @y, @w = %i[x y w].map { |n| RCAS::Var.new(n) }
  end
  def teardown = RCAS.forget
  def n(v) = RCAS::Num.new(v)

  # The value of a constant expression as a Complex, or nil when it stays symbolic.
  def value(e)
    v = RCAS::Expression.lift(e).evalf
    v = v.value if v.is_a?(RCAS::Num)
    v.is_a?(Numeric) ? Complex(v) : nil
  end

  def assert_value(expected, e, msg = nil)
    v = value(e)
    refute_nil v, "#{e} did not evaluate to a number #{msg}"
    assert_in_delta 0, (v - expected).abs, 1e-9, "#{e} = #{v}, expected #{expected} #{msg}"
  end

  def test_a_tiny_complex_coefficient_is_not_zero
    # i*exp(-40)*x = 1 has the single solution x = -i*exp(40); the
    # coefficient has modulus e**-40 != 0.
    c = RCAS::I * RCAS.exp(-40)
    refute RCAS::Scalar.zero?(c)
    roots = RCAS.solve(c * @x - 1, @x)
    assert_equal 1, roots.size
    assert_value 1, (c * roots.first).simplify
  end

  def test_substitution_leaves_bound_variables_alone
    # In integral_0^1 f(x) dx and sum_{x=1}^n f(x) the x is bound: the value
    # does not depend on x, so substituting for it changes nothing, and x is
    # not among the free variables.
    f = RCAS::Fn.new(:f, [@x])
    definite = RCAS::Integral.new(f, @x, n(0), n(1))
    assert_equal definite, definite.subs(x: 3)
    refute_includes definite.variables, :x
    total = RCAS::Sum.new(f, @x, n(1), RCAS::Var.new(:n))
    assert_equal total, total.subs(x: 3)
  end

  def test_substitution_does_not_capture_a_free_variable
    # integral_0^1 y*f(x) dx with y := x is x * integral_0^1 f(t) dt; writing
    # integral_0^1 x*f(x) dx instead integrates the new x as well.
    f = RCAS::Fn.new(:f, [@x])
    got = RCAS::Integral.new(@y * f, @x, n(0), n(1)).subs(y: @x)
    refute_equal RCAS::Integral.new(@x * f, @x, n(0), n(1)), got
  end

  def test_abs_of_an_even_power_needs_a_real_base
    # y is not declared real. At y = 2i: y**2 + 1 = -3, so |y**2 + 1| = 3 and
    # sqrt((y**2 + 1)**2) = sqrt(9) = 3; at y = i: |y**2| = |-1| = 1.
    two_i = n(Complex(0, 2))
    assert_value 3, RCAS.abs(@y**2 + 1).simplify.subs(y: two_i).simplify
    assert_value 3, RCAS.sqrt((@y**2 + 1)**2).simplify.subs(y: two_i).simplify
    assert_value 1, RCAS.abs(@y**2).simplify.subs(y: RCAS::I).simplify
  end

  def test_log_of_zero_is_not_a_real_number
    # log(0) has no value (its limit is -oo), so it is not a member of RR,
    # and log(x) for x in NN is not real at x = 0.
    refute RCAS.log(0).in?(RCAS::RR)
    RCAS.assume(x: RCAS::NN) do
      d = RCAS.log(@x).domain
      refute d && d <= RCAS::RR, "log(x) for x in NN inferred as #{d}"
    end
  end

  def test_numeric_evaluation_of_principal_complex_values
    # Principal values: log(-2) = log(2) + i*pi, and at z = 1/2 + i/4
    # log(z) = log|z| + i*atan2(1/4, 1/2), tan(z) = sin(z)/cos(z).
    assert_value Complex(Math.log(2), Math::PI), RCAS.log(-2)
    z = Complex(0.5, 0.25)
    log_z = Complex(Math.log(z.abs), Math.atan2(0.25, 0.5))
    assert_value log_z, RCAS.log(@x).evalf(x: z)
    sin = Complex(Math.sin(0.5) * Math.cosh(0.25), Math.cos(0.5) * Math.sinh(0.25))
    cos = Complex(Math.cos(0.5) * Math.cosh(0.25), -Math.sin(0.5) * Math.sinh(0.25))
    assert_value sin / cos, RCAS.tan(@x).evalf(x: z)
  end

  def test_logarithm_of_a_square_respects_a_negative_sign
    # For y < 0, log(y**2) is the real number 2*log|y|, while 2*log(y) has
    # imaginary part 2*pi. At y = -2 the value is log(4).
    # (Compared through Scalar.zero? rather than evalf, which leaves a log of
    # a negative number symbolic - a separate finding.)
    RCAS.assume(@y < 0) do
      got = RCAS.expand_log(RCAS.log(@y**2))
      assert RCAS::Scalar.zero?((got - RCAS.log(4)).subs(y: -2).simplify), "expand_log gave #{got}"
      combined = RCAS.logcombine(2 * RCAS.log(@y))
      assert RCAS::Scalar.zero?((combined - 2 * RCAS.log(@y)).subs(y: -2).simplify), "logcombine gave #{combined}"
    end
  end

  def test_gamma_at_a_pole_does_not_raise_a_math_error
    # gamma has a pole at -3; the answer may be a node, oo or undefined, but
    # Math::DomainError is an internal error that must not reach the user.
    begin
      RCAS.gamma(n(-3.0))
      RCAS.gamma(@x).evalf(x: -3)
    rescue Math::DomainError => e
      flunk "Math::DomainError escaped: #{e.message}"
    end
    pass
  end

  def test_popcorn_reads_back_a_double_negation
    # -(-x) is x; whatever POPCORN writes for it must parse to that value.
    [RCAS::Neg.new(RCAS::Neg.new(@x)), RCAS::Neg.new(n(-2))].each do |e|
      back = RCAS.from_popcorn(RCAS.popcorn(e))
      assert RCAS::Scalar.zero?((back - e).simplify), "#{e} came back as #{back}"
    end
  end

  def test_a_held_equation_can_be_evaluated
    # integral(x**2, x) = x evaluates to the equation x**3/3 = x.
    eq = RCAS::Equation.new(RCAS::Integral.new(@x**2, @x), @x)
    got = eq.doit
    assert_kind_of RCAS::Equation, got
    assert RCAS::Scalar.zero?((got.lhs - @x**3 / 3).simplify)
  end

  def test_expand_is_idempotent_on_negative_powers
    # (x + y)**-2 and 1/(x + y)**2 are the same expression; expand is a
    # normal form, so it gives them one answer and is its own fixed point.
    e = RCAS.expand((@x + @y)**-2)
    assert_equal e, RCAS.expand(e)
    assert_equal RCAS.expand(1 / (@x + @y)**2), e
  end

  def test_derivative_of_a_root_of_zero_is_zero
    # sqrt(y - y) is the constant 0, so its derivative in x is 0.
    assert_equal n(0), RCAS.diff(RCAS.sqrt(@y - @y), @x)
  end

  def test_eql_expressions_have_equal_hashes
    # Ruby's contract: a.eql?(b) implies a.hash == b.hash.
    a = RCAS::Fn.new(:sin, [n(1)])
    b = RCAS::Fn.new(:sin, [n(1.0)])
    c = RCAS::Add.new(@x, n(1))
    d = RCAS::Add.new(@x, n(1.0))
    assert_equal a.hash, b.hash, "sin(1) and sin(1.0) are eql?" if a.eql?(b)
    assert_equal c.hash, d.hash, "x + 1 and x + 1.0 are eql?" if c.eql?(d)
    refute a.eql?(b) && a.hash != b.hash
  end

  def test_membership_of_a_constant_that_is_an_integer
    # sqrt(2)**2 = 2 and pi - pi = 0 are integers.
    assert (RCAS.sqrt(2)**2).in?(RCAS::ZZ)
    assert (RCAS::PI - RCAS::PI).in?(RCAS::ZZ)
  end
end
