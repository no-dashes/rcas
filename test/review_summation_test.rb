# Discrete mathematics review: sums, products, recurrences, q-analogues.
# Every expectation is computed in the test by brute force over Rationals.
require_relative 'test_helper'
require 'rcas'

class ReviewSummationTest < Minitest::Test
  def setup
    @k, @n, @q = %i[k n q].map { |v| RCAS::Var.new(v) }
  end
  def n(v) = RCAS::Num.new(v)
  def u(arg) = RCAS::Fn.new(:u, [RCAS::Expression.lift(arg)])
  def s(arg) = RCAS::Fn.new(:s, [RCAS::Expression.lift(arg)])

  def binom(top, bottom)
    return 0r if bottom.negative?
    (0...bottom).reduce(1r) { |acc, i| acc * (top - i) / (i + 1) }
  end

  def qbinom(top, bottom, q)
    return 0r if bottom.negative? || bottom > top
    (0...bottom).reduce(1r) { |acc, i| acc * (1 - q**(top - i)) / (1 - q**(i + 1)) }
  end

  # The exact value of a closed form at concrete bindings, or nil.
  def value(expr, bindings)
    v = RCAS::Expression.lift(expr).subs(bindings).simplify
    v.is_a?(RCAS::Num) ? v.value : nil
  end

  # A result that honestly declines: formal node, undefined, or oo.
  def declined?(result)
    result.is_a?(RCAS::Sum) || result == RCAS::UNDEFINED || RCAS::Limits.infinite?(result)
  end

  def finite_number?(result)
    v = RCAS::Expression.lift(result).evalf
    v.is_a?(Numeric) && v.finite?
  rescue StandardError
    false
  end

  def test_binomial_sum_extends_to_infinity_only_where_terms_vanish
    # binomial(n,k)/(n-k+1) = binomial(n+1,k)/(n+1) does not vanish at k = n+1,
    # so the sum over 0..n is (2**(n+1) - 1)/(n+1), not 2**(n+1)/(n+1).
    [binomial_over(1), binomial_over(3)].each do |term, brute|
      result = RCAS.sum(term, @k, 0, @n)
      next if result.is_a?(RCAS::Sum)
      (0..6).each { |m| assert_equal brute.call(m), value(result, n: m), "#{term} at n = #{m}" }
    end
  end

  def test_divergent_logarithmic_and_arctangent_series_have_no_value
    # (-2)**k/k and (-4)**k/(2k+1) do not tend to 0: outside the radius of
    # convergence of log(1+x) and atan(x), the series has no sum.
    [(-2)**@k / @k, (-1)**@k * 4**@k / (2 * @k + 1), 3**@k / @k].each_with_index do |term, i|
      from = i == 1 ? 0 : 1
      result = begin
        RCAS.sum(term, @k, from, RCAS::OO)
      rescue ArgumentError, NotImplementedError
        next
      end
      refute finite_number?(result), "divergent #{term} summed to #{result}"
      assert declined?(result), "divergent #{term} summed to #{result}"
    end
  end

  def binomial_over(base)
    term = RCAS.binomial(@n, @k) * base**@k / (@n - @k + 1)
    [term, ->(m) { (0..m).sum(0r) { |j| binom(m, j) * base**j / (m - j + 1) } }]
  end
end
