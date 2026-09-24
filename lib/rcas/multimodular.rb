# frozen_string_literal: true

module RCAS
  # Determinants, inverses and solutions of Integer and Rational matrices
  # by computing modulo many primes and putting the answers together with
  # the Chinese remainder theorem [vzGG13, §5.5].
  #
  # Elimination over QQ is exact too, but its entries grow as it goes: each
  # step's numbers are quotients of minors of the matrix, and every one of
  # the n**3 operations pays for their size and for a gcd. Modulo a prime p
  # below 2**31 every number is one machine word. How many primes are
  # needed is known beforehand: Hadamard's inequality [Had93] bounds
  # |det A| by the product of the lengths of the rows (or of the columns),
  # and the answer is the unique residue modulo the product of the primes
  # that lies in (-M/2, M/2) once M exceeds twice the bound. That makes the
  # answer a proof, not a guess that agreed for a few more primes.
  #
  # A system A*X = B (B the identity for the inverse) is solved the same
  # way through Cramer's rule: det(A)*X is an integer matrix, the adjugate
  # times B, whose entries are determinants of A with one column replaced
  # by a column of B, and Hadamard's inequality bounds those as well. A
  # prime that divides det(A) cannot give det(A)*X by inverting A modulo p;
  # it still counts for the determinant, and there are only finitely many.
  #
  # Rational entries are scaled to Integers row by row first: the
  # determinant is then divided by the scales, and the solutions of the
  # scaled system (right-hand sides scaled with the rows) are those of the
  # original one.
  module Multimodular
    # Residues stay below 2**31, so a product of two is below 2**62 and
    # Ruby keeps it a machine integer.
    PRIME_LIMIT = 2**31

    # :auto takes the primes for every Integer and Rational matrix: they
    # were faster at every size measured on 24 Sept 2026, 2x2 included
    # (20 against 23 microseconds for det and inverse), five times at
    # n = 100 (MANUAL.md, "Determinants modulo many primes").
    ALGORITHMS = %i[auto multimodular elimination].freeze

    @primes = []
    @lock = Mutex.new

    module_function

    # The first k primes below PRIME_LIMIT, largest first.
    def primes(k)
      @lock.synchronize do
        candidate = @primes.last || PRIME_LIMIT
        while @primes.size < k
          candidate -= 1
          candidate -= 1 until NumberTheory.prime?(candidate)
          @primes << candidate
        end
        @primes.first(k)
      end
    end

    def prime(i) = primes(i + 1)[i]

    # The bare numbers of a square matrix of Integers and Rationals, or nil.
    def values(rows) = MatrixMultiply.rational_values(rows)

    def use?(rows, algorithm, allowed = ALGORITHMS)
      raise ArgumentError, "algorithm must be one of #{allowed.join(', ')}" unless allowed.include?(algorithm)
      algorithm != :elimination && !rows.empty? && !values(rows).nil?
    end

    # A system has one algorithm more: Dixon's, for one right-hand side.
    SOLVE_ALGORITHMS = %i[auto multimodular dixon elimination].freeze

    # Measured on random systems (24 Sept 2026): Dixon and the primes are
    # level at n = 24-30 and Dixon is ahead from 32 on, whatever the size of
    # the entries - 1.2x at 32 with one digit, 2x with five, 3-6x at
    # n = 100-150. Below it the one elimination and the reconstruction
    # attempts cost what a few more primes would.
    DIXON_MIN = 32

    # Multimodular, Dixon or nil (elimination) for A*x = b.
    def solver(rows, b, algorithm)
      return nil unless use?(rows, algorithm, SOLVE_ALGORITHMS) && MatrixMultiply.rational_values([b])
      return Dixon if algorithm == :dixon
      return self if algorithm == :multimodular
      rows.size >= DIXON_MIN ? Dixon : self
    end

    # det of a square matrix of Integers and Rationals.
    def det(rows)
      a, scales = integral(values(rows))
      d = crt_solve(a, []).first
      scales.all?(1) ? d : Rational(d, scales.reduce(1, :*))
    end

    # A**-1 as rows of Integers and Rationals, or nil when A is singular.
    def inverse(rows)
      a, scales = integral(values(rows))
      n = a.size
      identity = Array.new(n) { |i| Array.new(n) { |j| i == j ? scales[i] : 0 } }
      d, x = crt_solve(a, identity)
      return nil if d.zero?
      x.map { |r| r.map { |v| Rational(v, d) } }.map { |r| r.map { |v| v.denominator == 1 ? v.numerator : v } }
    end

    # The solution of A*x = b for a square non-singular A, or nil.
    def solve(rows, b)
      a, scales = integral(values(rows))
      column = b.map { |e| e.is_a?(Num) ? e.value : e }.each_with_index.map { |v, i| v * scales[i] }
      common = column.map(&:denominator).reduce(1, :lcm)
      d, x = crt_solve(a, column.map { |v| [(v * common).to_i] })
      return nil if d.zero?
      x.map { |r| Rational(r.first, d * common) }.map { |v| v.denominator == 1 ? v.numerator : v }
    end

    # Rows scaled to Integers by the lcm of their denominators, and the scales.
    def integral(a)
      scales = a.map { |r| r.map(&:denominator).reduce(1, :lcm) }
      [a.each_with_index.map { |r, i| r.map { |v| (v * scales[i]).to_i } }, scales]
    end

    # [d, N] with A**-1*B = N/d, for an Integer matrix A and Integer columns
    # B (rows of B, possibly none), by the Chinese remainder theorem; [0,
    # nil] when A is singular. With no columns, d is det A.
    #
    # Two ways to stop. The bound: once the primes multiply past twice
    # Hadamard's bound for det A (all primes) and for the Cramer numerators
    # det(A)*A**-1*B (the primes not dividing det A), d = det A and N are
    # proved. And early (`early:`): after 1, 2, 4, ... usable primes the
    # residues of A**-1*B are read back as fractions with one common
    # denominator (rational reconstruction [vzGG13, §5.10]), and if A*N = d*B
    # holds exactly, that is the solution - A is invertible, since it was
    # modulo a prime, so there is no other. The bounds are for the worst
    # matrix; a solution much smaller than its bound, as for a matrix of
    # determinant 1, is found after a fraction of the primes.
    def crt_solve(a, b, early: true)
      n = a.size
      return [1, b] if n.zero?
      det_bound = hadamard(a)
      return [0, nil] if det_bound.zero?
      width = b.first&.size || 0
      numerator_bound = cramer_bound(a, b)
      det = 0
      det_modulus = 1
      x = Array.new(n) { Array.new(width, 0) }
      x_modulus = 1
      usable = 0
      attempt = 1
      (0..).each do |i|
        if det_modulus > 2 * det_bound
          d = symmetric(det, det_modulus)
          return [0, nil] if d.zero?
          return [d, x.map { |r| r.map { |v| symmetric(v * d % x_modulus, x_modulus) } }] if width.zero? || x_modulus > 2 * numerator_bound
        end
        p = prime(i)
        d_p, x_p = eliminate(a, b, p)
        if det_modulus <= 2 * det_bound
          det = garner(det, det_modulus, d_p, p)
          det_modulus *= p
        end
        next if x_p.nil? || width.zero?
        x = x.each_with_index.map { |r, k| r.each_with_index.map { |v, j| garner(v, x_modulus, x_p[k][j], p) } }
        x_modulus *= p
        usable += 1
        next unless early && usable == attempt
        attempt *= 2
        found = verified(a, b, x, x_modulus) and return found
      end
    end

    # [d, N] with A*N = d*B exactly, read off the residues X of A**-1*B
    # modulo m, or nil.
    def verified(a, b, x, m)
      found = reconstruct(x, m) or return nil
      d, numerators = found
      product = MatrixMultiply::INTEGER.leaf(a, numerators)
      product.each_with_index.all? { |row, i| row.each_with_index.all? { |v, j| v == d * b[i][j] } } ? [d, numerators] : nil
    end

    # Rational reconstruction of a matrix of residues modulo m with one
    # common denominator: [d, N] with N/d congruent to the residues and
    # |N|, d <= sqrt(m/2), or nil. The denominator is grown entry by entry
    # - an entry that is already a small numerator over it costs one
    # multiplication, and the extended Euclidean algorithm runs only on the
    # others [vzGG13, §5.10].
    def reconstruct(x, m)
      bound = Integer.sqrt(m / 2)
      d = 1
      x.each do |row|
        row.each do |v|
          next if symmetric(v * d % m, m).abs <= bound
          fraction = rational(v * d % m, m, bound) or return nil
          d *= fraction.denominator
          return nil if d > bound
        end
      end
      [d, x.map { |row| row.map { |v| symmetric(v * d % m, m) } }]
    end

    # The fraction r/t = u modulo m with |r|, |t| <= bound, by the extended
    # Euclidean algorithm stopped halfway, or nil.
    def rational(u, m, bound)
      r0, r1 = m, u
      t0, t1 = 0, 1
      while r1 > bound
        q = r0 / r1
        r0, r1 = r1, r0 - q * r1
        t0, t1 = t1, t0 - q * t1
      end
      return nil if t1.zero? || t1.abs > bound || r1.gcd(t1) != 1
      Rational(r1, t1)
    end

    # The residue modulo m*p that is v modulo m and r modulo p (Garner).
    def garner(v, m, r, p)
      t = (r - v) * m.pow(p - 2, p) % p
      v + m * t
    end

    def symmetric(v, m) = v > m / 2 ? v - m : v

    # |det A| <= the product of the row lengths, and of the column lengths;
    # the smaller of the two, as an Integer that is not below the root.
    def hadamard(a)
      rows = a.map { |r| r.sum { |v| v * v } }
      cols = a.transpose.map { |c| c.sum { |v| v * v } }
      square = [rows.reduce(1, :*), cols.reduce(1, :*)].min
      square.zero? ? 0 : Integer.sqrt(square) + 1
    end

    # det(A)*x_i for A*x = b is det(A) with column i replaced by b, and its
    # Hadamard bound through the columns is |b| times the lengths of the
    # other columns of A.
    def cramer_bound(a, b)
      return 0 if b.empty? || b.first.empty?
      cols = a.transpose.map { |c| c.sum { |v| v * v } }
      rhs = b.transpose.map { |c| c.sum { |v| v * v } }.max
      Integer.sqrt(rhs * cols.reduce(1, :*) / cols.min) + 1
    end

    # det(A) mod p, and A**-1*B mod p unless p divides det(A):
    # elimination to a triangle, then substitution backwards.
    def eliminate(a, b, p)
      n = a.size
      width = b.first&.size || 0
      rows = Array.new(n) { |i| (a[i] + (b[i] || [])).map { |v| v % p } }
      total = n + width
      d = 1
      n.times do |c|
        pivot = (c...n).find { |i| rows[i][c] != 0 }
        return [0, nil] unless pivot
        if pivot != c
          rows[c], rows[pivot] = rows[pivot], rows[c]
          d = p - d
        end
        top = rows[c]
        d = d * top[c] % p
        inverse = top[c].pow(p - 2, p)
        ((c + 1)...n).each do |i|
          row = rows[i]
          f = row[c] * inverse % p
          next if f.zero?
          f = p - f
          j = c
          while j < total
            row[j] = (row[j] + f * top[j]) % p
            j += 1
          end
        end
      end
      return [d, nil] if width.zero?
      x = Array.new(n)
      (n - 1).downto(0) do |i|
        row = rows[i]
        inverse = row[i].pow(p - 2, p)
        x[i] = Array.new(width) do |j|
          s = row[n + j]
          k = i + 1
          while k < n
            s = (s - row[k] * x[k][j]) % p
            k += 1
          end
          s * inverse % p
        end
      end
      [d, x]
    end
  end
end
