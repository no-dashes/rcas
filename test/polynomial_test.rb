# frozen_string_literal: true

require_relative "test_helper"

class PolynomialTest < Minitest::Test
  include RCAS::Sets

  def setup
    @r = ZZ[:t]
    @f = @r.call(:t**2 - 1)
    @g = @r.call(:t - 1)
  end

  def teardown = RCAS.forget

  def test_structure
    assert_equal "-1 + t**2", @f.to_s
    assert_equal 2, @f.degree
    assert_equal [-1, 0, 1], @f.coefficients
    assert_equal 1, @f.leading_coefficient
    assert_equal(-1, @f.constant_term)
    assert_equal(-1, @r.zero.degree)
    assert @r.zero.zero?
    assert @r.call(5).constant?
    assert_equal [@r.call(:t)], @r.gens
  end

  def test_arithmetic
    assert_equal "-2 + t + t**2", (@f + @g).to_s
    assert_equal "1 - t - t**2 + t**3", (@f * @g).to_s
    assert_equal "t**2", (@f + 1).to_s
    assert_equal "-2 + 2*t**2", (2 * @f).to_s
    assert_equal "-t + t**3", (:t * @f).to_s
    assert_equal "1 - 2*t**2 + t**4", (@f**2).to_s
    assert_equal @f, :t**2 - 1
    assert_equal :t**2 - 1, @f
    refute_equal @f, :t**2
  end

  def test_division
    assert_equal "1 + t", (@f / @g).to_s
    q, r = (@f**2).divmod(@g)
    assert_equal "-1 - t + t**2 + t**3", q.to_s
    assert r.zero?
    _, r = @f.divmod(@r.call(:t + 2))
    assert_equal 3, r
    assert_equal "1/2 + t/2", (QQ[:t].call(:t**2 - 1) / (2 * :t - 2)).to_s
    e = assert_raises(RCAS::DomainError) { @f / (2 * :t - 2) }
    assert_match(/try QQ\[t\]/, e.message)
    assert_raises(RCAS::DomainError) { @f / @r.call(:t + 2) }
    assert_raises(ZeroDivisionError) { @f / 0 }
  end

  def test_gcd
    assert_equal "1 + t", @f.gcd(@r.call(:t**2 + 2 * :t + 1)).to_s
    assert_equal "2 + 2*t", @r.call(2 * :t + 2).gcd(@r.call(4 * :t**2 - 4)).to_s
    assert_equal "-1 + t", QQ[:t].call(:t**3 - :t).gcd(QQ[:t].call(:t**2 - 2 * :t + 1)).to_s
    assert_equal "1", @f.gcd(@r.call(:t**2 + 1)).to_s
    assert_equal "2 + t**2", QQ[:t].call(2 * :t**2 + 4).monic.to_s
  end

  def test_calculus_and_evaluation
    assert_equal "2*t", @f.derivative.to_s
    assert_equal 8, @f.call(t: 3)
    assert_equal "-1 + u**2", @f.call(t: :u).to_s
    assert_equal [0, 3, 8], [1, 2, 3].map(&@f)
  end

  def test_ring_promotion
    h = @f + Rational(1, 2)
    assert_equal QQ[:t], h.ring
    assert_equal "-1/2 + t**2", h.to_s
    k = @f + :u
    assert_equal ZZ[:t, :u], k.ring
    assert_equal "-1 + u + t**2", k.to_s
    m = @f + QQ[:u].call(:u / 2)
    assert_equal QQ[:t, :u], m.ring
  end

  def test_non_polynomials_fall_back_to_expressions
    e = @f + RCAS.sin(:t)
    assert_kind_of RCAS::Expression, e
    assert_equal "-1 + t**2 + sin(t)", e.to_s
    assert_raises(RCAS::DomainError) { @r.call(1 / :t) }
    assert_raises(RCAS::DomainError) { @r.call(:t / 2) }
  end

  def test_parameters
    RCAS.assume(a: ZZ)
    p = @r.call(:a * :t + 1)
    assert_equal "1 + a*t", p.to_s
    assert_equal :a.to_expr, p.leading_coefficient
    assert_equal "a", p.derivative.to_s
  end

  def test_multivariate
    r = QQ[:x, :y]
    p = r.call((:x + :y)**2)
    assert_equal "x**2 + 2*x*y + y**2", p.to_s
    assert_equal 2, p.degree
    assert_equal 2, p.degree(:y)
    assert_equal 2, p.coeff(1, 1)
    assert_equal "2*x + 2*y", p.derivative(:x).to_s
    assert_raises(NotImplementedError) { p.divmod(r.call(:x + :y)) }
    assert_equal "1/2 + x/2", (r.call(:x + 1) / 2).to_s
  end
end
