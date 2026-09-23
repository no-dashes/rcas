# frozen_string_literal: true

module RCAS
  # product(f, k, a, b): an unevaluated product, returned when no closed form is known.
  class Product < Expression
    attr_reader :term, :var, :from, :to

    def initialize(term, var, from, to)
      @term = term
      @var = var
      @from = from
      @to = to
      freeze
    end

    def bound_variable = var
    def children = [term, var, from, to]
    def rebuild(term, var, from, to) = Product.new(term, var, from, to)
    def to_sexp = [:product, term.to_sexp, var.to_sexp, from.to_sexp, to.to_sexp]
  end

  # Symbolic products.
  #
  #   product(k, k, 1, n)          # => n!
  #   product(2*k, k: 1..n)        # => 2**n*n!
  #   product(2*k - 1, k: 1..n)    # => 2**n*gamma(1/2 + n)/pi**(1/2)
  #   product(a**k, k: 1..n)       # => a**(n/2 + n**2/2)
  #
  # A term is split into factors: constants give powers, a**u(k) gives
  # a**sum(u), and a polynomial in k that factors into linear factors over QQ
  # gives ratios of factorials (integer shifts) or gamma values (rational
  # shifts), since prod_{k=a}^{b} (k + r) = gamma(b + r + 1) / gamma(a + r).
  # A linear factor whose root is a parameter gets the same ratio, under the
  # generic assumption that the root is not inside the range.
  # Products with integer bounds that fit no pattern are multiplied out.
  #
  # Sources (keys: MANUAL.md, Sources): [GKP94, §5.5] for the gamma function
  # and rising factorials; the rest is textbook algebra.
  module Products
    module_function

    def product(f, k, from, to)
      f = Expression.lift(f).simplify
      k = Expression.lift(k)
      # -1 + 3 is the bound 2 (what subs leaves), and 5/2 is no bound at all:
      # a product steps over integers, as a sum does (fourth review, S11)
      from = Expression.lift(from).simplify
      to = Expression.lift(to).simplify
      raise ArgumentError, "product: the index must be a symbol, got #{k}" unless k.is_a?(Var)
      [from, to].each do |b|
        next unless b.is_a?(Num) && b.value.is_a?(Numeric) && b.value.real? && b.value != b.value.round
        raise ArgumentError, "product: the bounds must be integers, got #{b}"
      end
      count = (to - from + 1).simplify
      return (f**count).simplify unless f.variables.include?(k.name)
      # a factor with no value makes a product with none: 1/k at k = 0
      return UNDEFINED if Summation.pole_in_range?(f, k, from, to)
      return Product.new(f, k, from, to) if Summation.pole_past_start?(f, k, from, to)
      return Product.new(f, k, from, to) if Limits.infinite?(to) || Limits.infinite?(from)

      closed_form(f, k, from, to, count) || direct(f, k, from, to) || Product.new(f, k, from, to)
    end

    def depends?(e, k) = e.variables.include?(k.name)

    def closed_form(f, k, from, to, count)
      f = f.cancel if f.is_a?(Add) || f.is_a?(Sub) # (k + 1)/k rather than 1 + 1/k
      coeff, factors = Simplify.factorize(f)
      result = Num.new(coeff)**count
      factors.each do |base, e|
        exponent = Expression.lift(e)
        if !depends?(base, k) && !depends?(exponent, k)
          result *= base**(exponent * count)
        elsif !depends?(base, k) # a**u(k) = a**sum(u)
          s = Summation.sum(exponent, k, from, to)
          return nil if s.is_a?(Sum)
          result *= Simplify.power_node(base, s)
        elsif e.is_a?(Integer) && (g = polynomial_product(base, k, from, to, count))
          result *= g**e
        else
          return nil
        end
      end
      result.simplify
    end

    # prod p(k) for p with linear factors over QQ, else nil.
    def polynomial_product(base, k, from, to, count)
      poly = begin
        QQ[k.name].call(base)
      rescue DomainError
        return parametric_product(base, k, from, to, count)
      end
      factorization = poly.factor
      result = factorization.unit**count
      factorization.factors.each do |g, m|
        return nil unless g.degree == 1
        a = g.coeff(1).value
        b = g.coeff(0).value
        result *= (Num.new(a)**count)**m unless a == 1
        ratio = gamma_ratio(Rational(b, a), from, to) or return nil
        result *= ratio**m
      end
      result
    end

    # prod_{k=from}^{to} (k + r) = gamma(to + r + 1) / gamma(from + r); with factorials
    # for integer r. Zero when a factor vanishes inside the range.
    def gamma_ratio(r, from, to)
      lower = (from + Num.new(r)).simplify # the first factor
      if lower.is_a?(Num) && lower.value.is_a?(Integer) && lower.value <= 0
        upper = (to + Num.new(r)).simplify
        return Num.new(0) if upper.is_a?(Num) && upper.value >= 0
        # a symbolic upper bound reaches the zero only from some n on:
        # product(k - 3, k, 1, n) is 1, -2, 2 at n = 0, 1, 2 and was 0 for
        # every n, and product(k - 1, k, 1, n) is the empty product 1 at
        # n = 0 (fourth review); no single closed form says both
        return nil unless upper.is_a?(Num)
      end
      if r.denominator == 1
        RCAS.factorial((to + Num.new(r)).simplify) / RCAS.factorial((from + Num.new(r) - 1).simplify)
      else
        RCAS.gamma((to + Num.new(r) + 1).simplify) / RCAS.gamma(lower)
      end
    end

    # A linear factor whose root is a parameter, a - k: the same gamma ratio.
    # Whether the root falls inside the range cannot be decided, so this is
    # the generic answer, as everywhere else where a symbolic quantity would
    # have to be zero for it to be wrong.
    def parametric_product(base, k, from, to, count)
      coefficients = Solve.polynomial_coefficients(base.expand, k)
      return nil unless coefficients && coefficients.size == 2
      lead = coefficients.last
      return nil if depends?(lead, k) || Scalar.zero?(lead)
      r = (coefficients.first / lead).cancel
      ((lead**count) * RCAS.gamma((to + r + 1).simplify) / RCAS.gamma((from + r).simplify)).simplify
    rescue DomainError, NotImplementedError, RCAS::Unsupported, ZeroDivisionError
      nil
    end

    # Integer bounds: multiply out (up to 1000 factors).
    def direct(f, k, from, to)
      return nil unless from.is_a?(Num) && to.is_a?(Num) && from.value.is_a?(Integer) && to.value.is_a?(Integer)
      return Num.new(1) if to.value < from.value
      return nil if to.value - from.value > 1000
      (from.value..to.value).reduce(Num.new(1)) { |acc, i| (acc * f.subs(k => i)).simplify }
    end
  end
end
