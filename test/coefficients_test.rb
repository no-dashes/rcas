# frozen_string_literal: true

require_relative "test_helper"

class CoefficientsTest < Minitest::Test
  include RCAS::Functions
  include RCAS::Sets

  def teardown = RCAS.forget

  def test_degree
    assert_equal 3, degree((:x + 1)**3, :x)
    assert_equal 4, degree(:x**2 * :y + :x * :y**3)
    assert_equal 2, degree(:x**2 * :y + :x * :y**3, :x)
    assert_equal 1, degree(:x)
    assert_equal 0, degree(:x**2 + 1, :y)
    assert_equal(-1, degree(0))
    assert_equal(-1, degree(:x - :x, :x))
    assert_equal 1, ldegree(:x**3 + :x, :x)
    assert_equal 0, ldegree(:x**3 + 1, :x)
    assert_equal 2, degree(RCAS::PI * :x**2 + sqrt(2), :x)
    assert_equal 2, degree(ZZ[:x, :y].call(:x**2 + :y), :x)
    assert_equal 2, (:x**2 + 1).degree
  end

  def test_leading_and_trailing_coefficient
    f = 3 * :a * :x**2 + :b * :x + :c
    assert_equal "3*a", lcoeff(f, :x).to_s
    assert_equal "c", tcoeff(f, :x).to_s
    assert_equal "b", tcoeff(3 * :a * :x**2 + :b * :x, :x).to_s
    assert_equal "1", lcoeff(:x**2 * :y + :x * :y**2).to_s
    assert_equal "-5", tcoeff(:x**2 * :y + :x * :y**2 - 5).to_s
    assert_equal "0", lcoeff(0).to_s
    assert_equal "3", (3 * :x**2 + 1).lcoeff.to_s
  end

  def test_coeff
    f = :a * :x**2 + :b * :x + :c
    assert_equal "a", coeff(f, :x, 2).to_s
    assert_equal "a", coeff(f, :x**2).to_s
    assert_equal "b", coeff(f, :x).to_s
    assert_equal "c", coeff(f, :x, 0).to_s
    assert_equal "0", coeff(f, :x, 5).to_s
    assert_equal "6", coeff((:x + 1)**4, :x, 2).to_s
    assert_equal "2*y", coeff((:x + :y)**2, :x).to_s
    assert_equal "b", f.coeff(:x).to_s
  end

  def test_coeffs
    assert_equal [0, -2, 0, 1], coeffs(:x**3 - 2 * :x, :x)
    assert_equal [1, 4, 6, 4, 1], ((:x + 1)**4).coeffs(:x)
    assert_equal [1, 2, 1], coeffs((:x + :y)**2)
    assert_equal ["c", "b", "a"], coeffs(:a * :x**2 + :b * :x + :c, :x).map(&:to_s)
    assert_equal [], coeffs(0, :x)
  end

  def test_collect
    assert_equal "y**2 + (a + 2*y)*x + x**2", collect((:x + :y)**2 + :a * :x, :x).to_s
    assert_equal "1 + (-3 + b)*x + (-1 + a)*x**2", collect(:a * :x**2 - :x**2 + :b * :x - 3 * :x + 1, :x).to_s
    assert_equal "-x + (-2 + a)*x**3", collect(-2 * :x**3 + :a * :x**3 - :x, :x).to_s
    assert_equal "(-1 + y)*x", collect(:x * :y - :x, :x).to_s
    assert_equal "0", collect(0, :x).to_s
    f = (:x + :y)**3 - :a * :x * :y
    assert_equal f.expand.simplify, f.collect(:x).expand.simplify
  end

  def test_not_a_polynomial
    assert_raises(RCAS::DomainError) { degree(sin(:x), :x) }
    assert_raises(RCAS::DomainError) { degree(1 / :x, :x) }
    assert_raises(RCAS::DomainError) { degree(:x**:n, :x) }
    assert_raises(RCAS::DomainError) { coeff(sqrt(:x) + :x, :x) }
    assert_raises(RCAS::DomainError) { degree(:x * sin(:y)) }
    assert_raises(ArgumentError) { coeff(:x**2, :x, 1 / 2r) }
    assert_raises(ArgumentError) { coeff(:x**2, 2, 1) }
    assert_equal 1, degree(:x * sin(:y), :x)
  end
end
