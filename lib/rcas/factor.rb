# frozen_string_literal: true


module RCAS
  # Exact polynomial factorization over ZZ and QQ.
  #
  # Univariate: numeric content, squarefree decomposition (Yun), then for
  # every squarefree part Zassenhaus' algorithm - factor modulo a small
  # prime with Cantor-Zassenhaus, Hensel-lift to a modulus beyond the
  # Mignotte bound, recombine subsets of the modular factors.
  #
  # Multivariate: pull out the content in the main variable (factored
  # recursively), squarefree-decompose, then reduce each part to one
  # variable by Kronecker substitution, factor that, and recombine subsets
  # of the univariate factors that map back to true divisors.
  #
  # Sources (keys: MANUAL.md, Sources): Yun [Yun76], [vzGG13, §14.6];
  # Zassenhaus [Zas69], [GCL92, ch. 8], [vzGG13, ch. 15]; Cantor-Zassenhaus
  # [CZ81]; Hensel lifting [GCL92, ch. 6]; Mignotte bound [Mig74]; Kronecker
  # substitution [Knu98, §4.6.2], [vzGG13, §8.4]; x**n -+ 1 by cyclotomic
  # polynomials [Lan02, VI §3].
  module Factor
    module_function

    # => Factorization
    def factor(poly)
      ring = poly.ring
      unless ring.base == ZZ || ring.base == QQ
        raise NotImplementedError, "factorization is implemented over ZZ and QQ, not #{ring.base}"
      end
      poly.terms.each_value do |c|
        next if c.is_a?(Num) && (c.value.is_a?(Integer) || c.value.is_a?(Rational))
        raise DomainError, "factorization needs numeric coefficients, got #{poly}"
      end
      return Factorization.new(ring, Num.new(0), []) if poly.zero?

      zz = ring.base == ZZ ? ring : ZZ[*ring.vars]
      scaled = poly.clear_denominators
      unit = Rational(poly.leading_coefficient.value, scaled.leading_coefficient.value)
      f = scaled.to_ring(zz)

      content = f.content
      content = -content if Scalar.negative?(f.leading_coefficient)
      f = f.primitive_part
      unit *= content

      factors = factor_primitive(f).map { |g, m| [g.to_ring(ring), m] }
      Factorization.new(ring, Num.new(Simplify.normalize_number(unit)), factors)
    end

    # x**n - 1 is the product of the cyclotomic polynomials Phi_d for the
    # divisors d of n, and x**n + 1 of those for the d dividing 2n but not
    # n - each irreducible over QQ [Lan02, VI §3]. Zassenhaus took nine
    # seconds over x**210 - 1, which is 48 factors read off a list (third
    # review, section 5). nil for anything else.
    def cyclotomic_split(f)
      ring = f.ring
      return nil unless ring.vars.size == 1 && f.terms.size == 2
      exponents = f.terms.keys.map(&:first).sort
      return nil unless exponents.first.zero? && exponents.last >= 2
      n = exponents.last
      lead = f.terms[[n]]
      tail = f.terms[[0]]
      return nil unless lead.is_a?(Num) && lead.value == 1 && tail.is_a?(Num) && [1, -1].include?(tail.value)
      divisors = tail.value == -1 ? (1..n).select { |d| (n % d).zero? } : (1..2 * n).select { |d| ((2 * n) % d).zero? && (n % d).nonzero? }
      divisors.map do |d|
        coefficients = Poly.send(:cyclotomic_coeffs, d) # Integers, lowest degree first
        [Polynomial.new(ring, coefficients.each_with_index.reject { |c, _| c.zero? }.to_h { |c, i| [[i], Num.new(c)] }), 1]
      end
    end

    # ---- multivariate driver (f primitive over ZZ, positive lc) -----------

    def factor_primitive(f)
      ring = f.ring
      return [] if f.constant?
      binomial = cyclotomic_split(f)
      return binomial if binomial

      out = []
      # monomial factors
      ring.vars.each do |v|
        k = f.terms.keys.map { |e| e[ring.index(v)] }.min
        next unless k.positive?
        out << [ring.call(Var.new(v)), k]
        f = f.exact_div(ring.call(Var.new(v)**k))
      end
      return out if f.constant?

      if ring.univariate?
        out.concat(factor_univariate(f))
      else
        x = ring.vars.find { |v| f.degree(v).positive? }
        content = PolyGCD.content_in(f, x)
        out.concat(factor_primitive(content.primitive_part))
        f = f.exact_div(content)
        squarefree(f, x).each do |part, mult|
          kronecker_factors(part, x).each { |g| out << [g, mult] }
        end
      end
      out.sort_by { |g, m| [g.degree, g.to_s, m] }
    end

    # Yun's squarefree decomposition with respect to x. f primitive in x.
    def squarefree(f, x)
      out = []
      fp = f.derivative(x)
      g = PolyGCD.gcd_zz(f, fp)
      c = f.exact_div(g)
      d = fp.exact_div(g) - c.derivative(x)
      i = 1
      while c.degree(x).positive?
        p = PolyGCD.gcd_zz(c, d)
        c = c.exact_div(p)
        d = d.exact_div(p) - c.derivative(x)
        out << [p.primitive_part, i] if p.degree(x).positive?
        i += 1
      end
      out
    end

    def factor_univariate(f)
      Dense.squarefree(Dense.from_poly(f)).flat_map do |part, mult|
        Zassenhaus.factor(part).map { |g| [Dense.to_poly(g, f.ring), mult] }
      end
    end

    # All irreducible factors of a dense integer polynomial, repeated by
    # multiplicity, ignoring content and sign. Includes x for monomial factors.
    def univariate_irreducibles(dense)
      f = Dense.primitive(dense)
      k = f.index { |c| !c.zero? }
      out = Array.new(k, [0, 1])
      f = f.drop(k)
      Dense.squarefree(f).each { |part, mult| out.concat(Zassenhaus.factor(part) * mult) }
      out
    end

    # Factor a squarefree multivariate polynomial through Kronecker substitution.
    def kronecker_factors(h, _x)
      ring = h.ring
      n = ring.vars.size
      d = ring.vars.map { |v| h.degree(v) }.max + 1
      weights = (0...n).map { |i| d**i }

      image = []
      h.terms.each do |e, c|
        idx = e.zip(weights).sum { |k, w| k * w }
        image[idx] = (image[idx] || 0) + c.value
      end
      image = Dense.trim(image.map { |c| c || 0 })

      remaining = univariate_irreducibles(image)
      current = h
      out = []
      size = 1
      while size <= remaining.size && current.degree.positive?
        found = false
        remaining.each_index.to_a.combination(size).each do |indices|
          prod = indices.reduce([1]) { |acc, i| Dense.mul(acc, remaining[i]) }
          cand = kronecker_inverse(prod, ring, d)
          next if cand.nil?
          begin
            q = current.exact_div(cand)
          rescue DomainError
            next
          end
          out << cand.primitive_part
          current = q
          remaining = remaining.reject.with_index { |_, i| indices.include?(i) }
          found = true
          break
        end
        size += 1 unless found
      end
      out << current.primitive_part if current.degree.positive?
      out
    end

    def kronecker_inverse(dense, ring, d)
      n = ring.vars.size
      terms = {}
      dense.each_with_index do |c, idx|
        next if c.zero?
        return nil if idx >= d**n
        e = Array.new(n) { |i| (idx / d**i) % d }
        terms[e] = Num.new(c)
      end
      Polynomial.new(ring, terms)
    end

    # ---- dense integer polynomials: index = degree ------------------------

    module Dense
      module_function

      def trim(a)
        a = a.dup
        a.pop while !a.empty? && a.last.zero?
        a
      end

      def deg(a) = a.size - 1

      def from_poly(p)
        raise ArgumentError, "univariate polynomial expected" unless p.ring.univariate?
        trim(Array.new(p.degree + 1) { |k| p.coeff(k).value })
      end

      def to_poly(a, ring)
        Polynomial.new(ring, a.each_with_index.to_h { |c, k| [[k], Num.new(c)] })
      end

      def add(a, b) = trim(Array.new([a.size, b.size].max) { |i| (a[i] || 0) + (b[i] || 0) })
      def sub(a, b) = trim(Array.new([a.size, b.size].max) { |i| (a[i] || 0) - (b[i] || 0) })
      def scale(a, c) = c.zero? ? [] : a.map { |x| x * c }

      def mul(a, b)
        return [] if a.empty? || b.empty?
        out = Array.new(a.size + b.size - 1, 0)
        a.each_with_index { |x, i| next if x.zero?; b.each_with_index { |y, j| out[i + j] += x * y } }
        trim(out)
      end

      def derivative(a) = trim(a.each_with_index.map { |c, i| c * i }.drop(1))

      # Exact division over ZZ; nil when b does not divide a.
      def div_exact(a, b)
        return [] if a.empty?
        return nil if b.empty? || deg(a) < deg(b)
        r = a.dup
        q = Array.new(deg(a) - deg(b) + 1, 0)
        lb = b.last
        (deg(a) - deg(b)).downto(0) do |k|
          c = r[k + deg(b)]
          return nil unless (c % lb).zero?
          c /= lb
          q[k] = c
          b.each_with_index { |y, j| r[k + j] -= c * y }
        end
        trim(r).empty? ? trim(q) : nil
      end

      def content(a) = a.reduce(0) { |g, c| g.gcd(c) }

      # Yun's algorithm: [[squarefree part, multiplicity], ...] for a
      # primitive polynomial with positive leading coefficient.
      def squarefree(f)
        out = []
        fp = derivative(f)
        g = gcd(f, fp)
        c = div_exact(f, g)
        d = sub(div_exact(fp, g), derivative(c))
        i = 1
        while deg(c) >= 1
          p = gcd(c, d)
          c = div_exact(c, p)
          d = sub(div_exact(d, p), derivative(c))
          out << [p, i] if deg(p) >= 1
          i += 1
        end
        out
      end

      def primitive(a)
        return [] if a.empty?
        c = content(a)
        c = -c if a.last.negative?
        a.map { |x| x / c }
      end

      def prem(a, b)
        r = a
        lb = b.last
        while !r.empty? && deg(r) >= deg(b)
          shift = deg(r) - deg(b)
          r = sub(scale(r, lb), scale(Array.new(shift, 0) + b, r.last))
        end
        r
      end

      def gcd(a, b)
        return primitive(b) if a.empty?
        return primitive(a) if b.empty?
        c = content(a).gcd(content(b))
        a = primitive(a)
        b = primitive(b)
        until b.empty?
          a, b = b, primitive(prem(a, b))
        end
        scale(primitive(a), c)
      end

      # ---- modulo a prime -------------------------------------------------

      def mod(a, p) = trim(a.map { |c| c % p })

      def sym_mod(a, m)
        trim(a.map { |c| c %= m; c > m / 2 ? c - m : c })
      end

      def mul_mod(a, b, p) = mod(mul(a, b), p)

      # Divide by the leading coefficient (or +lc+) modulo m; m need not be prime.
      def monic_mod(a, m, lc = a.last)
        return a if a.empty?
        mod(scale(a, inv_mod(lc, m)), m)
      end

      def inv_mod(a, m)
        g, x = a % m, 1
        r, y = m, 0
        until r.zero?
          q = g / r
          g, r = r, g - q * r
          x, y = y, x - q * y
        end
        raise ZeroDivisionError, "#{a} is not invertible mod #{m}" unless g == 1
        x % m
      end

      def divmod_mod(a, b, p)
        raise ZeroDivisionError if b.empty?
        r = mod(a, p)
        q = Array.new([deg(a) - deg(b) + 1, 0].max, 0)
        inv = b.last.pow(p - 2, p)
        while !r.empty? && deg(r) >= deg(b)
          shift = deg(r) - deg(b)
          c = (r.last * inv) % p
          q[shift] = c
          r = mod(sub(r, scale(Array.new(shift, 0) + b, c)), p)
        end
        [trim(q), r]
      end

      def rem_mod(a, b, p) = divmod_mod(a, b, p).last

      def gcd_mod(a, b, p)
        a = mod(a, p)
        b = mod(b, p)
        a, b = b, rem_mod(a, b, p) until b.empty?
        monic_mod(a, p)
      end

      # a**e mod (f, p)
      def powmod(a, e, f, p)
        result = [1]
        base = rem_mod(a, f, p)
        while e.positive?
          result = rem_mod(mul(result, base), f, p) if e.odd?
          base = rem_mod(mul(base, base), f, p)
          e >>= 1
        end
        result
      end

      # s, t with s*a + t*b = 1 mod p (a, b coprime mod p)
      def bezout_mod(a, b, p)
        r0, r1 = mod(a, p), mod(b, p)
        s0, s1 = [1], []
        t0, t1 = [], [1]
        until r1.empty?
          q, r = divmod_mod(r0, r1, p)
          r0, r1 = r1, r
          s0, s1 = s1, mod(sub(s0, mul(q, s1)), p)
          t0, t1 = t1, mod(sub(t0, mul(q, t1)), p)
        end
        inv = r0.last.pow(p - 2, p)
        [mod(scale(s0, inv), p), mod(scale(t0, inv), p)]
      end
    end

    # ---- Zassenhaus ---------------------------------------------------------

    module Zassenhaus
      module_function

      # f: primitive squarefree dense integer polynomial, positive leading
      # coefficient. Returns the irreducible factors (primitive, positive lc).
      def factor(f)
        n = Dense.deg(f)
        return [] if n < 1
        return [f] if n == 1

        lc = f.last
        chosen = nil
        tried = 0
        NumberTheory.each_prime do |p|
          next if p == 2 || (lc % p).zero?
          fp = Dense.mod(f, p)
          next unless Dense.deg(Dense.gcd_mod(fp, Dense.derivative(fp), p)).zero?
          modular = cantor_zassenhaus(fp, p)
          chosen = [p, modular] if chosen.nil? || modular.size < chosen[1].size
          tried += 1
          break if modular.size == 1 || tried >= 4
        end

        p, modular = chosen
        return [f] if modular.size == 1

        # Mignotte-style bound on the coefficients of lc * (any factor of f).
        bound = 2**n * Integer.sqrt(f.sum { |c| c * c }) * lc.abs + 1
        m = p
        k = 1
        while m <= 2 * bound
          m *= p
          k += 1
        end
        lifted = hensel_lift_leading(f, modular, p, k)
        recombine(f, lifted, m).sort_by { |g| [Dense.deg(g), g] }
      end

      # Distinct-degree then equal-degree factorization of a monic squarefree
      # polynomial modulo an odd prime.
      def cantor_zassenhaus(f, p)
        f = Dense.monic_mod(f, p)
        factors = []
        h = [0, 1] # x
        d = 0
        while Dense.deg(f) >= 2 * (d + 1)
          d += 1
          h = Dense.powmod(h, p, f, p)
          g = Dense.gcd_mod(Dense.sub(h, [0, 1]), f, p)
          next if Dense.deg(g) < 1
          factors.concat(equal_degree(g, d, p))
          f = Dense.divmod_mod(f, g, p).first
          h = Dense.rem_mod(h, f, p)
        end
        factors << f if Dense.deg(f) >= 1
        factors
      end

      def equal_degree(g, d, p, rng = Random.new(42))
        return [g] if Dense.deg(g) == d
        loop do
          a = Dense.trim(Array.new(Dense.deg(g)) { rng.rand(p) })
          next if Dense.deg(a) < 1
          b = Dense.sub(Dense.powmod(a, (p**d - 1) / 2, g, p), [1])
          c = Dense.gcd_mod(b, g, p)
          next unless Dense.deg(c).between?(1, Dense.deg(g) - 1)
          return equal_degree(c, d, p, rng) + equal_degree(Dense.divmod_mod(g, c, p).first, d, p, rng)
        end
      end

      # Lift f = lc * g1 * ... * gr (mod p), g_i monic, to (mod p**k). The
      # first factor absorbs the leading coefficient during lifting and is
      # made monic again afterwards; the returned factors are all monic mod p**k.
      def hensel_lift_leading(f, factors, p, k)
        m = p**k
        lc = f.last
        return [Dense.monic_mod(f, m, lc)] if factors.size == 1
        g = Dense.mod(Dense.scale(factors.first, lc), p)
        g = g + Array.new(Dense.deg(factors.first) - Dense.deg(g), 0) if Dense.deg(g) < Dense.deg(factors.first)
        g[-1] = lc
        h = factors.drop(1).reduce([1]) { |acc, x| Dense.mul_mod(acc, x, p) }
        g, h = lift_pair(f, g, h, p, k)
        [Dense.mod(Dense.scale(g, Dense.inv_mod(lc, m)), m)] + hensel_lift(h, factors.drop(1), p, k)
      end

      # Lift f = g1 * g2 * ... * gr (mod p), all monic, to (mod p**k).
      def hensel_lift(f, factors, p, k)
        return [Dense.sym_mod(f, p**k)] if factors.size == 1
        g = factors.first
        h = factors.drop(1).reduce([1]) { |acc, x| Dense.mul_mod(acc, x, p) }
        g, h = lift_pair(f, g, h, p, k)
        [g] + hensel_lift(h, factors.drop(1), p, k)
      end

      # Linear Hensel lifting of f = g*h (mod p) to (mod p**k). h is monic and
      # lc(g) == lc(f) exactly, which both updates preserve, so f - g*h always
      # has degree below deg(f).
      def lift_pair(f, g, h, p, k)
        s, t = Dense.bezout_mod(g, h, p)
        m = p
        (k - 1).times do
          e = Dense.trim(Dense.sub(f, Dense.mul(g, h)).map { |c| (c / m) % p })
          dg = Dense.rem_mod(Dense.mul(t, e), g, p)
          dh = Dense.rem_mod(Dense.mul(s, e), h, p)
          g = Dense.add(g, Dense.scale(dg, m))
          h = Dense.add(h, Dense.scale(dh, m))
          m *= p
        end
        [Dense.sym_mod(g, m), Dense.sym_mod(h, m)]
      end

      # Try products of the monic lifted factors, scaled by the current
      # leading coefficient and made primitive, as divisors of f.
      def recombine(f, modular, m)
        result = []
        remaining = modular
        current = f
        size = 1
        while 2 * size <= remaining.size
          found = false
          lc = current.last
          remaining.each_index.to_a.combination(size).each do |indices|
            # cheap filter on the trailing coefficient before the full product
            tail = indices.reduce(lc) { |acc, i| acc * remaining[i][0] % m }
            tail = tail > m / 2 ? tail - m : tail
            next if tail.zero? || (!current[0].zero? && ((lc * current[0]) % tail).nonzero?)

            prod = indices.reduce([lc]) { |acc, i| Dense.mul_mod(acc, remaining[i], m) }
            cand = Dense.primitive(Dense.sym_mod(prod, m))
            q = Dense.div_exact(current, cand)
            next if q.nil?
            result << cand
            current = q
            remaining = remaining.reject.with_index { |_, i| indices.include?(i) }
            found = true
            break
          end
          size += 1 unless found
        end
        result << Dense.primitive(current) if Dense.deg(current) >= 1
        result
      end
    end
  end

  # Result of Polynomial#factor: unit * product of factor**multiplicity.
  class Factorization
    include Enumerable

    attr_reader :ring, :unit, :factors

    def initialize(ring, unit, factors)
      @ring = ring
      @unit = unit
      @factors = factors.freeze
      freeze
    end

    def each(&block) = factors.each(&block)
    def size = factors.size
    def [](i) = factors[i]
    def irreducible? = factors.size == 1 && factors.first.last == 1 && Scalar.one?(unit)

    # Multiply back out.
    def expand
      factors.reduce(ring.call(unit)) { |acc, (g, m)| acc * g**m }
    end

    def to_expr
      product = factors.map { |g, m| Simplify.power_node(g.to_expr, m) }
      return unit if product.empty?
      body = product.reduce { |acc, f| Mul.new(acc, f) }
      case unit.value
      when 1 then body
      when -1 then Neg.new(body)
      else Mul.new(unit, body)
      end
    end

    def to_s = to_expr.to_s
    alias inspect to_s

    def ==(other) = other.is_a?(Factorization) && other.unit == unit && other.factors == factors
  end
end
