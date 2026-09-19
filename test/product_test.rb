# frozen_string_literal: true

require_relative "test_helper"

class ProductTest < Minitest::Test
  K = RCAS::Var.new(:k)
  N = RCAS::Var.new(:n)

  def product(f, from, to) = RCAS.product(f, K, from, to)

  # The closed form agrees with the multiplied-out product for small n.
  def assert_product(f, from, expected)
    result = product(f, from, N)
    assert_equal expected, result.to_s
    (from..from + 4).each do |n|
      direct = (from..n).reduce(1) { |acc, i| acc * f.call(k: i) }
      assert_in_delta direct.to_f, RCAS::Expression.lift(result).evalf(n: n).to_f, 1e-9 * [1, direct.abs].max, "#{result} at n = #{n}"
    end
  end

  # A linear factor whose root is a parameter: the same gamma ratio, under
  # the generic assumption that the root is not inside the range.
  def test_parametric_linear_factors
    a = RCAS::Var.new(:a)
    result = product(a - K, 0, N)
    assert_equal "-((-1)**n*gamma(1 - a + n))/gamma(-a)", result.to_s
    (0..4).each do |n|
      direct = (0..n).reduce(Rational(1)) { |acc, i| acc * (Rational(1, 3) - i) }
      assert_in_delta direct.to_f, result.evalf(a: Rational(1, 3), n: n).to_f, 1e-9, "at n = #{n}"
    end
    assert_equal "gamma(1 + b + n)/gamma(1 + b)", product(K + RCAS::Var.new(:b), 1, N).to_s
  end

  def test_closed_forms
    assert_product K, 1, "n!"
    assert_product 2 * K, 1, "2**n*n!"
    assert_product 2 * K - 1, 1, "2**n*gamma(1/2 + n)/pi**(1/2)"
    assert_product K**2, 1, "n!**2"
    assert_product K + 1, 0, "(1 + n)!"
    assert_product (K + 1) / K, 1, "1 + n"
    assert_product 1 + 1 / K, 1, "1 + n"
    assert_product RCAS::Num.new(2), 1, "2**n"
    assert_product 3**K, 0, "3**(n*(1 + n)/2)"
    assert_equal "a**(n*(1 + n)/2)", product(RCAS::Var.new(:a)**K, 1, N).to_s
    assert_equal "x**n", product(RCAS::Var.new(:x), 1, N).to_s
    assert_equal "0", product(K, 0, N).to_s
  end

  def test_numeric_and_formal
    assert_equal "120", product(K, 1, 5).to_s
    assert_equal "1", product(K, 3, 2).to_s
    assert_equal "product(k!, k, 1, n)", product(RCAS.factorial(K), 1, N).to_s
    assert_equal "product(1 + k**2, k, 1, n)", product(K**2 + 1, 1, N).to_s
    assert_equal "product(k, k, 1, oo)", RCAS.product(K, k: 1..).to_s
    formal = RCAS.hold { product(k, k: 1..n) }
    assert_instance_of RCAS::Product, formal
    assert_equal "n!", formal.evaluate.to_s
    assert_equal '\prod_{k=1}^{n} k', formal.to_latex
  end

  def test_harmonic_numbers
    assert_equal "harmonic(n)", RCAS.sum(1 / K, k: 1..N).to_s
    assert_equal "25/12", RCAS.harmonic(4).to_s
  end
end
