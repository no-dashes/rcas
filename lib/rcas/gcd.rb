# frozen_string_literal: true

module RCAS
  # Polynomial gcd.
  #
  # * univariate over a field: Euclid, result monic
  # * anything over ZZ or QQ (any number of variables): primitive
  #   pseudo-remainder sequences, recursing on the content in one variable
  #   at a time; result primitive with positive leading coefficient over ZZ,
  #   monic (leading coefficient 1 in graded lex order) over QQ
  module PolyGCD
    module_function

    def gcd(f, g)
      ring = f.ring
      numeric!(f)
      numeric!(g)

      if ring.univariate? && ring.base.field? && !exact?(ring.base)
        return euclid(f, g)
      end

      if ring.base == ZZ
        gcd_zz(f, g)
      elsif ring.base == QQ
        zz = ZZ[*ring.vars]
        result = gcd_zz(f.clear_denominators.to_ring(zz), g.clear_denominators.to_ring(zz))
        result.to_ring(ring).monic
      else
        raise NotImplementedError, "gcd over #{ring.base} needs a univariate ring"
      end
    end

    def lcm(f, g)
      return f.ring.zero if f.zero? || g.zero?
      (f * g).exact_div(gcd(f, g))
    end

    # Extended Euclid over a field: returns [g, s, t] with s*f + t*g = gcd, gcd monic.
    def xgcd(f, g)
      ring = f.ring
      raise NotImplementedError, "xgcd needs a univariate ring over a field" unless ring.univariate? && ring.base.field?
      r0, r1 = f, g
      s0, s1 = ring.one, ring.zero
      t0, t1 = ring.zero, ring.one
      until r1.zero?
        q, r = r0.divmod(r1)
        r0, r1 = r1, r
        s0, s1 = s1, s0 - q * s1
        t0, t1 = t1, t0 - q * t1
      end
      return [ring.zero, ring.zero, ring.zero] if r0.zero?
      inv = Scalar.div(Num.new(1), r0.leading_coefficient)
      [r0 * inv, s0 * inv, t0 * inv]
    end

    # ---- internals --------------------------------------------------------

    def exact?(base) = base == ZZ || base == QQ

    def numeric!(f)
      return if f.terms.values.all? { |c| c.is_a?(Num) && (c.value.is_a?(Integer) || c.value.is_a?(Rational) || !exact?(f.ring.base)) }
      raise DomainError, "gcd needs numeric coefficients, got #{f}"
    end

    def euclid(a, b)
      a, b = b, a % b until b.zero?
      a.monic
    end

    def gcd_zz(f, g)
      return g.primitive_part if f.zero?
      return f.primitive_part if g.zero?

      x = (f.ring.vars.find { |v| f.degree(v).positive? || g.degree(v).positive? })
      if x.nil?
        return Polynomial.constant(f.ring, f.constant_term.value.gcd(g.constant_term.value))
      end

      cf = content_in(f, x)
      cg = content_in(g, x)
      c = gcd_zz(cf, cg)
      a = f.exact_div(cf)
      b = g.exact_div(cg)
      until b.zero?
        r = prem(a, b, x)
        a, b = b, (r.zero? ? r : r.exact_div(content_in(r, x)))
      end
      c * a.exact_div(content_in(a, x)).primitive_part
    end

    # gcd of the coefficients of f seen as a polynomial in x.
    def content_in(f, x)
      coeffs = (0..f.degree(x)).map { |k| f.coefficient_in(x, k) }.reject(&:zero?)
      coeffs.reduce { |acc, c| gcd_zz(acc, c) }
    end

    # Pseudo-remainder of a by b with respect to x (no fractions introduced).
    def prem(a, b, x)
      db = b.degree(x)
      lb = b.leading_coefficient_in(x)
      r = a
      while !r.zero? && (dr = r.degree(x)) >= db
        r = lb * r - r.leading_coefficient_in(x) * b.shift(x, dr - db)
      end
      r
    end
  end
end
