# Algebra review: each test states a mathematical property that rcas violates.
require_relative 'test_helper'
require 'rcas'

class ReviewAlgebraTest < Minitest::Test
  def setup
    @x, @y, @a = %i[x y a].map { |n| RCAS::Var.new(n) }
  end
  def teardown = RCAS.forget
  def n(v) = RCAS::Num.new(v)

  # The numeric value of a constant expression as a Complex.
  def value(e)
    v = RCAS::Expression.lift(e).evalf
    v = v.value if v.is_a?(RCAS::Num)
    assert_kind_of Numeric, v, "#{e} does not evaluate to a number"
    Complex(v)
  end

  # Principal values by hand, for the logarithms evalf leaves alone (log(-1.0)).
  def principal(e)
    case e
    when RCAS::Num then Complex(e.value)
    when RCAS::Const then Complex(e.value.to_f)
    when RCAS::Neg then -principal(e.arg)
    when RCAS::Add then principal(e.left) + principal(e.right)
    when RCAS::Sub then principal(e.left) - principal(e.right)
    when RCAS::Mul then principal(e.left) * principal(e.right)
    when RCAS::Div then principal(e.left) / principal(e.right)
    when RCAS::Pow then clog_exp(principal(e.right) * clog(principal(e.left)))
    when RCAS::Fn
      raise "no principal value for #{e.name}" unless e.name == :log && e.args.size == 1
      clog(principal(e.args.first))
    else raise "no principal value for #{e.class}"
    end
  end
  def clog(z) = Complex(Math.log(z.abs), Math.atan2(z.imaginary.to_f, z.real.to_f))
  def clog_exp(z) = Math.exp(z.real) * Complex(Math.cos(z.imaginary), Math.sin(z.imaginary))

  def assert_principal(expected, e)
    assert_in_delta 0, (principal(e) - Complex(expected)).abs, 1e-9, "#{e}: expected #{expected}"
  end

  def assert_value(expected, e, msg = nil)
    assert_in_delta 0, (value(e) - Complex(expected)).abs, 1e-9, msg || "#{e}: expected #{expected}"
  end

  # i**(1/2) * i = exp(i*pi/4) * exp(i*pi/2) = exp(3*i*pi/4) = (-1 + i)/sqrt(2).
  # The exponents of the unit have to add up; one of them may not overwrite the other.
  def test_exponents_of_the_imaginary_unit_add
    expected = Complex(-1, 1) / Math.sqrt(2)
    half = RCAS::I**Rational(1, 2)
    assert_value expected, RCAS.simplify(half * RCAS::I)
    assert_value 3 * expected, RCAS.simplify(3 * RCAS::I * half)
    assert_value expected, RCAS.expand(RCAS::I * (@x + half)).subs(x: 0)
  end

  # GF(9) = GF(3)[b]/(b**2 + 1), so x**2 + 1 has the two roots b and -b there.
  def test_roots_over_an_extension_field
    k = RCAS.GF(9)
    roots = k[:x].call(@x**2 + 1).roots
    assert_equal 2, roots.size
    roots.each { |r| v = r.is_a?(RCAS::Num) ? r.value : r; assert_predicate v * v + 1, :zero? }
  end
end
