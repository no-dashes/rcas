# frozen_string_literal: true

module RCAS
  # Linear algebra for matrices whose entries are polynomials or rational
  # functions in one indeterminate with rational coefficients, by evaluation
  # and interpolation (P. Horn, Faktorisierung in Schief-Polynomringen,
  # Kassel 2008, chapter 6): a degree bound B for the result, B + 1 exact
  # rational evaluations of the matrix, numeric Gaussian elimination at every
  # point and Newton interpolation of the values.
  #
  #   PolyDet          determinant, O(n**4 d**2) field operations
  #   RatDet           the same after clearing row denominators
  #   PolyLinearSolve  M*Y = b through Cramer: interpolate det(M) and the
  #                    isolated numerators y_i * det(M)
  #   Nullspace        drop dependent rows and columns, solve the square
  #                    system for every remaining column (Algorithm 25)
  #
  # Source: [Hor08, ch. 6] (P. Horn, Faktorisierung in Schief-Polynomringen,
  # Kassel 2008), Algorithms 20-25; the same evaluation/interpolation idea
  # for determinants over ZZ is in [vzGG13, §5.5]. Keys: MANUAL.md, Sources.
  #
  # Every public function returns nil when the matrix is not of that shape
  # (several indeterminates, algebraic or floating point coefficients, ...),
  # so Matrix can fall back to elimination over expressions.
  module PolyMatrix
    module_function

    # ---- entry points -----------------------------------------------------

    # Determinant as an expression, or nil.
    def det(entries)
      data = prepare(entries) or return nil
      x, rows, scale = data
      d = poly_det(rows, x)
      quotient(d, scale.reduce { |acc, s| acc * s }) # Algorithm 22: divide by the row scales
    end

    # Solution of the square system M*Y = b as an Array of expressions, or nil
    # when M is singular or the data is not polynomial.
    def solve(entries, b)
      data = prepare(entries, [b]) or return nil
      x, rows, scale, columns = data
      _ = scale
      system = solve_columns(rows, columns, x) or return nil
      system.first.first
    end

    # Inverse as rows of expressions, or nil when singular or not polynomial.
    def inverse(entries)
      n = entries.size
      identity = Array.new(n) { |j| Array.new(n) { |i| Num.new(i == j ? 1 : 0) } }
      data = prepare(entries, identity) or return nil
      x, rows, scale, columns = data
      _ = scale # prepare scaled the identity columns along with the rows, so S*M*Y = S*e_j
      system = solve_columns(rows, columns, x) or return nil
      system.first.transpose
    end

    # Kernel basis in the reduced-row-echelon convention (1 in the free
    # column), as Arrays of expressions, or nil.
    def kernel(entries)
      data = prepare(entries) or return nil
      x, rows, = data
      k = rows.first.size
      independent_rows, pivots = independent(rows, x)
      free = (0...k).to_a - pivots
      return [] if free.empty?
      square = independent_rows.map { |r| pivots.map { |c| r[c] } }
      columns = free.map { |f| independent_rows.map { |r| negate(r[f]) } }
      system = solve_columns(square, columns, x) or return nil
      solutions = system.first
      vectors = free.each_with_index.map do |f, l|
        v = Array.new(k) { Num.new(0) }
        v[f] = Num.new(1)
        pivots.each_with_index { |p, i| v[p] = solutions[l][i] }
        v
      end
      return nil unless vectors.all? { |v| in_kernel?(rows, v, x) }
      vectors
    end

    # ---- preparation --------------------------------------------------------

    # => [x, rows of coefficient arrays, row scales (Polynomial), extra columns]
    # Every entry must be a rational function with rational coefficients in
    # one indeterminate. Rows are multiplied by the lcm of their denominators.
    def prepare(entries, extra_columns = [])
      all = entries.flatten + extra_columns.flatten
      vars = all.flat_map { |e| e.is_a?(Expression) ? e.variables : [] }.uniq
      return nil unless vars.size == 1
      x = vars.first
      ring = QQ[x]
      fractions = entries.map { |r| r.map { |e| fraction(e, ring) or return nil } }
      extras = extra_columns.map { |col| col.map { |e| fraction(e, ring) or return nil } }
      scale = fractions.each_with_index.map do |row, i|
        dens = row.map(&:last) + extras.map { |col| col[i].last }
        dens.reduce(ring.one) { |acc, d| acc.lcm(d) }
      end
      rows = fractions.each_with_index.map { |row, i| row.map { |n, d| coefficients(n * scale[i].exact_div(d)) } }
      columns = extras.map { |col| col.each_with_index.map { |(n, d), i| coefficients(n * scale[i].exact_div(d)) } }
      [x, rows, scale, columns]
    end

    def fraction(entry, ring)
      entry = Expression.lift(entry)
      if entry.is_a?(Num)
        return nil unless entry.value.is_a?(Integer) || entry.value.is_a?(Rational)
        return [ring.call(entry.value), ring.one]
      end
      pair = Fraction.as_fraction(entry, ring.vars) or return nil
      pair.map { |p| p.to_ring(ring) }
    end

    # Coefficient array (constant term first) of a univariate Polynomial.
    def coefficients(poly)
      return [] if poly.zero?
      poly.coefficients.map { |c| Rational(c.value) }
    end

    def degree(coeffs) = coeffs.size - 1

    def evaluate(coeffs, a) = coeffs.reverse_each.reduce(0r) { |acc, c| acc * a + c }

    def negate(coeffs) = coeffs.map(&:-@)

    # ---- PolyDet ------------------------------------------------------------

    # Lemma 6.1: deg det M <= min(sum of row maxima, sum of column maxima).
    def degree_bound(rows)
      row_max = rows.map { |r| r.map { |c| degree(c) }.max }
      col_max = rows.transpose.map { |c| c.map { |e| degree(e) }.max }
      return -1 if row_max.include?(-1) || col_max.include?(-1)
      [row_max.sum, col_max.sum].min
    end

    # Algorithm 21: determinant of a matrix of coefficient arrays, as a
    # coefficient array.
    def poly_det(rows, _x)
      bound = degree_bound(rows)
      return [] if bound.negative?
      points = evaluation_points.first(bound + 1)
      values = points.map { |a| numeric_det(rows.map { |r| r.map { |c| evaluate(c, a) } }) }
      interpolate(points, values)
    end

    # 0, 1, -1, 2, -2, ...
    def evaluation_points
      Enumerator.new do |y|
        y << 0r
        (1..).each { |i| y << Rational(i) << Rational(-i) }
      end
    end

    # ---- PolyLinearSolve ----------------------------------------------------

    # Algorithm 23 for several right-hand sides sharing the determinant and
    # the evaluation points. => [[solution columns as expressions], det]
    # or nil when the matrix is singular.
    def solve_columns(rows, columns, x)
      n = rows.size
      det = poly_det(rows, x)
      return nil if det.empty?
      bounds = columns.map do |col|
        (0...n).map { |i| degree_bound(rows.each_with_index.map { |r, k| r.dup.tap { |row| row[i] = col[k] } }) }.max
      end
      bound = [bounds.max || 0, 0].max
      points = []
      evaluation_points.each do |a|
        next if evaluate(det, a).zero?
        points << a
        break if points.size == bound + 1
      end
      det_values = points.map { |a| evaluate(det, a) }
      numerators = columns.map { Array.new(n) { [] } }
      points.each_with_index do |a, idx|
        matrix = rows.map { |r| r.map { |c| evaluate(c, a) } }
        columns.each_with_index do |col, l|
          y = numeric_solve(matrix, col.map { |c| evaluate(c, a) })
          n.times { |i| numerators[l][i][idx] = y[i] * det_values[idx] }
        end
      end
      det_poly = polynomial(det, x)
      solutions = numerators.map do |cols|
        cols.map { |values| quotient(interpolate(points, values), det_poly) }
      end
      [solutions, det_poly]
    end

    # Independent rows and pivot columns, found on the generic evaluation
    # that gives the largest rank among a few points. #kernel verifies the
    # result exactly afterwards.
    def independent(rows, _x)
      best = nil
      evaluation_points.first(4).each do |a|
        matrix = rows.map { |r| r.map { |c| evaluate(c, a) } }
        pivots, row_indices = numeric_pivots(matrix)
        best = [pivots, row_indices] if best.nil? || pivots.size > best.first.size
      end
      pivots, row_indices = best
      [row_indices.map { |i| rows[i] }, pivots]
    end

    def in_kernel?(rows, vector, x)
      rows.all? do |r|
        total = r.each_with_index.reduce(Num.new(0)) { |acc, (c, j)| acc + polynomial(c, x).to_expr * vector[j] }
        Scalar.zero?(Fraction.cancel(total))
      end
    end

    # ---- exact rational linear algebra --------------------------------------

    def numeric_det(matrix)
      m = matrix.map(&:dup)
      n = m.size
      result = 1r
      n.times do |c|
        p = (c...n).find { |i| !m[i][c].zero? } or return 0r
        if p != c
          m[c], m[p] = m[p], m[c]
          result = -result
        end
        pivot = m[c][c]
        result *= pivot
        ((c + 1)...n).each do |i|
          f = m[i][c] / pivot
          next if f.zero?
          m[i] = m[i].zip(m[c]).map { |a, b| a - f * b }
        end
      end
      result
    end

    # Solution of a regular square system over QQ.
    def numeric_solve(matrix, b)
      m = matrix.each_with_index.map { |r, i| r + [b[i]] }
      n = m.size
      n.times do |c|
        p = (c...n).find { |i| !m[i][c].zero? } or raise ZeroDivisionError, "singular evaluation"
        m[c], m[p] = m[p], m[c]
        pivot = m[c][c]
        m[c] = m[c].map { |v| v / pivot }
        n.times do |i|
          next if i == c
          f = m[i][c]
          next if f.zero?
          m[i] = m[i].zip(m[c]).map { |a, b| a - f * b }
        end
      end
      m.map(&:last)
    end

    # => [pivot columns, indices of the rows that carry them]
    def numeric_pivots(matrix)
      m = matrix.each_with_index.map { |r, i| [r.dup, i] }
      rows, cols = m.size, (m.first&.first&.size || 0)
      pivots = []
      row_indices = []
      r = 0
      cols.times do |c|
        break if r == rows
        p = (r...rows).find { |i| !m[i][0][c].zero? } or next
        m[r], m[p] = m[p], m[r]
        pivot = m[r][0][c]
        m[r][0] = m[r][0].map { |v| v / pivot }
        rows.times do |i|
          next if i == r
          f = m[i][0][c]
          next if f.zero?
          m[i][0] = m[i][0].zip(m[r][0]).map { |a, b| a - f * b }
        end
        pivots << c
        row_indices << m[r][1]
        r += 1
      end
      [pivots, row_indices.sort]
    end

    # ---- interpolation and output -------------------------------------------

    # Newton interpolation through (points[i], values[i]) => coefficient array.
    def interpolate(points, values)
      n = points.size
      coeffs = values.dup
      (1...n).each do |level|
        (n - 1).downto(level) { |i| coeffs[i] = (coeffs[i] - coeffs[i - 1]) / (points[i] - points[i - level]) }
      end
      poly = []
      (n - 1).downto(0) do |i|
        # poly = poly * (x - points[i]) + coeffs[i]
        shifted = [0r] + poly
        poly.each_with_index { |c, k| shifted[k] -= c * points[i] }
        shifted[0] += coeffs[i]
        poly = shifted
      end
      poly.pop while !poly.empty? && poly.last.zero?
      poly
    end

    def polynomial(coeffs, x)
      ring = QQ[x || :_]
      Polynomial.new(ring, coeffs.each_with_index.reject { |c, _| c.zero? }.to_h { |c, k| [[k], Num.new(Simplify.normalize_number(c))] })
    end

    # num / den as a cancelled expression; num a coefficient array or
    # Polynomial, den a Polynomial.
    def quotient(num, den)
      num = polynomial(num, den.ring.vars.first) if num.is_a?(Array)
      return Num.new(0) if num.zero?
      g = num.gcd(den)
      num = num.exact_div(g)
      den = den.exact_div(g)
      lc = den.leading_coefficient
      num *= Scalar.div(Num.new(1), lc)
      den = den.monic
      den.constant? ? num.to_expr : (num.to_expr / den.to_expr).simplify
    end
  end
end
