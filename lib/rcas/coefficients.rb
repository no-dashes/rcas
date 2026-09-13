# frozen_string_literal: true

module RCAS
  # Polynomial structure of expressions: degree, leading and trailing
  # coefficient, single coefficients, the coefficient list, and collecting
  # in one indeterminate.
  #
  #   degree((x + 1)**3, x)             # => 3
  #   coeff(a*x**2 + b*x + c, x, 2)     # => a
  #   collect((x + y)**2 + a*x, x)      # => y**2 + (a + 2*y)*x + x**2
  #
  # Everything works on Expand.table, so the input need not be expanded and
  # the coefficients come back in canonical form. Without an indeterminate
  # the functions look at all indeterminates of the expression: `degree` is
  # the total degree, `lcoeff`/`tcoeff` belong to the last/first term of the
  # canonical sum, `coeffs` lists the coefficients in that order.
  #
  # An expression that is not a polynomial in the indeterminate (x inside a
  # function, in a denominator, with a fractional or symbolic exponent)
  # raises DomainError rather than guessing.
  module Coefficients
    module_function

    # Highest exponent; -1 for the zero polynomial (as Polynomial#degree).
    def degree(expr, var = nil)
      terms = terms_in(expr, var)
      terms.empty? ? -1 : terms.map(&:first).max
    end

    # Lowest exponent; -1 for the zero polynomial.
    def ldegree(expr, var = nil)
      terms = terms_in(expr, var)
      terms.empty? ? -1 : terms.map(&:first).min
    end

    # Coefficient of the highest power of var (last term of the canonical sum
    # when var is nil).
    def lcoeff(expr, var = nil)
      terms = terms_in(expr, var)
      return Num.new(0) if terms.empty?
      var ? coefficient(terms, terms.map(&:first).max) : terms.last[1]
    end

    # Coefficient of the lowest power of var (first term of the canonical sum
    # when var is nil).
    def tcoeff(expr, var = nil)
      terms = terms_in(expr, var)
      return Num.new(0) if terms.empty?
      var ? coefficient(terms, terms.map(&:first).min) : terms.first[1]
    end

    # coeff(f, x, k) or coeff(f, x**k): the coefficient of x**k.
    def coeff(expr, var, k = 1)
      var, k = split_power(var, k)
      coefficient(terms_in(expr, var), k)
    end

    # Coefficients of x**0, x**1, ..., x**degree (zeros included), or the
    # coefficients of the canonical sum's terms when var is nil.
    def coeffs(expr, var = nil)
      terms = terms_in(expr, var)
      return terms.map(&:last) unless var
      return [] if terms.empty?
      (0..terms.map(&:first).max).map { |k| coefficient(terms, k) }
    end

    # Sum of coeff(f, x, k) * x**k over the exponents that occur, ascending.
    def collect(expr, var)
      var = variable(var)
      terms = terms_in(expr, var)
      return Num.new(0) if terms.empty?
      parts = terms.map(&:first).uniq.sort.map { |k| collected_term(coefficient(terms, k), var, k) }
      Simplify.sum_tree(parts)
    end

    # ---- internals --------------------------------------------------------

    # With var: [[exponent of var, coefficient expression], ...] sorted by
    # exponent, one entry per exponent. Without var: one entry per term of
    # the canonical sum, [total degree, coefficient], in canonical order.
    def terms_in(expr, var)
      expr = expr.to_expr if expr.respond_to?(:to_expr)
      expr = Expression.lift(expr)
      var = variable(var) if var
      names = var ? [var.name] : expr.variables
      constant, table = Expand.table(expr)
      grouped = Hash.new { |h, k| h[k] = [0, {}] }
      grouped[var ? 0 : {}] = [constant, {}] unless constant.zero?
      table.each do |factors, c|
        exponents = {}
        rest = {}
        factors.each do |base, exp|
          if base.is_a?(Var) && names.include?(base.name)
            polynomial_exponent!(expr, base, exp)
            exponents[base] = exp
          else
            offending = base.variables & names
            raise DomainError, "#{expr} is not a polynomial in #{offending.first}" unless offending.empty?
            rest[base] = exp
          end
        end
        key = var ? exponents.fetch(var, 0) : exponents
        entry = grouped[key]
        if rest.empty?
          entry[0] += c
        else
          Expand.add_term(entry[1], rest, c)
        end
      end
      if var
        grouped.sort.map { |k, (c, t)| [k, Simplify.rebuild_sum(c, t)] }
      else
        grouped.sort_by { |exponents, _| Simplify.sort_key(Simplify.rebuild_product(1, exponents)) }
               .map { |exponents, (c, t)| [exponents.values.sum, Simplify.rebuild_sum(c, t)] }
      end
    end

    def polynomial_exponent!(expr, base, exp)
      return if exp.is_a?(Integer) && exp >= 0
      raise DomainError, "#{expr} is not a polynomial in #{base}"
    end

    def coefficient(terms, k)
      entry = terms.assoc(k)
      entry ? entry[1] : Num.new(0)
    end

    def variable(var)
      v = Expression.lift(var)
      raise ArgumentError, "#{var} is not an indeterminate" unless v.is_a?(Var)
      v
    end

    def split_power(var, k)
      k = k.value if k.is_a?(Num) # literals arrive as Num inside hold { }
      v = var.is_a?(Symbol) ? var : Expression.lift(var)
      if v.is_a?(Pow) && v.exponent.is_a?(Num) && v.exponent.value.is_a?(Integer)
        [variable(v.base), v.exponent.value]
      else
        raise ArgumentError, "coeff: the exponent must be an integer" unless k.is_a?(Integer)
        [variable(v), k]
      end
    end

    # [expression, negative?] for one term of a collected sum.
    def collected_term(coefficient, var, k)
      return [coefficient, false] if k.zero?
      power = { var => k }
      case coefficient
      when Add, Sub then [Mul.new(coefficient, Simplify.rebuild_product(1, power)), false]
      else
        c, factors = Simplify.factorize(coefficient)
        negative = Simplify.sign_negative?(c)
        [Simplify.rebuild_product(negative ? -c : c, factors.merge(power)), negative]
      end
    end
  end

  class Expression
    def degree(var = nil) = Coefficients.degree(self, var)
    def ldegree(var = nil) = Coefficients.ldegree(self, var)
    def lcoeff(var = nil) = Coefficients.lcoeff(self, var)
    def tcoeff(var = nil) = Coefficients.tcoeff(self, var)
    def coeff(var, k = 1) = Coefficients.coeff(self, var, k)
    def coeffs(var = nil) = Coefficients.coeffs(self, var)
    def collect(var) = Coefficients.collect(self, var)
  end
end
