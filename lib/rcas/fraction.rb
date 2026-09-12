# frozen_string_literal: true

module RCAS
  # Rational-function normalisation: one numerator over one denominator with
  # the polynomial gcd cancelled.
  #
  #   (1/(a**2*(-1 - 1/a)) + 1/a).cancel   # => 1/(1 + a)
  #   ((:x**2 - 1)/(:x - 1)).cancel        # => 1 + x
  module Fraction
    module_function

    # => [numerator, denominator] as Polynomials over QQ in all variables, or
    # nil when the expression is not a rational function with rational
    # coefficients.
    def as_fraction(expr, vars = nil)
      vars = (vars || []) | expr.variables
      return nil if vars.empty?
      ring = QQ[*vars]
      constant, table = Expand.table(expr)
      return nil unless rational?(constant)
      num = ring.call(constant)
      den = ring.one
      table.each do |factors, coeff|
        return nil unless rational?(coeff)
        n = ring.call(coeff)
        d = ring.one
        factors.each do |base, exp|
          return nil unless exp.is_a?(Integer)
          bn, bd = begin
            [ring.call(base), ring.one]
          rescue DomainError
            return nil unless base.is_a?(Add) || base.is_a?(Sub) # nested fraction inside a sum
            inner = as_fraction(base) or return nil
            inner.map { |q| q.to_ring(ring) }
          end
          if exp.positive?
            n *= bn**exp
            d *= bd**exp
          else
            n *= bd**(-exp)
            d *= bn**(-exp)
          end
        end
        num = num * d + n * den
        den *= d
      end
      g = num.gcd(den)
      [num.exact_div(g), den.exact_div(g)]
    end

    def cancel(expr)
      pair = as_fraction(expr) or return expr.simplify
      num, den = pair
      lc = den.leading_coefficient
      num *= Scalar.div(Num.new(1), lc)
      den = den.monic
      (den.constant? ? num.to_expr : num.to_expr / den.to_expr).simplify
    end

    def rational?(v) = v.is_a?(Integer) || v.is_a?(Rational)

    # Clear square roots from denominators: 1/(1 + sqrt(2)) => -1 + sqrt(2).
    # Handles denominators that are sums of a rational and one surd term.
    def rationalize(expr)
      if (exact = Algebraic.exact(expr))
        return exact.to_expr.simplify
      end
      _, table = Expand.table(expr)
      surd_denominators = table.each_key.flat_map do |factors|
        factors.select { |base, exp| exp.is_a?(Integer) && exp.negative? && surd_sum?(base) }.map(&:first)
      end.uniq
      return expr.simplify if surd_denominators.empty?
      result = expr
      surd_denominators.each do |den|
        conj = conjugate(den)
        norm = (den * conj).expand
        return expr.simplify unless norm.is_a?(Num) && !norm.zero?
        constant, table = Expand.table(result)
        result = Num.new(constant)
        table.each do |factors, coeff|
          e = factors[den]
          if e.is_a?(Integer) && e.negative?
            k = -e
            rest = factors.reject { |b, _| b == den }
            result += (Simplify.rebuild_product(coeff.quo(norm.value**k), rest) * conj**k).expand
          else
            result += Simplify.rebuild_product(coeff, factors)
          end
        end
      end
      result.simplify
    end

    def surd_sum?(base)
      return false unless base.is_a?(Add) || base.is_a?(Sub)
      constant, terms = Simplify.termize(base)
      terms.size == 1 && terms.each_key.all? { |f| f.all? { |b, e| b.is_a?(Num) && e.is_a?(Rational) } } && (constant.is_a?(Integer) || constant.is_a?(Rational))
    end

    def conjugate(base)
      constant, terms = Simplify.termize(base)
      Simplify.rebuild_sum(constant, terms.transform_values { |c| -c })
    end
  end
end
