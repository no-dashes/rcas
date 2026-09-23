# frozen_string_literal: true

module RCAS
  # The i-th root (real roots first, ascending; then complex by real and
  # imaginary part) of an irreducible polynomial with rational coefficients.
  class RootOf < Expression
    attr_reader :poly, :index

    # poly: a univariate Polynomial over QQ (or ZZ)
    def initialize(poly, index)
      @poly = poly
      @index = index
      @value = RootOf.numeric_roots(poly)[index]
      freeze
    end

    attr_reader :value

    def var = poly.ring.vars.first
    def degree = poly.degree
    def ==(other) = other.is_a?(RootOf) && other.poly == poly && other.index == index
    alias eql? ==
    def hash = [RootOf, poly.to_expr.simplify, index].hash
    def to_sexp = [:root_of, poly.to_expr.to_sexp, index]

    def self.numeric_roots(poly)
      roots = Solve.numeric_roots(poly).map(&:value)
      roots.sort_by { |z| z.is_a?(Complex) ? [1, z.real, z.imaginary] : [0, z, 0] }
    end

    def real? = !value.is_a?(Complex)
  end

  # QQ(alpha): numbers a0 + a1*alpha + ... + a_{n-1}*alpha**(n-1) with the
  # minimal polynomial of alpha reducing higher powers.
  #
  # Sources (keys: MANUAL.md, Sources): arithmetic in QQ(alpha) and minimal
  # polynomials through resultants [Loo83], [Coh93, §4.2]; factoring over
  # QQ(alpha) by norms is Trager's method [Tra76], [Coh93, Algorithm 3.6.4].
  class AlgebraicField < Domain
    attr_reader :minpoly, :generator, :radicals

    A = :_a

    # generator: an Expression (2**(1/2), RootOf(...), 2**(1/2) + 3**(1/2))
    # radicals: { [base, q] => polynomial in _a for base**(1/q) } used when
    # converting expressions into the field.
    def initialize(minpoly, generator, radicals = {})
      @minpoly = minpoly
      @generator = generator
      @radicals = radicals
      freeze
    end

    def ring = QQ[A]
    def degree = minpoly.degree
    def name = "QQ(#{generator})"
    def field? = true

    def element(poly) = AlgebraicNumber.new(self, poly % minpoly)
    def zero = element(ring.zero)
    def one = element(ring.one)
    def alpha = element(ring.call(Var.new(A)))
    def constant(v) = element(ring.call(v))

    def include?(obj)
      case obj
      when AlgebraicNumber then obj.field == self
      when Numeric then QQ.include?(obj)
      when Expression then !Algebraic.convert(obj, self).nil?
      else false
      end
    end

    def subset?(other)
      case other
      when AlgebraicField then other == self
      when NumberSet then other.rank >= (generator_real? ? 3 : 4)
      else false
      end
    end

    # Decided: a RootOf knows from Sturm's count, a radical from its
    # radicand (an |Im| < 1e-12 test before: fourth review, 2.4).
    def generator_real?
      return generator.real? if generator.is_a?(RootOf)
      Inequalities.real?(generator)
    rescue NotImplementedError, RCAS::Unsupported
      false
    end

    def join(other)
      case other
      when NumberSet then other.rank <= 2 ? self : other
      when AlgebraicField then other == self ? self : (generator_real? && other.generator_real? ? RR : CC)
      when PolynomialRing then PolynomialRing.new(join(other.base), other.vars)
      when FractionField then FractionField.new(join(other.ring))
      else raise DomainError, "no common domain for #{self} and #{other}"
      end
    end

    def ==(other) = other.is_a?(AlgebraicField) && other.minpoly == minpoly && other.generator == generator
    alias eql? ==
    def hash = [AlgebraicField, minpoly.to_expr.simplify, generator].hash
  end

  class AlgebraicNumber
    include Algebraic

    attr_reader :field, :poly

    # QQ(alpha) is where an algebraic number lives.
    def domain = field

    def initialize(field, poly)
      @field = field
      @poly = poly
      freeze
    end

    def +(other) = field.element(poly + lift(other).poly)
    def -(other) = field.element(poly - lift(other).poly)
    def *(other) = field.element(poly * lift(other).poly)
    def -@ = field.element(-poly)
    def /(other) = self * lift(other).inverse

    def **(n)
      raise ArgumentError, "integer exponents only" unless n.is_a?(Integer)
      return inverse**(-n) if n.negative?
      result = field.one
      base = self
      while n.positive?
        result *= base if n.odd?
        base *= base
        n >>= 1
      end
      result
    end

    def inverse
      raise ZeroDivisionError, "division by zero in #{field}" if zero?
      g, s, = poly.xgcd(field.minpoly)
      raise ArgumentError, "#{field.minpoly} is not irreducible" unless g.constant?
      field.element(s * Scalar.div(Num.new(1), g.constant_term))
    end

    def zero? = poly.zero?
    def rational? = poly.constant?
    def coerce(other) = [lift(other), self]
    def ==(other) = other.is_a?(AlgebraicNumber) ? (self - other).zero? : (rational? && poly.constant_term == Expression.lift(other))
    alias eql? ==
    def hash = [AlgebraicNumber, poly.to_expr.simplify].hash

    # Back to radicals: a0 + a1*alpha + ...
    def to_expr
      poly.to_expr.subs(Var.new(AlgebraicField::A) => field.generator).expand
    end

    def evalf = to_expr.evalf
    def to_s = to_expr.to_s
    alias inspect to_s
    def to_latex(wrap: nil) = LaTeX.of(to_expr)

    # Minimal polynomial of this element over QQ, in +var+.
    def minpoly(var = :x)
      Algebraic.minpoly_of(self, var)
    end

    private

    def lift(other)
      return other if other.is_a?(AlgebraicNumber) && other.field == field
      raise ArgumentError, "different fields: #{field} and #{other.field}" if other.is_a?(AlgebraicNumber)
      Algebraic.convert(Expression.lift(other), field) or raise DomainError, "#{other} is not in #{field}"
    end
  end

  # Exact arithmetic with algebraic numbers: recognising the field an
  # expression lives in, converting into it, minimal polynomials, and
  # factorization over QQ(alpha) by Trager's method.
  module Algebraic
    module_function

    # The exact value of a constant expression in radicals / RootOf, or nil
    # when it involves anything else (pi, several incompatible radicals, ...).
    def exact(expr)
      expr = Expression.lift(expr)
      return nil unless expr.variables.empty?
      field = field_for(expr) or return nil
      convert(expr, field)
    rescue ZeroDivisionError, ArgumentError, DomainError
      nil
    end

    def radical?(n) = n.is_a?(Pow) && n.base.is_a?(Num) && (n.base.value.is_a?(Integer) || n.base.value.is_a?(Rational)) && n.exponent.is_a?(Num) && n.exponent.value.is_a?(Rational)

    # QQ(alpha) for the radicals / RootOf atoms of expr, or nil.
    def field_for(expr)
      radicals = {}
      roots = []
      expr.each_node do |n|
        if radical?(n)
          radicals[[n.base.value, n.exponent.value.denominator]] = true
        elsif n.is_a?(Num) && n.value.is_a?(Complex)
          radicals[[-1, 2]] = true
        elsif n.is_a?(RootOf)
          roots << n unless roots.include?(n)
        end
      end
      generators = radicals.keys.size + roots.size
      return nil if generators.zero? || generators > 2
      return root_field(roots.first) if generators == 1 && roots.size == 1
      return radical_field(*radicals.keys.first) if generators == 1
      return nil unless roots.empty? && radicals.keys.all? { |_, q| q == 2 }
      square_root_compositum(radicals.keys.map(&:first))
    end

    def adjoin(alpha)
      alpha = Expression.lift(alpha).simplify
      field_for(alpha) or raise ArgumentError, "can't build QQ(#{alpha})"
    end

    def root_field(root)
      ring = QQ[AlgebraicField::A]
      m = ring.call(root.poly.to_expr.subs(Var.new(root.var) => Var.new(AlgebraicField::A)))
      AlgebraicField.new(m.monic, root)
    end

    # QQ(base**(1/q))
    def radical_field(base, q)
      ring = QQ[AlgebraicField::A]
      a = Var.new(AlgebraicField::A)
      candidate = ring.call(a**q - base)
      generator = base == -1 && q == 2 ? I : Pow.new(Num.new(base), Num.new(Rational(1, q)))
      value = generator.evalf
      m = candidate.factor.factors.map(&:first).min_by { |g| g.to_expr.evalf(AlgebraicField::A => value).abs }
      AlgebraicField.new(m.monic, generator, { [base, q] => ring.call(a) })
    end

    # QQ(sqrt(a), sqrt(b)) = QQ(gamma), gamma = sqrt(a) + sqrt(b):
    # sqrt(a) = (gamma**2 + a - b) / (2 gamma)
    def square_root_compositum(bases)
      a, b = bases
      ring = QQ[AlgebraicField::A]
      g = Var.new(AlgebraicField::A)
      m = ring.call(((g**2 - (a + b))**2 - 4 * a * b).expand)
      field = AlgebraicField.new(m, (Pow.new(Num.new(a), Num.new(Rational(1, 2))) + Pow.new(Num.new(b), Num.new(Rational(1, 2)))).simplify)
      gamma = field.alpha
      half = gamma.inverse * Rational(1, 2)
      sqrt_a = ((gamma * gamma) + Rational(a - b)) * half
      sqrt_b = ((gamma * gamma) + Rational(b - a)) * half
      AlgebraicField.new(m, field.generator, { [a, 2] => sqrt_a.poly, [b, 2] => sqrt_b.poly })
    end

    # Expression => AlgebraicNumber in +field+, or nil.
    def convert(expr, field)
      case expr
      when Num
        v = expr.value
        return field.constant(v) if v.is_a?(Integer) || v.is_a?(Rational)
        return nil unless v.is_a?(Complex) && [v.real, v.imaginary].all? { |c| c.is_a?(Integer) || c.is_a?(Rational) }
        unit = field.radicals[[-1, 2]] or return nil
        field.constant(v.real) + field.element(unit) * v.imaginary
      when RootOf then field.generator == expr ? field.alpha : nil
      when Pow
        if radical?(expr)
          base, e = expr.base.value, expr.exponent.value
          root = field.radicals[[base, e.denominator]]
          root ? field.element(root)**e.numerator : nil
        elsif expr.exponent.is_a?(Num) && expr.exponent.integer?
          inner = convert(expr.base, field) or return nil
          inner**expr.exponent.value
        end
      when Add then binary(expr, field, :+)
      when Sub then binary(expr, field, :-)
      when Mul then binary(expr, field, :*)
      when Div then binary(expr, field, :/)
      when Neg then (inner = convert(expr.arg, field)) && -inner
      else
        folded = expr.simplify
        folded == expr ? nil : convert(folded, field)
      end
    end

    def binary(expr, field, op)
      l = convert(expr.left, field) or return nil
      r = convert(expr.right, field) or return nil
      l.public_send(op, r)
    end

    # Minimal polynomial of an AlgebraicNumber (or exact constant expression).
    def minpoly_of(number, var = :x)
      if number.is_a?(Expression) || number.is_a?(Numeric)
        expr = Expression.lift(number)
        # a rational is algebraic of degree 1 (A10); a nested radical is
        # algebraic too, and is taken apart by resultants rather than called
        # "not an algebraic number"
        folded = expr.simplify
        if folded.is_a?(Num) && (folded.value.is_a?(Integer) || folded.value.is_a?(Rational))
          return QQ[var].call(Var.new(var) - folded)
        end
        number = exact(expr)
        return resultant_minpoly(expr, var) if number.nil?
      end
      raise ArgumentError, "not an algebraic number" if number.nil?
      x = Var.new(var)
      ring2 = QQ[AlgebraicField::A, var]
      m = ring2.call(number.field.minpoly.to_expr)
      g = ring2.call(x - number.poly.to_expr)
      res = QQ[var].call(m.resultant(g, AlgebraicField::A).to_expr)
      value = number.evalf
      res.factor.factors.map(&:first).min_by { |f| f.to_expr.evalf(var => value).abs }.monic
    end

    # The minimal polynomial of a constant built from rationals, i, the
    # four operations and rational powers, by resultants [CLO15, §3.6]: a
    # polynomial for each part, combined - P(x) for u + v is
    # res_y(P_u(y), P_v(x - y)) - and the factor that vanishes at the value
    # kept. pi and e are transcendental and say so; anything else it cannot
    # take apart is a refusal (RCAS::Unsupported), never "not algebraic".
    def resultant_minpoly(expr, var)
      x = Var.new(var)
      poly = annihilator(expr, x)
      ring = QQ[var]
      value = expr.evalf
      raise RCAS::Unsupported, "minpoly: #{expr} has no numeric value to choose a factor by" unless value.is_a?(Numeric)
      ring.call(poly).factor.factors.map(&:first).min_by { |f| (f.to_expr.evalf(var => value)).abs }.monic
    end

    def annihilator(e, x)
      y = Var.new(:"_y#{x.name}")
      case e
      when Num
        v = e.value
        return (x - Num.new(v)).expand if v.is_a?(Integer) || v.is_a?(Rational)
        if v.is_a?(Complex) && [v.real, v.imaginary].all? { |c| c.is_a?(Integer) || c.is_a?(Rational) }
          return ((x - Num.new(v.real))**2 + Num.new(v.imaginary)**2).expand
        end
        raise RCAS::Unsupported, "minpoly: #{e} is not exact"
      when Const
        raise ArgumentError, "not an algebraic number: #{e} is transcendental" if %i[pi e].include?(e.name) || e == E
        raise RCAS::Unsupported, "minpoly: #{e}"
      when Neg then annihilator(e.arg, x).subs(x => Neg.new(x)).expand
      when Add, Sub, Mul, Div then combine(e, x, y)
      when Pow then power_annihilator(e, x, y)
      else
        raise ArgumentError, "not an algebraic number: #{e} is transcendental" if e == E || (e.is_a?(Fn) && e.name == :exp && e.args.first == Num.new(1))
        raise RCAS::Unsupported, "minpoly: #{e} is beyond the radicals rcas takes apart"
      end
    end

    def combine(e, x, y)
      pl = annihilator(e.left, x).subs(x => y)
      pr = annihilator(e.right, x)
      other =
        case e
        when Add then pr.subs(x => x - y)
        when Sub then pr.subs(x => y - x)
        when Mul then scaled(pr, x, x / y, y)
        when Div then annihilator(e.left, x).subs(x => x * y)
        end
      pl = annihilator(e.right, x).subs(x => y) if e.is_a?(Div)
      eliminate(pl, other.expand, y, x)
    end

    # y**deg * P(x/y), a polynomial again.
    def scaled(p, x, replacement, y)
      degree = Solve.polynomial_coefficients(p, x).size - 1
      (p.subs(x => replacement) * y**degree).expand
    end

    def power_annihilator(e, x, y)
      exponent = e.exponent
      raise RCAS::Unsupported, "minpoly: #{e} has a non-rational exponent" unless exponent.is_a?(Num) && (exponent.value.is_a?(Integer) || exponent.value.is_a?(Rational))
      r = Rational(exponent.value)
      base = annihilator(e.base, x)
      base = scaled(base, x, 1 / x, x) if r.negative? # the reciprocal
      r = r.abs
      rooted = base.subs(x => x**r.denominator).expand # b**(1/q): P(x**q)
      return rooted if r.numerator == 1
      eliminate(rooted.subs(x => y), (x - y**r.numerator).expand, y, x)
    end

    def eliminate(p, q, y, x)
      ring = QQ[y.name, x.name]
      ring.call(p).resultant(ring.call(q), y.name).to_expr.expand
    end

    # ---- factorization over QQ(alpha): Trager -------------------------------

    def factor_over(poly, field)
      raise ArgumentError, "univariate polynomials only" unless poly.ring.univariate?
      xname = poly.ring.vars.first
      x = Var.new(xname)
      a = Var.new(AlgebraicField::A)
      kring = PolynomialRing.new(field, [xname])
      unit = Num.new(poly.leading_coefficient.value)
      factors = []
      poly.clear_denominators.to_ring(QQ[xname]).squarefree_decomposition.each do |part, mult|
        part = part.monic
        next if part.degree.zero?
        shift = 0
        norm = nil
        loop do
          shifted = part.to_expr.subs(x => x - shift * a)
          ring2 = QQ[AlgebraicField::A, xname]
          norm = QQ[xname].call(ring2.call(shifted).resultant(ring2.call(field.minpoly.to_expr), AlgebraicField::A).to_expr)
          break if norm.gcd(norm.derivative).constant?
          shift += 1
        end
        norm.factor.factors.map(&:first).each do |ni|
          candidate = KPolynomial.from_rational(ni.to_expr.subs(x => x + shift * a), field, xname)
          g = KPolynomial.from_rational(part.to_expr, field, xname).gcd(candidate)
          next if g.degree.zero?
          factors << [g.to_polynomial(kring), mult]
        end
      end
      Factorization.new(kring, unit, factors.sort_by { |g, m| [g.degree, g.to_s, m] })
    end

    # Polynomials in x with coefficients in an algebraic field (dense array).
    class KPolynomial
      attr_reader :coeffs, :field

      def initialize(coeffs, field)
        @coeffs = coeffs.dup
        @coeffs.pop while !@coeffs.empty? && @coeffs.last.zero?
        @field = field
        freeze
      end

      # expr: polynomial in x whose coefficients are polynomials in _a
      def self.from_rational(expr, field, xname)
        ring2 = QQ[AlgebraicField::A, xname]
        p = ring2.call(expr)
        coeffs = (0..p.degree(xname)).map { |k| field.element(QQ[AlgebraicField::A].call(p.coefficient_in(xname, k).to_expr)) }
        new(coeffs, field)
      end

      def degree = coeffs.size - 1
      def zero? = coeffs.empty?
      def lc = coeffs.last

      def monic
        return self if zero?
        inv = lc.inverse
        KPolynomial.new(coeffs.map { |c| c * inv }, field)
      end

      def rem(other)
        r = coeffs.dup
        inv = other.lc.inverse
        while r.size >= other.coeffs.size && !r.empty?
          c = r.last * inv
          shift = r.size - other.coeffs.size
          other.coeffs.each_with_index { |oc, k| r[shift + k] = r[shift + k] - c * oc }
          r.pop while !r.empty? && r.last.zero?
        end
        KPolynomial.new(r, field)
      end

      def gcd(other)
        a, b = self, other
        a, b = b, a.rem(b) until b.zero?
        a.monic
      end

      def to_polynomial(kring)
        Polynomial.new(kring, coeffs.each_with_index.to_h { |c, k| [[k], c.to_expr] })
      end
    end
  end

  class NumberSet
    # QQ.adjoin(sqrt(2)) is the field QQ(sqrt(2)).
    def adjoin(alpha)
      raise DomainError, "adjoin extends QQ" unless self == QQ
      Algebraic.adjoin(alpha)
    end
  end
end
