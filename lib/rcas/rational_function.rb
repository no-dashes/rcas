# frozen_string_literal: true

module RCAS
  # Rational functions as expressions: numerator and denominator of the
  # normal form, partial fractions, and polynomial gcd / lcm / division
  # without building a ring by hand.
  #
  #   numer(1/x + 1/(x + 1))            # => 1 + 2*x
  #   apart(1/(x**2 - 1), x)            # => -1/(2*(1 + x)) + 1/(2*(-1 + x))
  #   gcd(x**2 - 1, x**2 + 2*x + 1)     # => 1 + x
  #   quo(x**3 - 1, x - 1)              # => 1 + x + x**2
  #
  # Rational-coefficient input goes through Fraction.as_fraction (one
  # numerator over one denominator, gcd cancelled). Anything else is split
  # syntactically: factors with negative exponents form the denominator.
  #
  # Sources: the partial fraction decomposition is the classical one in
  # [Bro05, §2.1] (see MANUAL.md, Sources): split over pairwise coprime
  # denominators with the extended Euclidean algorithm, then expand each
  # numerator p-adically in its irreducible factor. Denominators are
  # factored over QQ (factor.rb), so no algebraic numbers are introduced.
  module RationalFunction
    module_function

    # ---- numerator and denominator ----------------------------------------

    def numer(expr) = numer_denom(expr).first
    def denom(expr) = numer_denom(expr).last

    # [numerator, denominator] with integer coefficients, denominator with a
    # positive leading coefficient, when the expression is a rational
    # function over QQ; otherwise the syntactic split of the simplified form.
    def numer_denom(expr)
      expr = expr.to_expr if expr.is_a?(Polynomial)
      expr = Expression.lift(expr)
      if (pair = Fraction.as_fraction(expr))
        return integral_pair(*pair).map(&:to_expr)
      end
      coeff, factors = Simplify.factorize(expr, simplify: true)
      up = factors.reject { |_, e| Simplify.negative?(e) }
      down = factors.select { |_, e| Simplify.negative?(e) }.transform_values { |e| Simplify.multiply_exponents(e, -1) }
      num_c, den_c = coeff.is_a?(Rational) ? [coeff.numerator, coeff.denominator] : [coeff, 1]
      [Simplify.rebuild_product(num_c, up), Simplify.rebuild_product(den_c, down)]
    end

    # Scale two polynomials over QQ to integer coefficients with no common
    # integer factor and a positive leading coefficient in the denominator.
    def integral_pair(num, den)
      scale = [num, den].flat_map { |p| p.terms.values.map { |c| c.value.is_a?(Rational) ? c.value.denominator : 1 } }.reduce(1, :lcm)
      num *= scale
      den *= scale
      g = Polynomial.rational_gcd(num.content, den.content)
      g = -g if Scalar.negative?(den.leading_coefficient)
      [num * Rational(1, g), den * Rational(1, g)]
    end

    # ---- partial fractions ------------------------------------------------

    # Partial fraction decomposition over QQ in one indeterminate; other
    # indeterminates are treated as parameters.
    def apart(expr, var = nil)
      expr = expr.to_expr if expr.is_a?(Polynomial)
      expr = Expression.lift(expr)
      # a constant is its own decomposition (A11)
      return expr.simplify if expr.constant? && var.nil? && (expr.simplify.is_a?(Num))
      pair = Fraction.as_fraction(expr)
      raise DomainError, "apart: #{expr} is not a rational function with rational coefficients" unless pair
      num, den = pair
      vars = num.ring.vars
      x = apart_variable(expr, vars, var)
      return expr.simplify if den.constant?

      others = vars - [x]
      ring = others.empty? ? QQ[x] : QQ[*others].fraction_field[x]
      factorization = den.factor
      unit = factorization.unit
      numerator = (num * Scalar.div(Num.new(1), unit)).to_ring(ring)
      factors = factorization.factors.map { |p, e| [p.to_ring(ring), e] }

      polynomial, numerator = numerator.divmod(factors.reduce(ring.one) { |acc, (p, e)| acc * p**e })
      parts = []
      factors.each_with_index do |(p, e), i|
        if i == factors.size - 1
          parts << [numerator, p, e]
          break
        end
        a = p**e
        b = factors[(i + 1)..].reduce(ring.one) { |acc, (q, k)| acc * q**k }
        _, s, t = a.xgcd(b) # s*a + t*b = 1
        qa, ra = (numerator * t).divmod(a)
        qb, rb = (numerator * s).divmod(b)
        polynomial += qa + qb
        parts << [ra, p, e]
        numerator = rb
      end

      terms = []
      terms << [polynomial.to_expr, false] unless polynomial.zero?
      parts.each do |c, p, e|
        expansion = []
        e.downto(1) do |k|
          c, c0 = c.divmod(p)
          expansion << [c0, k] unless c0.zero?
        end
        expansion.reverse_each do |c0, k|
          n, d = numer_denom(c0.to_expr) # (a/2 + b/2) => (a + b)/2
          term = (n / (d * Simplify.power_node(p.to_expr, k))).simplify
          coeff, factors = Simplify.factorize(term)
          negative = Simplify.negative?(coeff)
          terms << [negative ? Simplify.rebuild_product(-coeff, factors) : term, negative]
        end
      end
      return Num.new(0) if terms.empty?
      Simplify.sum_tree(terms)
    end

    def apart_variable(expr, vars, var)
      if var
        v = Coefficients.variable(var)
        raise ArgumentError, "apart: #{v} does not occur in #{expr}" unless vars.include?(v.name)
        return v.name
      end
      return vars.first if vars.size == 1
      raise ArgumentError, "apart: #{expr} has several indeterminates (#{vars.join(', ')}); name one, e.g. apart(f, #{vars.first})"
    end

    # ---- gcd, lcm, division -----------------------------------------------

    def gcd(f, g) = ring_operation(f, g, :gcd)
    def lcm(f, g) = ring_operation(f, g, :lcm)

    # Quotient and remainder of polynomial division. With several
    # indeterminates, x names the one to divide by; the others are parameters.
    def divmod(f, g, x = nil)
      return f.divmod(g) if numeric?(f) && numeric?(g)
      ring = division_ring(f, g, x)
      q, r = ring.call(f).divmod(ring.call(g))
      [q, r].map { |p| polynomial_result(f, g, p) }
    end

    def quo(f, g, x = nil) = divmod(f, g, x).first
    def rem(f, g, x = nil) = divmod(f, g, x).last

    def ring_operation(f, g, op)
      if numeric?(f) && numeric?(g)
        a, b = [f, g].map { |v| v.is_a?(Num) ? v.value : v }
        return a.public_send(op, b) if a.is_a?(Integer) && b.is_a?(Integer)
        return op == :gcd ? Polynomial.rational_gcd(a, b) : Rational(a) * Rational(b) / Polynomial.rational_gcd(a, b)
      end
      first, second = f.is_a?(Polynomial) || !numeric?(f) ? [f, g] : [g, f]
      first = Expression.lift(first).to_poly unless first.is_a?(Polynomial)
      polynomial_result(f, g, first.public_send(op, second))
    end

    def division_ring(f, g, x)
      polys = [f, g].map { |e| e.is_a?(Polynomial) ? e : (numeric?(e) ? nil : Expression.lift(e).to_poly) }.compact
      base = polys.map { |p| p.ring.base }.reduce(QQ) { |acc, b| acc.join(b) }
      vars = polys.flat_map { |p| p.ring.vars }.uniq.sort
      if x
        x = Coefficients.variable(x).name
        raise ArgumentError, "#{x} does not occur in #{f} or #{g}" unless vars.include?(x)
        others = vars - [x]
        others.empty? ? base[x] : base[*others].fraction_field[x]
      else
        base[*vars]
      end
    end

    def polynomial_result(f, g, poly)
      f.is_a?(Polynomial) || g.is_a?(Polynomial) ? poly : poly.to_expr
    end

    def numeric?(v) = v.is_a?(Numeric) || (v.is_a?(Num) && !v.value.is_a?(Complex) && !v.finite_field?)
  end

  class Expression
    def numer = RationalFunction.numer(self)
    def denom = RationalFunction.denom(self)
    def apart(var = nil) = RationalFunction.apart(self, var)
    def gcd(other) = RationalFunction.gcd(self, other)
    def lcm(other) = RationalFunction.lcm(self, other)
    def divmod(other, var = nil) = RationalFunction.divmod(self, other, var)
    def quo(other, var = nil) = RationalFunction.quo(self, other, var)
    def rem(other, var = nil) = RationalFunction.rem(self, other, var)
  end
end
