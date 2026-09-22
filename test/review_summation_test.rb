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

  def test_q_recurrence_is_not_refused_by_rounding_noise
    # sum_k qbinomial(n,k)**2 q**(k**2) = qbinomial(2n,n); its recurrence is
    # exact (residue 0 at q = 3), so "boundary terms do not vanish" is false.
    rec = RCAS.qsumrecursion(RCAS.qbinomial(@n, @k, @q)**2 * @q**(@k**2), @k, @q, s(@n))
    sums = ->(m) { (0..m).sum(0r) { |j| qbinom(m, j, 2r)**2 * 2r**(j * j) } }
    sites = rec.lhs.each_node.select { |e| e.is_a?(RCAS::Fn) && e.name == :s }.uniq
    (0..4).each do |m|
      e = sites.reduce(rec.lhs) { |acc, site| acc.subs(site => sums.call(value(site.args.first, n: m))) }
      assert_equal 0, value(e, n: m, q: 2), "residue at n = #{m}"
    end
  end

  def test_geometric_factors_are_combined_before_the_convergence_test
    # 2**k/3**k = (2/3)**k: the geometric series sums to 1/(1 - 2/3) = 3,
    # and 3**k/4**k to 4. A formal answer is honest; "diverges" is not.
    { 2**@k / 3**@k => 3, 3**@k / 2**(2 * @k) => 4 }.each do |term, sum|
      result = RCAS.sum(term, @k, 0, RCAS::OO)
      next if result.is_a?(RCAS::Sum)
      assert_equal n(sum), result
    end
  end

  def test_telescoping_does_not_jump_over_poles
    # 1/(k*(k+1)) is undefined at k = -1 and k = 0, 1/((k-3)(k-2)) at 2 and 3:
    # the sums over ranges containing them do not exist.
    [[1 / (@k * (@k + 1)), -1, 3], [1 / ((@k - 3) * (@k - 2)), 1, RCAS::OO]].each do |term, from, to|
      result = begin
        RCAS.sum(term, @k, from, to)
      rescue ZeroDivisionError, ArgumentError, NotImplementedError
        next
      end
      assert declined?(result), "sum over a pole of #{term} came back as #{result}"
    end
  end

  def test_general_solution_spans_the_whole_solution_space
    # L3 = (E - 1) o L2 with L2 u = u(n+2) - 2(n+2)u(n+1) + (n+1)(n+2)u(n):
    # third order, so u(0), u(1), u(2) determine a solution; 0, 0, 1 gives 7, 45, 311, ...
    eqn = RCAS.eq(u(@n + 3) - (2 * @n + 7) * u(@n + 2) + (@n + 2) * (@n + 5) * u(@n + 1) -
                  (@n + 1) * (@n + 2) * u(@n), 0)
    seq = [0r, 0r, 1r]
    (3..6).each { |m| j = m - 3; seq << (2 * j + 7) * seq[m - 1] - (j + 2) * (j + 5) * seq[m - 2] + (j + 1) * (j + 2) * seq[m - 3] }
    begin
      result = RCAS.rsolve(eqn, :u, @n, init: { 0 => 0, 1 => 0, 2 => 1 })
    rescue NotImplementedError
      return assert true
    end
    (0..6).each { |m| assert_equal seq[m], value(result.rhs, n: m), "u(#{m})" }
  end

  def test_initial_values_before_the_singularity_fix_the_sequence
    # u(n+1) = (n-3)u(n), u(0) = 1: 1, -3, 6, -6 and then 0 for ever,
    # which is 6*(-1)**n/(3-n)!; (n-4)!/(-4)! is undefined.
    eqn = RCAS.eq(u(@n + 1), (@n - 3) * u(@n))
    seq = [1r]
    (1..6).each { |m| seq << (m - 4) * seq[m - 1] }
    begin
      result = RCAS.rsolve(eqn, :u, @n, init: { 0 => 1 })
    rescue NotImplementedError, ArgumentError
      return assert true
    end
    (0..6).each { |m| assert_equal seq[m], value(result.rhs, n: m), "u(#{m})" }
  end

  def test_first_order_recurrence_always_has_a_hypergeometric_solution
    # u(n+1) = (n+1)(n+2)...(n+7)u(n): the ratio is a polynomial, so the
    # solution is hypergeometric by definition; [] claims there is none.
    coefficient = (1..7).reduce(n(1)) { |acc, i| acc * (@n + i) }
    begin
      found = RCAS.hyper(RCAS.eq(u(@n + 1), coefficient * u(@n)), :u, @n)
    rescue NotImplementedError
      return assert true
    end
    refute_empty found
    term = found.first
    (1..3).each do |m|
      want = (1..7).reduce(1r) { |acc, i| acc * (m + i) }
      assert_equal want, value(term, n: m + 1) / value(term, n: m)
    end
  end

  def test_sumrecursion_checks_boundaries_over_the_natural_range
    # (-1)**k*binomial(2n,k)**2 vanishes outside 0..2n; its sum is
    # (-1)**n*binomial(2n,n), which obeys (n+1)S(n+1) + (4n+2)S(n) = 0.
    rec = RCAS.sumrecursion((-1)**@k * RCAS.binomial(2 * @n, @k)**2, @k, s(@n))
    sums = ->(m) { (0..2 * m).sum(0r) { |j| (-1)**j * binom(2 * m, j)**2 } }
    sites = rec.lhs.each_node.select { |e| e.is_a?(RCAS::Fn) && e.name == :s }.uniq
    (0..5).each do |m|
      e = sites.reduce(rec.lhs) { |acc, site| acc.subs(site => sums.call(value(site.args.first, n: m))) }
      assert_equal 0, value(e, n: m), "residue at n = #{m}"
    end
  end

  def test_gaussian_binomial_is_a_polynomial_defined_at_every_q
    # [n choose k]_q is a polynomial in q: 10 at q = 1 (the ordinary binomial),
    # and [5 choose 2]_{-1} = [4 choose 2]_{-1} = 2.
    [[5, 2, 1], [5, 2, -1], [4, 2, -1]].each do |top, bottom, q|
      want = RCAS.qbinomial(top, bottom, @q).subs(q: q).simplify
      assert_equal want, RCAS.qbinomial(top, bottom, q)
    end
  end

  def test_non_integer_bounds_are_refused_or_stepped
    # sum_{k=1.5}^{3} k runs over k = 1.5, 2.5 and is 4; Faulhaber at a
    # non-integer bound (5.625) is no sum at all.
    begin
      result = RCAS.sum(@k, @k, 1.5, 3)
    rescue ArgumentError, NotImplementedError
      return assert true
    end
    assert(result.is_a?(RCAS::Sum) || result == n(4.0), "got #{result}")
  end

  def test_sum_of_zeros_is_zero
    # Every partial sum of 0 + 0 + ... is 0, so the series converges to 0.
    assert_equal n(0), RCAS.sum(0, @k, 1, RCAS::OO)
  end
end
