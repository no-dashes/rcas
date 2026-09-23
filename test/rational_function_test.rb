# frozen_string_literal: true

require_relative "test_helper"

class RationalFunctionTest < Minitest::Test
  include RCAS::Functions
  include RCAS::Sets

  def teardown = RCAS.forget

  def test_numer_denom
    f = 1 / :x + 1 / (:x + 1)
    assert_equal "1 + 2*x", numer(f).to_s
    assert_equal "x + x**2", denom(f).to_s
    assert_equal ["x", "2"], [numer(:x / 2), denom(:x / 2)].map(&:to_s)
    g = (2 * :x + 1) / (2 * :x - 1)
    assert_equal ["1 + 2*x", "-1 + 2*x"], [numer(g), denom(g)].map(&:to_s)
    assert_equal ["1 + x", "1"], [numer((:x**2 - 1) / (:x - 1)), denom((:x**2 - 1) / (:x - 1))].map(&:to_s)
    assert_equal "3*x", denom(2 / (3 * :x)).to_s
    assert_equal ["3", "4"], [numer(3 / 4r), denom(3 / 4r)].map(&:to_s)
    assert_equal ["1", "1 + 2**(1/2)"], [numer(1 / (1 + sqrt(2))), denom(1 / (1 + sqrt(2)))].map(&:to_s)
    assert_equal ["sin(x)", "x**2"], [numer(sin(:x) / :x**2), denom(sin(:x) / :x**2)].map(&:to_s)
    assert_equal "1 + 2*x", f.numer.to_s
    assert_equal "x", numer(ZZ[:x].call(:x)).to_s
  end

  def test_apart_univariate
    assert_equal "1/(2*(-1 + x)) - 1/(2*(1 + x))", apart(1 / (:x**2 - 1)).to_s
    assert_equal "2/(-1 + x) - 2/x - 1/x**2", apart((:x + 1) / (:x**2 * (:x - 1)), :x).to_s
    assert_equal "x - x/(1 + x**2)", apart(:x**3 / (:x**2 + 1)).to_s
    assert_equal "1/(1 + x**2)**2", apart(1 / (:x**2 + 1)**2).to_s
    assert_equal "3/(2*(-1 + x)**2) - 1/(2*(1 + x**2))", apart((:x**2 + :x + 1) / ((:x - 1)**2 * (:x**2 + 1))).to_s
    assert_equal "-1/(1 + x) + 1/(2*(2 + x)) + 1/(2*x)", apart(1 / (:x * (:x + 1) * (:x + 2))).to_s
    assert_equal "1/(-2 + x**2)", apart(1 / (:x**2 - 2)).to_s # irreducible over QQ
    assert_equal "1 + x**2", apart(:x**2 + 1).to_s
    assert_equal "0", apart(:x - :x).to_s
    assert_equal "(a + b)/(2*(-1 + x)) + (a - b)/(2*(1 + x))", apart((:a * :x + :b) / (:x**2 - 1), :x).to_s
    assert_equal "-1/(2*a*(a + x)) - 1/(2*a*(a - x))", apart(1 / (:x**2 - :a**2), :x).to_s
    assert_equal apart(1 / (:x**2 - 1)), (1 / (:x**2 - 1)).apart
  end

  def test_apart_roundtrip
    [
      (:x**5 + 1) / ((:x - 1)**3 * (:x**2 + :x + 1)),
      1 / (:x**4 - 1),
      (3 * :x**2 - 2) / (:x**2 * (:x + 2)**2),
      1 / (:x * (:x - :a)**2),
      :x**2 / (:x**2 - :a**2),
      1 / ((:x - :a) * (:x - :b)),
      (:a * :x + :b) / (:x**2 - 1),
      (:x**2 + :b) / ((:x - :a) * (:x**2 + 1))
    ].each do |f|
      assert_equal "0", (apart(f, :x) - f).cancel.to_s, "apart(#{f}) does not recombine"
    end
  end

  def test_apart_errors
    assert_raises(ArgumentError) { apart(1 / (:x * :y - 1)) }
    assert_raises(ArgumentError) { apart(1 / (:x**2 - 1), :y) }
    assert_raises(RCAS::DomainError) { apart(1 / (sqrt(2) * :x + 1)) }
    assert_raises(RCAS::DomainError) { apart(sin(:x) / :x) }
  end

  def test_gcd_lcm
    assert_equal 6, gcd(12, 18)
    assert_equal 12, lcm(4, 6)
    assert_equal 1 / 4r, gcd(1 / 2r, 3 / 4r)
    assert_equal "2 + 2*x", gcd(2 * :x + 2, 4 * :x**2 - 4).to_s
    assert_equal "-1 - x + x**2 + x**3", lcm(:x**2 - 1, :x**2 + 2 * :x + 1).to_s
    assert_equal "1", gcd(:x**2 + 1, :x + 1).to_s
    assert_equal "1", gcd(:x - 1, 5).to_s
    assert_equal "x + y", gcd(:x**2 - :y**2, :x**2 + 2 * :x * :y + :y**2).to_s
    assert_kind_of RCAS::Polynomial, gcd(ZZ[:x].call(:x**2 - 1), :x - 1)
    assert_equal "1 + x", (:x**2 - 1).gcd(:x + 1).to_s
  end

  def test_division
    assert_equal "1 + x + x**2", quo(:x**3 - 1, :x - 1).to_s
    assert_equal "2", rem(:x**3 + 1, :x - 1).to_s
    assert_equal ["x/2", "1"], divmod(:x**2 + 1, 2 * :x).map(&:to_s)
    assert_equal ["1 + a + a*x", "1"], divmod(:a * :x**2 + :x - :a, :x - 1, :x).map(&:to_s)
    assert_equal "1 + x*y", quo(:x**2 * :y + :x, :x, :x).to_s
    assert_equal "0", rem(:x**2 + :y, :x, :y).to_s
    assert_equal [3, 1], divmod(10, 3)
    assert_equal ["1 + x + x**2", "0"], (:x**3 - 1).divmod(:x - 1).map(&:to_s)
    assert_raises(NotImplementedError, RCAS::Unsupported) { quo(:x**2 + :y, :x + 1) } # several indeterminates, no x named
  end

  def test_functional_forms
    assert_equal "2*x", simplify(:x + :x).to_s
    assert_equal "1 + 2*x + x**2", expand((:x + 1)**2).to_s
    assert_equal "1 + x", cancel((:x**2 - 1) / (:x - 1)).to_s
    assert_equal "-1 + 2**(1/2)", rationalize(1 / (1 + sqrt(2))).to_s
  end

  def test_scalar_over_fraction_field_base
    ring = ZZ[:a].fraction_field[:x]
    assert_equal "x**2/(2*a)", (ring.call(:x**2) * (1 / (2 * :a))).to_s
    assert_equal "x**2/(2*a)", ((1 / (2 * :a)) * ring.call(:x**2)).to_s
    assert_equal "1/a + x", ring.call(:a * :x + 1).monic.to_s
  end
end
