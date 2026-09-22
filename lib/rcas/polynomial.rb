# frozen_string_literal: true

module RCAS
  # An element of a PolynomialRing, stored as { exponent_vector => coefficient }.
  # Coefficients are Expressions (usually Num, but parameters are allowed).
  #
  #   R = QQ[:x]
  #   f = R.(:x**2 - 1)
  #   g = R.(:x - 1)
  #   f / g                # => 1 + x
  #   f.gcd(R.(:x**2 + 2 * :x + 1))   # => 1 + x
  class Polynomial
    include Algebraic

    attr_reader :ring, :terms

    def initialize(ring, terms)
      @ring = ring
      terms = terms.transform_values { |c| ring.base.normalize_coefficient(c) } if ring.base.respond_to?(:normalize_coefficient)
      @terms = terms.reject { |_, c| Scalar.zero?(c) }.freeze
      freeze
    end

    # Build from an Expression. Raises DomainError if the expression is not a
    # polynomial in the ring's variables with coefficients in the base domain.
    def self.from_expr(ring, expr, promote: false)
      return expr.to_ring(ring) if expr.is_a?(Polynomial)

      expr = Expression.lift(expr)
      size = ring.vars.size
      terms = {}

      constant, table = Expand.table(expr)
      terms[Array.new(size, 0)] = Num.new(constant) unless constant.zero?

      table.each do |factors, coeff|
        exps = Array.new(size, 0)
        c = Expression.lift(coeff)

        factors.each do |base, exp|
          if base.is_a?(Var) && (i = ring.index(base.name))
            unless exp.is_a?(Integer) && exp >= 0
              raise DomainError, "#{expr} is not a polynomial in #{base}: exponent #{exp}"
            end
            exps[i] += exp
          elsif (Simplify.power_node(base, exp).variables & ring.vars).empty?
            # the exponent counts too: exp(x) is e**x, no coefficient of a
            # polynomial in x (third review, A3)
            c *= Simplify.power_node(base, exp)
          else
            raise DomainError, "#{expr} is not a polynomial in #{ring.vars.join(', ')}"
          end
        end

        terms[exps] = Scalar.add(terms[exps] || Num.new(0), c.simplify)
      end

      terms.each_value do |c|
        next if Scalar.zero?(c) || ring.base.include?(c)
        if promote && (d = Infer.domain(c))
          return from_expr(PolynomialRing.new(ring.base.join(d), ring.vars), expr)
        end
        raise DomainError, "coefficient #{c} of #{expr} is not in #{ring.base}"
      end

      new(ring, terms)
    end

    # ---- structure --------------------------------------------------------

    # The ring is where the polynomial lives; base is its coefficient domain.
    def domain = ring
    def base = ring.base

    def zero? = terms.empty?
    def constant? = terms.keys.all? { |e| e.all?(&:zero?) }
    def constant_term = terms[Array.new(ring.vars.size, 0)] || Num.new(0)

    # Total degree, or the degree in one variable. The zero polynomial has degree -1.
    def degree(var = nil)
      return -1 if zero?
      if var
        i = ring.index(var.is_a?(Var) ? var.name : var.to_sym) or raise ArgumentError, "#{var} is not a variable of #{ring}"
        terms.keys.map { |e| e[i] }.max
      else
        terms.keys.map(&:sum).max
      end
    end

    def leading_exponents = terms.keys.max_by { |e| [e.sum, e] }
    def leading_coefficient = zero? ? Num.new(0) : terms[leading_exponents]

    # Coefficient of x**a * y**b ... given the exponents in ring order.
    def coeff(*exps) = terms[exps] || Num.new(0)

    # Univariate only: coefficients from the constant term upwards.
    def coefficients
      univariate!
      (0..degree).map { |k| coeff(k) }
    end

    def monomials
      terms.keys.sort_by { |e| [e.sum, e] }.map { |e| monomial(e) }
    end

    # ---- arithmetic -------------------------------------------------------

    def +(other) = combine(other, :+) { |a, b| Polynomial.new(a.ring, merge(a.terms, b.terms)) }
    def -(other) = combine(other, :-) { |a, b| a + -b }
    def -@ = Polynomial.new(ring, terms.transform_values { |c| Scalar.neg(c) })

    def *(other)
      combine(other, :*) do |a, b|
        product = {}
        a.terms.each do |ea, ca|
          b.terms.each do |eb, cb|
            e = ea.zip(eb).map(&:sum)
            product[e] = Scalar.add(product[e] || Num.new(0), Scalar.mul(ca, cb))
          end
        end
        Polynomial.new(a.ring, product)
      end
    end

    def **(n)
      raise ArgumentError, "polynomial powers must be non-negative integers" unless n.is_a?(Integer) && n >= 0
      result = ring.one
      base = self
      while n.positive?
        result *= base if n.odd?
        base *= base
        n >>= 1
      end
      result
    end

    # Exact division; raises DomainError if the remainder is not zero.
    def /(other)
      combine(other, :/) do |a, b|
        next a.exact_div(b) unless a.ring.univariate? || b.constant?
        q, r = a.divmod(b)
        raise DomainError, "#{b} does not divide #{a} (remainder #{r})" unless r.zero?
        q
      end
    end

    # Division that must come out exact, in any number of variables.
    def exact_div(other)
      other = Polynomial.from_expr(ring, other) unless other.is_a?(Polynomial) && other.ring == ring
      raise ZeroDivisionError, "division by the zero polynomial" if other.zero?
      remainder = terms.dup
      quotient = {}
      eg = other.leading_exponents
      cg = other.leading_coefficient
      until remainder.empty?
        er = remainder.keys.max_by { |e| [e.sum, e] }
        shift = er.zip(eg).map { |a, b| a - b }
        c = Scalar.div(remainder[er], cg)
        unless shift.all? { |k| k >= 0 } && ring.base.include?(c)
          raise DomainError, "#{other} does not divide #{self} in #{ring}"
        end
        quotient[shift] = c
        other.terms.each do |e, coeff|
          key = e.zip(shift).map(&:sum)
          v = Scalar.sub(remainder[key] || Num.new(0), Scalar.mul(c, coeff))
          Scalar.zero?(v) ? remainder.delete(key) : remainder[key] = v
        end
      end
      Polynomial.new(ring, quotient)
    end

    def divmod(other)
      combine(other, :divmod) do |a, b|
        raise ZeroDivisionError, "division by the zero polynomial" if b.zero?
        return [a * Scalar.div(Num.new(1), b.constant_term), a.ring.zero] if b.constant? && !b.constant_term.is_a?(Num)
        a.univariate! unless b.constant?

        quotient = {}
        remainder = a
        db = b.degree
        lb = b.leading_coefficient
        while !remainder.zero? && remainder.degree >= db
          c = Scalar.div(remainder.leading_coefficient, lb)
          unless a.ring.base.include?(c)
            raise DomainError, "#{b} does not divide #{a} in #{a.ring}; try #{a.ring.base.fraction_field}[#{a.ring.vars.join(', ')}]"
          end
          shift = remainder.leading_exponents.zip(b.leading_exponents).map { |x, y| x - y }
          quotient[shift] = Scalar.add(quotient[shift] || Num.new(0), c)
          remainder -= Polynomial.new(a.ring, { shift => c }) * b
        end
        [Polynomial.new(a.ring, quotient), remainder]
      end
    end

    def div(other) = divmod(other).first
    def %(other) = divmod(other).last

    def coerce(other) = [Polynomial.from_expr(ring, other), self]

    def rop(op, left)
      left = Expression.lift(left)
      scalar = scalar_in_base(left)
      return scalar.public_send(op, self) if scalar
      Polynomial.from_expr(ring.join(Polynomial.ring_for(ring.base, left)), left, promote: true).public_send(op, self)
    end

    # A parameter expression such as 1/(2*a) over Frac(QQ[a])[x] is a
    # constant of the ring, not a polynomial in a new variable a.
    def scalar_in_base(expr)
      return nil if expr.is_a?(Num) || expr.variables.empty? || !(expr.variables & ring.vars).empty?
      return nil unless (ring.base.is_a?(FractionField) || ring.base.is_a?(PolynomialRing)) && ring.base.include?(expr)
      Polynomial.new(ring, { Array.new(ring.vars.size, 0) => expr })
    end

    def ==(other)
      case other
      when Polynomial then to_expr.simplify == other.to_expr.simplify
      when Expression, Numeric, Symbol
        begin
          self == Polynomial.from_expr(ring.join(Polynomial.ring_for(ring.base, Expression.lift(other))), other)
        rescue DomainError
          false
        end
      else false
      end
    end
    alias eql? ==
    def hash = [Polynomial, to_expr.simplify].hash

    # ---- calculus / evaluation --------------------------------------------

    # Antiderivative in +var+, over the fraction field of the base if needed.
    def integrate(var = nil)
      var ||= ring.vars.first
      i = var_index(var)
      target = ring.base.field? ? ring : ring.base.fraction_field[*ring.vars]
      result = {}
      terms.each do |e, c|
        d = e.dup
        d[i] += 1
        result[d] = Scalar.div(c, Num.new(d[i]))
      end
      Polynomial.new(target, result)
    end

    def derivative(var = nil)
      var ||= ring.vars.first
      i = ring.index(var.is_a?(Var) ? var.name : var.to_sym) or raise ArgumentError, "#{var} is not a variable of #{ring}"
      result = {}
      terms.each do |e, c|
        next if e[i].zero?
        d = e.dup
        d[i] -= 1
        result[d] = Scalar.add(result[d] || Num.new(0), Scalar.mul(Num.new(e[i]), c))
      end
      Polynomial.new(ring, result)
    end
    alias diff derivative

    def call(*args, **bindings) = to_expr.call(*args, **bindings)
    def to_proc = to_expr.to_proc
    def subs(*args) = to_expr.subs(*args)

    # ---- gcd --------------------------------------------------------------

    # Monic gcd over a field; primitive gcd with positive leading coefficient
    # over ZZ. Works in any number of variables over ZZ and QQ.
    def gcd(other) = combine(other, :gcd) { |a, b| PolyGCD.gcd(a, b) }
    def lcm(other) = combine(other, :lcm) { |a, b| PolyGCD.lcm(a, b) }

    # [g, s, t] with s*self + t*other == g (univariate over a field).
    def xgcd(other) = combine(other, :xgcd) { |a, b| PolyGCD.xgcd(a, b) }

    def coprime?(other) = gcd(other).constant?

    # Resultant with respect to a variable, as the determinant of the
    # Sylvester matrix [GCL92, ch. 7], [CLO15, §3.6] (keys: MANUAL.md, Sources).
    def resultant(other, var = nil)
      combine(other, :resultant) do |a, b|
        x = var || a.ring.vars.first
        m = a.degree(x)
        n = b.degree(x)
        return a.ring.zero if m.negative? || n.negative?
        return a.ring.one if m.zero? && n.zero?
        size = m + n
        ac = (0..m).map { |k| a.coefficient_in(x, k).to_expr }
        bc = (0..n).map { |k| b.coefficient_in(x, k).to_expr }
        rows = []
        n.times { |i| rows << Array.new(size) { |j| (j - i).between?(0, m) ? ac[m - (j - i)] : Num.new(0) } }
        m.times { |i| rows << Array.new(size) { |j| (j - i).between?(0, n) ? bc[n - (j - i)] : Num.new(0) } }
        numeric = rows.flatten.all? { |e| Scalar.numeric?(e) }
        # polynomial entries by evaluation and interpolation (PolyMatrix):
        # the cofactor expansion is factorial in the size, and the dispersion
        # of a degree-five term (a 10 x 10 Sylvester matrix) took two minutes
        # (third review, section 5)
        det = numeric ? Elimination.det(rows) : (PolyMatrix.det(rows) || Elimination.cofactor_det(rows).expand)
        Polynomial.from_expr(a.ring, det)
      end
    end

    def discriminant(var = nil)
      x = var || ring.vars.first
      n = degree(x)
      raise ArgumentError, "discriminant needs degree >= 1" if n < 1
      res = resultant(derivative(x), x)
      sign = (n * (n - 1) / 2).even? ? 1 : -1
      (res * sign).exact_div(Polynomial.constant(ring, 1) * leading_coefficient_in(x))
    end

    # ---- factorization ----------------------------------------------------

    # Factorization over ZZ or QQ into irreducibles.
    #
    #   QQ[:x].(:x**4 - 1).factor   # => (-1 + x)*(1 + x)*(1 + x**2)
    def factor(extension: nil)
      return FiniteFieldFactor.factor(self) if ring.base.is_a?(FiniteField)
      return Factor.factor(self) if extension.nil?
      field = extension.is_a?(AlgebraicField) ? extension : Algebraic.adjoin(extension)
      Algebraic.factor_over(self, field)
    end

    def irreducible? = factor.irreducible?

    # [[squarefree part, multiplicity], ...] such that self = unit * prod part**mult.
    def squarefree_decomposition
      f = factor
      groups = f.factors.group_by(&:last).sort
      groups.map { |m, parts| [parts.map(&:first).reduce(ring.one) { |acc, g| acc * g }, m] }
    end

    def squarefree_part = squarefree_decomposition.map(&:first).reduce(ring.one) { |acc, g| acc * g }

    # Rational roots (with multiplicity) of a univariate polynomial.
    def roots
      univariate!
      factor.factors.flat_map do |g, m|
        next [] unless g.degree == 1
        if ring.base.is_a?(FiniteField)
          [Scalar.div(Scalar.neg(g.coeff(0)), g.coeff(1))] * m
        else
          [Simplify.normalize_number(Rational(-g.coeff(0).value, g.coeff(1).value))] * m
        end
      end.sort_by { |r| r.is_a?(Num) && r.value.respond_to?(:to_i) ? [r.value.to_i, ""] : [0, r.to_s] } # a GF(p^n) element has no integer
    end

    # ---- coefficients in one variable -------------------------------------

    # The coefficient of x**k as a polynomial in the remaining variables.
    def coefficient_in(var, k)
      i = var_index(var)
      picked = terms.select { |e, _| e[i] == k }.to_h { |e, c| [e.dup.tap { |d| d[i] = 0 }, c] }
      Polynomial.new(ring, picked)
    end

    def leading_coefficient_in(var) = coefficient_in(var, degree(var))

    # Multiply by var**k.
    def shift(var, k)
      i = var_index(var)
      Polynomial.new(ring, terms.to_h { |e, c| [e.dup.tap { |d| d[i] += k }, c] })
    end

    # Same polynomial times the lcm of its coefficient denominators.
    def clear_denominators
      lcm = terms.values.reduce(1) { |l, c| c.is_a?(Num) && c.value.is_a?(Rational) ? l.lcm(c.value.denominator) : l }
      lcm == 1 ? self : self * lcm
    end

    def self.constant(ring, value) = Polynomial.new(ring, { Array.new(ring.vars.size, 0) => Num.new(value) })

    def monic
      return self if zero?
      self * Scalar.div(Num.new(1), leading_coefficient)
    end

    # gcd of the numeric coefficients (ZZ or QQ coefficients only).
    def content
      values = terms.values.map { |c| c.is_a?(Num) ? c.value : raise(DomainError, "content needs numeric coefficients") }
      return 0 if values.empty?
      values.reduce { |g, v| Polynomial.rational_gcd(g, v) }.abs
    end

    def var_index(var)
      ring.index(var.is_a?(Var) ? var.name : var.to_sym) or raise ArgumentError, "#{var} is not a variable of #{ring}"
    end

    def self.rational_gcd(a, b)
      a, b = Rational(a), Rational(b)
      Simplify.normalize_number(Rational(a.numerator.gcd(b.numerator), a.denominator.lcm(b.denominator)))
    end

    # Integer-coefficient polynomial with content 1 and positive leading coefficient.
    def primitive_part
      return self if zero?
      c = content
      c = -c if Scalar.negative?(leading_coefficient)
      Polynomial.new(ring, terms.transform_values { |v| Num.new(Rational(v.value, c)) })
    end

    # ---- conversion -------------------------------------------------------

    def to_ring(other_ring)
      return self if other_ring == ring
      Polynomial.from_expr(other_ring, to_expr)
    end

    def to_expr
      return Num.new(0) if zero?
      terms.map { |e, c| e.all?(&:zero?) ? c : Mul.new(c, monomial(e)) }
           .reduce { |sum, t| Add.new(sum, t) }
           .simplify
    end

    def to_s = to_expr.to_s
    def inspect = to_s

    # Ring for an expression's undeclared variables (declared ones are parameters).
    def self.ring_for(base, expr)
      free = expr.variables.reject { |v| RCAS.assumption(v) }
      free.empty? ? base : PolynomialRing.new(base, free)
    end

    protected

    def univariate!
      raise NotImplementedError, "this operation needs a univariate ring, got #{ring}" unless ring.univariate?
    end

    private

    def monomial(exps)
      factors = ring.vars.zip(exps).reject { |_, k| k.zero? }.map { |v, k| Simplify.power_node(Var.new(v), k) }
      Simplify.product_node(factors)
    end

    def merge(a, b)
      a.merge(b) { |_, x, y| Scalar.add(x, y) }
    end

    # Bring +other+ into a common ring with self, or fall back to plain
    # Expression arithmetic when it is not a polynomial (e.g. sin(x)).
    def combine(other, op)
      case other
      when Polynomial
        target = ring.join(other.ring)
        yield to_ring(target), other.to_ring(target)
      when Expression, Numeric, Symbol
        expr = Expression.lift(other)
        scalar = scalar_in_base(expr)
        return yield self, scalar if scalar
        target = ring.join(Polynomial.ring_for(ring.base, expr))
        begin
          poly = Polynomial.from_expr(target, expr, promote: true)
        rescue DomainError
          raise if %i[divmod gcd lcm xgcd resultant].include?(op)
          return to_expr.public_send(op, expr)
        end
        target = target.join(poly.ring)
        yield to_ring(target), poly.to_ring(target)
      else
        raise TypeError, "can't combine #{self.class} with #{other.class}"
      end
    end
  end
end
