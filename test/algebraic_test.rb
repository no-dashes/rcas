# frozen_string_literal: true

require_relative "test_helper"

class AlgebraicTest < Minitest::Test
  include RCAS::Sets
  include RCAS::Constants

  def s2 = RCAS.sqrt(2)
  def s3 = RCAS.sqrt(3)

  def test_field_and_exact_values
    k = QQ.adjoin(s2)
    assert_equal "QQ(2**(1/2))", k.to_s
    assert_equal 2, k.degree
    assert k.field?
    assert k.include?(1 + s2)
    refute k.include?(s3)
    assert k < RR
    assert_equal "7 + 5*2**(1/2)", RCAS::Algebraic.exact((1 + s2)**3).to_s
    assert_equal "-1 + 2**(1/2)", RCAS::Algebraic.exact(1 / (1 + s2)).to_s
    assert_equal "5 + 2*2**(1/2)*3**(1/2)", RCAS::Algebraic.exact((s2 + s3)**2).to_expr.to_s
  end

  def test_exact_zero_tests
    assert RCAS::Scalar.zero?((1 + s2) * (1 - s2) + 1)
    assert RCAS::Scalar.zero?(s2 * s3 - RCAS.sqrt(6))
    refute RCAS::Scalar.zero?(s2 + s3 - RCAS.sqrt(5))
    c = RCAS.cbrt(2)
    assert RCAS::Scalar.zero?(c**3 - 2)
    assert RCAS::Scalar.zero?((I + 1) * (I - 1) + 2)
  end

  def test_rationalize_and_minpoly
    assert_equal "-1 + 2**(1/2)", (1 / (1 + s2)).rationalize.to_s
    assert_equal "-1/2 + 5**(1/2)/2", (1 / (Rational(1, 2) + RCAS.sqrt(5) / 2)).rationalize.to_s
    assert_equal "1 - 10*x**2 + x**4", RCAS.minpoly(s2 + s3).to_s
    assert_equal "-1 - 2*x + x**2", RCAS.minpoly(1 + s2).to_s
    assert_equal "-2 + x**3", RCAS.minpoly(RCAS.cbrt(2)).to_s
    assert_equal "1 + x**2", RCAS.minpoly(I).to_s
    assert_equal "1 + x + x**2", RCAS.minpoly(-Rational(1, 2) + I * s3 / 2, :x).to_s
  end

  def test_root_of
    roots = RCAS.solve(:x**3 - :x - 1, :x)
    r = roots.first
    assert_kind_of RCAS::RootOf, r
    assert_equal "RootOf(-1 - x + x**3, 0)", r.to_s
    assert_in_delta 1.3247179572447458, r.evalf, 1e-12
    assert_equal "-1 + RootOf(-1 - x + x**3, 0)**2", (1 / r).rationalize.to_s
    assert_equal RR, r.domain
    assert_equal CC, roots.last.domain
    assert_equal 0, r.diff(:x)
  end

  def test_factor_over_extensions
    assert_equal "(-2**(1/2) + x)*(2**(1/2) + x)", RCAS.factor(:x**2 - 2, extension: s2).to_s
    assert_equal "(-2**(1/2) + x)*(2**(1/2) + x)*(2 + x**2)", QQ[:x].call(:x**4 - 4).factor(extension: s2).to_s
    assert_equal "(-i + x)*(i + x)", RCAS.factor(:x**2 + 1, extension: I).to_s
    f = QQ[:x].call(:x**3 - 2).factor(extension: RCAS.cbrt(2))
    assert_equal 2, f.size
    assert_equal 1, f.factors.first.first.degree
    quartic = QQ[:x].call(:x**4 + 1)
    assert_equal "(1 + 2**(1/2)*x + x**2)*(1 - 2**(1/2)*x + x**2)", quartic.factor(extension: s2).to_s
    assert_equal "(-i + x**2)*(i + x**2)", quartic.factor(extension: I).to_s
    assert_equal "(1/2 + i*3**(1/2)/2 + x)*(1/2 - i*3**(1/2)/2 + x)", RCAS.factor(:x**2 + :x + 1, extension: I * s3).to_s
  end

  def test_exact_eigenvectors
    golden = QQ.matrix([[1, 1], [1, 0]])
    assert_equal [["(1/2 - 5**(1/2)/2, 1)"], ["(1/2 + 5**(1/2)/2, 1)"]], golden.eigenvectors.map { |_, _, vs| vs.map(&:to_s) }
    m = QQ.matrix([[2, 1, 0], [0, 1, 1], [1, 0, 2]])
    vectors = m.eigenvectors
    assert_equal 3, vectors.size
    vectors.each do |l, _, vs|
      assert_equal 1, vs.size
      v = vs.first
      assert (m * v - v * l).entries.all? { |e| RCAS::Scalar.zero?(e) }, "eigenvector check for #{l}"
    end
  end
end
