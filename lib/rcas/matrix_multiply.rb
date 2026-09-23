# frozen_string_literal: true

module RCAS
  # The product of two matrices, three ways.
  #
  # * A matrix of Integers and Rationals is multiplied on the bare Ruby
  #   numbers: each row of the left factor and each column of the right one
  #   is scaled to Integers by the lcm of its denominators, the product is
  #   taken in Integers, and each entry is divided once at the end. The
  #   entries are wrapped in Num only then - through Scalar, every one of the
  #   n**3 products and sums built a node, and that was twenty times the
  #   arithmetic.
  # * The schoolbook product: n**3 multiplications.
  # * Strassen's: two 2x2 block matrices multiplied with seven products
  #   instead of eight [Str69], in Winograd's form with fifteen additions
  #   instead of eighteen [Win71], applied to the blocks recursively. That
  #   is n**log2(7) = n**2.807 multiplications. An odd dimension gets a row
  #   or a column of zeros for one level, and a block with a dimension at
  #   most `cutoff` is multiplied the schoolbook way.
  #
  # The exponent has come down much further since - below 2.3714 [ADVXXZ25],
  # by the laser method of Coppersmith and Winograd [CW90] - but those
  # algorithms win only for matrices far beyond any that exist ("galactic"),
  # and nothing below Strassen's exponent is used in practice.
  #
  # `MatrixMultiply.algorithm` (thread-local, like Factor.recombination) is
  # :auto, :strassen or :schoolbook. :auto takes the schoolbook product for
  # symbolic entries - Strassen trades a product for additions, and with
  # symbolic entries its products are of sums that must be expanded again,
  # which is dearer - and Strassen for Integer/Rational matrices whose
  # smallest dimension reaches AUTO_MIN (AUTO_MIN_LARGE for entries past a
  # machine word). :strassen runs it on any entries, which is there to be compared.
  module MatrixMultiply
    ALGORITHMS = %i[auto strassen schoolbook].freeze

    # Measured on random square Integer matrices (24 Sept 2026, Ruby 3.3).
    # With one-digit entries Strassen is level with the schoolbook product
    # at n = 128 and 12% faster at 256, best with leaves of 48; with entries
    # of thirty digits the products outweigh the additions, and it is 15%
    # faster from n = 64 and 34% at 256, best with leaves of 16. Past
    # LARGE_BITS a product is no longer one machine word.
    AUTO_MIN = 192
    CUTOFF = 48
    AUTO_MIN_LARGE = 64
    CUTOFF_LARGE = 16
    LARGE_BITS = 62

    module_function

    def algorithm = Thread.current[:rcas_matrix_multiplication] || :auto

    # MatrixMultiply.with_algorithm(:strassen) { a * b }; nil keeps the algorithm
    # in force, so a caller that passes its own default does not reset it.
    def with_algorithm(name)
      return yield if name.nil?
      raise ArgumentError, "multiplication algorithm must be one of #{ALGORITHMS.join(', ')}" unless ALGORITHMS.include?(name)
      saved = Thread.current[:rcas_matrix_multiplication]
      Thread.current[:rcas_matrix_multiplication] = name
      yield
    ensure
      Thread.current[:rcas_matrix_multiplication] = saved unless name.nil?
    end

    # Rows of entries (Expressions or Ruby numbers) of a*b, for a m x k and
    # b k x n (columns = n says it when k is 0); the entries come back as Integer, Rational or Expression.
    def product(a, b, algorithm = self.algorithm, columns: b.first&.size || 0)
      raise ArgumentError, "multiplication algorithm must be one of #{ALGORITHMS.join(', ')}" unless ALGORITHMS.include?(algorithm)
      return Array.new(a.size) { Array.new(columns, 0) } if a.empty? || b.empty? || columns.zero?
      x = rational_values(a)
      y = x && rational_values(b)
      return rational_product(x, y, algorithm) if y
      rows = a.map { |r| r.map { |e| Scalar.lift(e) } }
      cols = b.map { |r| r.map { |e| Scalar.lift(e) } }
      algorithm == :strassen ? strassen(rows, cols, SCALAR, 1) : SCALAR.leaf(rows, cols)
    end

    # The bare numbers of a matrix of Integers and Rationals, or nil.
    def rational_values(rows)
      rows.map do |r|
        r.map do |e|
          v = e.is_a?(Num) ? e.value : e
          return nil unless v.is_a?(Integer) || v.is_a?(Rational)
          v
        end
      end
    end

    # Rows scaled by their denominators on the left, columns on the right:
    # the Integer product divided by the two scales is the Rational one.
    def rational_product(a, b, algorithm)
      left = a.map { |r| r.map(&:denominator).reduce(1, :lcm) }
      right = b.transpose.map { |c| c.map(&:denominator).reduce(1, :lcm) }
      x = left.all?(1) ? a : a.each_with_index.map { |r, i| r.map { |v| (v * left[i]).to_i } }
      y = right.all?(1) ? b : b.map { |r| r.each_with_index.map { |v, j| (v * right[j]).to_i } }
      c = strassen?(x, y, algorithm) ? strassen(x, y, INTEGER, cutoff_for(x, y)) : INTEGER.leaf(x, y)
      return c if left.all?(1) && right.all?(1)
      c.each_with_index.map { |r, i| r.each_with_index.map { |v, j| Rational(v, left[i] * right[j]) } }
    end

    def strassen?(a, b, algorithm)
      return true if algorithm == :strassen
      algorithm == :auto && [a.size, b.size, b.first.size].min >= (large?(a, b) ? AUTO_MIN_LARGE : AUTO_MIN)
    end

    def cutoff_for(a, b) = large?(a, b) ? CUTOFF_LARGE : CUTOFF

    def large?(a, b) = [a, b].any? { |m| m.any? { |r| r.any? { |v| v.abs.bit_length > LARGE_BITS } } }

    # Winograd's form of Strassen's algorithm [Win71] on blocks of rows,
    # with `ops` doing the arithmetic of whole blocks.
    def strassen(a, b, ops, cutoff)
      m = a.size
      k = b.size
      n = b.first.size
      return ops.leaf(a, b) if [m, k, n].min <= cutoff || [m, k, n].min < 2
      if m.odd? || k.odd? || n.odd?
        c = strassen(pad(a, m.odd?, k.odd?, ops.zero), pad(b, k.odd?, n.odd?, ops.zero), ops, cutoff)
        return c.first(m).map { |r| r.first(n) }
      end
      a11, a12, a21, a22 = quarters(a)
      b11, b12, b21, b22 = quarters(b)
      s1 = ops.add(a21, a22)
      s2 = ops.sub(s1, a11)
      s3 = ops.sub(a11, a21)
      s4 = ops.sub(a12, s2)
      t1 = ops.sub(b12, b11)
      t2 = ops.sub(b22, t1)
      t3 = ops.sub(b22, b12)
      t4 = ops.sub(t2, b21)
      m1 = strassen(a11, b11, ops, cutoff)
      m2 = strassen(a12, b21, ops, cutoff)
      m3 = strassen(s4, b22, ops, cutoff)
      m4 = strassen(a22, t4, ops, cutoff)
      m5 = strassen(s1, t1, ops, cutoff)
      m6 = strassen(s2, t2, ops, cutoff)
      m7 = strassen(s3, t3, ops, cutoff)
      u2 = ops.add(m1, m6)
      u3 = ops.add(u2, m7)
      c11 = ops.add(m1, m2)
      c12 = ops.add(ops.add(u2, m5), m3)
      c21 = ops.sub(u3, m4)
      c22 = ops.add(u3, m5)
      c11.zip(c12).map { |l, r| l + r } + c21.zip(c22).map { |l, r| l + r }
    end

    def quarters(a)
      h = a.size / 2
      w = a.first.size / 2
      top = a.first(h)
      bottom = a.drop(h)
      [top.map { |r| r.first(w) }, top.map { |r| r.drop(w) }, bottom.map { |r| r.first(w) }, bottom.map { |r| r.drop(w) }]
    end

    def pad(a, row, col, zero)
      a = a.map { |r| r + [zero] } if col
      a += [Array.new(a.first.size, zero)] if row
      a
    end

    # Block arithmetic on bare Integers.
    module IntegerBlocks
      module_function

      def zero = 0
      def add(a, b) = a.each_with_index.map { |r, i| s = b[i]; r.each_with_index.map { |v, j| v + s[j] } }
      def sub(a, b) = a.each_with_index.map { |r, i| s = b[i]; r.each_with_index.map { |v, j| v - s[j] } }

      def leaf(a, b)
        columns = b.transpose
        a.map do |r|
          l = r.size
          columns.map do |c|
            s = 0
            k = 0
            while k < l
              s += r[k] * c[k]
              k += 1
            end
            s
          end
        end
      end
    end

    # Block arithmetic on Expressions, through Scalar.
    module ScalarBlocks
      module_function

      def zero = Num.new(0)
      def add(a, b) = a.zip(b).map { |r, s| r.zip(s).map { |x, y| Scalar.add(x, y) } }
      def sub(a, b) = a.zip(b).map { |r, s| r.zip(s).map { |x, y| Scalar.sub(x, y) } }

      def leaf(a, b)
        columns = b.transpose
        a.map { |r| columns.map { |c| r.zip(c).map { |x, y| Scalar.mul(x, y) }.reduce { |s, v| Scalar.add(s, v) } || Num.new(0) } }
      end
    end

    INTEGER = IntegerBlocks
    SCALAR = ScalarBlocks
  end
end
