# frozen_string_literal: true

require_relative "test_helper"

class FactorTest < Minitest::Test
  include RCAS::Sets

  def setup
    @r = ZZ[:x]
    @s = ZZ[:x, :y]
  end

  def teardown = RCAS.forget

  def f(expr, ring = @r) = ring.call(expr).factor.to_s

  def test_univariate_over_zz
    assert_equal "(-1 + x)*(1 + x)", f(:x**2 - 1)
    assert_equal "(-1 + x)*(1 + x)*(1 + x**2)", f(:x**4 - 1)
    assert_equal "(-1 + x)*(1 + x)*(1 + x + x**2)*(1 - x + x**2)", f(:x**6 - 1)
    assert_equal "(-1 + x)*(1 + x)*x", f(:x**3 - :x)
    assert_equal "2*(1 + x)**2", f(2 * :x**2 + 4 * :x + 2)
    assert_equal "(-2 + 3*x)*(1 + 2*x)", f(6 * :x**2 - :x - 2)
    assert_equal "(2 + 2*x + x**2)*(2 - 2*x + x**2)", f(:x**4 + 4)
    assert_equal "(1 + x)**5", f((:x + 1)**5)
    assert_equal "(-1 + x)**3*(1 + x)**2*x", f((:x + 1)**2 * (:x - 1)**3 * :x)
    assert_equal "-((-1 + x)*(1 + x)*(1 + x**2)*(1 + x**4))", f(1 - :x**8)
    assert_equal "(-7 + 5*x)*(2 + 3*x)*(1 + x + x**2)", f((3 * :x + 2) * (5 * :x - 7) * (:x**2 + :x + 1))
    assert_equal "(3 + 2*x**2)*(-5 + x**3)*(1 + 2*x + x**3)*(-1 - x + x**4)",
                 f((:x**3 + 2 * :x + 1) * (:x**4 - :x - 1) * (2 * :x**2 + 3) * (:x**3 - 5))
  end

  def test_irreducibles_stay_whole
    assert_equal "1 + x**2", f(:x**2 + 1)
    assert_equal "-2 + x**2", f(:x**2 - 2)
    assert_equal "1 - 10*x**2 + x**4", f(:x**4 - 10 * :x**2 + 1)
    assert_equal "-1 - x + x**5", f(:x**5 - :x - 1)
    assert @r.call(:x**2 + 1).irreducible?
    refute @r.call(:x**2 - 1).irreducible?
  end

  def test_units_and_constants
    assert_equal "6", f(6)
    assert_equal "-1", f(-1)
    assert_equal "0", f(0)
    assert_equal(-3, @r.call(-3 * :x**2 + 3).factor.unit)
    assert_equal "-3*(-1 + x)*(1 + x)", f(-3 * :x**2 + 3)
  end

  def test_over_qq
    q = QQ[:x]
    assert_equal "(1/4)*(-1 + 2*x)*(1 + 2*x)", f(:x**2 - Rational(1, 4), q)
    assert_equal "(1/2)*(-2 + x)*(2 + x)", f(:x**2 / 2 - 2, q)
    fact = q.call(:x**2 - Rational(1, 4)).factor
    assert_equal Rational(1, 4), fact.unit
    assert_equal q, fact.ring
    assert_equal q.call(:x**2 - Rational(1, 4)), fact.expand
  end

  def test_factorization_object
    fact = @r.call(:x**6 - 1).factor
    assert_equal 4, fact.size
    assert_equal 1, fact.unit
    assert_equal [1, 1, 2, 2], fact.map { |g, _| g.degree }
    assert fact.all? { |_, m| m == 1 }
    assert_equal @r.call(:x**6 - 1), fact.expand
    assert_equal [[@r.call(:x), 1], [@r.call(:x + 1), 2], [@r.call(:x - 1), 3]],
                 @r.call((:x + 1)**2 * (:x - 1)**3 * :x).squarefree_decomposition
    assert_equal "(-1 + x)*(1 + x)*x", @r.call((:x + 1)**2 * (:x - 1)**3 * :x).squarefree_part.factor.to_s
  end

  def test_roots
    assert_equal [-1, 0, 1], @r.call(:x**3 - :x).roots
    assert_equal [-3, Rational(1, 2), Rational(1, 2)], QQ[:x].call((2 * :x - 1)**2 * (:x + 3)).roots
    assert_empty @r.call(:x**2 + 1).roots
  end

  def test_multivariate
    assert_equal "(x + y)*(x - y)", f(:x**2 - :y**2, @s)
    assert_equal "(x + y)*(x - y)*(x**2 + y**2)", f(:x**4 - :y**4, @s)
    assert_equal "(x + y)**2*(x - 2*y)", f((:x + :y)**2 * (:x - 2 * :y), @s)
    assert_equal "(-1 + x)*(1 + x)*y", f(:x**2 * :y - :y, @s)
    assert_equal "2*x*y**2*(2 + x*y)", f(2 * :x**2 * :y**3 + 4 * :x * :y**2, @s)
    assert_equal "(1 + x + y)*(-1 + x*y)", f((:x * :y - 1) * (:x + :y + 1), @s)
    assert_equal "(2*x + 3*y)**2*(x - y)*(x**2 + x*y + y**2)",
                 f((:x**2 + :x * :y + :y**2) * (:x - :y) * (2 * :x + 3 * :y)**2, @s)
    assert_equal "x**2 + y**2", f(:x**2 + :y**2, @s)
    assert_equal "(x + y + z)*(x - y)*(y + z**2)", f((:x + :y + :z) * (:x - :y) * (:y + :z**2), ZZ[:x, :y, :z])
    assert_equal "(1/4)*(x + 2*y)*(x - 2*y)", f(:x**2 / 4 - :y**2, QQ[:x, :y])
    g = @s.call((:x**2 + :x * :y + :y**2) * (:x - :y) * (2 * :x + 3 * :y)**2)
    assert_equal g, g.factor.expand
  end

  def test_expression_factor
    assert_equal "(-1 + x)*(1 + x)", (:x**2 - 1).factor.to_s
    assert_equal "(x + y)*(x - y)", (:x**2 - :y**2).factor.to_s
    assert_equal "2*y*(3*x**2 + y**2)", ((:x + :y)**3 - (:x - :y)**3).factor.to_s
    assert_equal "(1/4)*(-1 + 2*x)*(1 + 2*x)", (:x**2 - Rational(1, 4)).factor.to_s
    assert_equal "(-1 + x)*(1 + x)*(1 + x**2)", RCAS.factor(:x**4 - 1).to_s
    assert_equal ZZ[:x], (:x**2 - 1).to_poly.ring
    assert_equal QQ[:x], (:x / 2).to_poly.ring
    assert_raises(RCAS::DomainError) { RCAS.sin(:x).factor }
  end

  def test_unsupported_inputs
    assert_raises(NotImplementedError, RCAS::Unsupported) { RR[:x].call(:x**2 - 2).factor }
    RCAS.assume(a: ZZ)
    assert_raises(RCAS::DomainError) { @r.call(:a * :x**2 - 1).factor }
  end

  def test_gcd_family
    assert_equal "1 + x", @r.call(:x**2 - 1).gcd(:x**2 + 2 * :x + 1).to_s
    assert_equal "1 + x", QQ[:x].call(2 * :x**2 - 2).gcd(:x**2 + 2 * :x + 1).to_s
    assert_equal "-1 - x + x**2 + x**3", @r.call(:x**2 - 1).lcm(:x**2 + 2 * :x + 1).to_s
    assert @r.call(:x**2 + 1).coprime?(:x)
    assert_equal "-1.0 + x", RR[:x].call(:x**2 - 1.0).gcd(:x - 1.0).to_s

    g, s, t = QQ[:x].call(:x**2 + 1).xgcd(:x)
    assert_equal [1, 1, -:x], [g, s, t]
    assert_equal g, s * (:x**2 + 1) + t * :x
    assert_raises(NotImplementedError, RCAS::Unsupported) { @r.call(:x**2 + 1).xgcd(:x) }
  end

  def test_multivariate_gcd
    assert_equal "x + y", @s.call((:x + :y) * (:x - :y)).gcd((:x + :y)**2).to_s
    assert_equal "-y + x*y", @s.call(:x**2 * :y - :y).gcd(:x * :y**2 - :y**2).to_s
    assert_equal "1", @s.call(:x + 1).gcd(:y + 1).to_s
    assert_equal "x + y", QQ[:x, :y].call((:x + :y) * (:x - :y) / 2).gcd((:x + :y)**2).to_s
    assert_equal "x + y", (@s.call((:x + :y) * (:x - :y)) / (:x - :y)).to_s
    assert_raises(RCAS::DomainError) { @s.call((:x + :y) * (:x - :y)) / (:x - 1) }
    assert_raises(NotImplementedError, RCAS::Unsupported) { RR[:x, :y].call(:x * :y).gcd(:x) }
  end

  def test_resultant_and_discriminant
    assert_equal 0, @r.call(:x**2 - 1).resultant(:x - 1)
    assert_equal 2, @r.call(:x**2 + 1).resultant(:x - 1)
    assert_equal 16, @r.call(:x**2 - 4).discriminant
    assert_equal(-3, @r.call(:x**2 + :x + 1).discriminant)
    assert_equal "-4*a*c + b**2", ZZ[:x, :a, :b, :c].call(:a * :x**2 + :b * :x + :c).discriminant(:x).to_s
    assert_equal "y + y**2", @s.call(:x**2 + :y).resultant(:x + :y, :x).to_s
  end
end
