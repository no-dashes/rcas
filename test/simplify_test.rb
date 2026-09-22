# frozen_string_literal: true

require_relative "test_helper"

class SimplifyTest < Minitest::Test
  def s(expr) = expr.simplify.to_s

  def teardown = RCAS.forget

  # Infinity is an atom in the term tables like any other, so a cancelling
  # one used to come back as a number: oo - oo was 0 and oo/oo was 1.
  def test_infinity_does_not_cancel
    o = RCAS::OO
    assert_equal "undefined", s(o - o)
    assert_equal "undefined", s(o / o)
    assert_equal "undefined", s(RCAS::Num.new(0) * o)
    assert_equal "undefined", s(o * :x / o)
    assert_equal "undefined", s(o - 2 * o) # 2*oo is oo, so this cancels too
    assert_equal "undefined", (o - o).expand.to_s
    assert_equal "undefined", (o / o).expand.to_s
    assert_equal "undefined", ((:x + o) - (:x + o)).expand.to_s
    assert_nil RCAS::Infer.domain(RCAS::UNDEFINED)
    assert_nil RCAS.sign_of(RCAS::UNDEFINED)
    assert_equal "undefined", RCAS::UNDEFINED.diff(:x).to_s
    assert_equal "undefined", RCAS::UNDEFINED.evalf.to_s
  end

  # A power with an exact base 1 or an exact exponent 0 is 1 whatever the
  # other side is, infinity included (the user's call, 22 Sept 2026, as
  # IEEE pow has it). The indeterminate form 1**oo of the calculus books is
  # about a base that tends to 1, which is limit's business; oo/oo, whose
  # table exponent is also 0, still cancels to undefined.
  def test_powers_of_one_and_zero_exponents_of_infinity
    o = RCAS::OO
    assert_equal "1", s(RCAS::Num.new(1)**o)
    assert_equal "1", s(RCAS::Num.new(1)**-o)
    assert_equal "1", s(o**0)
    assert_equal "1", s((-o)**0)
    assert_equal "x", s(:x * o**0)
    assert_equal "1", (o**0).expand.to_s
    assert_equal "undefined", s(o / o)
    assert_equal "e", RCAS.limit((1 + 1 / :x)**:x, :x, o).to_s
  end

  # What infinity does absorb: a numeric factor, a positive power and any
  # finite term beside it. The sign is all that survives.
  def test_infinity_absorbs_the_finite
    o = RCAS::OO
    assert_equal "oo", s(2 * o)
    assert_equal "oo", s(o / 2)
    assert_equal "oo", s(o**2)
    assert_equal "-oo", s(-3 * o)
    assert_equal "0", s(1 / o)
    assert_equal "oo", s(o - 2)
    assert_equal "oo", s(o + :x)
    assert_equal "oo", s(o + o)
    assert_equal "oo*x", s(:x * o), "the sign of x is unknown, so this is not oo"
    assert_equal "-oo + oo*x", s(o * :x - o), "two different infinities say nothing"
  end

  # value**(1.0/n) overflows to Infinity above 10**308: root(10**400, 3)
  # raised FloatDomainError. The integer root is found by bisection.
  def test_roots_of_very_large_integers
    assert_equal "#{10**133}*10**(1/3)", RCAS.root(10**400, 3).to_s
    assert_equal (10**134).to_s, RCAS.root(10**402, 3).to_s
    assert_equal "#{10**200}", RCAS.sqrt(10**400).to_s
    assert_equal "#{10**400 + 1}**(1/3)", RCAS.root(10**400 + 1, 3).to_s
    assert_equal "2", RCAS.cbrt(8).to_s
  end

  # The ordering key of a term is read off its factor map instead of
  # building rebuild_product(1, factors) to ask it; the two must agree, or
  # the canonical order of sums changes.
  def test_the_term_key_agrees_with_the_long_way_round
    rng = Random.new(11)
    x = RCAS::Var.new(:x)
    atoms = [x, RCAS::Var.new(:y), RCAS.sin(x), RCAS.exp(x), x + 1, x * :y - 2, RCAS::PI,
             RCAS.sqrt(2), RCAS::Num.new(2), RCAS.log(:y), 1 / x, RCAS.sqrt(x), x**:y, RCAS::I]
    checked = 0
    2000.times do
      term = (1..rng.rand(1..4)).map { atoms.sample(random: rng)**[1, 2, -1, 3, 1r / 2, -1r / 2].sample(random: rng) }
                                .reduce(RCAS::Num.new([1, 2, -3, 1r / 2].sample(random: rng))) { |a, b| a * b }
      _, factors = RCAS::Simplify.factorize(term, 1, 1, {}, simplify: true)
      long = RCAS::Simplify.sort_key(RCAS::Simplify.rebuild_product(1, factors))
      short = RCAS::Simplify.term_key(factors)
      checked += 1
      assert_equal long, [short[0], short[1], short[2].text], "key of #{factors.inspect}"
    rescue ZeroDivisionError
      next
    end
    assert_operator checked, :>, 1500
  end

  def test_identities
    assert_equal "x", s(:x + 0)
    assert_equal "x", s(:x * 1)
    assert_equal "0", s(:x * 0)
    assert_equal "x", s(:x**1)
    assert_equal "1", s(:x**0)
    assert_equal "1", s(:x / :x)
    assert_equal "0", s(:x - :x)
  end

  def test_like_terms_and_factors
    assert_equal "2*x", s(:x + :x)
    assert_equal "-2*x", s(3 * :x - 5 * :x)
    assert_equal "x**2", s(:x * :x)
    assert_equal "x**(2 + y)", s(:x**2 * :x**:y)
    assert_equal "x", s(RCAS.sqrt(:x) * RCAS.sqrt(:x))
    assert_equal "x", s((:x**Rational(1, 2))**2)
    assert_equal "8*x**3", s((2 * :x)**3)
    assert_equal "x*y**2", s((:x * :y)**2 / :x)
  end

  def test_exact_number_folding
    assert_equal "9 + x", s(2**3 + 1 + :x)
    assert_equal "x/2", s(2**-1 * :x)
    assert_equal "2.0*x", s(1.5 * :x + 0.5 * :x)
    assert_equal "2", s(RCAS.sqrt(4))
    assert_equal "2**(1/2)", s(RCAS.sqrt(2))
    assert_equal "x/3 - y/2", s(:x / 3 - :y / 2)
    assert_raises(ZeroDivisionError) { (:x / 0).simplify }
  end

  def test_canonical_ordering
    assert_equal "1 + 2*x + x**2", s(:x**2 + 2 * :x + 1)
    assert_equal "1 + 2*x + x**2", s(1 + :x * 2 + :x * :x)
    assert_equal "-x - y", s(-:x - :y)
    assert_equal "1 - x", s(-(:x - 1))
    assert_equal "2*x*exp(x**2)", s(RCAS.exp(:x**2) * :x * 2)
    assert_equal (:x + 1).simplify, (1 + :x).simplify
  end

  def test_function_folding
    assert_equal "x", s(RCAS.exp(RCAS.log(:x)))
    assert_equal "1", s(RCAS.cos(0))
    assert_equal "0.0", s(RCAS.sin(0.0))
    assert_equal "sin(x)", s(RCAS.sin(:x))
  end

  def test_expand
    assert_equal "1 - x**2", ((:x + 1) * (1 - :x)).expand.to_s
    assert_equal "x**2 + 2*x*y + y**2", ((:x + :y)**2).expand.to_s
    assert_equal "x**3 - 3*x**2*y + 3*x*y**2 - y**3", ((:x - :y)**3).expand.to_s
    assert_equal "0", (:x**2 + 2 * :x + 1 - (:x + 1)**2).expand.to_s
    assert_equal "1 + x/y", ((:x + :y) / :y).expand.to_s
  end

  # sin**2 + cos**2 = 1 has to be used on every factor of a term, not only on
  # the last one: the length of a surface normal depends on it.
  def test_trigonometric_squares_in_one_term
    u = RCAS::Var.new(:u)
    v = RCAS::Var.new(:v)
    assert_equal "1", RCAS::Trigonometry.trigsimp(RCAS.sin(u)**2 + RCAS.cos(u)**2).to_s
    together = RCAS.cos(u)**2 * RCAS.cos(v)**2 + RCAS.cos(u)**2 * RCAS.sin(v)**2 + RCAS.sin(u)**2
    assert_equal "1", RCAS::Trigonometry.trigsimp(together).to_s
    assert_equal "cosh(u)**2", RCAS::Trigonometry.trigsimp(1 + RCAS.sinh(u)**2).to_s
  end

  # sqrt(c**2*w) is c*sqrt(w) for a c that cannot be negative; the rest of
  # the product stays inside, where its sign is still nobody's business.
  def test_a_nonnegative_factor_leaves_a_root
    a = RCAS::Var.new(:a)
    x = RCAS::Var.new(:x)
    assert_equal "(a**2*x**2)**(1/2)", RCAS.sqrt(a**2 * x**2).simplify.to_s, "nothing is known about a"
    RCAS.assume(a > 0) do
      assert_equal "a*(x**2)**(1/2)", RCAS.sqrt(a**2 * x**2).simplify.to_s
      assert_equal "a*x**(1/2)", RCAS.sqrt(a**2 * x).simplify.to_s
      assert_equal "(a**3*x**2)**(1/2)", RCAS.sqrt(a**3 * x**2).simplify.to_s, "the root has to divide the exponent"
      assert_equal "(a**2*x**2)**(1/4)", RCAS.root(a**2 * x**2, 4).simplify.to_s
    end
    RCAS.assume(a > 0, x > 0) { assert_equal "a*x", RCAS.sqrt(a**2 * x**2).simplify.to_s }
    assert_equal "2*(x**2)**(1/2)", RCAS.sqrt(4 * x**2).simplify.to_s, "a numeric factor came out already"
  end

  # sin and cos repeat every 2*pi, tan every pi, once the multiple is known
  # to be a whole number.
  def test_a_whole_period_drops_out_of_the_argument
    x = RCAS::Var.new(:x)
    k = RCAS::Var.new(:k)
    assert_equal "sin(2*pi*k + x)", RCAS.sin(x + 2 * RCAS::PI * k).simplify.to_s, "k could be 1/2"
    RCAS.assume(k: RCAS::ZZ) do
      assert_equal "sin(x)", RCAS.sin(x + 2 * RCAS::PI * k).simplify.to_s
      assert_equal "cos(x)", RCAS.cos(x + 2 * RCAS::PI * k).simplify.to_s
      assert_equal "tan(x)", RCAS.tan(x + RCAS::PI * k).simplify.to_s
      assert_equal "1", RCAS.cos(2 * RCAS::PI * k).simplify.to_s
      assert_equal "sin(pi*k + x)", RCAS.sin(x + RCAS::PI * k).simplify.to_s, "half a period is not one"
      # the family solve returns checks out against the equation it solves
      family = RCAS.solve(RCAS.sin(x) - Rational(1, 2), :x)
      assert_equal ["{pi/6 + 2*pi*k | k in ZZ}", "{5*pi/6 + 2*pi*k | k in ZZ}"], family.map(&:to_s)
      assert_equal ["1/2", "1/2"], family.map { |set| set.map { |e| RCAS.sin(e).simplify }.to_s }
    end
  end

  def test_numeric_content_leaves_a_root

    root = ->(base, q) { (base**(1 / q.to_r)).simplify.to_s }
    assert_equal "2*(1 - y**2)**(1/2)", root.call(4 - 4 * :y**2, 2)
    assert_equal "2*(-1 + y**2)**(1/2)", root.call(-4 + 4 * :y**2, 2)
    assert_equal "2*(1 + x)**(1/3)", root.call(8 * :x + 8, 3)
    assert_equal "(1 - y**2)**(1/2)/2", root.call(1 / 4r - :y**2 / 4, 2)
    assert_equal "(2 + 2*x)**(1/2)", root.call(2 + 2 * :x, 2) # 2 has no square root to extract
    assert_equal "(4 + 4*x)**(1/3)", root.call(4 + 4 * :x, 3)
    assert_equal "-(1 - y**2)**(1/2)", RCAS.solve(:x**2 + :y**2 - 1, :x).first.to_s
  end

  # exp(u)**v is exp(u*v) only where the choice of branch cannot change:
  # for an integer v, or for a u that is known to be real. In between the
  # rule moves the value. sqrt(exp(2*pi*i)) is sqrt(1) = 1, while the
  # rewritten exp(pi*i) is -1, so substituting and simplifying in the two
  # possible orders disagreed (22 Sept 2026, from a review).
  def test_a_power_of_exp_keeps_its_branch
    x = RCAS::Var.new(:x)
    z = 2 * RCAS::I * RCAS::PI
    f = RCAS.sqrt(RCAS.exp(x))
    assert_equal "exp(x)**(1/2)", f.simplify.to_s, "x is not known to be real"
    assert_equal "1", f.subs(x: z).simplify.to_s
    assert_equal "1", f.simplify.subs(x: z).simplify.to_s, "and simplifying first changes nothing"
    assert_equal "exp(2*x)**(1/2)", (RCAS.exp(2 * x)**(1 / 2r)).simplify.to_s
    assert_equal "exp(x)**(1/3)", (RCAS.exp(x)**(1 / 3r)).simplify.to_s
    assert_equal "exp(x)**x", (RCAS.exp(x)**x).simplify.to_s, "a symbolic exponent is not an integer either"
  end

  # The integer exponents are the ones that stay: a power of exp is then a
  # repeated product, whatever exp(u) is, and the factor tables still have
  # to merge them (every exponential in rcas is stored as a power of e).
  def test_integer_powers_of_exp_still_merge
    x = RCAS::Var.new(:x)
    assert_equal "exp(2*x)", (RCAS.exp(x)**2).simplify.to_s
    assert_equal "exp(-3*x)", (RCAS.exp(x)**-3).simplify.to_s
    assert_equal "exp(-x)", (1 / RCAS.exp(x)).simplify.to_s
    assert_equal "exp(3*x)", (RCAS.exp(x) * RCAS.exp(2 * x)).simplify.to_s
    assert_equal "e", (RCAS.exp(2)**(1 / 2r)).simplify.to_s, "a real u needs no integer exponent"
    assert_equal "1", RCAS.exp(2 * RCAS::I * RCAS::PI).simplify.to_s
  end

  # A declared domain is what makes the rewriting legal again, and the
  # block form of assume cannot leak it into the next test.
  def test_a_real_exponent_may_be_merged_once_it_is_declared
    x = RCAS::Var.new(:x)
    RCAS.assume(x: RCAS::RR) do
      assert_equal "exp(x/2)", RCAS.sqrt(RCAS.exp(x)).simplify.to_s
      assert_equal "exp(2*x/3)", (RCAS.exp(2 * x)**(1 / 3r)).simplify.to_s
      assert_equal "exp(x**2)", (RCAS.exp(x)**x).simplify.to_s
    end
    assert_equal "exp(x)**(1/2)", RCAS.sqrt(RCAS.exp(x)).simplify.to_s, "and it is forgotten afterwards"
  end
end
