# frozen_string_literal: true

module RCAS
  # Lattice basis reduction: the LLL algorithm, exactly.
  #
  #   lll(matrix([[1, 1, 1], [-1, 0, 2], [3, 5, 6]]))   # rows (0, 1, 0), (1, 0, 1), (-1, 0, 2)
  #   b, u = lll(m, transform: true)                    # u*m == b, u unimodular
  #   m.lll(delta: 99/100r)
  #
  # A lattice is every integer combination of some linearly independent
  # vectors, its basis; many bases give the same lattice, and most of them
  # are long and nearly parallel. A reduced basis is short and nearly
  # orthogonal. Its first vector is at most 2**((n - 1)/2) times as long as
  # the shortest non-zero vector of the lattice (for delta = 3/4), which is
  # what makes the algorithm useful far beyond lattices: integer relations
  # between real numbers, minimal polynomials from a decimal expansion,
  # simultaneous approximation, knapsacks.
  #
  # The vectors are the rows, as in the literature. The arithmetic is exact
  # (Rational), so the Gram-Schmidt coefficients are kept and updated rather
  # than recomputed, as in Cohen's formulation: size reduction touches one
  # row of mu, and a swap changes two rows and two columns of it. The price
  # of exactness is the size of those rationals; the integral version
  # [Coh93, Algorithm 2.6.7] keeps them as integers, and floating-point
  # variants trade exactness for speed, neither of which rcas needs at the
  # sizes a student reduces.
  #
  # Sources (keys: MANUAL.md, Sources): the algorithm and its bound
  # [LLL82]; the formulation with the incremental Gram-Schmidt update
  # [Coh93, §2.6, Algorithm 2.6.3]; [vzGG13, ch. 16] for the analysis.
  module Lattice
    DELTA = Rational(3, 4)

    module_function

    # The reduced basis in the shape it came in: a Matrix for a Matrix, an
    # Array of vectors otherwise; with transform: true also the unimodular
    # matrix U with U*B equal to the result.
    def lll(basis, delta: DELTA, transform: false)
      rows, shape = rows_of(basis)
      delta = rational(delta) { "lll: delta must be a rational number, got #{delta.inspect}" }
      raise ArgumentError, "lll: delta must lie in (1/4, 1], got #{delta}" unless delta > Rational(1, 4) && delta <= 1
      reduced, u = reduce(rows, delta)
      out = shape.call(reduced)
      transform ? [out, RCAS.matrix(u)] : out
    end

    # Cohen's Algorithm 2.6.3. mu[i][j] (j < i) are the Gram-Schmidt
    # coefficients and bb[i] the squared lengths of the orthogonalised
    # vectors; k is the first vector not yet known to be reduced against
    # the ones before it.
    def reduce(rows, delta)
      b = rows.map(&:dup)
      n = b.size
      u = Array.new(n) { |i| Array.new(n) { |j| i == j ? 1 : 0 } }
      mu, bb = gram_schmidt(b)
      if (i = bb.index(&:zero?))
        raise ArgumentError, "lll: the vectors are linearly dependent (vector #{i + 1} lies in the span of the ones before it); LLL reduces a basis"
      end
      k = 1
      while k < n
        size_reduce(b, u, mu, k, k - 1)
        # Lovasz's condition: the orthogonalised k-th vector is not much
        # shorter than the one before it
        if bb[k] >= (delta - mu[k][k - 1]**2) * bb[k - 1]
          (k - 2).downto(0) { |l| size_reduce(b, u, mu, k, l) }
          k += 1
        else
          swap(b, u, mu, bb, k)
          k = [k - 1, 1].max
        end
      end
      [b, u]
    end

    # b_k -= q*b_l with q the integer nearest mu[k][l], which leaves
    # |mu[k][l]| <= 1/2; mu[k][j] for j < l changes with it.
    def size_reduce(b, u, mu, k, l)
      q = mu[k][l].round
      return if q.zero?
      b[k] = b[k].zip(b[l]).map { |x, y| x - q * y }
      u[k] = u[k].zip(u[l]).map { |x, y| x - q * y }
      mu[k][l] -= q
      (0...l).each { |j| mu[k][j] -= q * mu[l][j] }
    end

    # Exchange b_(k-1) and b_k and update the Gram-Schmidt data in place
    # [Coh93, Algorithm 2.6.3, step 3]: only the two orthogonalised vectors
    # involved change, and with them rows k-1, k and columns k-1, k of mu.
    def swap(b, u, mu, bb, k)
      b[k], b[k - 1] = b[k - 1], b[k]
      u[k], u[k - 1] = u[k - 1], u[k]
      (0...k - 1).each { |j| mu[k][j], mu[k - 1][j] = mu[k - 1][j], mu[k][j] }
      m = mu[k][k - 1]
      big = bb[k] + m * m * bb[k - 1]
      mu[k][k - 1] = m * bb[k - 1] / big
      bb[k] = bb[k - 1] * bb[k] / big
      bb[k - 1] = big
      (k + 1...b.size).each do |i|
        t = mu[i][k]
        mu[i][k] = mu[i][k - 1] - m * t
        mu[i][k - 1] = t + mu[k][k - 1] * mu[i][k]
      end
    end

    # The Gram-Schmidt coefficients and squared lengths, exactly.
    def gram_schmidt(b)
      n = b.size
      mu = Array.new(n) { Array.new(n, 0r) }
      bb = Array.new(n, 0r)
      star = []
      b.each_with_index do |v, i|
        w = v.dup
        (0...i).each do |j|
          next if bb[j].zero?
          mu[i][j] = dot(v, star[j]) / bb[j]
          w = w.zip(star[j]).map { |x, y| x - mu[i][j] * y }
        end
        star << w
        bb[i] = dot(w, w)
      end
      [mu, bb]
    end

    # Whether the rows are LLL-reduced: size-reduced (|mu| <= 1/2) and
    # Lovasz's condition between neighbours. The tests ask this of every
    # answer.
    def reduced?(rows, delta: DELTA)
      rows = rows_of(rows).first
      mu, bb = gram_schmidt(rows)
      size = (1...rows.size).all? { |i| (0...i).all? { |j| mu[i][j].abs <= Rational(1, 2) } }
      size && (1...rows.size).all? { |k| bb[k] >= (Rational(delta) - mu[k][k - 1]**2) * bb[k - 1] }
    end

    def dot(v, w) = v.zip(w).sum { |x, y| x * y }

    # [rows as Arrays of Rationals, a lambda giving the answer its shape]
    def rows_of(basis)
      rows, shape =
        case basis
        when Matrix then [basis.to_a, ->(r) { RCAS.matrix(numbers(r)) }]
        when Array
          vectors = basis.map { |v| v.is_a?(Vector) ? v.entries : v }
          raise ArgumentError, "lll: expected a matrix or a list of vectors, got #{basis.inspect}" unless vectors.all?(Array)
          [vectors, ->(r) { numbers(r).map { |row| RCAS.vector(*row) } }]
        else raise ArgumentError, "lll: expected a matrix or a list of vectors, got #{basis.inspect}"
        end
      raise ArgumentError, "lll: no vectors to reduce" if rows.empty?
      raise ArgumentError, "lll: the vectors have different lengths" unless rows.map(&:size).uniq.size == 1
      entries = rows.map do |row|
        row.map do |e|
          rational(e) { "lll: the entries must be rational numbers, got #{e}; scale and round a real lattice first" }
        end
      end
      [entries, shape]
    end

    def rational(e)
      e = e.value if e.is_a?(Num)
      e = Expression.lift(e).simplify.then { |s| s.is_a?(Num) ? s.value : s } if e.is_a?(Expression)
      return e.to_r if e.is_a?(Integer) || e.is_a?(Rational)
      raise ArgumentError, yield
    end

    def numbers(rows) = rows.map { |row| row.map { |x| Simplify.normalize_number(x) } }
  end

  class Matrix
    # The LLL-reduced basis of the lattice spanned by the rows; see Lattice.
    def lll(delta: Lattice::DELTA, transform: false) = Lattice.lll(self, delta: delta, transform: transform)
  end
end
