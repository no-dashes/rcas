# frozen_string_literal: true

require_relative "test_helper"

# Determinants, inverses and solutions of Integer and Rational matrices
# modulo many primes (24 Sept 2026). The elimination over QQ is kept as
# algorithm: :elimination, and every answer here is checked against it or
# against the definition.
class MultimodularTest < Minitest::Test
  include RCAS::Sets
  MM = RCAS::Multimodular

  def random_matrix(n, big = 9, rational: false, rng: Random.new(n))
    (QQ**[n, n])[Array.new(n) { Array.new(n) { v = rng.rand(-big..big); rational ? Rational(v, rng.rand(1..7)) : v } }]
  end

  def test_agrees_with_elimination
    [1, 2, 3, 5, 8, 13].each do |n|
      [false, true].each do |rational|
        m = random_matrix(n, rational: rational)
        b = Array.new(n) { |i| Rational(i - 2, 3) }
        assert_equal m.det(algorithm: :elimination), m.det, "det #{n}"
        assert_equal m.inverse(algorithm: :elimination), m.inverse, "inverse #{n}"
        assert_equal m.solve(b, algorithm: :elimination), m.solve(b), "solve #{n}"
      end
    end
  end

  # the answer is the residue in (-M/2, M/2): negative determinants, and a
  # determinant far past one prime (entries of thirty digits, n = 12)
  def test_signs_and_many_primes
    assert_equal(-2, (QQ**[2, 2])[[1, 2], [3, 4]].det.value)
    big = random_matrix(12, 10**30)
    expected = big.det(algorithm: :elimination)
    assert_operator expected.value.abs.bit_length, :>, 31 * 10
    assert_equal expected, big.det
    assert_equal (QQ**[12, 12]).identity, big * big.inverse
  end

  # a prime that divides det A gives det A mod p = 0 and no inverse mod p;
  # it counts for the determinant and is skipped for the adjugate. Here
  # the first three primes all divide the determinant.
  def test_primes_that_divide_the_determinant_are_skipped_for_the_inverse
    p1, p2, p3 = MM.primes(3)
    unimodular = (ZZ**[4, 4])[[1, 2, 0, 1], [0, 1, 3, 0], [0, 0, 1, 5], [0, 0, 0, 1]]
    other = (ZZ**[4, 4])[[1, 0, 0, 0], [7, 1, 0, 0], [-2, 3, 1, 0], [4, 0, -1, 1]]
    diagonal = (ZZ**[4, 4])[[p1 * p2 * p3, 0, 0, 0], [0, 1, 0, 0], [0, 0, 2, 0], [0, 0, 0, 1]]
    m = unimodular * diagonal * other
    assert_equal 2 * p1 * p2 * p3, m.det.value
    assert_equal 0, MM.eliminate(MM.integral(MM.values(m.entries)).first, [], p1).first
    assert_equal (QQ**[4, 4]).identity, m * m.inverse
    assert_equal m.inverse(algorithm: :elimination), m.inverse
    x = m.solve([1, 2, 3, 4])
    assert_equal (QQ**4)[1, 2, 3, 4], m * x
  end

  def test_singular_matrices
    m = (QQ**[3, 3])[[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    assert_equal 0, m.det.value
    error = assert_raises(RCAS::DomainError) { m.inverse }
    assert_equal "matrix is singular", error.message
    # a consistent singular system still has the solution with free variables 0
    assert_equal m.solve([6, 15, 24], algorithm: :elimination), m.solve([6, 15, 24])
    assert_raises(RCAS::DomainError) { m.solve([1, 0, 0]) }
    assert_equal 0, (QQ**[2, 2])[[0, 0], [1, 2]].det.value
    assert_nil MM.inverse([[0, 0], [1, 2]])
  end

  # Hadamard's inequality is the proof: the bound is never below |det|,
  # and a Hadamard matrix of order 8 meets it (8**4 = 4096)
  def test_the_bound_is_hadamards
    assert_equal 20, MM.hadamard([[3, 4], [0, 5]])
    h2 = [[1, 1], [1, -1]]
    h8 = [h2, h2, h2].reduce { |a, b| a.flat_map { |ra| b.map { |rb| ra.flat_map { |x| rb.map { |y| x * y } } } } }
    assert_equal 4096, MM.det(h8).abs
    assert_operator MM.hadamard(h8), :>=, 4096
    assert_operator MM.hadamard(h8), :<=, 4097
    rng = Random.new(5)
    10.times do
      a = Array.new(5) { Array.new(5) { rng.rand(-20..20) } }
      d = MM.det(a)
      assert_operator MM.hadamard(a), :>=, d.abs
      adjugate = MM.crt_solve(a, Array.new(5) { |i| Array.new(5) { |j| i == j ? 1 : 0 } }).last
      assert_operator MM.cramer_bound(a, [[1]]), :>=, adjugate.flatten.map(&:abs).max if d.nonzero?
    end
  end

  def test_chinese_remaindering
    m = 101
    v = 37
    assert_equal 37 + 101 * ((5 - 37) * 101.pow(103 - 2, 103) % 103), MM.garner(v, m, 5, 103)
    assert_equal 5, MM.garner(v, m, 5, 103) % 103
    assert_equal 37, MM.garner(v, m, 5, 103) % 101
    assert_equal(-1, MM.symmetric(100, 101))
    assert_equal 50, MM.symmetric(50, 101)
  end

  def test_the_algorithm_can_be_named
    m = random_matrix(4)
    assert_raises(ArgumentError) { m.det(algorithm: :cramer) }
    expected = m.det
    TestSupport.replacing(MM, :det, ->(*) { raise "the primes were asked" }) do
      assert_equal expected, m.det(algorithm: :elimination)
      assert_raises(RuntimeError) { m.det }
    end
  end

  # Floats, symbols and algebraic numbers keep their own routes
  def test_other_entries_keep_their_routes
    refute MM.use?([[1.5, 2], [3, 4]], :auto)
    refute MM.use?([[RCAS::Num.new(Complex(1, 2)), 2], [3, 4]], :auto)
    assert MM.use?([[RCAS::Num.new(1/2r), 2], [3, 4]], :auto)
    assert_in_delta(-2.0, (RR**[2, 2])[[1.0, 2.0], [3.0, 4.0]].det.value, 1e-12)
    assert_equal "-1 + x**2", (ZZ[:x]**[2, 2])[[:x, 1], [1, :x]].det.to_s
  end

  def test_the_primes_are_below_two_to_the_thirty_first
    ps = MM.primes(5)
    assert_equal ps.sort.reverse, ps
    assert ps.all? { |p| p < 2**31 && RCAS::NumberTheory.prime?(p) }
    assert_equal 2**31 - 1, ps.first
  end
end
