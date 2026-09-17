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

    # (QQ**[2, 2])[[1, 2], [3, 4]]
    def [](*row_arrays)
      row_arrays = row_arrays.first if row_arrays.size == 1 && row_arrays.first.first.is_a?(Array)
      unless row_arrays.size == rows && row_arrays.all? { |r| r.size == cols }
        raise DomainError, "#{self} needs #{rows} rows of #{cols} entries"
      end
      entries = row_arrays.map { |r| r.map { |e| Scalar.lift(e) } }
      entries = entries.map { |r| r.map { |e| base.normalize_coefficient(e) } } if base.respond_to?(:normalize_coefficient)
      entries.flatten.each do |e|
        raise DomainError, "#{e} is not in #{base}" unless base.include?(e)
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

    def *(other)
      case other
      when Matrix
        raise ArgumentError, "shape mismatch: #{space} * #{other.space}" unless cols == other.rows
        product = Array.new(rows) do |i|
          Array.new(other.cols) do |j|
            (0...cols).map { |k| Scalar.mul(self[i, k], other[k, j]) }.reduce { |s, x| Scalar.add(s, x) } || Num.new(0)
          end
        end
        MatrixSpace.new(base.join(other.base), rows, other.cols).unchecked(product)
      when Vector
        raise ArgumentError, "shape mismatch: #{space} * #{other.space}" unless cols == other.dim
        VectorSpace.new(base.join(other.base), rows).unchecked(entries.map { |r| row_dot(r, other.entries) })
      else
        scale(other)
      end
    end

    def self.row_times(vector, matrix)
      raise ArgumentError, "shape mismatch: #{vector.space} * #{matrix.space}" unless vector.dim == matrix.rows
      VectorSpace.new(vector.base.join(matrix.base), matrix.cols).unchecked(
        (0...matrix.cols).map { |j| vector.entries.each_with_index.map { |v, i| Scalar.mul(v, matrix[i, j]) }.reduce { |s, x| Scalar.add(s, x) } }
      )
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

    def rank = Elimination.rref(entries).last.size

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
    def charpoly(var = :x)
      raise ArgumentError, "charpoly needs a square matrix" unless square?
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
        vectors = shifted.kernel.map { |v| v.space.unchecked(v.entries.map { |e| e.rationalize }) }
        [l, values.count { |v| v == l }, vectors]
      end
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

    def row_dot(a, b) = a.zip(b).map { |x, y| Scalar.mul(x, y) }.reduce { |s, x| Scalar.add(s, x) } || Num.new(0)

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
