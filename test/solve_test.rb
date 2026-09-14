# frozen_string_literal: true

require_relative "test_helper"

class SolveTest < Minitest::Test
  include RCAS::Sets

  def s(*a) = RCAS.solve(*a)
  def strs(list) = list.map(&:to_s)
  def eq(a, b) = RCAS::Equation.new(a, b)

  def test_polynomials_exactly
    assert_equal [1, 2], s(:x**2 - 3 * :x + 2, :x)
    assert_equal [3], s(2 * :x - 6)
    assert_equal ["-2**(1/2)", "2**(1/2)"], strs(s(:x**2 - 2, :x))
    assert_equal ["-1/2 - i*3**(1/2)/2", "-1/2 + i*3**(1/2)/2"], strs(s(:x**2 + :x + 1, :x))
    assert_equal ["-i", "i"], strs(s(eq(:x**2, -1), :x))
    assert_equal ["2", "-1 - i*3**(1/2)", "-1 + i*3**(1/2)"], strs(s(:x**3 - 8, :x))
    assert_equal ["1", "-1", "-i", "i"], strs(s(:x**4 - 1, :x))
    assert_equal [1], s((:x - 1)**3, :x), "multiple roots reported once"
    assert_equal [], s(:x**2 + 1 - :x**2 + 1, :x)
    assert_raises(ArgumentError) { s(:x - :x, :x) }
  end

  def test_irreducible_cubics_give_root_of
    roots = s(:x**3 - :x - 1, :x)
    assert_equal 3, roots.size
    assert_equal "RootOf(-1 - x + x**3, 0)", roots.first.to_s
    assert roots.first.real?
    assert_in_delta 1.3247179572, roots.first.evalf, 1e-9
    assert RCAS::Scalar.zero?(roots.first**3 - roots.first - 1), "exact arithmetic with the root"
    assert_equal 2, roots.count { |r| !r.real? }
  end

  def test_symbolic_coefficients
    roots = s(:a * :x**2 + :b * :x + :c, :x)
    assert_equal 2, roots.size
    assert_equal "-c/b", s(:b * :x + :c, :x).first.to_s
    RCAS.forget
  end

  def test_rational_and_radical_equations
    assert_equal [Rational(1, 2)], s(1 / :x - 2, :x)
    assert_equal [], s(:x / (:x - 1) - 1, :x)
    assert_equal ["-3**(1/2)", "3**(1/2)"], strs(s(1 / (:x - 1) - 1 / (:x + 1) - 1, :x))
    assert_equal [9], s(RCAS.sqrt(:x) - 3, :x)
    assert_equal [], s(RCAS.sqrt(:x) + 1, :x), "no real solution"
    assert_equal [4], s(:x + RCAS.sqrt(:x) - 6, :x)
  end

  def test_transcendental_equations
    assert_equal ["log(5)"], strs(s(RCAS.exp(:x) - 5, :x))
    assert_equal ["0", "log(2)"], strs(s(RCAS.exp(2 * :x) - 3 * RCAS.exp(:x) + 2, :x))
    assert_equal ["exp(2)"], strs(s(RCAS.log(:x) - 2, :x))
    assert_equal [3], s(2**:x - 8, :x)
    assert_equal ["pi/6", "5*pi/6"], strs(s(RCAS.sin(:x) - Rational(1, 2), :x))
    assert_equal ["pi/2", "-pi/2"], strs(s(RCAS.cos(:x), :x))
    assert_equal ["pi/4"], strs(s(RCAS.tan(:x) - 1, :x))
  end

  def test_linear_systems
    assert_equal [{ :x.to_expr => 2, :y.to_expr => 1 }], s([eq(:x + :y, 3), eq(:x - :y, 1)], [:x, :y])
    sol = s([:x + :y + :z - 1, :x - :y], [:x, :y, :z]).first
    assert_equal "1/2 - z/2", sol[:x.to_expr].to_s
    assert_equal "1/2 - z/2", sol[:y.to_expr].to_s
    assert_nil sol[:z.to_expr], "free variable stays free"
    assert_equal [], s([:x + :y - 1, :x + :y - 2], [:x, :y])
    sol = s([:a * :x + :y - 1, :x - :y], [:x, :y]).first
    assert_equal "1/(1 + a)", sol[:x.to_expr].to_s
    assert_equal "1/(1 + a)", sol[:y.to_expr].to_s
  end

  def test_polynomial_systems
    sols = s([:x**2 + :y**2 - 25, :x + :y - 7], [:x, :y])
    assert_equal [{ :x.to_expr => 4, :y.to_expr => 3 }, { :x.to_expr => 3, :y.to_expr => 4 }], sols
    sols = s([:x**2 + :y**2 - 1, :y - :x**2], [:x, :y])
    assert_equal 4, sols.size
    sols.each { |sol| assert eq(:x**2 + :y**2, 1).holds?(x: sol[:x.to_expr].evalf, y: sol[:y.to_expr].evalf) }
  end

  def test_equation_objects
    e = eq(:x + 1, 3)
    assert_equal "x + 1 = 3", e.to_s
    assert_equal "x + 1 - 1 = 3 - 1", (e - 1).to_s
    assert_equal "x = 2", (e - 1).simplify.to_s
    assert_equal [2], e.solve
    assert e.holds?(x: 2)
    refute e.holds?(x: 3)
    assert_equal "x**2 = 4", :x.eq(4).subs(x: :x**2).to_s
    assert_equal "y = x + 1", RCAS::LaTeX.of(eq(:y, :x + 1))
  end

  def test_eigenvalues_and_eigenvectors
    a = QQ.matrix([[2, 1], [1, 2]])
    assert_equal [1, 3], a.eigenvalues
    assert_equal [[1, 1, ["(-1, 1)"]], [3, 1, ["(1, 1)"]]], a.eigenvectors.map { |l, m, vs| [l, m, vs.map(&:to_s)] }
    assert a.diagonalizable?
    assert_equal ["-i", "i"], strs(QQ.matrix([[0, -1], [1, 0]]).eigenvalues)
    assert_equal [1, 11, 2], QQ.matrix([[2, 0, 0], [0, 3, 4], [0, 4, 9]]).eigenvalues
    j = QQ.matrix([[1, 1], [0, 1]])
    assert_equal [[1, 2, ["(1, 0)"]]], j.eigenvectors.map { |l, m, vs| [l, m, vs.map(&:to_s)] }
    refute j.diagonalizable?
    fib = QQ.matrix([[1, 1], [1, 0]])
    assert_equal ["1/2 - 5**(1/2)/2", "1/2 + 5**(1/2)/2"], strs(fib.eigenvalues)
    fib.eigenvectors.each do |l, _, vs|
      assert_equal 1, vs.size
      v = vs.first
      assert (fib * v - v * l).entries.all? { |e| RCAS::Scalar.zero?(e) }
    end
  end

  def test_positional_call
    assert_equal 82, (:x**2 + 1).call(9)
    assert_equal 9, ZZ[:x].call(:x**2).call(3)
    assert_equal 3, (:x + :y).call(1, 2)
    assert_raises(ArgumentError) { (:x + :y).call(1) }
  end

  def test_cancel_and_rationalize
    assert_equal "1 + x", ((:x**2 - 1) / (:x - 1)).cancel.to_s
    assert_equal "1/(1 + a)", (1 / (:a**2 * (-1 - 1 / :a)) + 1 / :a).cancel.to_s
    assert_equal "-1 + 2**(1/2)", (1 / (1 + RCAS.sqrt(2))).rationalize.to_s
  end
  def test_the_whole_family_of_trigonometric_solutions
    assert_equal ["pi/6", "5*pi/6"], RCAS.solve(RCAS.sin(:x) - Rational(1, 2), :x).map(&:to_s), "one period by default"
    assert_equal ["pi/6 + 2*pi*k", "5*pi/6 + 2*pi*k"], RCAS.solve(RCAS.sin(:x) - Rational(1, 2), :x, all: true).map(&:to_s)
    assert_equal ["pi/4 + pi*k"], RCAS.solve(RCAS.tan(:x) - 1, :x, all: true).map(&:to_s), "tan has period pi"
    assert_equal ["pi/2 + 2*pi*k", "-pi/2 + 2*pi*k"], RCAS.solve(RCAS.cos(:x), :x, all: true).map(&:to_s)
    assert_equal ["pi/12 + pi*k", "5*pi/12 + pi*k"], RCAS.solve(RCAS.sin(2 * :x) - Rational(1, 2), :x, all: true).map(&:to_s)
    assert_equal ["log(3)"], RCAS.solve(RCAS.exp(:x) - 3, :x, all: true).map(&:to_s), "no period to add"
    assert_equal ["-2**(1/2)", "2**(1/2)"], RCAS.solve(:x**2 - 2, :x, all: true).map(&:to_s)
    # the parameter avoids the names already in the equation
    assert_includes RCAS.solve(RCAS.sin(:k * :x), :x, all: true).map(&:to_s).join(" "), "n"
    # every member of the family really is a solution
    family = RCAS.solve(RCAS.sin(:x) - Rational(1, 2), :x, all: true).first
    (-2..2).each { |i| assert_in_delta 0.5, RCAS.sin(family.subs(k: i)).evalf, 1e-12 }
  end

  def test_a_ruby_comparison_is_explained
    error = assert_raises(ArgumentError) { RCAS.solve(:x**2 == 4, :x) }
    assert_includes error.message, "eq(lhs, rhs)"
    assert_equal [2, -2], RCAS.solve(RCAS::Equation.new(:x**2, 4), :x).map { |r| r.to_s.to_i }
  end
end
