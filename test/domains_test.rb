# frozen_string_literal: true

require_relative "test_helper"

class DomainsTest < Minitest::Test
  include RCAS::Sets

  def teardown = RCAS.forget

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
end
