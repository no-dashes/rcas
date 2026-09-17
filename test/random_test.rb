# frozen_string_literal: true

require_relative "test_helper"

class RandomTest < Minitest::Test
  ZZ = RCAS::ZZ
  QQ = RCAS::QQ
  NN = RCAS::NN
  RR = RCAS::RR
  CC = RCAS::CC

  def seed(n = 1) = Random.new(n)
  def teardown = RCAS.random = nil

  def test_the_same_seed_gives_the_same_object
    a = ZZ[:x].random(4, random: seed(3))
    b = ZZ[:x].random(4, random: seed(3))
    assert_equal a.to_s, b.to_s
    refute_equal a.to_s, ZZ[:x].random(4, random: seed(4)).to_s, "and another seed gives another one"
    RCAS.random = 42
    first = (ZZ**[2, 2]).random.to_s
    RCAS.random = 42
    assert_equal first, (ZZ**[2, 2]).random.to_s, "RCAS.random = 42 makes a whole session reproducible"
  end

  def test_polynomials_have_the_shape_they_are_asked_for
    f = ZZ[:x].random(5, random: seed)
    assert_equal 5, f.degree
    assert f.coefficients.all? { |c| ZZ.include?(c.value) }, "coefficients of ZZ[x] are integers"
    assert_equal 3, ZZ[:x].random(6, terms: 3, random: seed).monomials.size
    assert (2..5).cover?(ZZ[:x].random(2..5, random: seed).degree), "a range of degrees"
    monic = ZZ[:x].random(4, monic: true, random: seed)
    assert_equal "1", monic.leading_coefficient.to_s
    assert monic.coefficients.all? { |c| ZZ.include?(c.value) }, "monic does not divide ZZ[x] into fractions"
    assert_equal "1", ZZ[:x].random(3, primitive: true, random: seed).content.to_s
    assert QQ[:x].random(3, random: seed).coefficients.any? { |c| c.value.is_a?(Rational) }, "QQ[x] has rational coefficients"
  end

  def test_polynomials_with_a_property
    assert ZZ[:x].random(4, irreducible: true, random: seed).irreducible?
    assert ZZ[:x].random(5, irreducible: true, random: seed(9)).irreducible?
    f = ZZ[:x].random(4, squarefree: true, random: seed)
    assert f.squarefree_decomposition.all? { |_, multiplicity| multiplicity == 1 }
    assert RCAS.GF(5)[:x].random(3, irreducible: true, random: seed).irreducible?, "over a finite field too"
  end

  def test_a_polynomial_that_really_factors
    f = ZZ[:x].random(3, roots: true, random: seed)
    assert_equal 3, f.degree
    assert_equal 3, f.factor.factors.count { |g, _| g.degree == 1 }, "a product of linear factors"
    assert_equal [1, -2, 3].sort, ZZ[:x].random(roots: [1, -2, 3], monic: true, random: seed).roots.map(&:to_s).map(&:to_i).sort
    g = ZZ[:x].random(5, factors: 3, random: seed)
    assert_equal 5, g.degree
    assert_equal 3, g.factor.factors.count { |h, _| h.degree.positive? }
  end

  def test_several_variables
    f = ZZ[:x, :y].random(2, random: seed)
    assert_equal 2, f.degree
    assert_equal %i[x y], f.ring.vars
    h = ZZ[:x, :y].random(3, homogeneous: true, random: seed)
    assert h.monomials.all? { |m| m.degree == 3 }, "every monomial of the same total degree"
  end

  def test_matrices_have_the_shape_they_are_asked_for
    m = (ZZ**[2, 3]).random(random: seed)
    assert (ZZ**[2, 3]).include?(m)
    assert (QQ**[2, 2]).random(random: seed).entries.flatten.any? { |e| e.value.is_a?(Rational) }, "over QQ the entries are rationals"
    assert (ZZ**[3, 3]).random(symmetric: true, random: seed).symmetric?
    a = (ZZ**[3, 3]).random(antisymmetric: true, random: seed)
    assert_equal (-a).to_s, a.transpose.to_s
    upper = (ZZ**[3, 3]).random(triangular: :upper, random: seed)
    assert (0...3).all? { |i| (0...i).all? { |j| RCAS::Scalar.zero?(upper[i, j]) } }
    diagonal = (ZZ**[3, 3]).random(diagonal: true, random: seed)
    assert_equal 3, diagonal.entries.flatten.count { |e| !RCAS::Scalar.zero?(e) }
    sparse = (ZZ**[4, 4]).random(density: 0.25, random: seed)
    assert sparse.entries.flatten.count { |e| RCAS::Scalar.zero?(e) } > 8, "most of a sparse matrix is zero"
  end

  def test_matrices_with_a_property
    refute_equal "0", (ZZ**[3, 3]).random(invertible: true, random: seed(7)).det.to_s
    u = (ZZ**[3, 3]).random(unimodular: true, random: seed)
    assert_includes %w[1 -1], u.det.to_s
    assert (ZZ**[3, 3]).include?(u.inverse), "the inverse of a unimodular matrix is integral"
    assert_equal "12", (ZZ**[3, 3]).random(det: 12, random: seed).det.to_s
    assert_equal "0", (ZZ**[3, 3]).random(singular: true, random: seed).det.to_s
    r = (ZZ**[3, 4]).random(rank: 2, random: seed)
    assert_equal 2, r.rank
    assert_equal (ZZ**[3, 3]).zero.to_s, (ZZ**[3, 3]).random(rank: 0, random: seed).to_s
  end

  def test_a_matrix_with_the_eigenvalues_it_is_given
    m = (ZZ**[3, 3]).random(eigenvalues: [1, 2, 2], random: seed)
    assert (ZZ**[3, 3]).include?(m), "P*D*P**-1 with P unimodular stays over ZZ"
    assert_equal %w[1 2 2], m.eigenvalues.map(&:to_s).sort
    assert_equal "4", m.det.to_s
  end

  def test_a_positive_definite_matrix_has_a_cholesky_factorization
    m = (ZZ**[3, 3]).random(definite: true, random: seed)
    assert m.symmetric?
    l = RCAS.cholesky(m)
    assert_equal m.to_s, (l * l.transpose).simplify.to_s
    assert m.eigenvalues.all? { |e| RCAS::Analysis.numeric(e).positive? }, "and positive eigenvalues"
  end

  def test_vectors_and_numbers
    v = (ZZ**3).random(random: seed)
    assert (ZZ**3).include?(v)
    refute (QQ**3).random(nonzero: true, random: seed).zero?
    assert (1..100).cover?(ZZ.random(1..100, random: seed))
    assert_equal 0, NN.random(0..0, random: seed)
    assert_kind_of Rational, QQ.random(random: seed(2)).value, "a rational comes back as a Num, which is how rcas writes one"
    assert (0.0..1.0).cover?(RR.random(random: seed))
    assert (2.0..3.0).cover?(RR.random(2..3, random: seed))
    assert RCAS.isprime(ZZ.random(100..999, prime: true, random: seed))
    assert_kind_of Complex, CC.random(random: seed).value
    assert CC.random(random: seed(7)).to_s.match?(/\A-?\d+ [-+] \d+\*i\z/), "a Gaussian integer, written the way rcas writes one"
  end

  def test_the_other_structures
    x = RCAS.GF(9).random(random: seed)
    assert RCAS.GF(9).include?(x)
    k = QQ.adjoin(RCAS.sqrt(2))
    assert k.include?(k.random(random: seed).to_expr)
    f = RCAS::FractionField.new(ZZ[:x]).random(2, random: seed)
    assert RCAS::FractionField.new(ZZ[:x]).include?(f)
  end

  def test_what_cannot_be_asked_for
    assert_raises(ArgumentError) { (ZZ**[2, 3]).random(symmetric: true, random: seed) }
    assert_raises(ArgumentError) { (ZZ**[2, 3]).random(unimodular: true, random: seed) }
    assert_raises(ArgumentError) { (ZZ**[3, 3]).random(eigenvalues: [1, 2], random: seed) }
    assert_raises(ArgumentError) { (ZZ**[3, 3]).random(rank: 4, random: seed) }
    assert_raises(ArgumentError) { ZZ[:x, :y].random(2, roots: true, random: seed) }
    assert_raises(ArgumentError) { ZZ[:x].random(2, factors: 3, random: seed) }
    error = assert_raises(ArgumentError) { ZZ[:x].random(2, coefficients: 0..0, irreducible: true, random: seed) }
    assert_includes error.message, "tries", "an impossible request is refused, not looped on"
  end
end
