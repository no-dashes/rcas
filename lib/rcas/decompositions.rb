# frozen_string_literal: true

module RCAS
  # Matrix factorizations, exact: LU with row swaps, QR by Gram-Schmidt,
  # Cholesky, diagonalization and the Jordan normal form.
  #
  #   l, u, p = matrix([[0, 1], [2, 3]]).lu     # p*a == l*u
  #   q, r = a.qr                               # a == q*r, q orthogonal
  #   l = a.cholesky                            # a == l*l.transpose
  #   pm, d = a.diagonalize                     # a == pm*d*pm.inverse
  #   pm, j = a.jordan                          # a == pm*j*pm.inverse
  #
  # The arithmetic is the exact Scalar arithmetic the rest of the matrix
  # code uses, so pivots are swapped only when they are zero (there is no
  # rounding to steer away from): a symbolic pivot that is not identically
  # zero is taken to be non-zero, the generic case, as everywhere else.
  #
  # Sources (keys: MANUAL.md, Sources): LU, QR and Cholesky as in
  # [Str16, ch. 2, 4, 6]; the Jordan form built from chains of generalized
  # eigenvectors as in [HK71, ch. 7].
  module Decompositions
    module_function

    # P*A = L*U with L unit lower triangular, U upper triangular and P a
    # permutation. Rows are swapped only to get away from a zero pivot.
    def lu(matrix)
      square!(matrix, "lu")
      n = matrix.rows
      u = matrix.to_a
      l = identity_rows(n)
      p = identity_rows(n)
      (0...n).each do |k|
        pivot = (k...n).find { |i| !Scalar.zero?(u[i][k]) }
        next if pivot.nil?
        if pivot != k
          u[k], u[pivot] = u[pivot], u[k]
          p[k], p[pivot] = p[pivot], p[k]
          (0...k).each { |j| l[k][j], l[pivot][j] = l[pivot][j], l[k][j] }
        end
        ((k + 1)...n).each do |i|
          factor = Scalar.div(u[i][k], u[k][k])
          l[i][k] = factor
          (k...n).each { |j| u[i][j] = Scalar.sub(u[i][j], Scalar.mul(factor, u[k][j])).simplify }
        end
      end
      [field_matrix(matrix, l), field_matrix(matrix, u), field_matrix(matrix, p)]
    end

    # A = Q*R with the columns of Q orthonormal and R upper triangular.
    # Exact, so the entries of Q carry square roots.
    def qr(matrix)
      basis = LinearAlgebra.gram_schmidt(matrix.column_vectors, normalize: true)
      raise ArgumentError, "qr: the columns of the matrix are not independent" unless basis.size == matrix.cols
      q = field_matrix(matrix, basis.map(&:entries).transpose, matrix.rows, matrix.cols)
      r = (q.transpose * matrix).simplify
      [q, r]
    end

    # A = L*L' for a symmetric positive definite A.
    def cholesky(matrix)
      square!(matrix, "cholesky")
      raise ArgumentError, "cholesky: the matrix is not symmetric" unless matrix.symmetric?
      n = matrix.rows
      l = Array.new(n) { Array.new(n, Num.new(0)) }
      (0...n).each do |i|
        (0..i).each do |j|
          rest = (0...j).reduce(matrix[i, j]) { |acc, k| Scalar.sub(acc, Scalar.mul(l[i][k], l[j][k])) }.simplify
          l[i][j] =
            if i == j
              raise ArgumentError, "cholesky: the matrix is not positive definite" if nonpositive?(rest)
              Pow.new(rest, Num.new(Rational(1, 2))).simplify
            else
              Scalar.div(rest, l[j][j]).simplify
            end
        end
      end
      field_matrix(matrix, l)
    end

    # A = P*D*P**-1 with D diagonal: the eigenvectors as the columns of P.
    def diagonalize(matrix)
      square!(matrix, "diagonalize")
      pairs = matrix.eigenvectors.flat_map { |value, _, vectors| vectors.map { |v| [value, v] } }
      unless pairs.size == matrix.rows
        raise ArgumentError, "diagonalize: #{pairs.size} independent eigenvectors for #{matrix.rows} dimensions; " \
                             "the matrix is not diagonalizable - jordan gives its Jordan form"
      end
      [basis_matrix(matrix, pairs.map { |_, v| v.entries }), diagonal(matrix, pairs.map(&:first))]
    end

    # A = P*J*P**-1 with J in Jordan normal form: one block per chain of
    # generalized eigenvectors.
    def jordan(matrix)
      square!(matrix, "jordan")
      n = matrix.rows
      columns = []
      blocks = []
      Solve.dedupe(matrix.eigenvalues).each do |value|
        chains = chains_for(matrix, value)
        chains.each do |chain|
          columns.concat(chain)
          blocks << [value, chain.size]
        end
      end
      unless columns.size == n
        raise NotImplementedError, "jordan: only #{columns.size} of #{n} basis vectors were found; " \
                                   "the eigenvalues have to be exact for the chains to be built"
      end
      [basis_matrix(matrix, columns), jordan_matrix(matrix, blocks)]
    end

    # ---- the Jordan chains ---------------------------------------------------

    # The chains for one eigenvalue, longest first. A chain is
    # [N**(k-1) u, ..., N u, u] with N = A - lambda and u in ker(N**k) but
    # not in ker(N**(k-1)), so that N maps each vector to the one before it
    # and the first one is an eigenvector.
    def chains_for(matrix, value)
      shifted = matrix - matrix.space.identity.scale(value)
      kernels = nested_kernels(shifted)
      chains = []
      taken = []
      kernels.size.downto(1) do |k|
        candidates(kernels, k).each do |u|
          chain = build_chain(shifted, u, k)
          next if chain.nil? || !independent?(taken + chain.flatten(0), matrix)
          chains << chain
          taken.concat(chain)
        end
      end
      chains
    end

    # [basis of ker(N), basis of ker(N**2), ...] up to the point where the
    # kernel stops growing.
    def nested_kernels(shifted)
      out = []
      power = shifted
      loop do
        basis = power.kernel.map { |v| v.entries.map { |e| Expression.lift(e).simplify } }
        break if !out.empty? && basis.size <= out.last.size
        out << basis
        break if basis.size >= shifted.rows
        power = (power * shifted).simplify
      end
      out
    end

    # Vectors of ker(N**k) that are not already in ker(N**(k-1)).
    def candidates(kernels, k)
      return [] if kernels[k - 1].nil?
      lower = k >= 2 ? kernels[k - 2] : []
      kernels[k - 1].reject { |v| in_span?(lower, v) }
    end

    def build_chain(shifted, top, length)
      chain = [top]
      (length - 1).times do
        previous = apply(shifted, chain.first)
        return nil if previous.all? { |e| Scalar.zero?(e) }
        chain.unshift(previous)
      end
      chain
    end

    def apply(matrix, vector)
      (0...matrix.rows).map do |i|
        (0...matrix.cols).reduce(Num.new(0)) { |acc, j| Scalar.add(acc, Scalar.mul(matrix[i, j], vector[j])) }.simplify
      end
    end

    def in_span?(vectors, v)
      return false if vectors.empty?
      rank_of(vectors) == rank_of(vectors + [v])
    end

    def independent?(vectors, _matrix) = rank_of(vectors) == vectors.size

    def rank_of(vectors)
      return 0 if vectors.empty?
      Elimination.rref(vectors.map { |v| v.map { |e| Expression.lift(e) } }).last.size
    end

    # ---- building matrices ---------------------------------------------------

    def square!(matrix, name)
      raise ArgumentError, "#{name}: the matrix must be square" unless matrix.square?
    end

    def identity_rows(n) = Array.new(n) { |i| Array.new(n) { |j| Num.new(i == j ? 1 : 0) } }

    def field_matrix(matrix, rows, r = nil, c = nil)
      space = MatrixSpace.new(matrix.base.fraction_field, r || rows.size, c || rows.first.size)
      space.unchecked(rows)
    end

    # The vectors as the columns of one matrix.
    def basis_matrix(matrix, vectors) = field_matrix(matrix, vectors.map { |v| v.map { |e| Expression.lift(e).simplify } }.transpose)

    def diagonal(matrix, values)
      n = values.size
      field_matrix(matrix, Array.new(n) { |i| Array.new(n) { |j| i == j ? Expression.lift(values[i]) : Num.new(0) } })
    end

    # One Jordan block per [eigenvalue, size], on the diagonal.
    def jordan_matrix(matrix, blocks)
      n = blocks.sum(&:last)
      rows = Array.new(n) { Array.new(n, Num.new(0)) }
      offset = 0
      blocks.each do |value, size|
        (0...size).each do |i|
          rows[offset + i][offset + i] = Expression.lift(value)
          rows[offset + i][offset + i + 1] = Num.new(1) if i + 1 < size
        end
        offset += size
      end
      field_matrix(matrix, rows)
    end

    def nonpositive?(entry)
      return true if Scalar.zero?(entry)
      value = Expression.lift(entry).evalf
      value.is_a?(Numeric) && value.real? && value.negative?
    end
  end

  class Matrix
    # P*A = L*U: l, u, p = a.lu
    def lu = Decompositions.lu(self)
    # A = Q*R with Q orthogonal: q, r = a.qr
    def qr = Decompositions.qr(self)
    # A = L*L' for a symmetric positive definite matrix
    def cholesky = Decompositions.cholesky(self)
    # A = P*D*P**-1 with D diagonal: p, d = a.diagonalize
    def diagonalize = Decompositions.diagonalize(self)
    # A = P*J*P**-1 with J in Jordan normal form: p, j = a.jordan
    def jordan = Decompositions.jordan(self)
  end
end
