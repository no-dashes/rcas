# frozen_string_literal: true


module RCAS
  # An element of GF(p): an integer modulo a prime. Lives inside Num, so all
  # of rcas' arithmetic (simplify, polynomials, matrices) applies unchanged.
  class Mod
    attr_reader :value, :p

    # GF(p) is where an element modulo p lives; x.in?(GF(7)) asks the same
    # question the other way round, as for every other value.
    def domain = FiniteField.of(p)
    def in?(domain) = domain.include?(self)

    def initialize(value, p)
      @p = p
      @value = value % p
      freeze
    end

    def field = FiniteField.of(p)

    def lift(other)
      case other
      when Mod then raise ArgumentError, "different moduli #{p} and #{other.p}" unless other.p == p
      when Integer then return Mod.new(other, p)
      when Rational then return Mod.new(other.numerator, p) * Mod.new(other.denominator, p).inverse
      when Num then return lift(other.value)
      else raise TypeError, "can't combine #{other.class} with GF(#{p})"
      end
      other
    end

    def symbolic?(other) = other.is_a?(Expression) || other.is_a?(Symbol) || other.is_a?(Algebraic)

    def +(other) = symbolic?(other) ? Num.new(self) + other : Mod.new(value + lift(other).value, p)
    def -(other) = symbolic?(other) ? Num.new(self) - other : Mod.new(value - lift(other).value, p)
    def *(other) = symbolic?(other) ? Num.new(self) * other : Mod.new(value * lift(other).value, p)
    def -@ = Mod.new(-value, p)
    def quo(other) = symbolic?(other) ? Num.new(self) / other : self * lift(other).inverse
    alias / quo

    def inverse
      raise ZeroDivisionError, "0 has no inverse in GF(#{p})" if value.zero?
      Mod.new(value.pow(p - 2, p), p)
    end

    def **(e)
      return Num.new(self)**e if symbolic?(e)
      raise ArgumentError, "integer exponents only" unless e.is_a?(Integer)
      return inverse**(-e) if e.negative?
      Mod.new(value.pow(e, p), p)
    end

    def zero? = value.zero?
    def one? = value == 1
    def coerce(other) = [lift(other), self]
    def to_i = value
    def to_f = value.to_f
    def to_s = value.to_s
    alias inspect to_s
    def to_latex(wrap: nil) = value.to_s

    def ==(other)
      case other
      when Mod then other.p == p && other.value == value
      when Integer then other % p == value
      when Rational then lift(other).value == value
      else false
      end
    end
    alias eql? ==
    def hash = [Mod, value, p].hash

    # multiplicative order
    def order
      raise ArgumentError, "0 has no multiplicative order" if zero?
      field.element_order(self)
    end
  end

  # An element of GF(p**n): a polynomial in the generator modulo the field's
  # irreducible polynomial. coeffs: Integers mod p, index = power of the generator.
  class GFElement
    attr_reader :coeffs, :field

    def domain = field
    def in?(domain) = domain.include?(self)

    def initialize(coeffs, field)
      @field = field
      c = coeffs.map { |x| x % field.p }
      c.pop while !c.empty? && c.last.zero?
      @coeffs = c.freeze
      freeze
    end

    def p = field.p

    def lift(other)
      case other
      when GFElement
        raise ArgumentError, "different fields #{field} and #{other.field}" unless other.field == field
        other
      when Mod then GFElement.new([other.value], field)
      when Integer then GFElement.new([other], field)
      when Rational then GFElement.new([other.numerator], field) * GFElement.new([other.denominator], field).inverse
      when Num then lift(other.value)
      else raise TypeError, "can't combine #{other.class} with #{field}"
      end
    end

    def symbolic?(other) = other.is_a?(Expression) || other.is_a?(Symbol) || other.is_a?(Algebraic)

    def +(other) = symbolic?(other) ? Num.new(self) + other : GFElement.new(Factor::Dense.add(coeffs, lift(other).coeffs), field)
    def -(other) = symbolic?(other) ? Num.new(self) - other : GFElement.new(Factor::Dense.sub(coeffs, lift(other).coeffs), field)
    def -@ = GFElement.new(coeffs.map(&:-@), field)
    def *(other) = symbolic?(other) ? Num.new(self) * other : GFElement.new(Factor::Dense.rem_mod(Factor::Dense.mul(coeffs, lift(other).coeffs), field.modulus, p), field)
    def quo(other) = symbolic?(other) ? Num.new(self) / other : self * lift(other).inverse
    alias / quo

    def inverse
      raise ZeroDivisionError, "0 has no inverse in #{field}" if zero?
      s, = Factor::Dense.bezout_mod(coeffs, field.modulus, p)
      GFElement.new(s, field)
    end

    def **(e)
      return Num.new(self)**e if symbolic?(e)
      raise ArgumentError, "integer exponents only" unless e.is_a?(Integer)
      return inverse**(-e) if e.negative?
      result = field.one_value
      base = self
      while e.positive?
        result *= base if e.odd?
        base *= base
        e >>= 1
      end
      result
    end

    def zero? = coeffs.empty?
    def one? = coeffs == [1]
    def constant? = coeffs.size <= 1
    def coerce(other) = [lift(other), self]
    def order = field.element_order(self)
    def frobenius = self**p

    def ==(other)
      case other
      when GFElement then other.field == field && other.coeffs == coeffs
      when Mod, Integer, Rational then lift(other).coeffs == coeffs
      else false
      end
    end
    alias eql? ==
    def hash = [GFElement, coeffs, field.order].hash

    def to_s
      return "0" if zero?
      parts = coeffs.each_with_index.reject { |c, _| c.zero? }.map do |c, k|
        base = k.zero? ? nil : (k == 1 ? field.gen_name.to_s : "#{field.gen_name}**#{k}")
        if base.nil? then c.to_s
        elsif c == 1 then base
        else "#{c}*#{base}"
        end
      end
      parts.join(" + ")
    end
    alias inspect to_s

    def to_latex(wrap: nil)
      return "0" if zero?
      coeffs.each_with_index.reject { |c, _| c.zero? }.map do |c, k|
        base = k.zero? ? "" : (k == 1 ? field.gen_name.to_s : "#{field.gen_name}^{#{k}}")
        c == 1 && !base.empty? ? base : "#{c}#{base}"
      end.join(" + ")
    end

    # For the printer: a sum needs parentheses inside products.
    def printer_precedence
      nonzero = coeffs.count { |c| !c.zero? }
      return Printer::ATOM if nonzero <= 1 && (coeffs.size <= 1 || coeffs.last == 1) && coeffs.size <= 2
      nonzero > 1 ? Printer::ADDITIVE : Printer::MULTIPLICATIVE
    end
  end

  # GF(q), q = p**n. GF(7), GF(8), GF(9, :b).
  class FiniteField < Domain
    attr_reader :p, :n, :modulus, :gen_name

    @registry = {}

    # GF(q) or GF(p, n); the generator of an extension is called +gen+.
    def self.of(q, gen = :a, n = nil)
      p, n = n ? [q, n] : prime_power(q)
      raise ArgumentError, "#{q} is not a prime power" if p.nil?
      @registry[[p, n, gen]] ||= new(p, n, gen)
    end

    def self.prime_power(q)
      return nil unless q.is_a?(Integer) && q > 1
      division = NumberTheory.prime_division(q)
      return nil unless division.size == 1
      division.first
    end

    def initialize(p, n, gen)
      @p = p
      @n = n
      @gen_name = gen
      @modulus = n > 1 ? FiniteField.irreducible(p, n) : nil
      freeze
    end

    def name = "GF(#{order})"
    def order = p**n
    def characteristic = p
    def degree = n
    def prime? = n == 1
    def field? = true
    def finite? = true
    def fraction_field = self

    # Smallest (lexicographically, by coefficients from the top) monic
    # irreducible polynomial of degree n over GF(p), as a dense array.
    def self.irreducible(p, n)
      (0...p**n).each do |code|
        digits = Array.new(n) { |i| (code / p**i) % p }
        f = digits + [1]
        return f if irreducible_mod?(f, p)
      end
      raise "no irreducible polynomial found" # unreachable
    end

    # Rabin's test: f of degree n is irreducible iff x**(p**n) = x mod f and
    # gcd(f, x**(p**(n/r)) - x) = 1 for every prime r dividing n.
    def self.irreducible_mod?(f, p)
      n = f.size - 1
      return false if n < 1
      x = [0, 1]
      return false unless Factor::Dense.rem_mod(Factor::Dense.sub(Factor::Dense.powmod(x, p**n, f, p), x), f, p).empty?
      NumberTheory.prime_division(n).map(&:first).all? do |r|
        h = Factor::Dense.sub(Factor::Dense.powmod(x, p**(n / r), f, p), x)
        Factor::Dense.deg(Factor::Dense.gcd_mod(h, f, p)) <= 0
      end
    end

    # ---- elements --------------------------------------------------------------

    def zero_value = prime? ? Mod.new(0, p) : GFElement.new([], self)
    def one_value = prime? ? Mod.new(1, p) : GFElement.new([1], self)
    def gen_value = prime? ? Mod.new(1, p) : GFElement.new([0, 1], self)

    def zero = zero_value
    def one = one_value
    def gen = gen_value
    alias generator gen

    # Bring an integer, rational, Num or expression in the generator into the
    # field. Returns the element itself (a Mod or GFElement).
    def call(v)
      case v
      when Num then call(v.value)
      when Mod, GFElement, Integer, Rational then one_value.lift(v)
      when Expression
        e = v.subs(Var.new(gen_name) => Num.new(gen_value)).simplify
        raise DomainError, "#{v} is not an element of #{self}" unless e.is_a?(Num)
        call(e)
      else raise DomainError, "#{v.inspect} is not an element of #{self}"
      end
    end
    alias value_of call

    def normalize_coefficient(c)
      c.is_a?(Num) && !c.finite_field? ? Num.new(call(c)) : c
    end

    def include?(obj)
      case obj
      when Mod then prime? && obj.p == p
      when GFElement then obj.field == self
      when Integer, Rational then true
      when Num then include?(obj.value)
      when Expression then obj.variables.empty? && !(call(obj) rescue nil).nil?
      else false
      end
    end

    def subset?(other)
      case other
      when FiniteField then other == self || (prime? && other.p == p)
      else false
      end
    end

    def join(other)
      case other
      when FiniteField
        return self if other == self
        return other if prime? && other.p == p
        return self if other.prime? && other.p == p
        raise DomainError, "no common field for #{self} and #{other}"
      when NumberSet then other.rank <= 2 ? self : raise(DomainError, "no common field for #{self} and #{other}")
      when PolynomialRing then PolynomialRing.new(join(other.base), other.vars)
      when FractionField then FractionField.new(join(other.ring))
      else raise DomainError, "no common domain for #{self} and #{other}"
      end
    end

    def elements
      return (0...p).map { |i| Mod.new(i, p) } if prime?
      (0...order).map { |code| GFElement.new(Array.new(n) { |i| (code / p**i) % p }, self) }
    end

    def random_value(rng = Random.new)
      prime? ? Mod.new(rng.rand(p), p) : GFElement.new(Array.new(n) { rng.rand(p) }, self)
    end

    # ---- structure -------------------------------------------------------------

    def element_order(x)
      m = order - 1
      NumberTheory.prime_division(m).each do |r, _|
        m /= r while (m % r).zero? && (x**(m / r)).one?
      end
      m
    end

    @primitive = {}

    def primitive_element
      FiniteField.primitive_cache[self] ||= begin
        candidates = prime? ? (2...p).map { |i| Mod.new(i, p) } : elements.reject(&:constant?)
        candidates = [Mod.new(1, p)] if prime? && p == 2
        candidates.find { |x| element_order(x) == order - 1 }
      end
    end

    def self.primitive_cache = @primitive

    # Discrete logarithm: base**k == x (baby-step giant-step).
    def log(x, base = primitive_element)
      x = value_of(x)
      b = value_of(base)
      raise ZeroDivisionError, "log of zero" if x.zero?
      m = Integer.sqrt(order - 1) + 1
      table = {}
      cur = one_value
      m.times do |j|
        table[cur] ||= j
        cur *= b
      end
      factor = (b**m).inverse
      gamma = x
      m.times do |i|
        return i * m + table[gamma] if table.key?(gamma)
        gamma *= factor
      end
      raise ArgumentError, "#{x} is not a power of #{b}"
    end

    def frobenius(x) = value_of(x)**p

    # Minimal polynomial over GF(p) of an element, as a polynomial in +var+
    # over GF(p): the product over the distinct conjugates x, x**p, x**(p**2), ...
    def minpoly(x, var = :x)
      x = value_of(x)
      base = prime? ? self : FiniteField.of(p)
      ring = base[var]
      conjugates = [x]
      conjugates << conjugates.last**p while conjugates.last**p != x
      big = PolynomialRing.new(self, [var])
      poly = conjugates.reduce(big.one) { |acc, c| acc * big.call(Var.new(var) - Num.new(c)) }
      Polynomial.new(ring, poly.terms.transform_values { |c| Num.new(Mod.new(c.value.is_a?(Mod) ? c.value.value : (c.value.coeffs.first || 0), p)) })
    end

    # Roots of a polynomial in this field.
    def solve(expr, var = nil)
      expr = Solve.to_zero(expr)
      var = Solve.variable(expr, var)
      self[var.name].call(expr).roots
    end

    def ==(other) = other.is_a?(FiniteField) && other.p == p && other.n == n && other.gen_name == gen_name
    alias eql? ==
    def hash = [FiniteField, p, n, gen_name].hash
  end

  # Factorization over a finite field: squarefree decomposition in
  # characteristic p, then Cantor-Zassenhaus (distinct-degree and equal-degree
  # splitting, with the trace trick in characteristic 2).
  #
  # Sources (keys: MANUAL.md, Sources): [CZ81]; [vzGG13, §14.2-14.3]; the
  # irreducibility test above is Rabin's [Rab80].
  module FiniteFieldFactor
    module_function

    def factor(poly)
      field = poly.ring.base
      raise ArgumentError, "univariate polynomials only" unless poly.ring.univariate?
      return Factorization.new(poly.ring, field.zero, []) if poly.zero?
      f = to_dense(poly)
      lc = f.last
      unit = Num.new(lc)
      f = FP.monic(f)
      factors = []
      FP.squarefree(f, field).each do |part, mult|
        FP.cantor_zassenhaus(part, field).each { |g| factors << [from_dense(g, poly.ring), mult] }
      end
      Factorization.new(poly.ring, unit, factors.sort_by { |g, m| [g.degree, g.to_s, m] })
    end

    def to_dense(poly)
      field = poly.ring.base
      FP.trim((0..poly.degree).map { |k| field.value_of(poly.coeff(k)) })
    end

    def from_dense(a, ring)
      Polynomial.new(ring, a.each_with_index.to_h { |c, k| [[k], Num.new(c)] })
    end

    # Dense polynomials with coefficients that are field element values.
    module FP
      module_function

      def trim(a)
        a = a.dup
        a.pop while !a.empty? && a.last.zero?
        a
      end

      def deg(a) = a.size - 1

      def add(a, b) = trim(Array.new([a.size, b.size].max) { |i| (a[i] && b[i]) ? a[i] + b[i] : (a[i] || b[i]) })
      def sub(a, b) = trim(Array.new([a.size, b.size].max) { |i| a[i] && b[i] ? a[i] - b[i] : (a[i] || -b[i]) })

      def mul(a, b)
        return [] if a.empty? || b.empty?
        out = Array.new(a.size + b.size - 1) { nil }
        a.each_with_index do |x, i|
          next if x.zero?
          b.each_with_index { |y, j| out[i + j] = out[i + j] ? out[i + j] + x * y : x * y }
        end
        trim(out.map { |v| v || a.first * 0 })
      end

      def monic(a)
        return a if a.empty?
        inv = a.last.inverse
        a.map { |c| c * inv }
      end

      def divmod(a, b)
        raise ZeroDivisionError if b.empty?
        r = a.dup
        q = Array.new([deg(a) - deg(b) + 1, 0].max) { b.last * 0 }
        inv = b.last.inverse
        while !r.empty? && deg(r) >= deg(b)
          shift = deg(r) - deg(b)
          c = r.last * inv
          q[shift] = c
          b.each_with_index { |y, j| r[shift + j] = r[shift + j] - c * y }
          r = trim(r)
        end
        [trim(q), r]
      end

      def rem(a, b) = divmod(a, b).last
      def div(a, b) = divmod(a, b).first

      def gcd(a, b)
        a, b = b, rem(a, b) until b.empty?
        monic(a)
      end

      def powmod(a, e, f)
        result = [a.first * 0 + 1]
        base = rem(a, f)
        while e.positive?
          result = rem(mul(result, base), f) if e.odd?
          base = rem(mul(base, base), f)
          e >>= 1
        end
        result
      end

      def derivative(a) = trim(a.each_with_index.map { |c, i| c * i }.drop(1))

      # f = g(x**p) => the g with coefficients' p-th roots (Frobenius inverse)
      def pth_root(a, field)
        p = field.p
        coeffs = (0..deg(a) / p).map do |k|
          c = a[k * p]
          field.prime? ? c : c**(field.order / p)
        end
        trim(coeffs)
      end

      # [[squarefree part, multiplicity], ...] for a monic f (characteristic p).
      def squarefree(f, field)
        out = []
        return out if deg(f) < 1
        d = derivative(f)
        if d.empty?
          squarefree(pth_root(f, field), field).each { |g, m| out << [g, m * field.p] }
          return out
        end
        g = gcd(f, d)
        w = div(f, g)
        i = 1
        while deg(w) >= 1
          y = gcd(w, g)
          z = div(w, y)
          out << [z, i] if deg(z) >= 1
          w = y
          g = div(g, y)
          i += 1
        end
        if deg(g) >= 1
          squarefree(pth_root(g, field), field).each { |h, m| out << [h, m * field.p] }
        end
        out
      end

      def cantor_zassenhaus(f, field)
        f = monic(f)
        q = field.order
        factors = []
        x = [f.first * 0, f.first * 0 + 1]
        h = x
        d = 0
        while deg(f) >= 2 * (d + 1)
          d += 1
          h = powmod(h, q, f)
          g = gcd(sub(h, x), f)
          next if deg(g) < 1
          factors.concat(equal_degree(g, d, field))
          f = div(f, g)
          h = rem(h, f)
        end
        factors << f if deg(f) >= 1
        factors
      end

      def equal_degree(g, d, field, rng = Random.new(42))
        return [g] if deg(g) == d
        q = field.order
        one = g.first * 0 + 1
        loop do
          r = trim(Array.new(deg(g)) { field.random_value(rng) })
          next if deg(r) < 1
          if field.p == 2
            # trace map: r + r**2 + r**4 + ... (d * n terms)
            t = r
            acc = r
            (d * field.n - 1).times do
              t = rem(mul(t, t), g)
              acc = add(acc, t)
            end
            b = acc
          else
            b = sub(powmod(r, (q**d - 1) / 2, g), [one])
          end
          c = gcd(b, g)
          next unless deg(c).between?(1, deg(g) - 1)
          return equal_degree(c, d, field, rng) + equal_degree(div(g, c), d, field, rng)
        end
      end
    end
  end

  # Wire finite-field elements into the rest of the system.
  class Num
    def finite_field? = value.is_a?(Mod) || value.is_a?(GFElement)
  end
end
