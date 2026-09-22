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

  # log(-1) = i*pi on the principal branch, so 2*log(-1) = 2*i*pi, -log(-1) = -i*pi
  # and 3*log(i) = 3*i*pi/2; log(1), log(-1) and log(-i) are 0, i*pi and -i*pi/2.
  def test_logcombine_keeps_the_value
    pi = Math::PI
    assert_principal Complex(0, 2 * pi), RCAS.logcombine(2 * RCAS.log(-1))
    assert_principal Complex(0, -pi), RCAS.logcombine(-RCAS.log(-1))
    assert_principal Complex(0, 3 * pi / 2), RCAS.logcombine(3 * RCAS.log(RCAS::I))
  end

  # For x < 0, log(x**2) is real while 2*log(x) = 2*log|x| + 2*i*pi.
  # At x = -1: log(1) = 0, not 2*i*pi.
  def test_expand_log_respects_a_declared_negative_sign
    RCAS.assume(@x < 0) do
      assert_principal 0, RCAS.expand_log(RCAS.log(@x**2)).subs(x: -1)
    end
  end

  # Declaring x an integer says what values x takes; x is still an indeterminate,
  # so x**2 - 1 = (x - 1)(x + 1) and gcd(a*x, a) = a as without the declaration.
  def test_declared_domain_keeps_the_indeterminate_in_the_polynomial_ring
    RCAS.assume(x: RCAS::ZZ) do
      f = RCAS.factor(@x**2 - 1)
      assert_equal n(0), RCAS.expand(f - (@x**2 - 1))
      assert_equal 2, RCAS::QQ[:x].call(@x**2 - 1).factor.size
      assert_equal n(0), RCAS.expand(RCAS.gcd(@x**2 - 1, @x + 1) - (@x + 1))
    end
    RCAS.assume(a: RCAS::ZZ) do
      f = RCAS.factor(@x**2 - @a**2)
      assert_equal n(0), RCAS.expand(f - (@x**2 - @a**2))
      assert_equal n(0), RCAS.expand(RCAS.gcd(@a * @x, @a) - @a)
    end
  end

  # x*exp(x) is not a polynomial in x, so it has no degree in x; exp(x) is not the
  # constant coefficient of exp(x). A refusal is fine, the value 1 is not.
  def test_an_indeterminate_in_an_exponent_is_not_a_coefficient
    { -> { RCAS.degree(@x * RCAS.exp(@x), @x) } => n(1).value,
      -> { RCAS.coeff(RCAS.exp(@x), @x, 0) } => RCAS.exp(@x),
      -> { RCAS.coeff(@x * n(2)**@x, @x, 1) } => n(2)**@x,
      -> { RCAS.lcoeff(RCAS.exp(@x) * @x**3 + @x, @x) } => RCAS.exp(@x) }.each do |call, wrong|
      begin
        result = call.call
      rescue RCAS::DomainError, NotImplementedError
        next
      end
      refute_equal wrong, result
    end
  end

  # sqrt(m**2 + 1) = [m; 2m, 2m, 2m, ...], and pi = [3; 7, 15, 1, 292, 1, 1, 1, 2,
  # 1, 3, 1, 14, 2, 1, 1, 2, 2, 2, 2, ...] (OEIS A001203): exact numbers, exact terms.
  def test_continued_fraction_of_an_irrational_is_exact
    assert_equal [1000] + [2000] * 29, RCAS.continued_fraction(RCAS.sqrt(1_000_001), 30)
    assert_equal [3, 7, 15, 1, 292, 1, 1, 1, 2, 1, 3, 1, 14, 2, 1, 1, 2, 2, 2, 2],
                 RCAS.continued_fraction(RCAS::PI, 20)
  end

  # |1 + i| = sqrt(2) and |3 + 4i| = 5: exact input, exact output.
  def test_modulus_of_an_exact_complex_number_is_exact
    [[1 + RCAS::I, 2], [3 + 4 * RCAS::I, 25], [Rational(1, 2) + RCAS::I / 2, Rational(1, 2)]].each do |z, square|
      m = RCAS.abs(z)
      refute_kind_of Float, (m.is_a?(RCAS::Num) ? m.value : m), "abs(#{z}) is a Float"
      assert_equal n(square), (m**2).simplify
    end
  end

  # arg(1 - sqrt(3)*i) = -pi/3 and arg(-sqrt(3) + i) = 5*pi/6 (tan = -sqrt(3), -1/sqrt(3));
  # arg(0) has no value. None of them is a silent Float.
  def test_argument_of_an_exact_complex_number_is_exact
    s3 = RCAS.sqrt(3)
    { 1 - s3 * RCAS::I => -Math::PI / 3, -s3 + RCAS::I => 5 * Math::PI / 6 }.each do |z, angle|
      a = RCAS.arg(z)
      refute_kind_of Float, (a.is_a?(RCAS::Num) ? a.value : a), "arg(#{z}) is a Float"
      assert_value angle, a
    end
    begin
      zero = RCAS.arg(0)
    rescue RCAS::DomainError, ArgumentError, ZeroDivisionError
      return
    end
    refute_kind_of Float, (zero.is_a?(RCAS::Num) ? zero.value : zero), 'arg(0) is a Float'
  end

  # The unit group mod 2 is {1}, cyclic of order 1 = totient(2): its generator is 1.
  def test_two_has_a_primitive_root
    assert_equal 1, RCAS.primitive_root(2)
  end

  # A rational q is algebraic of degree 1: its minimal polynomial is x - q.
  def test_a_rational_number_has_a_minimal_polynomial
    m = RCAS.minpoly(n(Rational(1, 2)))
    assert_equal 1, RCAS.degree(m, @x)
    assert_equal n(0), m.subs(x: Rational(1, 2)).simplify
  end

  # sqrt(1 + sqrt(2)) is a root of x**4 - 2*x**2 - 1, so it *is* algebraic. rcas may
  # decline the nested radical, but it may not say the number is not algebraic.
  def test_nested_radical_is_not_called_transcendental
    m = RCAS.minpoly(RCAS.sqrt(1 + RCAS.sqrt(2)))
    assert_equal n(0), RCAS.expand(m - (@x**4 - 2 * @x**2 - 1))
  rescue NotImplementedError
    assert true
  end

  # A constant is a rational function; its partial fraction decomposition is itself.
  def test_partial_fractions_of_a_constant
    assert_equal n(7), RCAS.apart(n(7))
  end
end
