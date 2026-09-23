# frozen_string_literal: true

module RCAS
  module Factor
    # How the p-adic factors are put back together: :van_hoeij (the lattice),
    # :zassenhaus (subsets of increasing size, the original method), or
    # :auto, which takes the lattice once there are VAN_HOEIJ_FROM local
    # factors or more. Below that the subsets are cheap - the trailing
    # coefficient test throws out nearly all of them - and measured faster
    # (24 Sept 2026, products of Swinnerton-Dyer polynomials: 0.12 s against
    # 0.22 s at 16 local factors, 0.21 s against 0.47 s at 20, but 1.7 s
    # against 0.9 s at 24 and more than a minute against 3 s at 32, where
    # the subsets run into their 2**(r - 1)). The old method stays so that
    # the two can be compared: factor(f, recombination: :zassenhaus).
    RECOMBINATIONS = %i[auto van_hoeij zassenhaus].freeze
    VAN_HOEIJ_FROM = 20

    def self.recombination = Thread.current[:rcas_recombination] || :auto

    # The recombination for the calls made inside the block; nil keeps the
    # one already in force, so an outer choice reaches the inner calls.
    def self.with_recombination(method)
      return yield if method.nil?
      method = method.to_sym
      raise ArgumentError, "factor: recombination must be one of #{RECOMBINATIONS.join(', ')}, got #{method}" unless RECOMBINATIONS.include?(method)
      saved = Thread.current[:rcas_recombination]
      Thread.current[:rcas_recombination] = method
      yield
    ensure
      Thread.current[:rcas_recombination] = saved
    end

    def self.van_hoeij?(local_factors)
      case recombination
      when :van_hoeij then local_factors > 1
      when :zassenhaus then false
      else local_factors >= VAN_HOEIJ_FROM
      end
    end

    # Van Hoeij's recombination of the p-adic factors by lattice reduction.
    #
    # Zassenhaus tries subsets of the r local factors, and an irreducible
    # polynomial with many of them - a Swinnerton-Dyer polynomial splits into
    # quadratics modulo every prime - makes that 2**(r - 1) trials. Van Hoeij
    # asks instead which 0/1 vectors v (v_i = 1 when f_i is in the factor)
    # belong to a true factor, and finds them all at once as short vectors
    # of a lattice: a knapsack problem LLL can solve [vHo02].
    #
    # What makes the lattice is a quantity that is additive over the local
    # factors and small for a true one. The coefficients of the logarithmic
    # derivative times f serve [HvHN11]: for a factor g of f in ZZ[x],
    # f*g'/g = (f/g)*g' has integer coefficients, bounded by B_j (the sum
    # over the roots of g of f/(x - root), each root below the Fujiwara
    # bound); and f*(g*h)'/(g*h) = f*g'/g + f*h'/h, so modulo p**k the
    # coefficient of a product of local factors is the sum of theirs. The
    # lattice spanned by
    #
    #   [ e_i | c_i,j / B_j ]    for each local factor f_i
    #   [ 0   | p**k / B_j  ]    for each coefficient j used
    #
    # contains (v, small) for every true factor, with squared length at most
    # M = r + (number of columns). After LLL, a lattice vector whose top
    # Gram-Schmidt length exceeds sqrt(M) cannot be one of those, so the
    # true vectors lie in the span of the first s reduced vectors, where s is
    # the last index with |b*_s|**2 <= M. Their first r coordinates are the
    # basis the next round starts from, with more coefficients. When the
    # reduced echelon form of that basis is a 0/1 matrix with one 1 in every
    # column, its rows are the candidate factors; each is checked by
    # division, so a wrong guess costs a round, never a wrong answer. When
    # the coefficients run out undecided, the precision is raised, and after
    # that the subsets take over.
    #
    # Sources (keys: MANUAL.md, Sources): the algorithm [vHo02]; the
    # coefficients of the logarithmic derivative and their bounds [HvHN11];
    # LLL [LLL82], as in lattice.rb; the root bound [Fuj16].
    module VanHoeij
      MAX_RAISES = 3 # precision doublings before giving up to the subsets
      COLUMNS_PER_ROUND = 2
      SAFETY_BITS = 10 # how far p**k has to stand above B_j * 2**(r/2) for column j

      module_function

      # The irreducible factors of f (primitive, squarefree, positive leading
      # coefficient), or nil when the lattice did not decide - the caller
      # then recombines by subsets.
      def recombine(f, modular, p, k)
        n = Dense.deg(f)
        r = modular.size
        bounds = cld_bounds(f)
        # enough precision for the first few columns, which have the
        # smallest bounds: the top coefficients
        wanted = bounds.last(3).max * 2**(r / 2 + SAFETY_BITS)
        k += 1 while p**k <= wanted
        MAX_RAISES.times do
          lifted = Zassenhaus.hensel_lift_leading(f, modular, p, k)
          found = attempt(f, lifted, p**k, bounds)
          return found if found
          k *= 2
        end
        nil
      end

      def attempt(f, lifted, m, bounds)
        r = lifted.size
        n = Dense.deg(f)
        cld = lifted.map { |fi| coefficients(f, fi, m, n) }
        # the columns whose bound stands well below p**k, smallest bound first
        usable = (0...n).select { |j| m > bounds[j] * 2**(r / 2 + SAFETY_BITS) }.sort_by { |j| [bounds[j], -j] }
        basis = Array.new(r) { |i| Array.new(r) { |l| i == l ? 1 : 0 } }
        until usable.empty?
          columns = usable.shift(COLUMNS_PER_ROUND)
          basis = cut(basis, cld, columns, m, bounds)
          return nil if basis.empty? # nothing short survived: the bounds were wrong
          subsets = partition(basis)
          next unless subsets
          factors = candidates(f, lifted, subsets, m)
          return factors if factors
        end
        nil
      end

      # f*fi'/fi modulo m, symmetric, as n coefficients.
      def coefficients(f, fi, m, n)
        q = Dense.divmod_mod(Dense.mod(f, m), fi, m).first
        c = Dense.sym_mod(Dense.mul_mod(q, Dense.derivative(fi), m), m)
        c + Array.new(n - c.size, 0)
      end

      # One round: the lattice of the current basis with the new columns,
      # reduced, and cut to the vectors a true factor can lie among.
      def cut(basis, cld, columns, m, bounds)
        r = cld.size
        rows = basis.map do |w|
          traces = columns.map do |j|
            t = w.each_index.sum { |i| w[i] * cld[i][j] } % m
            t -= m if t > m / 2
            Rational(t, bounds[j])
          end
          w.map(&:to_r) + traces
        end
        columns.each_with_index do |j, c|
          rows << Array.new(r, 0r) + Array.new(columns.size) { |d| d == c ? Rational(m, bounds[j]) : 0r }
        end
        reduced, = Lattice.reduce(rows, Lattice::DELTA)
        _, lengths = Lattice.gram_schmidt(reduced)
        bound = r + columns.size
        s = lengths.rindex { |b| b <= bound }
        return [] if s.nil?
        reduced.first(s + 1).map { |row| row.first(r).map { |e| e.to_i } }
      end

      # The rows of the reduced echelon form when it is a 0/1 matrix with
      # exactly one 1 in every column - a partition of the local factors -
      # as lists of indices; nil otherwise.
      def partition(basis)
        echelon = rref(basis.map { |row| row.map(&:to_r) }).reject { |row| row.all?(&:zero?) }
        return nil unless echelon.flatten.all? { |e| e.zero? || e == 1 }
        return nil unless echelon.transpose.all? { |column| column.count(1) == 1 }
        echelon.map { |row| row.each_index.select { |i| row[i] == 1 } }
      end

      def rref(rows)
        rows = rows.map(&:dup)
        lead = 0
        cols = rows.first&.size || 0
        rows.each_index do |i|
          lead += 1 while lead < cols && rows[i..].all? { |row| row[lead].zero? }
          break if lead >= cols
          j = (i...rows.size).find { |l| !rows[l][lead].zero? }
          rows[i], rows[j] = rows[j], rows[i]
          pivot = rows[i][lead]
          rows[i] = rows[i].map { |e| e / pivot }
          rows.each_index do |l|
            next if l == i || rows[l][lead].zero?
            factor = rows[l][lead]
            rows[l] = rows[l].zip(rows[i]).map { |a, b| a - factor * b }
          end
          lead += 1
        end
        rows
      end

      # lc(f) times the product of each subset of local factors, made
      # primitive; the list when every one divides f and they multiply to
      # its degree, nil otherwise.
      def candidates(f, lifted, subsets, m)
        lc = f.last
        rest = f
        factors = subsets.map do |indices|
          product = indices.reduce([lc]) { |acc, i| Dense.mul_mod(acc, lifted[i], m) }
          g = Dense.primitive(Dense.sym_mod(product, m))
          g = Dense.scale(g, -1) if g.last.negative?
          quotient = Dense.div_exact(rest, g)
          return nil if quotient.nil?
          rest = quotient
          g
        end
        return nil unless Dense.deg(rest).zero?
        factors.sort_by { |g| [Dense.deg(g), g] }
      end

      # B_j: the coefficient of x**j in f*g'/g for any factor g of f is at
      # most n * sum_{i > j} |f_i| * R**(i - j - 1), with R a bound on the
      # absolute values of the roots of f.
      def cld_bounds(f)
        n = Dense.deg(f)
        radius = root_bound(f)
        (0...n).map do |j|
          n * (j + 1..n).sum { |i| f[i].abs * radius**(i - j - 1) } + 1
        end
      end

      # Fujiwara's bound: every root lies within 2*max |a_(n-i)/a_n|**(1/i)
      # [Fuj16], rounded up to an integer.
      def root_bound(f)
        n = Dense.deg(f)
        lead = f.last.abs
        terms = (1..n).map do |i|
          a = f[n - i].abs
          a = Rational(a, 2) if i == n # the constant term enters halved
          next 0 if a.zero?
          ratio = Rational(a, lead)
          root = Simplify.integer_root(ratio.ceil, i)
          root += 1 while root**i < ratio
          root
        end
        2 * terms.max
      end
    end
  end
end
