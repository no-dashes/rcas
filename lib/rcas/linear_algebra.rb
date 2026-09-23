# frozen_string_literal: true

module RCAS
  # The second course in linear algebra: orthogonality and least squares.
  #
  #   gram_schmidt([vector(1, 1, 0), vector(1, 0, 1)])      # orthogonal basis
  #   gram_schmidt(vs, normalize: true)                     # orthonormal
  #   least_squares(matrix([[1, 1], [1, 2], [1, 3]]), vector(1, 2, 4))
  #   project(vector(1, 2), onto: vector(1, 0))
  #
  # Exact throughout, so an orthonormal basis keeps its square roots.
  #
  # Sources (keys: MANUAL.md, Sources): Gram-Schmidt and the normal equations
  # as in [Str16, ch. 4]; the numerically stabler QR route is not used because
  # the arithmetic here is exact.
  module LinearAlgebra
    module_function

    # The inner product, Hermitian where an entry carries an explicit
    # complex number: (1, i).(1, i) is 1 + i*i = 0 bilinearly, and |(1, i)|
    # is sqrt(2), not 0 (third review, L12). Symbolic entries are taken as
    # they stand, so the real case is unchanged.
    def dot(u, v)
      same_length!(u, v, "dot")
      u.entries.zip(v.entries).map { |a, b| Scalar.mul(a, conjugate(b)) }.reduce { |x, y| Scalar.add(x, y) }.simplify
    end

    # zip drops the extra coordinates of the longer vector, which made
    # project((1, 2), onto: (1, 0, 3)) a plausible (1/10, 0) (a review,
    # 23 Sept 2026): vectors of two different spaces have no inner product.
    def same_length!(u, v, name)
      return if u.entries.size == v.entries.size
      raise ArgumentError, "#{name}: the vectors have #{u.entries.size} and #{v.entries.size} entries; they must lie in the same space"
    end

    def conjugate(e)
      e = Expression.lift(e)
      return e unless e.each_node.any? { |n| n.is_a?(Num) && n.value.is_a?(Complex) }
      ComplexParts.conj(e)
    end

    def norm(v) = RCAS.sqrt(dot(v, v)).simplify

    def scale(v, factor) = v.space.unchecked(v.entries.map { |e| (e * factor).simplify })

    def subtract(u, v)
      same_length!(u, v, "subtract")
      u.space.unchecked(u.entries.zip(v.entries).map { |a, b| (a - b).simplify })
    end

    # The projection of v onto a vector or onto the span of several.
    #
    # The sum of the single projections is the projection onto the span only
    # when the targets are pairwise orthogonal; a slanted pair has to be
    # orthogonalised first. project(e1, onto: [e1, e1 + e2]) is e1 - those
    # two span the plane, so the projection onto it is the identity - and
    # was (3/2, 1/2) before (22 Sept 2026, from a review). Dependent
    # generators drop out on the way, as they do in gram_schmidt.
    def project(v, onto:)
      targets = onto.is_a?(Array) ? onto : [onto]
      targets.each do |u|
        raise ArgumentError, "project: cannot project onto the zero vector" if Scalar.zero?(dot(u, u))
      end
      targets = gram_schmidt(targets) unless orthogonal_family?(targets)
      onto_orthogonal(v, targets)
    end

    def orthogonal_family?(targets) = targets.combination(2).all? { |u, w| orthogonal?(u, w) }

    # The sum of the single projections, which is the projection itself once
    # the targets are known to be pairwise orthogonal. gram_schmidt builds
    # such a family as it goes and calls this directly, so that project does
    # not orthogonalise what it has just orthogonalised.
    def onto_orthogonal(v, targets)
      targets.reduce(v.space.unchecked(Array.new(v.entries.size, Num.new(0)))) do |sum, u|
        add(sum, scale(u, (dot(v, u) / dot(u, u)).simplify))
      end
    end

    def add(u, v)
      same_length!(u, v, "add")
      u.space.unchecked(u.entries.zip(v.entries).map { |a, b| (a + b).simplify })
    end

    # An orthogonal (or orthonormal) basis of the same span; dependent
    # vectors drop out rather than appearing as zeros.
    def gram_schmidt(vectors, normalize: false)
      basis = []
      Array(vectors).each do |v|
        w = basis.empty? ? v : subtract(v, onto_orthogonal(v, basis))
        next if w.entries.all? { |e| Scalar.zero?(e) }
        basis << w
      end
      return basis unless normalize
      basis.map { |w| scale(w, (1 / norm(w)).simplify) }
    end

    # The x minimising |A x - b|, from the normal equations A* A x = A* b
    # with A* the conjugate transpose. The plain transpose is right only for
    # real entries: for A = (1, 2i)' it gave -1/3 where the minimiser of
    # |z - 1|**2 + |2iz|**2 is 1/5, and (1, i)' had "dependent columns"
    # (a review, 23 Sept 2026). `conjugate` leaves a symbolic entry alone,
    # as `dot` does, so the real case is unchanged.
    def least_squares(matrix, target)
      unless target.entries.size == matrix.rows
        raise ArgumentError, "least_squares: the matrix has #{matrix.rows} rows and the vector #{target.entries.size} entries"
      end
      adjoint = RCAS.matrix(matrix.transpose.to_a.map { |row| row.map { |e| conjugate(e) } })
      normal = adjoint * matrix
      right = adjoint * target
      raise ArgumentError, "least_squares: the columns are dependent, so the solution is not unique" if Scalar.zero?(normal.det)
      normal.solve(right.entries)
    end

    def orthogonal?(u, v) = Scalar.zero?(dot(u, v))
  end
end
