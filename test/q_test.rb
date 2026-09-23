# frozen_string_literal: true

require_relative "test_helper"

# The q-analogues: q-Pochhammer and friends, q-Gosper, q-Petkovsek and
# q-Zeilberger.
class QFunctionsTest < Minitest::Test
  include RCAS::Functions

  Q = RCAS::Var.new(:q)
  N = RCAS::Var.new(:n)
  K = RCAS::Var.new(:k)
  A = RCAS::Var.new(:a)

  def test_integer_arguments_fold
    assert_equal "(1 - a)*(1 - a*q)*(1 - a*q**2)", qpochhammer(A, Q, 3).to_s
    assert_equal "1", qpochhammer(A, Q, 0).to_s
    assert_equal "1 + q + q**2", qbracket(3, Q).to_s
    assert_equal "1 + 2*q + 2*q**2 + q**3", qfactorial(3, Q).to_s
    assert_equal "1 + q + 2*q**2 + q**3 + q**4", qbinomial(4, 2, Q).to_s
  end

  def test_the_gaussian_binomial_is_the_ordinary_one_at_q_equals_one
    (0..5).each do |n|
      (0..n).each do |k|
        assert_equal RCAS.binomial(n, k).value, qbinomial(n, k, Q).subs(q: 1).simplify.value, "#{n} over #{k}"
      end
    end
  end

  def test_symbolic_arguments_stay
    assert_equal "qbinomial(n, k, q)", qbinomial(N, K, Q).to_s
    assert_equal "qpochhammer(a, q, n)", qpochhammer(A, Q, N).to_s
    # and fold once the index is known
    assert_equal "1 + q", qbinomial(N, K, Q).subs(n: 2, k: 1).simplify.to_s
  end

  def test_the_pieces_the_algorithms_work_with
    pochhammer = RCAS::QFunctions.to_pochhammer(qbinomial(N, K, Q)).to_s
    assert_equal "qpochhammer(q, q, n)/(qpochhammer(q, q, k)*qpochhammer(q, q, -k + n))", pochhammer
    assert_equal "(1 - q**n)/(1 - q)", RCAS::QFunctions.to_pochhammer(qbracket(N, Q)).to_s
  end
end

class QSummationTest < Minitest::Test
  include RCAS::Functions

  Q = RCAS::Var.new(:q)
  N = RCAS::Var.new(:n)
  K = RCAS::Var.new(:k)
  A = RCAS::Var.new(:a)

  # S(k + 1) - S(k) = f(k) at a few integer points, with q a number.
  def assert_telescopes(f, s, q: 3)
    (1..5).each do |i|
      left = (s.subs(K => i + 1) - s.subs(K => i)).subs(Q => q).simplify
      right = f.subs(K => i).subs(Q => q).simplify
      assert_equal right.to_s, left.to_s, "the antidifference fails at k = #{i}"
    end
  end

  def test_the_ratio_is_rational_in_q_to_the_k
    assert_equal "q", RCAS::QSummation.ratio(Q**K, K, Q).to_s
    assert_equal "_qx**2*q", RCAS::QSummation.ratio(Q**(K**2), K, Q).to_s
    assert_equal "1 - a*_qx", RCAS::QSummation.ratio(qpochhammer(A, Q, K), K, Q).to_s
    assert_nil RCAS::QSummation.ratio(RCAS.factorial(K), K, Q), "not q-hypergeometric"
  end

  def test_the_geometric_series
    s = RCAS.qgosper(Q**K, Q, K)
    assert_equal "q**k/(-1 + q)", s.to_s
    assert_telescopes Q**K, s
    assert_equal "-1/(-1 + q) + q**n/(-1 + q)", RCAS.qsum(Q**K, Q, K, 0, N - 1).to_s, "[n]_q"
  end

  def test_a_term_that_telescopes_only_as_a_whole
    s = Q**K / qpochhammer(Q, Q, K)
    f = (s.subs(K => K + 1) - s).simplify
    found = RCAS.qgosper(f, Q, K)
    assert_equal "q**k/qpochhammer(q, q, k)", found.to_s
    assert_telescopes f, found
  end

  def test_a_definite_q_sum
    value = RCAS.qsum(Q**K * qbracket(K, Q), Q, K, 0, N)
    (0..4).each do |n|
      direct = (0..n).reduce(RCAS::Num.new(0)) { |acc, i| acc + (Q**i * qbracket(i, Q)).simplify }
      assert_equal direct.subs(q: 3).simplify.value, value.subs(n: n, q: 3).simplify.value, "n = #{n}"
    end
  end

  def test_what_has_no_q_antidifference
    assert_nil RCAS.qgosper(qbracket(K, Q), Q, K)
    assert_kind_of RCAS::Sum, RCAS.qsum(qbinomial(N, K, Q), Q, K, 0, N)
  end
end

class QDifferenceTest < Minitest::Test
  include RCAS::Functions

  Q = RCAS::Var.new(:q)
  X = RCAS::Var.new(:x)
  A = RCAS::Var.new(:a)
  N = RCAS::Var.new(:n)

  def f(arg) = RCAS::Fn.new(:f, [arg])
  def qsolve(lhs, rhs, **opts) = RCAS.qsolve(RCAS::Equation.new(lhs, rhs), :f, X, Q, **opts)
  def qhyper(lhs, rhs) = RCAS.qhyper(RCAS::Equation.new(lhs, rhs), :f, X, Q).map(&:to_s)

  # u(n + 1) = ratio(q**n)*u(n) for the solution at x = q**n.
  def assert_q_solution(term, ratio, q: 2, a: 3)
    (0..4).each do |m|
      left = term.subs(N => m + 1).simplify.subs(Q => q, A => a).simplify
      right = (term.subs(N => m) * ratio.subs(X => Q**m)).simplify.subs(Q => q, A => a).simplify
      assert_equal right.to_s, left.to_s, "the solution fails at n = #{m}"
    end
  end

  def test_the_q_pochhammer_symbol_solves_its_own_equation
    assert_equal ["1 - a*x"], qhyper(f(Q * X), (1 - A * X) * f(X))
    assert_equal "f(q**n) = C1*qpochhammer(a, q, n)", qsolve(f(Q * X), (1 - A * X) * f(X)).to_s
    assert_q_solution qpochhammer(A, Q, N), 1 - A * X
  end

  def test_powers_and_the_q_gaussian
    assert_equal "f(q**n) = 3**n*C1", qsolve(f(Q * X), 3 * f(X)).to_s
    assert_equal "f(q**n) = C1*q**(n*(-1 + n)/2)", qsolve(f(Q * X), X * f(X)).to_s
    assert_q_solution RCAS::Var.new(:q)**(N * (N - 1) / 2), X
  end

  # (1; q)_n vanishes, so the product starts past the zero.
  def test_a_degenerate_pochhammer_is_shifted
    assert_equal "f(q**n) = C1/qpochhammer(q, q, -1 + n)", qsolve((1 - X) * f(Q * X), f(X)).to_s
  end

  def test_second_order_with_constant_ratios
    assert_equal "f(q**n) = 2**n*C1 + 3**n*C2", qsolve(f(Q**2 * X), 5 * f(Q * X) - 6 * f(X)).to_s
  end

  def test_equations_without_q_hypergeometric_solutions
    assert_empty qhyper(f(Q**2 * X), f(Q * X) + X * f(X)) # q-Airy
    assert_raises(NotImplementedError, RCAS::Unsupported) { qsolve(f(Q**2 * X), f(Q * X) + X * f(X)) }
  end

  def test_the_index_can_be_named
    assert_equal "f(q**m) = C1*qpochhammer(a, q, m)", qsolve(f(Q * X), (1 - A * X) * f(X), n: :m).to_s
  end
end

class QZeilbergerTest < Minitest::Test
  include RCAS::Functions

  Q = RCAS::Var.new(:q)
  N = RCAS::Var.new(:n)
  K = RCAS::Var.new(:k)
  Z = RCAS::Var.new(:z)

  def s = RCAS::Fn.new(:S, [N])
  def recursion(term) = RCAS.qsumrecursion(term, K, Q, s).to_s

  def assert_q_recurrence(term, coefficients)
    (0..3).each do |i|
      total = coefficients.each_with_index.reduce(RCAS::Num.new(0)) do |acc, (c, j)|
        sum = (0..(i + j)).reduce(RCAS::Num.new(0)) { |inner, l| inner + term.subs(N => i + j, K => l).simplify }
        acc + c.subs(N => i) * sum
      end
      assert_predicate total.subs(q: 3, z: 2).simplify, :zero?, "the recurrence fails at n = #{i}"
    end
  end

  # The Galois numbers: G(n + 2) = 2*G(n + 1) + (q**(n + 1) - 1)*G(n).
  def test_the_sum_of_the_gaussian_binomial_coefficients
    assert_equal "-2*S(1 + n) + S(2 + n) + S(n)*(1 - q**(1 + n)) = 0", recursion(qbinomial(N, K, Q))
    assert_q_recurrence qbinomial(N, K, Q), [1 - Q**(N + 1), RCAS::Num.new(-2), RCAS::Num.new(1)]
  end

  # The q-binomial theorem: the sum is (-z; q)_n.
  def test_the_q_binomial_theorem
    term = qbinomial(N, K, Q) * Q**(K * (K - 1) / 2) * Z**K
    assert_equal "S(1 + n) + S(n)*(-1 - q**n*z) = 0", recursion(term)
    assert_q_recurrence term, [-1 - Q**N * Z, RCAS::Num.new(1)]
    # and the recurrence is the q-difference equation the q-Pochhammer solves
    x = RCAS::Var.new(:x)
    solved = RCAS.qsolve(RCAS::Equation.new(RCAS::Fn.new(:f, [Q * x]), (1 + Z * x) * RCAS::Fn.new(:f, [x])), :f, x, Q)
    assert_equal "f(q**n) = C1*qpochhammer(-z, q, n)", solved.to_s
  end

  def test_the_certificate
    term = qbinomial(N, K, Q) * Q**(K * (K - 1) / 2) * Z**K
    assert_includes RCAS.qsumcertificate(term, K, Q, s).to_s, "q**k"
  end

  def test_no_recurrence_within_the_order
    assert_raises(NotImplementedError, RCAS::Unsupported) { recursion(qbinomial(N, K, Q)**2) }
  end
end
