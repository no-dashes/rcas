# frozen_string_literal: true

require_relative "test_helper"

class LinearAlgebraTest < Minitest::Test
  include RCAS::Sets

  def teardown = RCAS.forget

  def test_vector_space
    v3 = QQ**3
    assert_equal "QQ**3", v3.to_s
    assert_equal 3, v3.dim
    assert_equal "(0, 0, 0)", v3.zero.to_s
    assert_equal ["(1, 0, 0)", "(0, 1, 0)", "(0, 0, 1)"], v3.basis.map(&:to_s)
    assert v3.include?(v3[1, 2, 3])
    assert v3.include?([1, Rational(1, 2), 3])
    refute v3.include?([1, 2])
    refute (ZZ**3).include?([1, Rational(1, 2), 3])
    assert_raises(RCAS::DomainError) { (ZZ**2)[1, Rational(1, 2)] }
    assert_raises(RCAS::DomainError) { (QQ**3)[1, 2] }
    e = assert_raises(RCAS::DomainError) { (QQ**2)[:z, 1] }
    assert_match(/assume\(z: QQ\)/, e.message)
  end

  def test_vector_arithmetic
    v = (QQ**3)[1, 2, 3]
    w = (QQ**3)[Rational(1, 2), 0, -1]
    assert_equal "(3/2, 2, 2)", (v + w).to_s
    assert_equal "(1/2, 2, 4)", (v - w).to_s
    assert_equal "(2, 4, 6)", (2 * v).to_s
    assert_equal "(2, 4, 6)", (v * 2).to_s
    assert_equal "(1/2, 1, 3/2)", (v / 2).to_s
    assert_equal "(-1, -2, -3)", (-v).to_s
    assert_equal Rational(-5, 2), v * w
    assert_equal Rational(-5, 2), v.dot(w)
    assert_equal "(-2, 5/2, -1)", v.cross(w).to_s
    assert_equal "14**(1/2)", v.norm.to_s
    assert_equal 5.0, (RR**2)[3.0, 4.0].norm
    assert_equal v, [1, 2, 3]
    assert_raises(TypeError) { 2 - v }
    assert_raises(ArgumentError) { v + (QQ**2)[1, 2] }
  end

  def test_result_spaces_follow_the_scalars
    z = (ZZ**2)[1, 2]
    assert_equal ZZ**2, z.space
    assert_equal QQ**2, (z / 2).space
    assert_equal QQ**2, (z * Rational(1, 2)).space
    assert_equal RR**2, (z * 1.5).space
    RCAS.assume(x: RR)
    assert_equal RR**2, (:x * z).space
    assert_equal "(x, 2*x)", (:x * z).to_s
    assert_equal "5*x**2", ((:x * z) * (:x * z)).to_s
  end

  def test_symbolic_vectors
    RCAS.assume(x: QQ, y: QQ)
    v = (QQ**2)[:x, :y]
    assert_equal "(x, y)", v.to_s
    assert_equal "x**2 + y**2", (v * v).to_s
    assert_equal "(x**2 + y**2)**(1/2)", v.norm.to_s
    assert_equal "(3, 4)", v.call(x: 3, y: 4).to_s
  end

  def test_matrix_space
    m = QQ**[2, 2]
    assert_equal "QQ**[2, 2]", m.to_s
    assert_equal "[1 0]\n[0 1]", m.identity.to_s
    assert_equal "[0 0]\n[0 0]", m.zero.to_s
    assert m.include?([[1, 2], [3, 4]])
    refute (ZZ**[2, 2]).include?([[1, Rational(1, 2)], [3, 4]])
    assert_raises(RCAS::DomainError) { m[[1, 2, 3], [4, 5, 6]] }
    assert_raises(ArgumentError) { (QQ**[2, 3]).identity }
  end

  def test_matrix_arithmetic
    a = (QQ**[2, 2])[[1, 2], [3, 4]]
    assert_equal "[1 2]\n[3 4]", a.to_s
    assert_equal "[2 4]\n[6 8]", (a + a).to_s
    assert_equal "[2 4]\n[6 8]", (2 * a).to_s
    assert_equal "[0 0]\n[0 0]", (a - a).to_s
    assert_equal "[ 7 10]\n[15 22]", (a * a).to_s
    assert_equal "[37  54]\n[81 118]", (a**3).to_s
    assert_equal "[1 3]\n[2 4]", a.transpose.to_s
    assert_equal a.t, a.transpose
    assert_equal 5, a.trace
    assert_equal "(3, 7)", (a * (QQ**2)[1, 1]).to_s
    assert_equal "(4, 6)", ((QQ**2)[1, 1] * a).to_s
    assert_raises(ArgumentError) { a * (QQ**3)[1, 1, 1] }
    assert_raises(ArgumentError) { a + (QQ**[2, 3]).zero }
  end

  def test_determinant_rank_inverse
    a = (QQ**[2, 2])[[1, 2], [3, 4]]
    assert_equal(-2, a.det)
    assert_equal 2, a.rank
    assert a.invertible?
    assert_equal "[ -2    1]\n[3/2 -1/2]", a.inverse.to_s
    assert_equal a.inverse, a**-1
    assert (a * a.inverse).identity?
    assert_equal QQ**[2, 2], a.inverse.space

    z = ZZ.matrix([[2, 0], [0, 2]])
    assert_equal ZZ**[2, 2], z.space
    assert_equal QQ**[2, 2], z.inverse.space
    assert_equal "[1/2   0]\n[  0 1/2]", z.inverse.to_s

    singular = QQ.matrix([[1, 2], [2, 4]])
    assert_equal 0, singular.det
    assert_equal 1, singular.rank
    refute singular.invertible?
    assert_raises(RCAS::DomainError) { singular.inverse }

    hilbert = QQ.matrix((1..5).map { |i| (1..5).map { |j| Rational(1, i + j - 1) } })
    assert_equal Rational(1, 266_716_800_000), hilbert.det
    assert (hilbert * hilbert.inverse).identity?
  end

  def test_rref_kernel_solve
    b = (QQ**[2, 3])[[1, 2, 3], [2, 4, 6]]
    assert_equal "[1 2 3]\n[0 0 0]", b.rref.to_s
    assert_equal 1, b.rank
    assert_equal ["(-2, 1, 0)", "(-3, 0, 1)"], b.kernel.map(&:to_s)
    b.kernel.each { |k| assert (b * k).zero? }
    assert_equal "(1, 0, 0)", b.solve([1, 2]).to_s
    assert_raises(RCAS::DomainError) { b.solve([1, 3]) }

    a = (QQ**[2, 2])[[1, 2], [3, 4]]
    x = a.solve((QQ**2)[5, 6])
    assert_equal "(-4, 9/2)", x.to_s
    assert_equal (QQ**2)[5, 6], a * x
    assert_empty a.kernel
  end

  def test_charpoly
    a = (QQ**[2, 2])[[1, 2], [3, 4]]
    p = a.charpoly
    assert_equal "-2 - 5*x + x**2", p.to_s
    assert_equal QQ[:x], p.ring
    assert_equal "-2 - 5*l + l**2", a.charpoly(:l).to_s
    assert_equal ZZ[:x], ZZ.matrix([[0, 1], [1, 0]]).charpoly.ring
    assert_equal "-1 + x**2", ZZ.matrix([[0, 1], [1, 0]]).charpoly.to_s
  end

  def test_symbolic_matrices
    RCAS.assume(x: RR)
    s = RR.matrix([[:x, 1], [1, :x]])
    assert_equal RR**[2, 2], s.space
    assert_equal "-1 + x**2", s.det.to_s
    assert_equal "-1 + l**2 - 2*l*x + x**2", s.charpoly(:l).to_s
    assert_equal "[ x/(-1 + x**2) -1/(-1 + x**2)]\n[-1/(-1 + x**2)  x/(-1 + x**2)]", s.inverse.to_s
    assert (s * s.inverse).simplify.identity? || (s * s.inverse).call(x: 2).identity?
    assert_equal "[2 1]\n[1 2]", s.call(x: 2).to_s
    assert_equal 3, s.call(x: 2).det
  end

  def test_helpers_infer_domains
    assert_equal ZZ**[2, 2], RCAS.matrix([[1, 2], [3, 4]]).space
    assert_equal QQ**[1, 2], RCAS.matrix([[1, Rational(1, 2)]]).space
    assert_equal RR**2, RCAS.vector(1, 2.5).space
    assert_equal QQ**2, RCAS.vector(QQ, 1, 2).space
    # an undeclared name is an indeterminate of the entries' ring
    assert_equal ZZ[:undeclared]**2, RCAS.vector(:undeclared, 1).space
  end

  def test_complex_entries
    m = CC.matrix([[Complex(0, 1), 0], [0, 1]])
    assert_equal Complex(0, 1), m.det
    assert_equal "[i 0]\n[0 1]", m.to_s
    assert_equal "(1 + 2*i)*x", (Complex(1, 2) * :x).to_s
  end
  def test_gram_schmidt
    basis = RCAS.gram_schmidt([RCAS.vector(1, 1, 0), RCAS.vector(1, 0, 1)])
    assert_equal ["(1, 1, 0)", "(1/2, -1/2, 1)"], basis.map(&:to_s)
    assert RCAS.orthogonal?(basis[0], basis[1])
    orthonormal = RCAS.gram_schmidt([RCAS.vector(1, 1, 0), RCAS.vector(1, 0, 1)], normalize: true)
    orthonormal.each { |v| assert_equal "1", RCAS::LinearAlgebra.norm(v).to_s, "every vector has length one" }
    assert RCAS.orthogonal?(orthonormal[0], orthonormal[1])
    assert_equal 1, RCAS.gram_schmidt([RCAS.vector(1, 0), RCAS.vector(2, 0)]).size, "a dependent vector drops out"
  end

  def test_projection_and_least_squares
    assert_equal "(1, 0)", RCAS.project(RCAS.vector(1, 2), onto: RCAS.vector(1, 0)).to_s
    assert_equal "(1, 1, 0)", RCAS.project(RCAS.vector(1, 1, 5), onto: [RCAS.vector(1, 0, 0), RCAS.vector(0, 1, 0)]).to_s
    fit = RCAS.least_squares(RCAS.matrix([[1, 1], [1, 2], [1, 3]]), RCAS.vector(1, 2, 4))
    assert_equal "(-2/3, 3/2)", fit.to_s
    line = RCAS.linreg([1, 2, 3], [1, 2, 4], :x)
    assert_equal "-2/3 + 3*x/2", line.to_s, "the same line as linreg finds"
    assert_raises(ArgumentError) { RCAS.least_squares(RCAS.matrix([[1, 2], [2, 4]]), RCAS.vector(1, 2)) }
  end

  # The sum of the single projections is the projection onto the span only
  # when the targets are pairwise orthogonal. A slanted pair is
  # orthogonalised first: (1, 0) and (1, 1) span the plane, so projecting
  # onto them is the identity, and the sum of the two single projections
  # answered (3/2, 1/2) (22 Sept 2026, from a review).
  def test_projecting_onto_a_slanted_span
    e1 = RCAS.vector(1, 0)
    plane = [e1, RCAS.vector(1, 1)]
    assert_equal e1, RCAS.project(e1, onto: plane)
    assert_equal RCAS.vector(2, -3), RCAS.project(RCAS.vector(2, -3), onto: plane), "onto the whole space: the identity"
    assert_equal "(1/3, 8/3, 7/3)", RCAS.project(RCAS.vector(1, 2, 3), onto: [RCAS.vector(1, 1, 0), RCAS.vector(0, 1, 1)]).to_s
  end

  # What a projection has to satisfy, whatever the targets look like:
  # v - p is orthogonal to every one of them, and projecting again changes
  # nothing.
  def test_a_projection_is_orthogonal_and_idempotent
    [[RCAS.vector(1, 1, 0), RCAS.vector(0, 1, 1)],
     [RCAS.vector(1, 0, 0), RCAS.vector(0, 1, 0)],
     [RCAS.vector(2, 1, -1), RCAS.vector(1, 3, 1), RCAS.vector(0, 1, 5)],
     [RCAS.vector(1, 2, 3)]].each do |targets|
      v = RCAS.vector(1, 2, 3)
      p = RCAS.project(v, onto: targets)
      targets.each do |u|
        assert_equal "0", RCAS::LinearAlgebra.dot(v - p, u).to_s, "v - p is perpendicular to #{u}"
      end
      assert_equal p, RCAS.project(p, onto: targets), "projecting twice is projecting once"
    end
  end

  # Dependent generators name the same span twice; they drop out on the way
  # rather than being counted twice.
  def test_dependent_targets_do_not_count_twice
    v = RCAS.vector(1, 2, 3)
    line = RCAS.project(v, onto: [RCAS.vector(1, 1, 0)])
    assert_equal "(3/2, 3/2, 0)", line.to_s
    assert_equal line, RCAS.project(v, onto: [RCAS.vector(1, 1, 0), RCAS.vector(2, 2, 0)])
    assert_equal line, RCAS.project(v, onto: [RCAS.vector(1, 1, 0), RCAS.vector(1, 1, 0)])
    assert_raises(ArgumentError) { RCAS.project(v, onto: [RCAS.vector(0, 0, 0)]) }
    assert_raises(ArgumentError) { RCAS.project(v, onto: [RCAS.vector(1, 1, 0), RCAS.vector(0, 0, 0)]) }
  end

  # gram_schmidt builds an orthogonal family as it goes and projects onto
  # that directly, so it neither orthogonalises twice nor recurses.
  def test_gram_schmidt_still_spans_the_same_space
    vs = [RCAS.vector(1, 1, 0), RCAS.vector(1, 0, 1), RCAS.vector(0, 1, 1)]
    basis = RCAS.gram_schmidt(vs)
    assert_equal 3, basis.size
    basis.combination(2) { |u, w| assert_equal "0", RCAS::LinearAlgebra.dot(u, w).to_s }
    vs.each { |v| assert_equal v, RCAS.project(v, onto: basis), "every generator is back in the span" }
    assert_equal 2, RCAS.gram_schmidt([RCAS.vector(1, 1, 0), RCAS.vector(2, 2, 0), RCAS.vector(0, 1, 1)]).size
  end

  # matrix([[a, b], [c, d]]) with nothing declared raised "can't infer a
  # domain for a" (the fourth external review): the entries live in
  # ZZ[a, b, c, d], as [[1, 2], [3, 4]] live in ZZ, and past a polynomial
  # in the fraction field. The answers are those of RR.matrix after
  # declaring every name real.
  def test_a_symbolic_matrix_is_over_the_ring_of_its_indeterminates
    a, b, c, d = %i[a b c d]
    m = RCAS.matrix([[a, b], [c, d]])
    assert_equal "ZZ[a, b, c, d]**[2, 2]", m.space.to_s
    assert_equal "a*d - b*c", m.det.to_s
    %i[det inverse rref rank adjugate eigenvalues].each do |op|
      expected = RCAS.assume(a: RR, b: RR, c: RR, d: RR) { RCAS.matrix([[a, b], [c, d]]).public_send(op).to_s }
      assert_equal expected, m.public_send(op).to_s, op
    end
    assert_equal "QQ[a]**[2, 2]", RCAS.matrix([[a, Rational(1, 2)], [0, a]]).space.to_s
    assert_equal "Frac(QQ[a])**[2, 2]", RCAS.matrix([[1 / RCAS::Var.new(:a), 1], [1, a]]).space.to_s
    assert_equal "RR[a]**[1, 2]", RCAS.matrix([[RCAS.sqrt(2) * a, 1]]).space.to_s
    assert_equal "ZZ[a, b]**2", RCAS.vector([a, b]).space.to_s
    # a numeric matrix keeps its number set
    assert_equal "ZZ**[2, 2]", RCAS.matrix([[1, 2], [3, 4]]).space.to_s
    assert_equal "QQ**[1, 2]", RCAS.matrix([[Rational(1, 2), 2]]).space.to_s
    # a declared name is a scalar of its domain, not an indeterminate
    RCAS.assume(x: RR) { assert_equal "RR[a]**[1, 2]", RCAS.matrix([[:x, a]]).space.to_s }
  end

  def test_an_entry_without_any_domain_says_what_to_type
    e = assert_raises(RCAS::DomainError) { RCAS.matrix([[RCAS.D(:y, :x), 1]]) }
    assert_match(/y\.in\(RR\)/, e.message)
    assert_match(/RR\.matrix/, e.message)
  end

  # The generic eigenvalue has a square root, so no polynomial ring or
  # fraction field holds it and matrix([[lam, 0], [0, lam]]) refused: a
  # reader could not write M - lambda*I with the answer rcas had just
  # given. Undeclared names now read as complex numbers there.
  def test_radical_and_transcendental_entries_are_over_cc
    a, b, c, d = %i[a b c d]
    m = RCAS.matrix([[a, b], [c, d]])
    m.eigenvalues.each do |lam|
      lm = RCAS.matrix([[lam, 0], [0, lam]])
      assert_equal "CC**[2, 2]", lm.space.to_s
      assert_equal true, RCAS::Scalar.zero?((m - lm).det), "#{lam} is an eigenvalue"
      assert_equal 1, (m - lm).rank
    end
    assert_equal "CC**[1, 2]", RCAS.matrix([[RCAS.sin(:a), 1]]).space.to_s
    assert_equal "CC**2", RCAS.vector([RCAS.sqrt(:a), 1]).space.to_s
    assert_empty RCAS.assumptions, "the complex reading is not left behind"
    # a declared name keeps its own domain
    RCAS.assume(a: RR) { assert_equal "RR**[1, 2]", RCAS.matrix([[RCAS.sin(:a), 1]]).space.to_s }
  end

  # Over a polynomial ring the charpoly lives in QQ[x, _l], where
  # Polynomial#coeff(k) reads an exponent vector: eigenvalues were [] for
  # QQ[x].matrix([[x, 1], [1, x]]).
  def test_eigenvalues_over_a_polynomial_ring
    m = QQ[:x].matrix([[:x, 1], [1, :x]])
    assert_equal ["1 + x", "-1 + x"], m.eigenvalues.map(&:to_s)
    assert_equal ["-1 + x**2", "1 + x**2"], RCAS.matrix([[:x**2, 1], [1, :x**2]]).eigenvalues.map(&:to_s)
    assert_equal 2, RCAS.matrix([[:x**2, 1], [1, :x]]).eigenvalues.size
  end

  # A radical is an atom to cancel, so sqrt(x)**2 - x and its relatives
  # were not seen to vanish; reduced modulo t**2 - x they are 0.
  def test_a_radical_identity_is_a_zero_entry
    r = RCAS.sqrt(:x)
    assert RCAS::Scalar.zero?(r**2 - :x)
    assert RCAS::Scalar.zero?((r + 1) * (r - 1) - :x + 1)
    assert RCAS::Scalar.zero?(RCAS.sqrt(1 + r)**2 - r - 1)
    refute RCAS::Scalar.zero?(r - 1)
  end

  # A - lambda*I at an eigenvalue of the generic 2x2 has a pivot that is
  # zero only because lambda**2 = (a + d)*lambda - a*d + b*c, and it read
  # as non-zero, so both eigenspaces came back empty (under RR too).
  def test_the_eigenvectors_of_the_generic_two_by_two
    a, b, c, d = %i[a b c d]
    m = RCAS.matrix([[a, b], [c, d]])
    pairs = m.eigenvectors
    assert_equal 2, pairs.size
    pairs.each do |value, multiplicity, vectors|
      assert_equal 1, multiplicity
      assert_equal 1, vectors.size, "an eigenvalue has an eigenvector"
      v = vectors.first
      residual = m * v - v.scale(value)
      residual.entries.each { |r| assert RCAS::Scalar.zero?(r), "A*v = lambda*v: #{r}" }
    end
    pairs = RCAS.matrix([[RCAS.sqrt(2) * a, 1], [1, a]]).eigenvectors
    assert_equal [1, 1], pairs.map { |_, _, vs| vs.size }
  end
end
