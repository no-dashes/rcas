# frozen_string_literal: true

require_relative "test_helper"

class DomainsTest < Minitest::Test
  include RCAS::Sets

  def teardown = RCAS.forget

  # assume(x: ZZ) { ... } holds for the block and puts back what was there.
  def test_an_assumption_can_be_scoped_to_a_block
    x = RCAS::Var.new(:x)
    assert_empty RCAS.assume(x: RCAS::ZZ) { RCAS.solve(RCAS.eq(x / 3, Rational(1, 2)), :x) },
                 "3/2 is not an integer, and the block's value comes back"
    assert_empty RCAS.assumptions, "nothing leaks out"

    RCAS.assume(x: RCAS::RR)
    assert_equal RCAS::ZZ, RCAS.assume(x: RCAS::ZZ) { RCAS.assumption(:x) }
    assert_equal RCAS::RR, RCAS.assumption(:x), "what was there before is restored, not forgotten"

    assert_raises(RuntimeError) { RCAS.assume(x: RCAS::NN) { raise "boom" } }
    assert_equal RCAS::RR, RCAS.assumption(:x), "even when the block raises"

    assert_equal RCAS::QQ, RCAS.assume(x: RCAS::ZZ) { RCAS.assume(x: RCAS::QQ) { RCAS.assumption(:x) } }
    assert_equal RCAS::RR, RCAS.assumption(:x), "and they nest"

    RCAS.assume(x: RCAS::ZZ) { RCAS.forget }
    assert_equal RCAS::RR, RCAS.assumption(:x), "a forget inside the block is local too"

    assert_equal ["2"], RCAS.assume(x > 0) { RCAS.solve(x**2 - 4, :x).map(&:to_s) }, "a sign is scoped the same way"
    assert_empty RCAS.signs
    RCAS.forget
  end

  # Every value answers `domain` with the structure it lives in; every
  # structure answers `base` with the domain its entries come from.
  def test_a_value_knows_where_it_lives
    m = (RCAS::ZZ**[2, 2]).random(random: Random.new(1))
    assert_equal "ZZ**[2, 2]", m.domain.to_s
    assert_equal RCAS::ZZ, m.base
    assert_equal m.space, m.domain
    assert_equal "ZZ**3", (RCAS::ZZ**3).random(random: Random.new(1)).domain.to_s
    f = RCAS::ZZ[:x].random(2, random: Random.new(1))
    assert_equal RCAS::ZZ[:x], f.domain
    assert_equal RCAS::ZZ, f.base
    assert_equal RCAS.GF(9), RCAS.GF(9).random(random: Random.new(1)).domain
    assert_equal RCAS.GF(7), RCAS.GF(7).random(random: Random.new(1)).domain, "a Mod knows its field"
    k = RCAS::QQ.adjoin(RCAS.sqrt(2))
    assert_equal k, k.random(random: Random.new(1)).domain
    assert_equal RCAS::QQ, RCAS::Num.new(Rational(1, 2)).domain, "an expression still infers its number set"
  end

  # The spaces are domains like the rest: they compare and they join.
  def test_spaces_are_domains
    assert (RCAS::ZZ**[2, 2]) < (RCAS::QQ**[2, 2])
    refute (RCAS::ZZ**[2, 2]) < (RCAS::QQ**[3, 3])
    assert (RCAS::ZZ**3) < (RCAS::QQ**3)
    assert_equal (RCAS::QQ**[2, 2]), (RCAS::ZZ**[2, 2]).join(RCAS::QQ**[2, 2])
    assert_equal (RCAS::QQ**[2, 2]), (RCAS::ZZ**[2, 2]).join(RCAS::QQ), "joining with a domain of scalars is scaling"
    assert_raises(RCAS::DomainError) { (RCAS::ZZ**[2, 2]).join(RCAS::ZZ**[3, 3]) }
    assert_equal RCAS::ZZ, (RCAS::ZZ**[2, 2]).base
    # a square matrix space is a ring, a shape that is not square is not,
    # and a vector space is neither
    assert (RCAS::ZZ**[2, 2]).ring?
    refute (RCAS::ZZ**[2, 3]).ring?
    refute (RCAS::QQ**[2, 2]).field?
    assert (RCAS::QQ**[1, 1]).field?
    refute (RCAS::QQ**3).ring?
  end

  # in? is the same question the domain answers with include?, asked of the
  # value: an expression, a polynomial, a vector, a matrix, a field element.
  def test_membership_from_the_value
    m = (RCAS::ZZ**[2, 2]).random(random: Random.new(1))
    assert m.in?(RCAS::ZZ**[2, 2])
    assert m.in?(RCAS::QQ**[2, 2])
    refute m.in?(RCAS::ZZ**[3, 3])
    assert_equal (RCAS::ZZ**[2, 2]).include?(m), m.in?(RCAS::ZZ**[2, 2])
    assert (RCAS::ZZ**3).random(random: Random.new(1)).in?(RCAS::ZZ**3)
    assert RCAS::ZZ[:x].random(2, random: Random.new(1)).in?(RCAS::ZZ[:x])
    assert RCAS.GF(9).random(random: Random.new(1)).in?(RCAS.GF(9))
    refute RCAS.GF(7).random(random: Random.new(1)).in?(RCAS.GF(9))
    assert (RCAS::Var.new(:x)**2 + 1).in?(RCAS::ZZ[:x])
  end

  def test_membership_of_numbers
    assert NN.include?(3)
    assert NN.include?(0)
    refute NN.include?(-3)
    assert ZZ.include?(-3)
    assert ZZ.include?(Rational(4, 2))
    refute ZZ.include?(Rational(1, 2))
    assert QQ === Rational(1, 2)
    refute QQ.include?(2.0)
    assert RR.include?(2.0)
    refute RR.include?(Complex(1, 2))
    assert CC.include?(Complex(1, 2))
    assert ZZ.include?(Complex(2, 0))
  end

  def test_chain_of_inclusions
    assert NN < ZZ
    assert ZZ < QQ
    assert QQ < RR
    assert RR < CC
    assert NN <= NN
    refute NN < NN
    refute CC < NN
    assert_equal QQ, ZZ.join(QQ)
    assert_equal QQ, NN.fraction_field
    refute NN.ring?
    assert ZZ.ring?
    refute ZZ.field?
    assert QQ.field?
  end

  def test_declaring_variables
    refute ZZ.include?(:x)
    assert_nil (:x + 1).domain

    :x.in(ZZ)
    assert_equal ZZ, :x.domain
    assert ZZ.include?(:x)
    assert :x.in?(RR)
    refute :x.in?(NN)

    RCAS.assume(n: NN, y: QQ)
    assert_equal({ x: ZZ, n: NN, y: QQ }, RCAS.assumptions)
    assert_equal RCAS::Var.new(:k), ZZ.var(:k)
    assert_equal ZZ, :k.domain

    RCAS.forget(:k)
    assert_nil :k.domain
    assert_raises(TypeError) { RCAS.assume(x: 3) }
    assert_raises(TypeError) { (:x + 1).in(ZZ) }
  end

  def test_domain_inference
    RCAS.assume(x: ZZ, n: NN, y: QQ, r: RR)
    assert_equal ZZ, (:x + 1).domain
    assert_equal ZZ, (:x**2).domain
    assert_equal QQ, (:x / 2).domain
    assert_equal QQ, (:x**-1).domain
    assert_equal NN, (:n + 1).domain
    assert_equal ZZ, (:n - 1).domain
    assert_equal ZZ, (-:n).domain
    assert_equal RR, RCAS.sqrt(:n).domain
    assert_equal CC, RCAS.sqrt(:x).domain
    assert_equal ZZ, (:x**:n).domain
    assert_equal QQ, (:x**(-:n)).domain
    assert_equal RR, RCAS.sin(:y).domain
    assert_equal RR, RCAS.log(:n).domain
    assert_equal CC, RCAS.log(:x).domain
    assert_equal RR, (:r * :x).domain
    assert_equal CC, (Complex(0, 1) * :x).domain
    assert_nil (:x + :unknown).domain
  end

  def test_polynomial_ring_construction
    assert_equal "ZZ[x]", ZZ[:x].to_s
    assert_equal "QQ[x, y]", QQ[:x, :y].to_s
    assert_equal ZZ[:x, :y], ZZ[:x][:y]
    assert_equal ZZ[:x], ZZ[RCAS::Var.new(:x)]
    assert ZZ[:x] < QQ[:x]
    assert QQ[:x] < QQ[:x, :y]
    assert ZZ < ZZ[:x]
    refute ZZ[:x] < ZZ
    assert_equal QQ[:x, :y], ZZ[:x].join(QQ[:y])
    assert_raises(RCAS::DomainError) { NN[:x] }
  end

  def test_polynomial_ring_membership
    r = ZZ[:x]
    assert r.include?(:x**2 + 1)
    assert r.include?((:x + 1) * (:x - 1))
    assert r.include?(:x)
    assert r.include?(3)
    refute r.include?(:x / 2)
    assert QQ[:x].include?(:x / 2)
    refute r.include?(1 / :x)
    refute r.include?(RCAS.sin(:x))
    refute r.include?(:x**:x)
    refute r.include?(:a * :x), "undeclared parameter"
    RCAS.assume(a: ZZ, q: QQ)
    assert r.include?(:a * :x + 1)
    refute r.include?(:q * :x)
    assert QQ[:x].include?(:q * :x)
    assert QQ.include?(QQ[:x].call(3))
    refute QQ.include?(QQ[:x].call(:x))
  end

  def test_fraction_field
    f = ZZ[:x].fraction_field
    assert_equal "Frac(ZZ[x])", f.to_s
    assert f.field?
    assert f.include?((:x + 1) / (:x - 1))
    assert f.include?(:x**-2)
    assert f.include?(Rational(1, 2))
    refute f.include?(RCAS.sin(:x) / :x)
    refute f.include?(RCAS.sqrt(:x))
    assert ZZ[:x] < f
    assert ZZ < f
  end
  def test_the_double_struck_letters
    assert_equal [NN, ZZ, QQ, RR, CC], [RCAS::ℕ, RCAS::ℤ, RCAS::ℚ, RCAS::ℝ, RCAS::ℂ]
    assert_equal ZZ[:x], RCAS::ℤ[:x], "a ring builds from the symbol too"
    assert_equal RCAS::Sets::ℤ, RCAS::Sets::ZZ, "and they come with include RCAS::Sets"
  end

  def test_unicode_printing_is_off_by_default
    refute RCAS.unicode?
    assert_equal "ZZ", ZZ.to_s
    assert_equal "ZZ[x]", ZZ[:x].to_s
    assert_equal "pi", RCAS::PI.to_s
    RCAS.unicode = true
    assert RCAS.unicode?
    assert_equal "ℤ", ZZ.to_s
    assert_equal "ℤ[x]", ZZ[:x].to_s
    assert_equal "Frac(ℤ[x])", ZZ[:x].fraction_field.to_s
    assert_equal "ℚ**3", (QQ**3).to_s
    assert_equal ["π", "∞"], [RCAS::PI.to_s, RCAS::OO.to_s]
    assert_equal "π + x", (RCAS::Var.new(:x) + RCAS::PI).simplify.to_s
    assert_equal '\mathbb{Z}', ZZ.to_latex, "typesetting is unaffected"
    RCAS.unicode = false
    assert_equal "ZZ", ZZ.to_s
    assert_equal "off", (RCAS.unicode = "off") ? "off" : "off"
    refute RCAS.unicode?, "a string switches it too"
  ensure
    RCAS.unicode = false
  end
  def test_sign_assumptions
    refute RCAS.nonnegative?(RCAS::Var.new(:x))
    RCAS.assume(RCAS::Var.new(:x) > 0)
    assert_equal :positive, RCAS.sign_of(RCAS::Var.new(:x))
    assert RCAS.nonnegative?(RCAS::Var.new(:x))
    assert_equal "x", RCAS.sqrt(RCAS::Var.new(:x)**2).simplify.to_s, "the square root of a square is the number itself now"
    assert_equal "x", RCAS.abs(RCAS::Var.new(:x)).simplify.to_s
    assert_equal "x > 0", RCAS.assumptions[:x].to_s, "the sign is listed as the statement it is"
    RCAS.assume(RCAS::Var.new(:z) < 0)
    assert_equal "-z", RCAS.abs(RCAS::Var.new(:z)).simplify.to_s
    RCAS.assume(RCAS::Var.new(:w) >= 0)
    assert_equal "w", RCAS.sqrt(RCAS::Var.new(:w)**2).simplify.to_s
    # products and even powers follow
    assert_equal :nonnegative, RCAS.sign_of(RCAS::Var.new(:q)**2)
    assert_equal :positive, RCAS.sign_of(RCAS::Var.new(:x) * RCAS::Var.new(:x))
    RCAS.forget(:x)
    assert_equal "(x**2)**(1/2)", RCAS.sqrt(RCAS::Var.new(:x)**2).simplify.to_s, "and it is unsafe again once forgotten"
    assert_raises(TypeError) { RCAS.assume(RCAS::Var.new(:x) > 1) }
  ensure
    RCAS.forget
  end
end
