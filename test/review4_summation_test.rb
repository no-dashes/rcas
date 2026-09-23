# Verification round (review of da72570..8c10e71): sums, products, recurrences.
# Every expectation is computed in the test by brute force over Rationals.
require_relative 'test_helper'
require 'rcas'

class Review2SummationTest < Minitest::Test
  def setup
    @k, @n, @a = %i[k n a].map { |v| RCAS::Var.new(v) }
  end
  def n(v) = RCAS::Num.new(v)
  def u(arg) = RCAS::Fn.new(:u, [RCAS::Expression.lift(arg)])

  def binom(top, bottom)
    return 0r if bottom.negative? || bottom > top
    (0...bottom).reduce(1r) { |acc, i| acc * (top - i) / (i + 1) }
  end

  # The exact value of an expression at concrete bindings, or nil.
  def value(expr, bindings = {})
    v = RCAS::Expression.lift(expr).subs(bindings).simplify
    v.is_a?(RCAS::Num) ? v.value : nil
  end

  # A result that honestly declines: formal node, undefined, or oo.
  def declined?(result)
    result.is_a?(RCAS::Sum) || result.is_a?(RCAS::Product) || result == RCAS::UNDEFINED || RCAS::Limits.infinite?(result)
  end

  def finite_number?(result)
    v = RCAS::Expression.lift(result).evalf
    v = v.value if v.is_a?(RCAS::Num)
    v.is_a?(Numeric) && v.finite?
  rescue StandardError
    false
  end

  # REGRESSION (5d8294a). Gosper now accepts the antidifference of a term with
  # binomial(k, c): g(k) = binomial(k, c)*P(k)/(k(k-1)...(k-c+1)), whose poles
  # at k = 0..c-1 are removable. Evaluating g at a lower bound below c divides
  # by zero, so sums rcas used to add up term by term now raise.
  # Hockey stick: sum_{k=0}^{10} binomial(k, 3) = binomial(11, 4) = 330.
  def test_a_binomial_antidifference_is_evaluated_across_its_removable_poles
    [[RCAS.binomial(@k, 3), ->(j) { binom(j, 3) }],
     [RCAS.binomial(@k, 2) * 2**@k, ->(j) { binom(j, 2) * 2**j }],
     [@k * RCAS.binomial(@k, 2), ->(j) { j * binom(j, 2) }]].each do |term, brute|
      [0, 1].each do |lo|
        assert_equal (lo..10).sum(0r) { |j| brute.call(j) }, value(RCAS.sum(term, @k, lo, 10)), "sum(#{term}, k, #{lo}, 10)"
      end
    end
    closed = RCAS.sum(RCAS.binomial(@k, 3), @k, 0, @n)
    return if closed.is_a?(RCAS::Sum)
    (0..6).each { |m| assert_equal binom(m + 1, 4), value(closed, n: m), "n = #{m}" }
  end

  # REGRESSION (c3a3419). The "initial value before the start index" guard reads
  # @start, which only the Petkovsek path sets: for constant coefficients it is
  # nil, nil.to_i is 0, and every negative index is refused with the message
  # "holds from n =  on". Fibonacci from u(-1) = 1, u(0) = 0 is F(n).
  def test_constant_coefficient_initial_values_at_negative_indices
    fib = RCAS.rsolve(RCAS.eq(u(@n + 2), u(@n + 1) + u(@n)), :u, @n, init: { -1 => 1, 0 => 0 })
    seq = { -1 => 1r, 0 => 0r }
    (1..10).each { |m| seq[m] = seq[m - 1] + seq[m - 2] }
    (-1..10).each { |m| assert_in_delta seq[m], RCAS::Expression.lift(fib.rhs).subs(n: m).evalf.to_f, 1e-9, "F(#{m})" }
    lin = RCAS.rsolve(RCAS.eq(u(@n + 1), 2 * u(@n) + 1), :u, @n, init: { -2 => 0 })
    seq = { -2 => 0r }
    (-1..6).each { |m| seq[m] = 2 * seq[m - 1] + 1 }
    (-2..6).each { |m| assert_equal seq[m], value(lin.rhs, n: m), "u(#{m})" }
  end

  # REGRESSION (c3a3419). Both n! and a**n*n! solve
  #   u(n+2) - (a+1)(n+2)u(n+1) + a(n+2)(n+1)u(n) = 0
  # (substitute: the brackets are 1 - (a+1) + a and a**2 - (a+1)a + a, both 0),
  # and their Casoratian is (a - 1)*n!*(n+1)!*a**n, not identically 0. The new
  # independence test evaluates only numeric rows, so a parameter makes it say
  # "do not span" - a false claim, where da72570 answered C1*n! + C2*a**n*n!.
  def test_a_parametric_basis_is_not_called_dependent
    eqn = RCAS.eq(u(@n + 2) - (@a + 1) * (@n + 2) * u(@n + 1) + @a * (@n + 2) * (@n + 1) * u(@n), 0)
    result = RCAS.rsolve(eqn, :u, @n, init: { 0 => 1, 1 => 5 })
    # at a = 3: u(n+2) = 4(n+2)u(n+1) - 3(n+2)(n+1)u(n), u(0) = 1, u(1) = 5
    seq = { 0 => 1r, 1 => 5r }
    (2..7).each { |m| seq[m] = 4 * m * seq[m - 1] - 3 * m * (m - 1) * seq[m - 2] }
    (0..7).each { |m| assert_equal seq[m], value(result.rhs, a: 3, n: m), "u(#{m}) at a = 3" }
  end

  # REGRESSION (c3a3419), the same root cause at order 1: the one solution of
  # u(n+1) = (n**2 + 1)u(n) is product(1 + i**2, i, 0, n - 1), which spans the
  # solutions trivially, but independent? cannot evaluate a product node and
  # calls it dependent. da72570 answered C1*product(...). u(0) = 1 gives
  # 1, 1, 2, 10, 100, 1700, ...
  def test_a_first_order_solution_that_does_not_fold_still_spans
    result = RCAS.rsolve(RCAS.eq(u(@n + 1), (@n**2 + 1) * u(@n)), :u, @n, init: { 0 => 1 })
    assert_kind_of RCAS::Equation, result
    products = result.rhs.each_node.select { |e| e.is_a?(RCAS::Product) }
    refute_empty products, "u(n) = #{result.rhs}"
  end

  # REGRESSION (c3a3419), a closed form lost. vanishes_past_upper? keeps the
  # bound n whenever another factor mentions k, though binomial(k, 2) is a
  # polynomial in k and has no pole: sum_k binomial(n,k)*binomial(k,2) =
  # binomial(n,2)*2**(n-2), which da72570 found.
  def test_a_polynomial_factor_does_not_stop_the_binomial_theorem
    result = RCAS.sum(RCAS.binomial(@n, @k) * RCAS.binomial(@k, 2), @k, 0, @n)
    (0..7).each { |m| assert_equal (0..m).sum(0r) { |j| binom(m, j) * binom(j, 2) }, value(result, n: m), "n = #{m}" }
  end

  # REGRESSION (c3a3419), a closed form lost behind a false claim. The leading
  # coefficient of u(n+2) = 2(n+2)u(n+1) - (n+1)(n+2)u(n) is 1, so an initial
  # value at 0 determines the sequence, and n!, n*n! are defined at 0; the
  # answer for u(0) = 1, u(1) = 2 is (n+1)! (da72570 found it). The refusal
  # "the closed form holds from n = 1 on" comes from the product form of the
  # ratio (n+1)**2/n, not from the recurrence.
  def test_a_start_index_is_not_invented_for_a_regular_recurrence
    eqn = RCAS.eq(u(@n + 2), 2 * (@n + 2) * u(@n + 1) - (@n + 1) * (@n + 2) * u(@n))
    result = RCAS.rsolve(eqn, :u, @n, init: { 0 => 1, 1 => 2 })
    (0..7).each { |m| assert_equal (1..m + 1).reduce(1, :*), value(result.rhs, n: m), "u(#{m})" }
  end
end
