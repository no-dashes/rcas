# frozen_string_literal: true

require_relative "test_helper"

class SimplifyTest < Minitest::Test
  def s(expr) = expr.simplify.to_s

  def teardown = RCAS.forget

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
      family = RCAS.solve(RCAS.sin(x) - Rational(1, 2), :x, all: true)
      assert_equal ["pi/6 + 2*pi*k", "5*pi/6 + 2*pi*k"], family.map(&:to_s)
      assert_equal ["1/2", "1/2"], family.map { |s| RCAS.sin(s).simplify.to_s }
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
end
