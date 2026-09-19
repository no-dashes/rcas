# frozen_string_literal: true

require_relative "test_helper"

class NumberTheoryTest < Minitest::Test
  include RCAS::Functions

  def test_factor_integers
    assert_equal "2**3*3**2*5", factor(360).to_s
    assert_equal "-(2**2*3)", factor(-12).to_s
    assert_equal "1", factor(1).to_s
    assert_equal "97", factor(97).to_s
    assert_equal [[2, 3], [3, 2], [5, 1]], factor(360).factors
    assert_equal 360, factor(360).expand
    assert_equal 1, factor(360).unit
    assert factor(97).prime?
    refute factor(360).prime?
    assert_equal factor(360), ifactor(RCAS::Num.new(360))
    assert_raises(ArgumentError) { factor(0) }
  end

  def test_factor_rationals
    assert_equal "2/3", factor(12/18r).to_s
    assert_equal "2**2/3**2", factor(4/9r).to_s
    assert_equal [[2, 2], [3, -2]], factor(4/9r).factors
    assert_equal 4/9r, factor(4/9r).expand
    assert_equal "1/2**3", factor(1/8r).to_s
  end

  def test_factor_large
    assert_equal [[274177, 1], [67280421310721, 1]], factor(2**64 + 1).factors
    assert_equal [[193707721, 1], [761838257287, 1]], factor(2**67 - 1).factors
    assert_equal [[2**89 - 1, 1]], factor(2**89 - 1).factors
    assert_equal [[999983, 1], [1000003, 1], [1000033, 1]], factor(1000003 * 1000033 * 999983).factors
    assert_equal [[1000003, 2]], factor(1000003**2).factors
    assert_equal [[2, 100]], factor(2**100).factors
  end

  def test_primes
    assert isprime(2)
    assert isprime(97)
    assert isprime(2**61 - 1)
    assert isprime(10**30 + 57)
    refute isprime(1)
    refute isprime(0)
    refute isprime(-7)
    refute isprime(2**64 + 1)
    refute isprime(1000003 * 1000033)
    refute isprime(3215031751) # strong pseudoprime to bases 2, 3, 5, 7
    assert_equal 101, nextprime(100)
    assert_equal 2, nextprime(-5)
    assert_equal 18_446_744_073_709_551_629, nextprime(2**64)
    assert_equal 97, prevprime(100)
    assert_equal 2, prevprime(3)
    assert_raises(ArgumentError) { prevprime(2) }
    assert_raises(ArgumentError) { isprime(:x) }
  end

  def test_divisors_and_totient
    assert_equal [1, 2, 3, 4, 6, 12], divisors(12)
    assert_equal [1], divisors(1)
    assert_equal [1, 97], divisors(97)
    assert_equal [1, 2, 3, 4, 6, 12], divisors(-12)
    assert_equal 4, totient(12)
    assert_equal 96, totient(97)
    assert_equal 1, totient(1)
    assert_equal 400, totient(1000)
    assert_raises(ArgumentError) { divisors(0) }
  end

  def test_modular_arithmetic
    assert_equal 5, invmod(3, 7)
    assert_equal 1, invmod(1, 2)
    assert_equal 5, invmod(10, 7)
    assert_raises(ZeroDivisionError) { invmod(2, 4) }
    assert_equal 8, chrem([2, 3], [3, 5])
    assert_equal 23, chrem([2, 3, 2], [3, 5, 7])
    assert_equal 3, chrem([1, 3], [2, 4])
    assert_raises(ArgumentError) { chrem([1, 2], [2, 4]) }
    assert_raises(ArgumentError) { chrem([1], []) }
  end

  def test_integer_factorization_latex
    assert_equal RCAS::LaTeX.of((2**3 * 3**2 * 5).then { factor(360).to_expr }), factor(360).to_latex
  end
  def test_congruences
    assert_equal [6], RCAS.congruence(3 * :x - 4, :x, 7)
    assert_equal [2, 5], RCAS.congruence(2 * :x - 4, :x, 6), "gcd(2, 6) = 2 solutions"
    assert_equal [], RCAS.congruence(2 * :x - 3, :x, 4), "no solution when the gcd does not divide"
    assert_equal [1, 3, 5, 7], RCAS.congruence(:x**2 - 1, :x, 8), "four square roots of one modulo 8"
    assert_equal [0], RCAS.congruence(:x, :x, 5)
    assert_raises(ArgumentError) { RCAS.congruence(RCAS.sin(:x), :x, 5) }
  end

  def test_quadratic_residues_and_orders
    assert_equal(-1, RCAS.legendre(3, 7))
    assert_equal 1, RCAS.legendre(2, 7)
    assert_equal 0, RCAS.legendre(7, 7)
    assert_equal(-1, RCAS.jacobi(1001, 9907), "the textbook example")
    assert_equal 1, RCAS.jacobi(1, 9)
    assert_equal 6, RCAS.order(3, 7), "3 generates the group modulo 7"
    assert_equal 1, RCAS.order(1, 7)
    assert_equal 3, RCAS.primitive_root(7)
    assert_equal 2, RCAS.primitive_root(11)
    assert_raises(ArgumentError) { RCAS.order(7, 7) }
    assert_raises(ArgumentError) { RCAS.legendre(1, 8) }
  end

  def test_continued_fractions
    assert_equal [4, 2, 6, 7], RCAS.continued_fraction(Rational(415, 93))
    assert_equal [Rational(4), Rational(9, 2), Rational(58, 13), Rational(415, 93)], RCAS.convergents(Rational(415, 93))
    assert_equal [3, 7, 15, 1, 292], RCAS.continued_fraction(Math::PI, 5)
    assert_includes RCAS.convergents(Math::PI, 4), Rational(355, 113), "the classic approximation of pi"
    assert_equal [1, 2, 2, 2, 2], RCAS.continued_fraction(Math.sqrt(2), 5), "the square root of two repeats"
  end
  # Trial division on a 64-bit number is 2**32 divisions: sqrt, GF and log
  # each hung on 2**61 - 1 until they went through Miller-Rabin and rho.
  def test_big_integers_do_not_go_through_trial_division
    m = 2**61 - 1 # a Mersenne prime
    assert RCAS.isprime(m)
    assert_equal [[m, 1]], RCAS::NumberTheory.prime_division(m)
    assert_equal "#{m}**(1/2)", RCAS.sqrt(m).to_s
    assert_equal "log(#{m})", RCAS.log(m).to_s
    assert_equal m, RCAS.GF(m).order
    assert_equal 168, RCAS::NumberTheory::SMALL_PRIMES.size
    assert_equal 997, RCAS::NumberTheory::SMALL_PRIMES.last
    first = []
    RCAS::NumberTheory.each_prime { |p| first << p; break if first.size == 5 }
    assert_equal [2, 3, 5, 7, 11], first
  end

  # A number nobody asked to factor is not factored: tidying sqrt(n) and
  # log(n) stops where the work would start.
  def test_tidying_does_not_factor_the_unfactorable
    hard = 1_000_000_000_039 * 1_000_000_000_061 * 1_000_000_000_063
    assert_nil RCAS::NumberTheory.prime_division(hard, hard: false)
    assert_equal "#{hard}**(1/2)", RCAS.sqrt(hard).to_s
    assert_equal [[2, 2], [3, 2]], RCAS::NumberTheory.prime_division(36, hard: false)
  end

end
