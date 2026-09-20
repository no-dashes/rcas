# frozen_string_literal: true

require_relative "test_helper"

class SolveTest < Minitest::Test
  include RCAS::Sets

  def s(*a, **kw) = RCAS.solve(*a, **kw)

  def teardown = RCAS.forget

  X = RCAS::Var.new(:x)

  # What the unknown was declared to be keeps the answers honest: a solution
  # that demonstrably does not lie in the domain is not a solution of the
  # question that was asked.
  def test_a_declared_domain_restricts_the_solutions
    RCAS.assume(x: ZZ)
    assert_equal ["0"], s(RCAS.sin(X).eq(0), :x).map(&:to_s), "pi is not an integer"
    assert_empty s(X**2 - 2, :x), "and neither is 2**(1/2)"
    assert_empty s(2 * X - 1, :x)
    assert_equal %w[-2 2], s(X**2 - 4, :x).map(&:to_s)
    RCAS.forget
    RCAS.assume(x: NN)
    assert_equal ["2"], s(X**2 - 4, :x).map(&:to_s), "NN drops the negative one"
    RCAS.forget
    RCAS.assume(x: RR)
    assert_empty s(X**2 + 1, :x), "the complex roots go"
    assert_equal %w[-2**(1/2) 2**(1/2)], s(X**2 - 2, :x).map(&:to_s), "an irrational real stays"
  end

  # domain: says it for one call, without a session-wide assumption.
  def test_the_domain_can_be_named_in_the_call
    assert_empty s(X**2 - 2, :x, domain: ZZ)
    assert_equal ["2"], s(X**2 - 4, :x, domain: NN).map(&:to_s)
    assert_equal ["1/2"], s(2 * X - 1, :x, domain: QQ).map(&:to_s)
    assert_equal ["{pi/4 + pi*k | k in ZZ}"], s(RCAS.tan(X) - 1, :x, domain: RR).map(&:to_s),
                 "every real solution, since every one of them is real"
    assert_equal %w[-2**(1/2) 2**(1/2)], s(X**2 - 2, :x).map(&:to_s), "and nothing is remembered"
  end

  def test_a_declared_sign_restricts_them_too
    RCAS.assume(X > 0)
    assert_equal ["2"], s(X**2 - 4, :x).map(&:to_s)
    assert_equal ["2**(1/2)"], s(X**2 - 2, :x).map(&:to_s)
    assert_empty s(X**2, :x), "zero is not positive"
    RCAS.forget
    RCAS.assume(X >= 0)
    assert_equal ["0"], s(X**2, :x).map(&:to_s), "but it is non-negative"
  end

  # Nothing is dropped on a guess: a family with a parameter in it, or a
  # constant rcas cannot place, stays in the list.
  def test_what_cannot_be_decided_stays
    RCAS.assume(x: ZZ)
    assert_equal ["0"], s(RCAS.sin(X).eq(0), :x).map(&:to_s),
                 "2*pi*k is an integer only at k = 0, and pi + 2*pi*k never"
    assert_equal ["log(2)"], s(RCAS.exp(X) - 2, :x, domain: QQ).map(&:to_s),
                 "log(2) is irrational, but not for a reason rcas can state"
  end

  def test_a_system_respects_the_domains_of_its_unknowns
    y = RCAS::Var.new(:y)
    RCAS.assume(x: ZZ)
    solutions = s([X + y - 3, X * y - 2], [:x, :y])
    assert_equal [["1", "2"], ["2", "1"]], solutions.map { |sol| [sol[X].to_s, sol[y].to_s] }.sort
    RCAS.forget
    RCAS.assume(x: NN)
    assert_empty s([X + y, X - y - 4], [:x, :y]).select { |sol| sol[X].to_s == "-2" }, "x = -2 is not in NN"
  end
  def strs(list) = list.map(&:to_s)
  def eq(a, b) = RCAS::Equation.new(a, b)

  def test_polynomials_exactly
    assert_equal [1, 2], s(:x**2 - 3 * :x + 2, :x)
    assert_equal [3], s(2 * :x - 6)
    assert_equal ["-2**(1/2)", "2**(1/2)"], strs(s(:x**2 - 2, :x))
    assert_equal ["-1/2 - i*3**(1/2)/2", "-1/2 + i*3**(1/2)/2"], strs(s(:x**2 + :x + 1, :x))
    assert_equal ["-i", "i"], strs(s(eq(:x**2, -1), :x))
    assert_equal ["2", "-1 - i*3**(1/2)", "-1 + i*3**(1/2)"], strs(s(:x**3 - 8, :x))
    assert_equal ["-1", "1", "-i", "i"], strs(s(:x**4 - 1, :x))
    assert_equal [1], s((:x - 1)**3, :x), "multiple roots reported once"
    assert_equal [], s(:x**2 + 1 - :x**2 + 1, :x)
    # 0 = 0 is a true statement, not a failure: every real number solves it
    assert_equal RCAS::RealSet.reals, RCAS.solve(:x - :x, :x)
    assert_equal "(-oo, oo)", RCAS.solve(:x - :x, :x).to_s
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
    assert_equal ["pi/6", "5*pi/6"], strs(s(RCAS.sin(:x) - Rational(1, 2), :x, principal: true))
    assert_equal ["-pi/2", "pi/2"], strs(s(RCAS.cos(:x), :x, principal: true))
    assert_equal ["pi/4"], strs(s(RCAS.tan(:x) - 1, :x, principal: true))
    # and without asking, the whole family
    assert_equal ["{pi/4 + pi*k | k in ZZ}"], strs(s(RCAS.tan(:x) - 1, :x))
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
    assert_equal ["pi/6", "5*pi/6"], RCAS.solve(RCAS.sin(:x) - Rational(1, 2), :x, principal: true).map(&:to_s),
                 "one period when it is asked for"
    assert_equal ["{pi/6 + 2*pi*k | k in ZZ}", "{5*pi/6 + 2*pi*k | k in ZZ}"],
                 RCAS.solve(RCAS.sin(:x) - Rational(1, 2), :x).map(&:to_s), "and every solution by default"
    assert_equal ["{pi/4 + pi*k | k in ZZ}"], RCAS.solve(RCAS.tan(:x) - 1, :x).map(&:to_s), "tan has period pi"
    assert_equal ["{pi/2 + pi*k | k in ZZ}"], RCAS.solve(RCAS.cos(:x), :x).map(&:to_s),
                 "the two families of a period apart are one of half the period"
    assert_equal ["{pi/12 + pi*k | k in ZZ}", "{5*pi/12 + pi*k | k in ZZ}"],
                 RCAS.solve(RCAS.sin(2 * :x) - Rational(1, 2), :x).map(&:to_s)
    assert_equal ["log(3)"], RCAS.solve(RCAS.exp(:x) - 3, :x).map(&:to_s), "no period to add"
    assert_equal ["-2**(1/2)", "2**(1/2)"], RCAS.solve(:x**2 - 2, :x).map(&:to_s)
    # the answer checks out against the equation it solves, with no assumption from the reader
    assert_equal ["1/2", "1/2"], RCAS.solve(RCAS.sin(:x) - Rational(1, 2), :x)
                                     .map { |set| set.map { |e| RCAS.sin(e).simplify }.to_s }
    # the parameter avoids the names already in the equation
    assert_includes RCAS.solve(RCAS.sin(:k * :x), :x, all: true).map(&:to_s).join(" "), "n"
    # every member of the family really is a solution
    family = RCAS.solve(RCAS.sin(:x) - Rational(1, 2), :x).first
    (-2..2).each { |i| assert_in_delta 0.5, RCAS.sin(family.at(i)).evalf, 1e-12 }
  end

  def test_a_ruby_comparison_is_explained
    error = assert_raises(ArgumentError) { RCAS.solve(:x**2 == 4, :x) }
    assert_includes error.message, "eq(lhs, rhs)"
    assert_equal [-2, 2], RCAS.solve(RCAS::Equation.new(:x**2, 4), :x).map { |r| r.to_s.to_i }
  end
  def test_absolute_values_and_sign_are_split_into_cases
    abs = ->(e) { RCAS.abs(e) }
    assert_equal ["-1", "1"], strs(s(abs[:x] - 1, :x))
    assert_equal ["-1", "5"], strs(s(abs[:x - 2] - 3, :x))
    assert_empty s(abs[:x] + 1, :x), "|x| = -1 has no solution"
    assert_equal ["-5**(1/2)", "-3**(1/2)", "3**(1/2)", "5**(1/2)"], strs(s(abs[:x**2 - 4] - 1, :x))
    assert_equal ["-1", "2"], strs(s(abs[:x] + abs[:x - 1] - 3, :x)), "two absolute values, four cases"
    assert_equal ["2"], strs(s(:x * abs[:x] - 4, :x)), "the root of the other branch does not lie in it"
    assert_equal ["0"], strs(s(RCAS.sign(:x), :x)), "sign vanishes where its argument does"
    assert_equal ["-1", "1"], strs(s(RCAS.sign(:x) * :x - 1, :x))
    assert_equal ["-pi/6", "pi/6", "5*pi/6", "7*pi/6"],
                 strs(s(abs[RCAS.sin(:x)] - Rational(1, 2), :x, principal: true))
  end

  def test_a_whole_branch_of_solutions_says_so
    error = assert_raises(ArgumentError) { s(RCAS.abs(:x) - :x, :x) }
    assert_equal "every x with x >= 0 solves abs(x) - x = 0", error.message
    error = assert_raises(ArgumentError) { s(RCAS.sign(:x) - 1, :x) }
    assert_equal "every x with x > 0 solves -1 + sign(x) = 0", error.message
  end

  # Two school-standard equations that used to raise NotImplementedError.
  # Squaring and combining logarithms both invent roots, so the answers are
  # kept only where the original equation is defined and true.
  def test_radical_and_logarithmic_equations
    x = RCAS::Var.new(:x)
    assert_equal ["3"], strs(RCAS.solve(RCAS.eq(RCAS.sqrt(x + 1), x - 1), x))
    assert_equal ["4"], strs(RCAS.solve(RCAS.eq(RCAS.sqrt(x), 2), x))
    assert_equal ["1"], strs(RCAS.solve(RCAS.eq(RCAS.sqrt(x + 3), x + 1), x)), "x = -2 solves the square, not this"
    assert_empty RCAS.solve(RCAS.eq(RCAS.sqrt(x), -1), x)
    assert_equal ["3/2 + (9 + 4*e)**(1/2)/2"], strs(RCAS.solve(RCAS.eq(RCAS.log(x) + RCAS.log(x - 3), 1), x))
    assert_equal ["4"], strs(RCAS.solve(RCAS.eq(RCAS.log(x) - RCAS.log(x - 3), RCAS.log(4)), x))
  end

  # The order roots happen to be found in is not an answer about them.
  def test_real_roots_come_back_in_order
    x = RCAS::Var.new(:x)
    assert_equal ["-2", "-1", "1", "2"], strs(RCAS.solve(x**4 - 5 * x**2 + 4, x))
    assert_equal ["0", "1"], strs(RCAS.solve(x**2 - x, x))
    assert_equal ["-i", "i"], strs(RCAS.solve(x**2 + 1, x)), "no order to impose on these"
    assert_equal ["1", "-1/2 - i*3**(1/2)/2", "-1/2 + i*3**(1/2)/2"], strs(RCAS.solve(x**3 - 1, x))
  end

  # An equation rcas cannot solve says where the numbers are.
  def test_the_message_points_at_nsolve
    e = assert_raises(NotImplementedError) { RCAS.solve(RCAS.cos(:x) - :x, :x) }
    assert_match(/nsolve/, e.message)
  end

  # A product vanishes where one of its factors does, so a product no rule
  # takes whole is still several easy equations: solve of
  # (x + 1)*(x - 2)*sin(x) raised NotImplementedError.
  def test_a_product_is_solved_factor_by_factor
    x = RCAS::Var.new(:x)
    assert_equal ["-1", "0", "2", "pi"], strs(RCAS.solve((x + 1) * (x - 2) * RCAS.sin(x), x, principal: true))
    assert_equal ["-1", "2", "{pi*k | k in ZZ}"],
                 strs(RCAS.solve((x + 1) * (x - 2) * RCAS.sin(x), x))
    assert_equal ["2"], strs(RCAS.solve(RCAS.exp(x) * (x - 2), x)), "exp is never zero"
    assert_equal ["-1", "2"], strs(RCAS.solve(RCAS.sqrt(x + 1) * (x - 2), x))
    assert_equal ["0", "1", "pi"], strs(RCAS.solve((x - 1)**2 * RCAS.sin(x), x, principal: true))
    assert_equal ["-2", "2"], strs(RCAS.solve((x**2 - 4) * RCAS.exp(-x), x))
    assert_equal ["0", "pi"], strs(RCAS.solve(RCAS.sin(x) / (x - 2), x, principal: true)), "a denominator has no roots"
    # the product the normal form has already multiplied out
    assert_equal ["1", "2"], strs(RCAS.solve((x - 2) * RCAS.log(x) / x, x))
    assert_equal ["-1", "0", "pi"], strs(RCAS.solve(RCAS.sin(x) * x + RCAS.sin(x), x, principal: true))
    assert_equal [["log(x)", "-2 + x"]],
                 [RCAS::Simplify.common_factor((RCAS.log(x) * x - 2 * RCAS.log(x)).simplify).map(&:to_s)]
  end

  # A root of one factor solves the product only where the rest of the
  # product is defined: log(x)*(x**2 - 4) does not vanish at -2, and
  # x*sqrt(x - 1) does not vanish at 0.
  def test_a_products_roots_are_checked_against_the_whole_product
    x = RCAS::Var.new(:x)
    assert_equal ["1", "2"], strs(RCAS.solve(RCAS.log(x) * (x**2 - 4), x))
    assert_equal ["1"], strs(RCAS.solve(x * RCAS.sqrt(x - 1), x))
    assert_equal ["1", "2"], strs(RCAS.solve((x - 2) * RCAS.log(x) / x, x))
    assert_equal ["-1", "0", "2", "pi"],
                 strs(RCAS.solve((x + 1) * (x - 2) * RCAS.sin(x), x, principal: true)), "and nothing lost"
  end

  # "Every value of x" is every value x can take: with x an integer,
  # sin(pi*x) vanishes on ZZ, and the real line would be an overstatement.
  def test_every_value_means_every_value_the_unknown_can_take
    x = RCAS::Var.new(:x)
    assert_equal RCAS::RealSet.reals, RCAS.solve(x - x, x)
    assert_equal RCAS::ZZ, RCAS.solve(x - x, x, domain: RCAS::ZZ)
    RCAS.assume(x: RCAS::ZZ) do
      assert_equal RCAS::ZZ, RCAS.solve(RCAS.sin(RCAS::PI * x), x)
    end
    assert_equal ["ZZ"], strs(RCAS.solve(RCAS.sin(RCAS::PI * x), x)),
                 "undeclared: every solution, which is every integer, and it says so"
  end

  # Every term of the same total degree in sin(u) and cos(u): divide by
  # cos(u)**n and it is a polynomial in tan(u). sin(x) + cos(x) = 0 raised
  # NotImplementedError, where it is tan(x) = -1.
  def test_homogeneous_in_sine_and_cosine
    x = RCAS::Var.new(:x)
    assert_equal ["{3*pi/4 + pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x) + RCAS.cos(x), x))
    assert_equal ["{pi/4 + pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x) - RCAS.cos(x), x))
    assert_equal ["{-atan(2) + pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x) + 2 * RCAS.cos(x), x))
    assert_equal ["{pi/4 + pi*k/2 | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x)**2 - RCAS.cos(x)**2, x))
    assert_equal ["{3*pi/8 + pi*k/2 | k in ZZ}"], strs(RCAS.solve(RCAS.sin(2 * x) + RCAS.cos(2 * x), x))
    # and the members really solve it
    [RCAS.sin(x) + RCAS.cos(x), RCAS.sin(2 * x) + RCAS.cos(2 * x)].each do |f|
      set = RCAS.solve(f, x).first
      (-3..3).each { |i| assert_in_delta 0.0, f.evalf(x: set.at(i).evalf), 1e-12, "#{f} at #{set.at(i)}" }
    end
    # a term of another degree is not this rule's business
    assert_raises(NotImplementedError) { RCAS.solve(RCAS.sin(x) + RCAS.cos(x) + 1, x) }
  end

  # One factor rcas cannot solve means roots it cannot name: a partial list
  # would say nothing about what is missing, so the message stands.
  def test_a_product_with_an_unsolvable_factor_still_says_so
    x = RCAS::Var.new(:x)
    e = assert_raises(NotImplementedError) { RCAS.solve(RCAS.sin(x) * (x - RCAS.cos(x)), x) }
    assert_match(/nsolve/, e.message)
  end

  # The set itself: what it prints as, what it is made of, and what can be
  # asked of it without taking it apart.
  def test_an_image_set_is_an_object
    k = RCAS::Var.new(:k)
    set = RCAS::ImageSet.new((RCAS::PI / 6 + 2 * RCAS::PI * k).simplify, k)
    assert_equal "{pi/6 + 2*pi*k | k in ZZ}", set.to_s
    assert_equal "\\left\\{ \\frac{\\pi}{6} + 2 \\pi k \\mid k \\in \\mathbb{Z} \\right\\}", set.to_latex
    assert_equal "pi/6", set.at(0).to_s
    assert_equal "25*pi/6", set.at(2).to_s
    assert_equal [], set.variables, "k belongs to the set, not to the reader"
    assert_equal RCAS::ZZ, set.domain
    assert_equal set, RCAS::ImageSet.new((RCAS::PI / 6 + 2 * RCAS::PI * k).simplify, [k])
    refute_equal set, RCAS::ImageSet.new((RCAS::PI / 6 + 2 * RCAS::PI * k).simplify, k, RCAS::RR)
    # the members between two numbers, and nil when there are more than asked for
    assert_equal ["pi/6", "13*pi/6"], set.between(0.0, 8.0).map(&:to_s)
    assert_nil set.between(0.0, 1e6, limit: 64)
    # map keeps the family when the parameter survives and drops it when not
    assert_equal "{1 + pi/6 + 2*pi*k | k in ZZ}", set.map { |e| (e + 1).simplify }.to_s
    assert_equal "1/2", set.map { |e| RCAS.sin(e).simplify }.to_s
    assert_empty RCAS.assumptions, "the parameter's domain is the set's business, not the session's"
  end

  # Families of one period that repeat the same set, or that together make
  # a finer one, are merged: sin(x)**2 = 1 was three sets of which two were
  # literally the same, and all three together are {pi/2 + pi*k}.
  def test_families_of_the_same_period_are_merged
    x = RCAS::Var.new(:x)
    assert_equal ["{pi/2 + pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x)**2 - 1, x))
    assert_equal ["{pi*k/2 | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x) * RCAS.cos(x), x))
    assert_equal ["{pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x), x))
    assert_equal ["ZZ"], strs(RCAS.solve(RCAS.sin(RCAS::PI * x), x)), "{k | k in ZZ} is ZZ"
    # two families a third of a period apart are not one family
    assert_equal ["{pi/6 + 2*pi*k | k in ZZ}", "{5*pi/6 + 2*pi*k | k in ZZ}"],
                 strs(RCAS.solve(RCAS.sin(x) - Rational(1, 2), x))
    # and every member of the merged set really solves the equation
    set = RCAS.solve(RCAS.sin(x)**2 - 1, x).first
    (-3..3).each { |i| assert_in_delta 1.0, RCAS.sin(set.at(i)).evalf**2, 1e-12 }
  end

  # (-1)**x = 1 holds for every even x, not just for 0: a base of modulus
  # one repeats, and the logarithm route answered with one member of the
  # family. cos(pi*x) rewrites to (-1)**x when x is an integer, so this is
  # what that equation comes to.
  def test_a_root_of_unity_has_a_period_too
    x = RCAS::Var.new(:x)
    assert_equal ["{2*k | k in ZZ}"], strs(RCAS.solve((-1)**x - 1, x))
    assert_equal ["{1 + 2*k | k in ZZ}"], strs(RCAS.solve((-1)**x + 1, x))
    assert_empty RCAS.solve((-1)**x - 2, x)
    assert_equal ["{4*k | k in ZZ}"], strs(RCAS.solve(RCAS::I**x - 1, x))
    assert_equal ["2"], strs(RCAS.solve(2**x - 4, x)), "no period when the base is bigger than one"
    assert_equal ["0"], strs(RCAS.solve((-1)**x - 1, x, principal: true))
    RCAS.assume(x: ZZ) do
      assert_equal ["{1 + 2*k | k in ZZ}"], strs(RCAS.solve(RCAS.cos(RCAS::PI * x) + 1, x)),
                   "the odd integers, not just the first of them"
      assert_equal ["{2*k | k in ZZ}"], strs(RCAS.solve(RCAS.cos(RCAS::PI * x) - 1, x))
    end
  end

  # tan(z) = i has no root anywhere in the complex plane, so inverting the
  # tangent there invents solutions: sin(x)**2 + cos(x)**2 = 0 came back as
  # two families built on atan(-i) and atan(i), which are not numbers at
  # all. cos(x) = 2 is a different case and keeps its families - the cosine
  # does reach 2, at i*log(2 + sqrt(3)).
  def test_the_tangent_never_takes_i
    x = RCAS::Var.new(:x)
    assert_empty RCAS.solve(RCAS.tan(x) - RCAS::I, x)
    assert_empty RCAS.solve(RCAS.tan(x) + RCAS::I, x)
    assert_equal ["{atan(2*i) + pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.tan(x) - 2 * RCAS::I, x))
    assert_equal ["{acos(2) + 2*pi*k | k in ZZ}", "{-acos(2) + 2*pi*k | k in ZZ}"],
                 strs(RCAS.solve(RCAS.cos(x) - 2, x))
  end

  # sin(x)**2 + cos(x)**2 is 1 however it is written, and Scalar.zero? only
  # sees it after trigsimp: the identity is every x, and the two equations
  # beside it have no solutions at all rather than "can't solve".
  def test_a_trigonometric_identity_is_an_answer
    x = RCAS::Var.new(:x)
    assert_equal "(-oo, oo)", RCAS.solve(RCAS.sin(x)**2 + RCAS.cos(x)**2 - 1, x).to_s
    assert_equal "(-oo, oo)", RCAS.solve(RCAS.cosh(x)**2 - RCAS.sinh(x)**2 - 1, x).to_s
    assert_empty RCAS.solve(RCAS.sin(x)**2 + RCAS.cos(x)**2, x)
    assert_empty RCAS.solve(RCAS.sin(x)**2 + RCAS.cos(x)**2 + 1, x)
    RCAS.assume(x: ZZ) do
      assert_equal "ZZ", RCAS.solve(RCAS.sin(x)**2 + RCAS.cos(x)**2 - 1, x).to_s,
                   "every value of x, and x was declared an integer"
    end
    # an equation no rule can take is still unsolved, not "no solutions"
    assert_raises(NotImplementedError) { RCAS.solve(RCAS.sin(x) + x, x) }
    assert_raises(NotImplementedError) { RCAS.solve(x + RCAS.cos(x) * RCAS.sin(x), x) }
  end

  # sin(x)*cos(x) = 1/2 is homogeneous once the 1/2 is read as
  # (sin(x)**2 + cos(x)**2)/2, which is the trick the identity is taught
  # for. A term short of the top degree by an odd number has no such
  # reading, and the rule declines rather than guessing.
  def test_a_constant_term_is_raised_to_the_common_degree
    x = RCAS::Var.new(:x)
    assert_equal ["{pi/4 + pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x) * RCAS.cos(x) - Rational(1, 2), x))
    assert_equal ["{3*pi/4 + pi*k | k in ZZ}"], strs(RCAS.solve(RCAS.sin(x) * RCAS.cos(x) + Rational(1, 2), x))
    set = RCAS.solve(RCAS.sin(x) * RCAS.cos(x) - Rational(1, 2), x).first
    (-3..3).each { |i| assert_in_delta 0.5, (RCAS.sin(set.at(i)) * RCAS.cos(set.at(i))).evalf, 1e-12 }
    # the odd gap is left to the substitution that already answers it
    assert_equal ["{pi/6 + 2*pi*k | k in ZZ}", "{5*pi/6 + 2*pi*k | k in ZZ}"],
                 strs(RCAS.solve(RCAS.sin(x) - Rational(1, 2), x))
  end

  # A root of one factor solves the product only where the rest of it is
  # defined, and asin is the first condition with an upper bound as well
  # as a lower one: 3 is a root of x - 3 and asin(3) is not a real number,
  # so it is not a root of the product.
  def test_a_factor_root_outside_the_inverse_interval_is_dropped
    x = RCAS::Var.new(:x)
    assert_equal ["0"], strs(RCAS.solve(RCAS.asin(x) * (x - 3), x))
    assert_equal ["1"], strs(RCAS.solve(RCAS.acos(x) * (x + 2), x))
    assert_equal ["1"], strs(RCAS.solve(RCAS.asin(x - 1) * (x - 3), x))
    # and a root inside the interval is kept
    assert_equal ["0", "1/2"], strs(RCAS.solve(RCAS.asin(x) * (x - Rational(1, 2)), x))
  end

end
