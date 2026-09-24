# frozen_string_literal: true

require_relative "test_helper"

# Dixon's p-adic solution of one square system (24 Sept 2026), and the
# early stop of the primes that came with it: both read a solution back by
# rational reconstruction and believe it only when A*x = b holds exactly.
class DixonTest < Minitest::Test
  include RCAS::Sets
  MM = RCAS::Multimodular

  def random_system(n, big = 9, rational: false, seed: n)
    rng = Random.new(seed)
    rows = Array.new(n) { Array.new(n) { v = rng.rand(-big..big); rational ? Rational(v, rng.rand(1..7)) : v } }
    [(QQ**[n, n])[rows], Array.new(n) { rng.rand(-big..big) }]
  end

  def test_agrees_with_the_primes_and_with_elimination
    [[1, 9], [2, 9], [5, 9], [12, 9], [33, 9], [8, 10**20], [20, 999]].each do |n, big|
      [false, true].each do |rational|
        m, b = random_system(n, big, rational: rational)
        expected = m.solve(b, algorithm: :elimination)
        assert_equal expected, m.solve(b, algorithm: :dixon), "#{n} x #{n}, #{big}"
        assert_equal expected, m.solve(b, algorithm: :multimodular), "#{n} x #{n}, #{big}"
      end
    end
  end

  # the first prime divides det A, so C = A**-1 is taken modulo the second
  def test_a_prime_that_divides_the_determinant_is_passed_over
    p1 = MM.prime(0)
    a = [[p1, 1, 0], [0, 1, 2], [0, 0, 1]]
    assert_equal 0, MM.eliminate(a, [], p1).first
    assert_equal MM.prime(1), RCAS::Dixon.inverse_modulo_a_prime(a).first
    x = RCAS::Dixon.solve(a, [1, 2, 3])
    assert_equal [1, 2, 3], a.map { |row| row.zip(x).sum { |v, y| v * y } }
  end

  def test_singular_systems
    assert_nil RCAS::Dixon.solve([[1, 2], [2, 4]], [1, 2])
    assert_nil RCAS::Dixon.solve([[0, 0], [0, 0]], [1, 2])
    m = (QQ**[3, 3])[[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    assert_equal m.solve([6, 15, 24], algorithm: :elimination), m.solve([6, 15, 24], algorithm: :dixon)
    assert_raises(RCAS::DomainError) { m.solve([1, 0, 0], algorithm: :dixon) }
  end

  # 10**12/3 modulo one prime reads back as a small fraction that is not
  # the solution: without the exact check that would be the answer
  def test_a_reconstruction_is_believed_only_after_the_exact_check
    p = MM.prime(0)
    x = 10**12 * 3.pow(p - 2, p) % p
    d, numerators = MM.reconstruct([[x]], p)
    refute_equal Rational(10**12, 3), Rational(numerators[0][0], d)
    assert_nil MM.verified([[3]], [[10**12]], [[x]], p)
    m = p**3
    assert_equal [3, [[10**12]]], MM.verified([[3]], [[10**12]], [[10**12 * inverse(3, m) % m]], m)
  end

  def test_rational_reconstruction
    assert_equal Rational(1, 3), MM.rational(3.pow(99, 101), 101, 7)
    assert_equal Rational(-2, 5), MM.rational(-2 * 5.pow(99, 101) % 101, 101, 7)
    p = MM.prime(0)
    residues = [[Rational(1, 3), Rational(2, 3)], [Rational(5, 6), 1]].map { |r| r.map { |v| v.numerator * v.denominator.pow(p - 2, p) % p } }
    assert_equal [6, [[2, 4], [5, 6]]], MM.reconstruct(residues, p)
  end

  # a matrix of determinant 1 has a small inverse and a Hadamard bound of
  # many primes; the early stop needs a fraction of them
  def test_the_primes_stop_early_when_the_solution_is_small
    RCAS.random = 5
    u = (ZZ**[30, 30]).random(unimodular: true)
    a = (u * u * u).entries.map { |r| r.map(&:value) }
    identity = Array.new(30) { |i| Array.new(30) { |j| i == j ? 1 : 0 } }
    counts = [true, false].to_h do |early|
      calls = 0
      original = MM.method(:eliminate)
      TestSupport.replacing(MM, :eliminate, ->(*args) { calls += 1; original.call(*args) }) { MM.crt_solve(a, identity, early: early) }
      [early, calls]
    end
    assert_operator counts[true] * 3, :<, counts[false]
    d, n = MM.crt_solve(a, identity)
    assert_equal a.size.times.map { |i| identity[i].map { |v| v * d } }, RCAS::MatrixMultiply::INTEGER.leaf(a, n)
  ensure
    RCAS.random = nil
  end

  def test_the_solver_is_chosen_by_size
    small, b_small = random_system(31)
    large, b_large = random_system(32)
    assert_equal MM, MM.solver(small.entries, b_small, :auto)
    assert_equal RCAS::Dixon, MM.solver(large.entries, b_large, :auto)
    assert_equal MM, MM.solver(large.entries, b_large, :multimodular)
    assert_equal RCAS::Dixon, MM.solver(small.entries, b_small, :dixon)
    assert_nil MM.solver(large.entries, b_large, :elimination)
    assert_nil MM.solver([[1.5, 2], [3, 4]], [1, 2], :auto)
    assert_raises(ArgumentError) { small.solve(b_small, algorithm: :gauss) }
    assert_raises(ArgumentError) { small.det(algorithm: :dixon) }
    assert_raises(ArgumentError) { small.inverse(algorithm: :dixon) }
  end

  private

  def inverse(a, m) = RCAS::NumberTheory.invmod(a, m)
end
