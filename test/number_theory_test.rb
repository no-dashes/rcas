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
end
