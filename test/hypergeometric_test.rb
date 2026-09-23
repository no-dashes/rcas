# frozen_string_literal: true

require_relative "test_helper"

# Hypergeometric summation: polynomial solutions of a recurrence,
# Petkovsek's algorithm and Zeilberger's.
class PolyRecurrenceTest < Minitest::Test
  N = RCAS::Var.new(:n)

  def basis(*coeffs) = RCAS::PolyRecurrence.basis(coeffs.map { |c| RCAS::Expression.lift(c) }, N).map(&:to_s)

  def test_constants_solve_the_difference_equation
    assert_equal ["1"], basis(-1, 1) # c(n + 1) - c(n) = 0
  end

  def test_a_polynomial_solution_is_found
    assert_equal ["1 + n"], basis(N + 2, -(N + 1)) # (n + 2)c(n) = (n + 1)c(n + 1)
    assert_equal ["n**2"], basis(N**2 + 2 * N + 1, -N**2 - 2 * N - 1 + (2 * N + 1), 0)
  end

  def test_no_polynomial_solution
    assert_empty basis(-1, -1, 1) # Fibonacci
    assert_empty basis(-2, 1)     # c(n + 1) = 2c(n)
  end

  def test_an_inhomogeneous_equation_has_a_particular_solution
    particular, homogeneous = RCAS::PolyRecurrence.solutions([RCAS::Num.new(-1), RCAS::Num.new(1)], N, N)
    assert_equal "-n/2 + n**2/2", particular.to_s, "sum of 0..n-1"
    assert_equal ["1"], homogeneous.map(&:to_s)
  end

  def test_the_degree_bound_is_read_off_the_indicial_equation
    assert_equal 0, RCAS::PolyRecurrence.degree_bound([RCAS::Num.new(-1), RCAS::Num.new(1)], N)
    assert_nil RCAS::PolyRecurrence.degree_bound([RCAS::Num.new(-2), RCAS::Num.new(1)], N)
  end
end

class PetkovsekTest < Minitest::Test
  N = RCAS::Var.new(:n)

  def u(arg) = RCAS::Fn.new(:u, [arg])
  def hyper(lhs, rhs) = RCAS.hyper(RCAS::Equation.new(lhs, rhs), :u, :n)
  def rsolve(lhs, rhs, **opts) = RCAS.rsolve(RCAS::Equation.new(lhs, rhs), :u, :n, **opts)

  # t(n + 1)/t(n) really is the ratio the recurrence asks for.
  def assert_solves(lhs, rhs, term)
    (1..5).each do |i|
      values = { u(N + 2) => term.subs(N => i + 2), u(N + 1) => term.subs(N => i + 1), u(N) => term.subs(N => i), N => i }
      left = lhs.subs(values).evalf
      right = RCAS::Expression.lift(rhs).subs(values).evalf
      assert_in_delta left, right, 1e-9 * [1, left.abs].max, "#{term} fails at n = #{i}"
    end
  end

  def test_first_order_gives_factorials
    assert_equal ["(-1 + n)!"], hyper(u(N + 1), N * u(N)).map(&:to_s)
    assert_equal ["n!"], hyper(u(N + 1), (N + 1) * u(N)).map(&:to_s)
    assert_equal ["1/(1 + n)!"], hyper((N + 2) * u(N + 1), u(N)).map(&:to_s)
    assert_solves u(N + 1), N * u(N), RCAS.factorial(N - 1)
  end

  def test_constant_coefficients_give_the_characteristic_roots
    solutions = hyper(u(N + 2), u(N + 1) + u(N))
    assert_equal ["(1/2 - 5**(1/2)/2)**n", "(1/2 + 5**(1/2)/2)**n"], solutions.map(&:to_s)
    solutions.each { |t| assert_solves u(N + 2), u(N + 1) + u(N), t }
    assert_equal ["2**n", "2**n*n/2"], hyper(u(N + 2), 4 * u(N + 1) - 4 * u(N)).map(&:to_s), "a double root"
  end

  def test_a_power_times_a_factorial
    assert_equal ["2**n*n!"], hyper(u(N + 1), 2 * (N + 1) * u(N)).map(&:to_s)
  end

  def test_recurrences_without_hypergeometric_solutions
    assert_empty hyper(u(N + 2), u(N + 1) + (N + 1) * u(N))
    assert_empty hyper(u(N + 2), u(N + 1) + N * u(N))
  end

  def test_rsolve_uses_them_and_fits_initial_values
    assert_equal "u(n) = n!", rsolve(u(N + 1), (N + 1) * u(N), init: { 1 => 1 }).to_s
    assert_equal "u(n) = C1*(-1 + n)!", rsolve(u(N + 1), N * u(N)).to_s
    # one of two solutions is not enough for the general one
    error = assert_raises(NotImplementedError, RCAS::Unsupported) do
      rsolve((N + 2) * u(N + 2), (2 * N + 3) * u(N + 1) - (N + 1) * u(N))
    end
    assert_match(/only 1 of 2/, error.message)
  end
end

class ZeilbergerTest < Minitest::Test
  N = RCAS::Var.new(:n)
  K = RCAS::Var.new(:k)
  M = RCAS::Var.new(:m)

  include RCAS::Functions

  def s = RCAS::Fn.new(:S, [N])
  def recursion(term, **opts) = RCAS.sumrecursion(term, K, s, **opts).to_s

  # The sum itself obeys the recurrence, checked by adding the terms up.
  def assert_recurrence(term, coefficients, upper: N)
    order = coefficients.size - 1
    (0..4).each do |i|
      total = coefficients.each_with_index.reduce(RCAS::Num.new(0)) do |acc, (c, j)|
        top = upper.subs(N => i + j).simplify.value
        sum = (0..top).reduce(RCAS::Num.new(0)) { |inner, l| inner + term.subs(N => i + j, K => l).simplify }
        acc + c.subs(N => i) * sum
      end
      assert_predicate total.simplify, :zero?, "the recurrence fails at n = #{i}"
    end
  end

  def test_the_binomial_theorem
    assert_equal "S(1 + n) - 2*S(n) = 0", recursion(binomial(N, K))
    assert_recurrence binomial(N, K), [RCAS::Num.new(-2), RCAS::Num.new(1)]
  end

  def test_the_square_of_a_binomial_coefficient
    assert_equal "S(n)*(-2 - 4*n) + S(1 + n)*(1 + n) = 0", recursion(binomial(N, K)**2)
    assert_recurrence binomial(N, K)**2, [-2 - 4 * N, 1 + N]
  end

  # Dixon's: three binomial coefficients need an order of two.
  def test_the_cube_needs_a_second_order_recurrence
    expected = "S(1 + n)*(-16 - 21*n - 7*n**2) + S(n)*(-8 - 16*n - 8*n**2) + S(2 + n)*(4 + 4*n + n**2) = 0"
    assert_equal expected, recursion(binomial(N, K)**3)
    assert_recurrence binomial(N, K)**3, [-8 - 16 * N - 8 * N**2, -16 - 21 * N - 7 * N**2, 4 + 4 * N + N**2]
  end

  def test_a_second_parameter_is_carried_along
    assert_equal "S(n)*(-1 - m - n) + S(1 + n)*(1 + n) = 0", recursion(binomial(N, K) * binomial(M, K))
  end

  def test_the_certificate_proves_it
    r = RCAS.sumcertificate(binomial(N, K), K, s)
    assert_equal "k/(-1 + k - n)", r.to_s
    # sigma_0*F(n, k) + sigma_1*F(n + 1, k) = G(k + 1) - G(k) with G = r*F
    f = binomial(N, K)
    g = (r * f)
    left = -2 * f + f.subs(N => N + 1)
    right = g.subs(K => K + 1) - g
    (0..4).each do |i|
      (0..4).each do |j|
        next if j == i || j == i + 1 # G has its pole where k - n - 1 = 0
        assert_equal left.subs(n: i, k: j).simplify.to_s, right.subs(n: i, k: j).simplify.to_s, "n = #{i}, k = #{j}"
      end
    end
  end

  # The identity holds under the summation sign, but 1/(k + 1) has a pole at
  # k = -1, so the sum does not obey the recurrence and we say so.
  def test_boundary_terms_that_do_not_vanish_are_refused
    error = assert_raises(NotImplementedError, RCAS::Unsupported) { recursion(binomial(N, K) / (K + 1)) }
    assert_match(/boundary terms/, error.message)
  end

  def test_no_recurrence_at_all
    assert_raises(NotImplementedError, RCAS::Unsupported) { recursion(1 / (K**2 + 1) + N) }
  end

  # sum() reaches for creative telescoping when nothing else works.
  def test_definite_sums_get_a_closed_form
    value = RCAS.sum(binomial(N, K)**2, K, 0, N)
    assert_equal "binomial(2*n, n)", value.to_s, "the gammas read back as the binomial they are"
    (0..6).each do |i|
      expected = (0..i).sum { |l| RCAS.binomial(i, l).value**2 }
      assert_equal expected, value.subs(n: i).simplify.value, "n = #{i}"
    end
  end

  def test_a_sum_without_a_hypergeometric_closed_form_stays_a_sum
    assert_kind_of RCAS::Sum, RCAS.sum(binomial(N, K)**3, K, 0, N)
  end
end
