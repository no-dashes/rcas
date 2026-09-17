# frozen_string_literal: true

module RCAS
  class << self
    # The source of randomness every `random` uses when it is not handed one.
    # RCAS.random = 42 (or a Random) makes a session reproducible.
    def random = @random ||= Random.new

    def random=(source)
      @random = source.is_a?(Integer) ? Random.new(source) : source
    end
  end

  # Random elements of the structures rcas already has: ZZ[x].random(3),
  # (QQ**[2, 2]).random, (ZZ**3).random, ZZ.random(1..100), GF(9).random.
  # Every one of them takes `random:` (a Ruby Random) and otherwise uses
  # RCAS.random, so a session is reproducible by setting that once.
  #
  # The keywords say what the object should be, not how to build it:
  #
  #   ZZ[x].random(4, irreducible: true)
  #   ZZ[x].random(3, roots: true)              # one that really factors
  #   QQ[x, y].random(2, terms: 3)
  #   (ZZ**[3, 3]).random(unimodular: true)     # det +-1, so the inverse is integral
  #   (ZZ**[3, 3]).random(eigenvalues: [1, 2, 2])
  #   (QQ**[3, 3]).random(definite: true)       # a Cholesky factorization exists
  #
  # Where a property cannot be built directly it is sampled for and rejected
  # (an irreducible polynomial, a matrix of full rank); after TRIES attempts
  # the request is refused rather than looped on, because "no such object"
  # and "unlucky" look the same from in here.
  #
  # Sources (keys: MANUAL.md, Sources): rejection sampling for irreducibles is
  # the textbook use of their density 1/n [vzGG13, §14.9]; a unimodular matrix
  # is a product of elementary ones and a positive definite one is L*L^T
  # [Str16, ch. 2, 6].
  module Randoms
    module_function

    COEFFICIENTS = (-9..9).freeze     # small enough to do by hand
    NATURALS = (0..9).freeze
    DENOMINATORS = (1..9).freeze
    UNIT = (0.0..1.0).freeze
    TRIES = 500

    def source(given) = given || RCAS.random

    def refuse(what, wanted)
      raise ArgumentError, "random #{what}: no #{wanted} came up in #{TRIES} tries; loosen the request"
    end

    # ---- numbers ---------------------------------------------------------------

    # A number of the set, as Ruby writes it where that is the useful thing
    # (an Integer for NN and ZZ, a Float for RR) and as rcas writes it where
    # that reads better: a Num for QQ, and for CC a Gaussian integer, whose
    # parts become rational when denominators: says so. `prime: true` draws
    # a prime from the range.
    def number(domain, range = nil, prime: false, denominators: nil, random: nil)
      rng = source(random)
      return prime_number(domain, range, rng) if prime
      # NumberSet#=== is membership, so these are compared with ==, never `case`.
      if domain == NN then rng.rand(integer_range(range || NATURALS))
      elsif domain == ZZ then rng.rand(integer_range(range || COEFFICIENTS))
      elsif domain == QQ then rational(range, denominators, rng)
      elsif domain == RR then float(range, rng)
      elsif domain == CC
        Complex(*Array.new(2) { denominators ? rational(range, denominators, rng) : rng.rand(integer_range(range || COEFFICIENTS)) })
      else raise ArgumentError, "random: #{domain} has no random elements"
      end
    end

    def integer_range(range)
      first = range.first
      last = range.last
      raise ArgumentError, "random: #{range} is not a range of integers" unless first.is_a?(Integer) && last.is_a?(Integer)
      range.exclude_end? ? (first...last) : (first..last)
    end

    def rational(range, denominators, rng)
      numerator = rng.rand(integer_range(range || COEFFICIENTS))
      denominator = rng.rand(integer_range(denominators || DENOMINATORS))
      value = Rational(numerator, denominator.zero? ? 1 : denominator)
      value.denominator == 1 ? value.numerator : value
    end

    def float(range, rng)
      range ||= UNIT
      rng.rand(range.first.to_f..range.last.to_f)
    end

    def prime_number(domain, range, rng)
      range = integer_range(range || (2..99))
      TRIES.times do
        candidate = rng.rand(range)
        return candidate if candidate >= 2 && NumberTheory.prime?(candidate) && domain.include?(candidate)
      end
      refuse("number", "prime in #{range}")
    end

    # A non-zero element of the coefficient domain of a ring or space.
    def coefficient(domain, range, denominators, rng, zero: true)
      TRIES.times do
        value = case domain
                when FiniteField then domain.random_value(rng)
                when AlgebraicField then algebraic(domain, range, denominators, rng)
                when NumberSet then number(domain, range, denominators: denominators, random: rng)
                else number(QQ, range, denominators: denominators, random: rng)
                end
        return value if zero || !Scalar.zero?(Scalar.lift(value))
      end
      refuse("coefficient", "non-zero value")
    end

    def algebraic(field, range, denominators, rng)
      coeffs = Array.new(field.degree) { number(QQ, range, denominators: denominators, random: rng) }
      terms = coeffs.each_with_index.to_h { |c, i| [[i], Num.new(c)] }.reject { |_, c| Scalar.zero?(c) }
      field.element(Polynomial.new(field.ring, terms))
    end

    # ---- polynomials -----------------------------------------------------------

    # A polynomial of the ring. `degree` is the total degree (an Integer or a
    # Range to choose from), `terms` how many monomials it should have,
    # `coefficients` the range they are drawn from.
    #
    #   monic:       leading coefficient 1
    #   primitive:   content 1 (over ZZ)
    #   squarefree:  no repeated factor
    #   irreducible: no factor at all, over the coefficient domain
    #   roots:       true, a count, or a list - a product of linear factors,
    #                so that it factors over ZZ
    #   factors:     a product of that many random irreducible factors
    #   homogeneous: every monomial of the same total degree
    def polynomial(ring, degree = nil, terms: nil, coefficients: nil, denominators: nil,
                   monic: false, primitive: false, squarefree: false, irreducible: false,
                   roots: nil, factors: nil, homogeneous: false, random: nil)
      rng = source(random)
      degree = pick(degree || (ring.univariate? ? 3 : 2), rng)
      return from_roots(ring, degree, roots, coefficients, monic, rng) if roots
      return from_factors(ring, degree, factors, coefficients, monic, rng) if factors
      wanted = [("squarefree" if squarefree), ("irreducible" if irreducible)].compact.join(" and ")
      TRIES.times do
        f = raw_polynomial(ring, degree, terms, coefficients, denominators, homogeneous, rng)
        f = monic_form(f) if monic
        f = f.primitive_part if primitive && !monic
        next if f.degree != degree
        next if squarefree && !squarefree?(f)
        next if irreducible && !(f.degree.positive? && f.irreducible?)
        return f
      end
      refuse("polynomial", wanted.empty? ? "polynomial of degree #{degree}" : "#{wanted} polynomial of degree #{degree}")
    end

    # The monomials of total degree at most d, the ones of degree exactly d
    # first so that the leading term is always there.
    def monomials(ring, degree, homogeneous)
      vars = ring.vars.size
      all = exponent_vectors(vars, degree)
      top, rest = all.partition { |e| e.sum == degree }
      homogeneous ? top : top + rest
    end

    def exponent_vectors(vars, degree)
      return (0..degree).map { |d| [d] } if vars == 1
      (0..degree).flat_map do |d|
        exponent_vectors(vars - 1, degree - d).map { |rest| [d] + rest }
      end
    end

    def raw_polynomial(ring, degree, terms, coefficients, denominators, homogeneous, rng)
      available = monomials(ring, degree, homogeneous)
      leading = available.first(available.count { |e| e.sum == degree })
      count = terms ? pick(terms, rng) : available.size
      count = count.clamp(1, available.size)
      chosen = [leading.sample(random: rng)]
      chosen += (available - chosen).sample(count - 1, random: rng)
      table = chosen.to_h do |exponents|
        [exponents, Num.new(coefficient(ring.base, coefficients, denominators, rng, zero: false))]
      end
      Polynomial.new(ring, table)
    end

    # The leading coefficient set to 1 rather than divided out, so that a
    # monic polynomial over ZZ still has integer coefficients.
    def monic_form(f)
      return f if f.zero?
      Polynomial.new(f.ring, f.terms.merge(f.leading_exponents => Num.new(1)))
    end

    def squarefree?(f)
      f.squarefree_decomposition.all? { |_, multiplicity| multiplicity == 1 }
    rescue DomainError, NotImplementedError
      false
    end

    # A product of linear factors, which is a polynomial that really factors.
    def from_roots(ring, degree, roots, coefficients, monic, rng)
      raise ArgumentError, "random: roots: needs one variable" unless ring.univariate?
      values = case roots
               when Array then roots
               when Integer then Array.new(roots) { number(ZZ, coefficients, random: rng) }
               else Array.new(degree) { number(ZZ, coefficients, random: rng) }
               end
      x = ring.gen
      product = values.reduce(ring.one) { |acc, r| acc * (x - Polynomial.constant(ring, r)) }
      monic ? product : product * Polynomial.constant(ring, coefficient(ring.base, (-3..3), nil, rng, zero: false))
    end

    # A product of `count` irreducible factors whose degrees add up to `degree`.
    def from_factors(ring, degree, count, coefficients, monic, rng)
      raise ArgumentError, "random: factors: needs one variable" unless ring.univariate?
      raise ArgumentError, "random: #{count} factors need a degree of at least #{count}" if degree < count
      degrees = split_degree(degree, count, rng)
      product = degrees.reduce(ring.one) do |acc, d|
        acc * polynomial(ring, d, coefficients: coefficients, monic: true, irreducible: true, random: rng)
      end
      monic ? product : product * Polynomial.constant(ring, coefficient(ring.base, (-3..3), nil, rng, zero: false))
    end

    def split_degree(degree, count, rng)
      degrees = Array.new(count, 1)
      (degree - count).times { degrees[rng.rand(count)] += 1 }
      degrees
    end

    # An Integer, or one drawn from a Range.
    def pick(value, rng) = value.is_a?(Range) ? rng.rand(integer_range(value)) : value

    # ---- vectors and matrices --------------------------------------------------

    # A vector of the space; `nonzero: true` refuses the zero vector.
    def vector(space, entries: nil, denominators: nil, nonzero: false, random: nil)
      rng = source(random)
      TRIES.times do
        v = space.unchecked(Array.new(space.dim) { coefficient(space.base, entries, denominators, rng) })
        return v unless nonzero && v.zero?
      end
      refuse("vector", "non-zero vector")
    end

    # A matrix of the space. The shape keywords build what they name;
    # invertible, singular, rank and the rest are sampled for and checked.
    #
    #   entries:       the range the entries are drawn from
    #   density:       the proportion of them that is not zero
    #   symmetric:, antisymmetric:, diagonal:, triangular: :upper | :lower
    #   invertible:, singular:, rank:, det:
    #   unimodular:    determinant +-1, so that the inverse stays integral
    #   eigenvalues:   a list - P*D*P**-1 for a unimodular P
    #   definite:      symmetric positive definite, L*L.transpose
    def matrix(space, entries: nil, denominators: nil, density: nil, symmetric: false,
               antisymmetric: false, diagonal: false, triangular: nil, invertible: false,
               singular: false, unimodular: false, det: nil, rank: nil, eigenvalues: nil,
               definite: false, random: nil)
      rng = source(random)
      return unimodular_matrix(space, entries, rng) if unimodular
      return with_determinant(space, det, entries, rng) unless det.nil?
      return with_eigenvalues(space, eigenvalues, entries, rng) if eigenvalues
      return definite_matrix(space, entries, rng) if definite
      return with_rank(space, rank, entries, denominators, rng) unless rank.nil?
      return with_rank(space, [space.rows, space.cols].min - 1, entries, denominators, rng) if singular
      shape = { symmetric: symmetric, antisymmetric: antisymmetric, diagonal: diagonal, triangular: triangular, density: density }
      TRIES.times do
        m = shaped_matrix(space, entries, denominators, shape, rng)
        next if invertible && !(space.square? && !Scalar.zero?(m.det))
        return m
      end
      refuse("matrix", "invertible matrix")
    end

    def shaped_matrix(space, entries, denominators, shape, rng)
      rng_entry = lambda do |i, j|
        return 0 if shape[:diagonal] && i != j
        return 0 if shape[:triangular] == :upper && i > j
        return 0 if shape[:triangular] == :lower && i < j
        return 0 if shape[:antisymmetric] && i == j
        return 0 if shape[:density] && rng.rand > shape[:density]
        coefficient(space.base, entries, denominators, rng)
      end
      rows = Array.new(space.rows) { |i| Array.new(space.cols) { |j| rng_entry.call(i, j) } }
      if shape[:symmetric] || shape[:antisymmetric]
        raise ArgumentError, "random matrix: #{shape[:symmetric] ? 'symmetric' : 'antisymmetric'} needs a square shape" unless space.square?
        sign = shape[:symmetric] ? 1 : -1
        (0...space.rows).each do |i|
          (0...i).each { |j| rows[i][j] = Scalar.mul(Scalar.lift(rows[j][i]), sign) }
        end
      end
      space.unchecked(rows)
    end

    # The identity with 2n row operations done to it and its rows shuffled:
    # the determinant is +-1, so every entry of the inverse is in the ring
    # again. The multipliers are +-1 by default, because the entries grow
    # with them and a matrix to work with by hand is the point.
    def unimodular_matrix(space, entries, rng)
      square!(space, "unimodular")
      n = space.rows
      return space.identity if n < 2
      m = space.identity
      bound = (entries || (-1..1))
      (2 * n).times do
        i, j = (0...n).to_a.sample(2, random: rng)
        factor = coefficient(space.base, bound, nil, rng, zero: false)
        rows = m.to_a
        rows[i] = rows[i].each_with_index.map { |e, k| Scalar.add(e, Scalar.mul(Scalar.lift(rows[j][k]), Scalar.lift(factor))) }
        m = space.unchecked(rows)
      end
      space.unchecked(m.to_a.shuffle(random: rng))
    end

    # Upper triangular with the determinant on the diagonal, then mixed by
    # unimodular matrices on both sides, which leaves the determinant alone.
    def with_determinant(space, det, entries, rng)
      square!(space, "det:")
      n = space.rows
      rows = Array.new(n) { |i| Array.new(n) { |j| i == j ? (i.zero? ? det : 1) : (i < j ? coefficient(space.base, entries || (-3..3), nil, rng) : 0) } }
      triangular = space.unchecked(rows)
      m = (unimodular_matrix(space, entries, rng) * triangular * unimodular_matrix(space, entries, rng)).simplify
      # each unimodular factor has determinant +-1: a row changes sign when
      # the two of them came out to -1 between them.
      return m if Scalar.zero?(Scalar.sub(m.det, Scalar.lift(det)))
      space.unchecked(m.to_a.each_with_index.map { |row, i| i.zero? ? row.map { |e| Scalar.neg(e) } : row })
    end

    # P*D*P**-1 with P unimodular, so the entries stay in the ring and the
    # eigenvalues are the ones asked for.
    def with_eigenvalues(space, eigenvalues, entries, rng)
      square!(space, "eigenvalues:")
      unless eigenvalues.size == space.rows
        raise ArgumentError, "random matrix: #{eigenvalues.size} eigenvalues for a #{space.rows} by #{space.cols} matrix"
      end
      d = space.unchecked(Array.new(space.rows) { |i| Array.new(space.cols) { |j| i == j ? eigenvalues[i] : 0 } })
      TRIES.times do
        p = unimodular_matrix(space, entries, rng)
        m = (p * d * p.inverse).simplify
        # a triangular answer would show its eigenvalues on the diagonal,
        # which is no exercise at all
        return m unless triangular?(m)
      end
      refuse("matrix", "matrix that is not triangular")
    end

    def triangular?(m)
      [:upper, :lower].any? do |side|
        (0...m.rows).all? do |i|
          (0...m.cols).all? { |j| (side == :upper ? i <= j : i >= j) || Scalar.zero?(m[i, j]) }
        end
      end
    end

    # L*L.transpose for a lower triangular L with a positive diagonal:
    # symmetric, and positive definite because L is invertible.
    def definite_matrix(space, entries, rng)
      square!(space, "definite:")
      n = space.rows
      bound = entries || (-3..3)
      rows = Array.new(n) do |i|
        Array.new(n) do |j|
          if i == j then rng.rand(1..3)
          elsif i > j then coefficient(space.base, bound, nil, rng)
          else 0
          end
        end
      end
      l = space.unchecked(rows)
      (l * l.transpose).simplify
    end

    # A product of a rows-by-r and an r-by-cols matrix has rank at most r,
    # and generically exactly r.
    def with_rank(space, rank, entries, denominators, rng)
      limit = [space.rows, space.cols].min
      raise ArgumentError, "random matrix: a rank between 0 and #{limit} is needed, not #{rank}" unless (0..limit).cover?(rank)
      return space.zero if rank.zero?
      left = MatrixSpace.new(space.base, space.rows, rank)
      right = MatrixSpace.new(space.base, rank, space.cols)
      TRIES.times do
        m = (matrix(left, entries: entries, denominators: denominators, random: rng) *
             matrix(right, entries: entries, denominators: denominators, random: rng)).simplify
        return space.unchecked(m.to_a) if m.rank == rank
      end
      refuse("matrix", "matrix of rank #{rank}")
    end

    def square!(space, what)
      raise ArgumentError, "random matrix: #{what} needs a square shape, not #{space}" unless space.square?
    end
  end

  # The structures answer `random` themselves, beside zero, one, gen and
  # identity: the domain already says what its elements look like.
  class NumberSet
    # ZZ.random(1..100), QQ.random, ZZ.random(2..99, prime: true)
    def random(range = nil, **opts)
      value = Randoms.number(self, range, **opts)
      value.is_a?(Integer) || value.is_a?(Float) ? value : Num.new(value).simplify
    end
  end

  class PolynomialRing
    # ZZ[x].random(3), ZZ[x].random(4, irreducible: true), QQ[x, y].random(2, terms: 3)
    def random(degree = nil, **opts) = Randoms.polynomial(self, degree, **opts)
  end

  class FractionField
    # Frac(QQ[x]).random(2): a quotient of two random polynomials, cancelled
    def random(degree = nil, **opts)
      numerator = ring.random(degree, **opts)
      denominator = ring.random(degree, **opts)
      denominator = ring.one if denominator.zero?
      (numerator.to_expr / denominator.to_expr).cancel
    end
  end

  class VectorSpace
    # (ZZ**3).random, (QQ**3).random(nonzero: true)
    def random(**opts) = Randoms.vector(self, **opts)
  end

  class MatrixSpace
    # (ZZ**[3, 3]).random, (ZZ**[3, 3]).random(unimodular: true)
    def random(**opts) = Randoms.matrix(self, **opts)
  end

  class FiniteField
    # GF(9).random
    def random(random: nil) = random_value(Randoms.source(random))
  end

  class AlgebraicField
    # QQ(sqrt(2)).random: a + b*sqrt(2) with random rational a and b
    def random(coefficients: nil, denominators: nil, random: nil)
      Randoms.algebraic(self, coefficients, denominators, Randoms.source(random))
    end
  end
end
