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
end
