# frozen_string_literal: true

require_relative "test_helper"

class NamedPolynomialsTest < Minitest::Test
  include RCAS::Constants

  Poly = RCAS::Poly

  def x = :x

  # ---- the families, as they are printed ---------------------------------

  def test_chebyshev
    assert_equal ["1", "x", "-1 + 2*x**2", "-3*x + 4*x**3"], (0..3).map { |n| Poly.chebyshev_t(n, x).to_s }
    assert_equal "5*x - 20*x**3 + 16*x**5", Poly.chebyshev_t(5, x).to_s
    assert_equal ["1", "2*x", "-1 + 4*x**2", "-4*x + 8*x**3"], (0..3).map { |n| Poly.chebyshev_u(n, x).to_s }
    assert_equal "1 - 12*x**2 + 16*x**4", Poly.chebyshev_u(4, x).to_s
  end

  def test_legendre_hermite_laguerre
    assert_equal ["1", "x", "-1/2 + 3*x**2/2", "-3*x/2 + 5*x**3/2"], (0..3).map { |n| Poly.legendre(n, x).to_s }
    assert_equal "3/8 - 15*x**2/4 + 35*x**4/8", Poly.legendre(4, x).to_s
    assert_equal ["1", "2*x", "-2 + 4*x**2", "-12*x + 8*x**3"], (0..3).map { |n| Poly.hermite(n, x).to_s }
    assert_equal "3 - 6*x**2 + x**4", Poly.hermite_prob(4, x).to_s
    assert_equal "1 - 3*x + 3*x**2/2 - x**3/6", Poly.laguerre(3, x).to_s
    assert_equal "3 - 3*x + x**2/2", Poly.laguerre(2, x, alpha: 1).to_s
  end

  def test_the_parameters_may_stay_symbolic
    assert_equal "1 + 3*a/2 - 2*x + a**2/2 - a*x + x**2/2", Poly.laguerre(2, x, alpha: :a).to_s
    assert_equal "-alpha + 2*alpha*x**2 + 2*alpha**2*x**2", Poly.gegenbauer(2, x).to_s
    assert_equal "alpha/2 - beta/2 + x + alpha*x/2 + beta*x/2", Poly.jacobi(1, x).to_s
  end

  def test_special_cases_of_the_general_families
    # Gegenbauer at alpha = 1 is Chebyshev of the second kind, at 1/2 Legendre
    (0..4).each do |n|
      assert_equal Poly.chebyshev_u(n, x), Poly.gegenbauer(n, x, alpha: 1), "C_#{n}^1 = U_#{n}"
      assert_equal Poly.legendre(n, x), Poly.gegenbauer(n, x, alpha: Rational(1, 2)), "C_#{n}^(1/2) = P_#{n}"
      assert_equal Poly.legendre(n, x), Poly.jacobi(n, x, alpha: 0, beta: 0), "P_#{n}^(0,0) = P_#{n}"
    end
    # He_n(x) = 2**(-n/2)*H_n(x/sqrt(2))
    assert_equal Poly.hermite_prob(4, x), (Poly.hermite(4, x / RCAS.sqrt(2)) / 4).expand
  end

  def test_the_combinatorial_families
    assert_equal "-1/30 + x**2 - 2*x**3 + x**4", Poly.bernoulli(4, x).to_s
    assert_equal "1/4 - 3*x**2/2 + x**3", Poly.euler(3, x).to_s
    assert_equal "1 - x**2 + x**4", Poly.cyclotomic(12, x).to_s
    assert_equal "1 - 10*x**2 + x**4", Poly.swinnerton_dyer(2, x).to_s
    assert_equal "9*x - 6*x**2 + x**3", Poly.abel(3, x).to_s
    assert_equal "3*x + 4*x**3 + x**5", Poly.fibonacci(6, x).to_s
    assert_equal "5*x + 5*x**3 + x**5", Poly.lucas(5, x).to_s
    assert_equal "x + 7*x**2 + 6*x**3 + x**4", Poly.bell(4, x).to_s
  end

  # ---- the properties that define them -----------------------------------

  def test_orthogonality_on_the_interval
    assert_equal 0, RCAS.integrate(Poly.legendre(2, x) * Poly.legendre(3, x), x: -1..1)
    assert_equal Rational(2, 7), RCAS.integrate(Poly.legendre(3, x)**2, x: -1..1).value
    assert_equal 0, RCAS.integrate(Poly.hermite_prob(1, x) * Poly.hermite_prob(2, x) * RCAS.exp(-:x**2 / 2), x: -RCAS::OO..RCAS::OO)
  end

  def test_the_differential_equations
    (2..5).each do |n|
      p = Poly.legendre(n, x)
      assert_equal 0, ((1 - :x**2) * p.diff(x, 2) - 2 * :x * p.diff(x) + n * (n + 1) * p).expand, "Legendre, n = #{n}"
      h = Poly.hermite(n, x)
      assert_equal 0, (h.diff(x, 2) - 2 * :x * h.diff(x) + 2 * n * h).expand, "Hermite, n = #{n}"
      l = Poly.laguerre(n, x)
      assert_equal 0, (:x * l.diff(x, 2) + (1 - :x) * l.diff(x) + n * l).expand, "Laguerre, n = #{n}"
    end
  end

  def test_chebyshev_is_the_multiple_angle
    t = Poly.chebyshev_t(5, RCAS.cos(:t))
    assert_in_delta Math.cos(5 * 0.7), t.call(t: 0.7).to_f, 1e-12
    u = Poly.chebyshev_u(3, RCAS.cos(:t))
    assert_in_delta Math.sin(4 * 0.7) / Math.sin(0.7), u.call(t: 0.7).to_f, 1e-12
  end

  def test_bernoulli_and_euler_difference_equations
    (1..5).each do |n|
      b = Poly.bernoulli(n, x)
      assert_equal 0, (b.subs(x => :x + 1) - b - n * :x**(n - 1)).expand, "B_#{n}(x + 1) - B_#{n}(x)"
      e = Poly.euler(n, x)
      assert_equal 0, (e.subs(x => :x + 1) + e - 2 * :x**n).expand, "E_#{n}(x + 1) + E_#{n}(x)"
    end
    assert_equal RCAS.bernoulli(6), Poly.bernoulli(6, 0)
  end

  def test_cyclotomic_divides_x_to_the_n_minus_one
    (1..12).each do |n|
      product = RCAS.divisors(n).map { |d| Poly.cyclotomic(d, x) }.reduce(:*)
      assert_equal 0, (product - (:x**n - 1)).expand, "the Phi_d of the divisors of #{n}"
      assert_equal RCAS.totient(n), Poly.cyclotomic(n, x).degree(x)
    end
    # the smallest cyclotomic polynomial with a coefficient outside {-1, 0, 1}
    assert_equal(-2, Poly.cyclotomic(105, x).coeff(x, 7))
    assert Poly.cyclotomic(7, x).factor.to_s.start_with?("1 + x"), "Phi_7 is irreducible over QQ"
  end

  def test_swinnerton_dyer_is_a_minimal_polynomial
    assert_equal RCAS.minpoly(RCAS.sqrt(2) + RCAS.sqrt(3)), Poly.swinnerton_dyer(2, x)
    assert_equal 8, Poly.swinnerton_dyer(3, x).degree(x)
    root = RCAS.sqrt(2) + RCAS.sqrt(3)
    assert RCAS::Scalar.zero?(Poly.swinnerton_dyer(2, root).rationalize), "sqrt(2) + sqrt(3) is a root"
  end

  def test_the_counting_families
    assert_equal [1, 1, 2, 3, 5, 8], (1..6).map { |n| Poly.fibonacci(n, 1) }
    assert_equal [1, 3, 4, 7, 11, 18], (1..6).map { |n| Poly.lucas(n, 1) }
    assert_equal [1, 1, 2, 5, 15, 52, 203], (0..6).map { |n| Poly.bell(n, 1) }
    (1..5).each { |n| assert_equal 0, (Poly.abel(n, x) - :x * (:x - n)**(n - 1)).expand, "A_#{n}" }
    assert_equal "-8*x + x**2", Poly.abel(2, x, a: 4).to_s
  end

  # ---- the edges ---------------------------------------------------------

  def test_degree_zero_and_other_arguments
    assert_equal 1, Poly.legendre(0, x)
    assert_equal 1, Poly.bell(0, x)
    assert_equal 0, Poly.fibonacci(0, x)
    assert_equal 40, Poly.hermite(3, 2)
    assert_equal "1 + 3*y + 3*y**2/2", Poly.legendre(2, 1 + :y).to_s
  end

  def test_a_bad_degree_says_so
    error = assert_raises(ArgumentError) { Poly.legendre(-1, x) }
    assert_includes error.message, "non-negative integer"
    assert_raises(ArgumentError) { Poly.chebyshev_t(Rational(1, 2), x) }
    assert_raises(ArgumentError) { Poly.cyclotomic(0, x) }
  end

  def test_the_names_are_documented
    assert_equal "Poly.legendre(n, x = :x)", RCAS.doc("Poly.legendre").signature
    assert_equal "Poly.chebyshev_t(n, x = :x)", RCAS.doc("chebyshev_t").signature, "the bare name too, when nothing else has it"
    assert_equal "legendre(a, p)", RCAS.doc("legendre").signature, "the bare name stays the Legendre symbol"
    assert_includes RCAS.doc("Poly.bell").background[:maths], "Bell number"
    assert_includes RCAS.doc(:Poly).lines.last, "chebyshev_t"
    assert_equal RCAS::Poly, RCAS::Constants.const_get(:Poly), "the front ends see it under RCAS::Constants"
  end
end
