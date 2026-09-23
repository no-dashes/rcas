# frozen_string_literal: true

module RCAS
  # QQ**[2, 3]: matrices with a fixed shape over a domain, and a domain
  # itself: a matrix answers `domain` with the space it lives in, and the
  # space answers `base` with the domain its entries come from.
  class MatrixSpace < Domain
    attr_reader :base, :rows, :cols

    def initialize(base, rows, cols = rows)
      unless rows.is_a?(Integer) && cols.is_a?(Integer) && rows >= 0 && cols >= 0
        raise ArgumentError, "matrix shape must be two non-negative integers"
      end
      @base = base
      @rows = rows
      @cols = cols
      freeze
    end

    # (QQ**[2, 2])[[1, 2], [3, 4]]. This is the element constructor and it
    # shadows Domain#[], the polynomial ring - which rcas cannot build over a
    # space anyway, since a coefficient is a number. A symbol therefore has no
    # meaning here, and saying so is more use than counting rows.
    def [](*row_arrays)
      if (names = row_arrays.grep(Symbol) + row_arrays.grep(Var).map(&:name)).any?
        raise DomainError, "#{self} is not a domain of numbers: polynomial coefficients are scalars. " \
                           "Matrices of polynomials are (#{base}[#{names.join(', ')}])**[#{rows}, #{cols}]"
      end
      row_arrays = row_arrays.first if row_arrays.size == 1 && row_arrays.first.first.is_a?(Array)
      unless row_arrays.size == rows && row_arrays.all? { |r| r.size == cols }
        raise DomainError, "#{self} needs #{rows} rows of #{cols} entries"
      end
      entries = row_arrays.map { |r| r.map { |e| Scalar.lift(e) } }
      entries = entries.map { |r| r.map { |e| base.normalize_coefficient(e) } } if base.respond_to?(:normalize_coefficient)
      entries.flatten.each do |e|
        raise DomainError, "#{e} is not in #{base}" unless Infer.where_defined { base.include?(e) }
      end
      Matrix.new(self, entries)
    end

    def unchecked(entries) = Matrix.new(self, entries.map { |r| r.map { |e| Scalar.lift(e) } })

    def include?(obj)
      obj = self[*obj] if obj.is_a?(Array)
      obj.is_a?(Matrix) && obj.rows == rows && obj.cols == cols && obj.entries.flatten.all? { |e| base.include?(e) }
    rescue DomainError
      false
    end
    alias member? include?
    def ===(obj) = include?(obj)

    def zero = unchecked(Array.new(rows) { Array.new(cols, 0) })

    def identity
      raise ArgumentError, "identity needs a square shape" unless square?
      unchecked(Array.new(rows) { |i| Array.new(cols) { |j| i == j ? 1 : 0 } })
    end

    def square? = rows == cols

    # Square matrices over a ring are a ring under multiplication; a shape
    # that is not square is not, and only the 1 by 1 case can be a field.
    def ring? = square? && base.ring?
    def field? = rows == 1 && cols == 1 && base.field?

    # Matrices are not numbers: no polynomial has them as coefficients.
    def scalar? = false

    def over(other_base) = MatrixSpace.new(other_base, rows, cols)

    # The same shape over a larger base: (ZZ**[2, 2]) < (QQ**[2, 2]).
    def subset?(other) = other.is_a?(MatrixSpace) && other.rows == rows && other.cols == cols && base.subset?(other.base)

    def join(other)
      return MatrixSpace.new(base.join(other.base), rows, cols) if other.is_a?(MatrixSpace) && other.rows == rows && other.cols == cols
      raise DomainError, "no common domain for #{self} and #{other}" if other.is_a?(MatrixSpace) || other.is_a?(VectorSpace)
      MatrixSpace.new(base.join(other), rows, cols) # a domain of scalars: what scaling gives
    end

    def ==(other) = other.is_a?(MatrixSpace) && other.base == base && other.rows == rows && other.cols == cols
    alias eql? ==
    def hash = [MatrixSpace, base, rows, cols].hash

    def name = "#{base}**[#{rows}, #{cols}]"
  end

  class Matrix
    include Algebraic

    attr_reader :space, :entries

    def initialize(space, entries)
      @space = space
      @entries = entries.map(&:freeze).freeze
      freeze
    end

    def rows = space.rows
    def cols = space.cols
    # The space is where the matrix lives, base where its entries come from.
    def domain = space
    def base = space.base
    def square? = space.square?
    def [](i, j) = entries.fetch(i).fetch(j)
    def to_a = entries.map(&:dup)

    def row(i) = VectorSpace.new(base, cols).unchecked(entries.fetch(i))
    def column(j) = VectorSpace.new(base, rows).unchecked(entries.map { |r| r.fetch(j) })
    def row_vectors = (0...rows).map { |i| row(i) }
    def column_vectors = (0...cols).map { |j| column(j) }

    # ---- arithmetic -------------------------------------------------------

    def +(other) = zip_with(other, :+) { |a, b| Scalar.add(a, b) }
    def -(other) = zip_with(other, :-) { |a, b| Scalar.sub(a, b) }
    def -@ = space.unchecked(map_entries { |e| Scalar.neg(e) })

    # The product goes through MatrixMultiply: Integer and Rational entries
    # on the bare numbers, Strassen for large ones (MatrixMultiply.algorithm
    # chooses; `multiply` names the algorithm for one product).
    def *(other)
      case other
      when Matrix then multiply(other)
      when Vector
        raise ArgumentError, "shape mismatch: #{space} * #{other.space}" unless cols == other.dim
        column = other.entries.map { |e| [e] }
        product = MatrixMultiply.product(entries, column, :schoolbook, columns: 1).map(&:first)
        VectorSpace.new(base.join(other.base), rows).unchecked(product)
      else
        scale(other)
      end
    end

    # a.multiply(b, algorithm: :strassen): the product by :schoolbook,
    # :strassen [Str69], [Win71] or :auto, for comparing them.
    def multiply(other, algorithm: nil)
      raise TypeError, "can't multiply a Matrix by #{other.class} with an algorithm" unless other.is_a?(Matrix)
      raise ArgumentError, "shape mismatch: #{space} * #{other.space}" unless cols == other.rows
      product = MatrixMultiply.product(entries, other.entries, algorithm || MatrixMultiply.algorithm, columns: other.cols)
      MatrixSpace.new(base.join(other.base), rows, other.cols).unchecked(product)
    end

    def self.row_times(vector, matrix)
      raise ArgumentError, "shape mismatch: #{vector.space} * #{matrix.space}" unless vector.dim == matrix.rows
      product = MatrixMultiply.product([vector.entries], matrix.entries, :schoolbook, columns: matrix.cols).first
      VectorSpace.new(vector.base.join(matrix.base), matrix.cols).unchecked(product)
    end

    def /(scalar)
      s = Scalar.lift(scalar)
      space.over(result_base(s).fraction_field).unchecked(map_entries { |e| Scalar.div(e, s) })
    end

    def scale(scalar)
      s = Scalar.lift(scalar)
      space.over(result_base(s)).unchecked(map_entries { |e| Scalar.mul(e, s) })
    end

    def coerce(other) = [ScalarProxy.new(other), self]
    def rop(op, left) = op == :* ? scale(left) : super

    def **(n)
      raise ArgumentError, "matrix powers need a square matrix" unless square?
      raise ArgumentError, "matrix powers must be integers" unless n.is_a?(Integer)
      return inverse**(-n) if n.negative?
      result = space.identity
      base = self
      while n.positive?
        result *= base if n.odd?
        base *= base
        n >>= 1
      end
      result
    end

    def transpose = MatrixSpace.new(base, cols, rows).unchecked(entries.transpose)
    alias t transpose

    def trace
      raise ArgumentError, "trace needs a square matrix" unless square?
      (0...rows).map { |i| self[i, i] }.reduce { |s, x| Scalar.add(s, x) } || Num.new(0)
    end

    # ---- elimination ------------------------------------------------------

    # Reduced row echelon form, over the fraction field of the base.
    def rref = space.over(base.fraction_field).unchecked(Elimination.rref(entries).first)

    # A Float matrix counts a pivot below its rounding as zero, the tolerance
    # its eigenvectors use: [[1, 3], [0.1, 0.3]] has proportional rows, and
    # the exact elimination found the -5.6e-17 left of 0.3 - 3*0.1 (fourth
    # review, L10).
    def rank
      found = full_rank_at_a_point
      return found if found
      return Elimination.rref(entries).last.size unless floating?
      rows = Matrix.float_rows(entries)
      Matrix.float_eliminate(rows, Matrix.float_scale(rows) * FLOAT_TOLERANCE).last.size
    end

    # Numeric: Gaussian elimination. Polynomial or rational-function entries
    # in one indeterminate: evaluation and interpolation (PolyMatrix).
    # Anything else: cofactor expansion.
    def det
      raise ArgumentError, "determinant needs a square matrix" unless square?
      return Elimination.det(entries) if numeric?
      PolyMatrix.det(entries) || Elimination.cofactor_det(entries).expand
    end

    # Numeric matrices are inverted by row reduction, symbolic ones through
    # the adjugate so the entries come out as cofactor/det.
    def inverse
      raise ArgumentError, "inverse needs a square matrix" unless square?
      target = space.over(base.fraction_field)
      if numeric?
        augmented = entries.each_with_index.map { |r, i| r + Array.new(rows) { |j| Num.new(i == j ? 1 : 0) } }
        reduced, pivots = Elimination.rref(augmented)
        raise DomainError, "matrix is singular" unless pivots.first(rows) == (0...rows).to_a
        target.unchecked(reduced.map { |r| r.drop(rows) })
      elsif (inv = PolyMatrix.inverse(entries))
        target.unchecked(inv)
      else
        d = det
        raise DomainError, "matrix is singular" if Scalar.zero?(d)
        target.unchecked(adjugate.entries.map { |r| r.map { |e| Scalar.div(e, d) } })
      end
    end
    alias inv inverse

    def cofactor(i, j)
      minor = entries.reject.with_index { |_, r| r == i }.map { |r| r.reject.with_index { |_, c| c == j } }
      d = Elimination.cofactor_det(minor).expand
      (i + j).even? ? d : Scalar.neg(d)
    end

    def adjugate
      raise ArgumentError, "adjugate needs a square matrix" unless square?
      space.unchecked(Array.new(rows) { |i| Array.new(cols) { |j| cofactor(j, i) } })
    end

    def invertible? = square? && rank == rows

    # Solve A*x = b. Free variables are set to zero; use #kernel for the rest.
    def solve(b)
      b = b.entries if b.is_a?(Vector)
      raise ArgumentError, "right-hand side needs #{rows} entries" unless b.size == rows
      if square? && !numeric? && (y = PolyMatrix.solve(entries, b.map { |e| Scalar.lift(e) }))
        return VectorSpace.new(base.fraction_field, cols).unchecked(y)
      end
      augmented = entries.each_with_index.map { |r, i| r + [Scalar.lift(b[i])] }
      reduced, pivots = Elimination.rref(augmented)
      pivots = pivots.reject { |c| c == cols }
      reduced.each do |r|
        if r.take(cols).all? { |e| Scalar.zero?(e) } && !Scalar.zero?(r[cols])
          raise DomainError, "system is inconsistent"
        end
      end
      x = Array.new(cols) { Num.new(0) }
      pivots.each_with_index { |c, i| x[c] = reduced[i][cols] }
      VectorSpace.new(base.fraction_field, cols).unchecked(x)
    end

    # Basis of the null space, as vectors over the fraction field.
    def kernel
      space_k = VectorSpace.new(base.fraction_field, cols)
      if !numeric? && (basis = PolyMatrix.kernel(entries))
        return basis.map { |v| space_k.unchecked(v) }
      end
      reduced, pivots = Elimination.rref(entries)
      free = (0...cols).to_a - pivots
      space_k = VectorSpace.new(base.fraction_field, cols)
      free.map do |f|
        v = Array.new(cols) { Num.new(0) }
        v[f] = Num.new(1)
        pivots.each_with_index { |p, i| v[p] = Scalar.neg(reduced[i][f]) }
        space_k.unchecked(v)
      end
    end
    alias nullspace kernel

    # Characteristic polynomial det(t*I - A) as an element of base[t].
    # The variable is x unless the entries use x themselves, and then the
    # first of lambda, t, s that they do not: det(x*I - A) with the x of A
    # inside collapsed [[x, 1], [1, x]] to -1 (third review, L11). A name
    # given explicitly that the entries use is refused.
    def charpoly(var = nil)
      raise ArgumentError, "charpoly needs a square matrix" unless square?
      used = entries.flatten.flat_map { |e| Expression.lift(e).variables }.uniq
      if var.nil?
        var = %i[x lambda t s].find { |name| !used.include?(name) } || Expression.fresh_variable(:x, used).name
      elsif used.include?(var.to_sym)
        raise ArgumentError, "charpoly: the entries already use #{var}; name another variable"
      end
      t = Var.new(var)
      shifted = Array.new(rows) { |i| Array.new(cols) { |j| i == j ? Scalar.sub(t, self[i, j]) : Scalar.neg(self[i, j]) } }
      ring = (base.ring? ? base : ZZ)[var]
      ring = base[var] if base.is_a?(FiniteField)
      ring.call(PolyMatrix.det(shifted) || Elimination.cofactor_det(shifted).expand)
    end

    # ---- eigenvalues ------------------------------------------------------

    # Eigenvalues with multiplicity, exact when the characteristic polynomial
    # factors into pieces of degree <= 2 over QQ, numeric otherwise.
    def eigenvalues
      p = charpoly(:_l)
      return p.roots if base.is_a?(FiniteField)
      Solve.polynomial_roots((0..p.degree).map { |k| p.coeff(k) })
    end

    # [[eigenvalue, multiplicity, [basis of the eigenspace]], ...]
    def eigenvectors
      values = eigenvalues
      Solve.dedupe(values).map do |l|
        shifted = self - space.identity.scale(l)
        vectors = if floating?
                    float_kernel(shifted, Matrix.float_scale(Matrix.float_rows(entries)))
                  else
                    shifted.kernel.map { |v| v.space.unchecked(v.entries.map { |e| e.rationalize }) }
                  end
        [l, values.count { |v| v == l }, vectors]
      end
    end

    def floating? = entries.flatten.any? { |e| e.is_a?(Num) && (e.value.is_a?(Float) || (e.value.is_a?(Complex) && e.value.real.is_a?(Float))) }

    # The kernel of a Float matrix, by elimination with partial pivoting and
    # a pivot counted as zero below rounding relative to the matrix: A - l*I
    # at a Float eigenvalue is singular only up to its last digits, and the
    # exact kernel of it was empty (third review, L10). Relative to the
    # matrix it came from, and to nothing else: max(|A|, 1) made the
    # tolerance absolute for a small matrix, and a Jordan block of size
    # 1e-12 was diagonalizable (fourth review).
    def float_kernel(m, scale = nil)
      rows = Matrix.float_rows(m.entries)
      tolerance = (scale || Matrix.float_scale(rows)) * FLOAT_TOLERANCE
      reduced, pivots = Matrix.float_eliminate(rows, tolerance)
      n = cols
      free = (0...n).to_a - pivots
      space_v = VectorSpace.new(base, n)
      free.map do |f|
        v = Array.new(n, Complex(0.0))
        v[f] = Complex(1.0)
        pivots.each_with_index { |c, i| v[c] = -reduced[i][f] }
        space_v.unchecked(v.map { |z| Num.new(z.imaginary.abs <= tolerance ? z.real : z) })
      end
    end

    FLOAT_TOLERANCE = 1e-9

    # The rank of a symbolic matrix is the generic one, and full rank at a
    # single rational point proves it: a maximal minor that is not 0 there
    # is not the zero function. The elimination over rational functions
    # swells (a generic 5x5 ran for minutes: fourth review, section 4), so
    # it is left for a matrix that is deficient at the point. nil otherwise.
    def full_rank_at_a_point
      return nil if floating?
      names = entries.flatten.flat_map { |e| Expression.lift(e).variables }.uniq
      return nil if names.empty?
      point = names.each_with_index.to_h { |name, i| [name, Num.new(Rational(Scalar::PRIMES[i % Scalar::PRIMES.size] + i, 7 + 2 * i))] }
      values = entries.map { |row| row.map { |e| Expression.lift(e).subs(point).simplify } }
      return nil unless values.flatten.all? { |v| v.is_a?(Num) && (v.value.is_a?(Integer) || v.value.is_a?(Rational)) }
      full = [rows, cols].min
      Elimination.rref(values).last.size == full ? full : nil
    rescue ZeroDivisionError
      nil
    end

    def self.float_rows(entries) = entries.map { |row| row.map { |e| Complex(Expression.lift(e).evalf) } }
    def self.float_scale(rows) = rows.flatten.map(&:abs).max || 0.0

    # Gauss-Jordan with partial pivoting on Complex Floats; [rows, pivots].
    def self.float_eliminate(rows, tolerance)
      rows = rows.map(&:dup)
      pivots = []
      r = 0
      (0...(rows.first&.size || 0)).each do |c|
        break if r >= rows.size
        best = (r...rows.size).max_by { |i| rows[i][c].abs }
        next if rows[best][c].abs <= tolerance
        rows[r], rows[best] = rows[best], rows[r]
        pivot = rows[r][c]
        rows[r] = rows[r].map { |v| v / pivot }
        rows.each_index do |i|
          next if i == r || rows[i][c].zero?
          factor = rows[i][c]
          rows[i] = rows[i].each_with_index.map { |v, j| v - factor * rows[r][j] }
        end
        pivots << c
        r += 1
      end
      [rows, pivots]
    end

    def diagonalizable? = eigenvectors.sum { |_, _, vs| vs.size } == rows

    # ---- misc -------------------------------------------------------------

    def numeric? = entries.flatten.all? { |e| Scalar.numeric?(e) }
    def zero? = entries.flatten.all? { |e| Scalar.zero?(e) }
    def identity? = square? && self == space.identity
    def symmetric? = square? && self == transpose

    def ==(other)
      other = space.unchecked(other) if other.is_a?(Array)
      other.is_a?(Matrix) && other.rows == rows && other.cols == cols &&
        entries.flatten.zip(other.entries.flatten).all? { |a, b| Scalar.zero?(Scalar.sub(a, b)) }
    end
    alias eql? ==
    def hash = [Matrix, entries.flatten.map(&:simplify)].hash

    def simplify = space.unchecked(map_entries(&:simplify))
    def subs(*args) = space.unchecked(map_entries { |e| e.subs(*args) })
    def call(**bindings) = space.unchecked(map_entries { |e| Scalar.lift(e.call(**bindings)) })

    def to_s
      return "[]" if rows.zero? || cols.zero?
      cells = entries.map { |r| r.map(&:to_s) }
      widths = (0...cols).map { |j| cells.map { |r| r[j].size }.max }
      cells.map { |r| "[" + r.each_with_index.map { |c, j| c.rjust(widths[j]) }.join(" ") + "]" }.join("\n")
    end
    alias inspect to_s

    private

    def map_entries(&block) = entries.map { |r| r.map(&block) }

    def zip_with(other, op)
      raise TypeError, "can't apply #{op} to Matrix and #{other.class}" unless other.is_a?(Matrix)
      raise ArgumentError, "shape mismatch: #{space} #{op} #{other.space}" unless rows == other.rows && cols == other.cols
      MatrixSpace.new(base.join(other.base), rows, cols).unchecked(
        entries.zip(other.entries).map { |ra, rb| ra.zip(rb).map { |a, b| yield a, b } }
      )
    end

    def result_base(scalar)
      d = Scalar.domain(scalar)
      d ? base.join(d) : base
    end
  end

  # Row reduction on plain arrays of Expressions. Symbolic entries that are
  # not identically zero are treated as non-zero pivots (the generic case).
  module Elimination
    module_function

    # => [reduced_rows, pivot_columns]
    def rref(rows)
      rows = rows.map(&:dup)
      m = rows.size
      n = rows.first&.size || 0
      pivots = []
      r = 0
      n.times do |c|
        break if r == m
        p = (r...m).find { |i| !Scalar.zero?(rows[i][c]) }
        next unless p
        rows[r], rows[p] = rows[p], rows[r]
        pivot = rows[r][c]
        rows[r] = rows[r].map { |v| Scalar.div(v, pivot) } unless Scalar.one?(pivot)
        m.times do |i|
          next if i == r
          f = rows[i][c]
          next if Scalar.zero?(f)
          rows[i] = rows[i].zip(rows[r]).map { |a, b| Scalar.sub(a, Scalar.mul(f, b)) }
        end
        pivots << c
        r += 1
      end
      # an entry that is zero but not written so reads as a pivot:
      # (x - 1)**2 - (x - 1)*(x**2 - 1)/(x + 1) is 0 (fourth review)
      rows = rows.map { |row| row.map { |v| !v.is_a?(Num) && v.is_a?(Expression) && Scalar.zero?(v) ? Num.new(0) : v } }
      [rows, pivots]
    end

    # Determinant by Gaussian elimination (exact for numeric entries).
    def det(rows)
      rows = rows.map(&:dup)
      n = rows.size
      result = Num.new(1)
      n.times do |c|
        p = (c...n).find { |i| !Scalar.zero?(rows[i][c]) }
        return Num.new(0) unless p
        if p != c
          rows[c], rows[p] = rows[p], rows[c]
          result = Scalar.neg(result)
        end
        pivot = rows[c][c]
        result = Scalar.mul(result, pivot)
        ((c + 1)...n).each do |i|
          f = Scalar.div(rows[i][c], pivot)
          next if Scalar.zero?(f)
          rows[i] = rows[i].zip(rows[c]).map { |a, b| Scalar.sub(a, Scalar.mul(f, b)) }
        end
      end
      result
    end

    # Laplace expansion along the first row; fine for small symbolic matrices.
    def cofactor_det(rows)
      n = rows.size
      return Num.new(1) if n.zero?
      return rows[0][0] if n == 1
      total = Num.new(0)
      rows[0].each_with_index do |a, j|
        next if Scalar.zero?(a)
        minor = rows.drop(1).map { |r| r.reject.with_index { |_, k| k == j } }
        term = Scalar.mul(a, cofactor_det(minor))
        total = j.even? ? Scalar.add(total, term) : Scalar.sub(total, term)
      end
      total
    end
  end
end
