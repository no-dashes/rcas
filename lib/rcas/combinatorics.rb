# frozen_string_literal: true

module RCAS
  # factorial, binomial and gamma: exact values, the (k+1)!/k! = k+1
  # cancellation used by simplify and Gosper, and the classical power series
  # (exp, sin, cos, sinh, cosh, log, atan, the binomial theorem) that turn
  # infinite hypergeometric sums into closed forms.
  module Combinatorics
    module_function

    # Fibonacci numbers by fast doubling; F(-n) = (-1)**(n + 1) F(n).
    def fibonacci(n)
      return (n.even? ? -1 : 1) * fibonacci(-n) if n.negative?
      a, b = 0, 1 # F(k), F(k + 1)
      n.bit_length.downto(1) do |i|
        c = a * (2 * b - a) # F(2k)
        d = a * a + b * b   # F(2k + 1)
        a, b = n[i - 1] == 1 ? [d, c + d] : [c, d]
      end
      a
    end

    def factorial_value(n)
      case n
      when Integer then n >= 0 ? Num.new((1..n).reduce(1, :*)) : nil
      when Rational then gamma_value(n + 1)
      when Float then Num.new(Math.gamma(n + 1))
      end
    end

    # gamma(n) for integers and half-integers exactly, floats numerically.
    def gamma_value(v)
      case v
      when Integer then v >= 1 ? Num.new((1..v - 1).reduce(1, :*)) : nil
      when Rational
        return nil unless v.denominator == 2
        # gamma(n + 1/2) = (2n)! / (4**n n!) sqrt(pi), extended downwards by gamma(x) = gamma(x + 1) / x
        n = (v - Rational(1, 2)).to_i
        if n >= 0
          c = Rational((1..2 * n).reduce(1, :*), 4**n * (1..n).reduce(1, :*))
        else
          c = Rational(1)
          (n...0).each { |j| c /= (j + Rational(1, 2)) }
        end
        (Num.new(c) * RCAS.sqrt(PI)).simplify
      when Float then Num.new(Math.gamma(v))
      end
    end

    def binomial_value(n, k)
      return nil unless k.is_a?(Num) && k.value.is_a?(Integer)
      kk = k.value
      return Num.new(0) if kk.negative?
      return Num.new(1) if kk.zero?
      return n if kk == 1
      if n.is_a?(Num) && n.value.is_a?(Integer)
        nn = n.value
        return Num.new(0) if nn >= 0 && kk > nn
        return Num.new((0...kk).reduce(1) { |acc, i| acc * (nn - i) } / (1..kk).reduce(1, :*))
      end
      # binomial(1/2, 3) is a number too: the falling factorial over k!
      if n.is_a?(Num) && (n.value.is_a?(Rational) || n.value.is_a?(Float))
        falling = (0...kk).reduce(1) { |acc, i| acc * (n.value - i) }
        return Num.new(Simplify.normalize_number(falling / (1..kk).reduce(1, :*)))
      end
      nil
    end

    # binomial(n, k) with a numeric k as the polynomial n(n-1)...(n-k+1)/k!
    def expand_binomial(n, k)
      return nil unless k.is_a?(Num) && k.value.is_a?(Integer) && k.value >= 0
      kk = k.value
      product = (0...kk).reduce(Num.new(1)) { |acc, i| acc * (n - i) }
      (product / (1..kk).reduce(1, :*)).expand
    end

    # Replace binomials by factorials (for ratios of consecutive terms).
    def to_factorials(expr)
      expr = expr.map_children { |c| to_factorials(c) }
      if expr.is_a?(Fn) && expr.name == :binomial
        n, k = expr.args
        return Fn.new(:factorial, [n]) / (Fn.new(:factorial, [k]) * Fn.new(:factorial, [(n - k).simplify]))
      end
      expr
    end

    # Merge factorials whose arguments differ by an integer:
    # (k + 2)! / k!  =>  (k + 1)(k + 2). Mutates +factors+ (base => exponent).
    def merge_factorials(factors)
      loop do
        facts = factors.keys.select { |b| b.is_a?(Fn) && b.name == :factorial }
        pair = nil
        facts.combination(2).each do |a, b|
          d = (a.args.first - b.args.first).simplify
          next unless d.is_a?(Num) && d.value.is_a?(Integer) && !d.zero?
          pair = d.value.positive? ? [a, b, d.value] : [b, a, -d.value]
          break
        end
        return factors unless pair
        big, small, m = pair
        e = factors.delete(big)
        Simplify.add_factor(factors, small, e)
        (1..m).each { |i| Simplify.add_factor(factors, (small.args.first + i).simplify, e) }
      end
    end

    # A closed form built out of gammas and factorials is often a binomial
    # coefficient wearing a disguise: the sum of binomial(n, k)**2 comes
    # back as 2**(2*n)*gamma(1/2 + n)/(pi**(1/2)*n!), which is
    # binomial(2*n, n). The shape is guessed - one of a handful of linear
    # arguments - and then checked at several integers, which is what makes
    # guessing safe (fps offers its coefficient in three forms and lets the
    # same kind of check decide). nil when nothing fits.
    UPPER = [1, 2].freeze
    LOWER = [0, 1, 2].freeze
    SHIFTS = [0, 1, -1, 2, -2].freeze # nearest first, so binomial(2*n, n) wins over 2*binomial(2*n - 1, n - 1)
    SAMPLES = [3, 4, 5, 6].freeze

    def as_binomial(expr, var)
      expr = Expression.lift(expr)
      return nil unless expr.each_node.any? { |n| n.is_a?(Fn) && %i[gamma factorial].include?(n.name) }
      values = SAMPLES.map { |m| numeric_at(expr, var, m) }
      return nil if values.any? { |v| v.nil? || v.zero? }

      UPPER.each do |a|
        LOWER.each do |c|
          next if c > a
          SHIFTS.each do |b|
            SHIFTS.each do |d|
              ratio = constant_ratio(values, a, b, c, d)
              next unless ratio
              form = (Expression.lift(ratio) * Fn.new(:binomial, [(a * var + b).simplify, (c * var + d).simplify])).simplify
              return form
            end
          end
        end
      end
      nil
    end

    # The same rational multiple of binomial(a*m + b, c*m + d) at every
    # sample, or nil. A "nice" rational only: a ratio that needs sixty digits
    # is the numerics talking, not an identity.
    def constant_ratio(values, a, b, c, d)
      first = nil
      SAMPLES.each_with_index do |m, i|
        top = a * m + b
        bottom = c * m + d
        return nil if bottom.negative? || top < bottom
        binomial = (0...bottom).reduce(1) { |acc, j| acc * (top - j) } / (1..bottom).reduce(1, :*)
        return nil if binomial.zero?
        ratio = values[i] / binomial.to_f
        rational = Rational(ratio).rationalize(Rational(1, 10**9))
        return nil if rational.numerator.abs > 64 || rational.denominator > 64
        first ||= rational
        return nil unless (ratio - first).abs < 1e-9 * [1.0, ratio.abs].max
      end
      first
    end

    def numeric_at(expr, var, m)
      value = expr.evalf(var.name => m)
      value = value.value if value.is_a?(Num)
      value.is_a?(Numeric) && value.real? && value.finite? ? value.to_f : nil
    rescue StandardError
      nil
    end

    # sum_k binomial(n, k)*x**k is a polynomial when n is a non-negative
    # integer and otherwise converges only for |x| < 1. Without the test
    # sum((-1)**k, k, 0, oo) came back as 1/2 - the value the formula gives
    # at x = 1, where the series does not converge at all.
    def binomial_series_converges?(n, x)
      return true unless n.is_a?(Num) # a symbolic upper index: the terms vanish past k = n
      return true if n.value.is_a?(Integer) && n.value >= 0
      value = x.is_a?(Num) ? x.value : (x.variables.empty? ? x.evalf : nil)
      value = value.value if value.is_a?(Num)
      return true unless value.is_a?(Numeric) # symbolic: convergence is assumed, as elsewhere here
      value.abs < 1
    end

    def divergent?(value)
      value.each_node.any? do |n|
        (n.is_a?(Fn) && n.name == :log && n.args.first.is_a?(Num) && n.args.first.zero?) || n == OO
      end
    end

    # sqrt(e) when e is a perfect square (x**2, 4*y**2); any sqrt when not exact_only.
    def root_of(e, exact_only)
      coeff, factors = Simplify.factorize(e)
      if factors.values.all? { |x| x.is_a?(Integer) && x.even? } && coeff.is_a?(Integer) && coeff.positive? &&
         Integer.sqrt(coeff)**2 == coeff
        return Simplify.rebuild_product(Integer.sqrt(coeff), factors.transform_values { |x| x / 2 })
      end
      exact_only ? nil : RCAS.sqrt(e)
    end

    # ---- classical series ---------------------------------------------------

    # Infinite hypergeometric sums with a known closed form. r is the ratio
    # f(k+1)/f(k) as a rational function of k; m0 is the natural first index.
    # Returns [start_index, sum of the series whose first term is 1].
    def known_series(r, k)
      one = Num.new(1)
      two = Num.new(2)
      candidates = []
      candidates << [0, ->(x) { Fn.new(:exp, [x]) }, (r * (k + 1)).cancel, :direct]
      candidates << [0, ->(x) { Fn.new(:cos, [x]) }, (r * (2 * k + 1) * (2 * k + 2)).cancel, :neg_square]
      candidates << [0, ->(x) { Fn.new(:sin, [x]) / x }, (r * (2 * k + 2) * (2 * k + 3)).cancel, :neg_square]
      candidates << [0, ->(x) { Fn.new(:cosh, [x]) }, (r * (2 * k + 1) * (2 * k + 2)).cancel, :square]
      candidates << [0, ->(x) { Fn.new(:sinh, [x]) / x }, (r * (2 * k + 2) * (2 * k + 3)).cancel, :square]
      candidates << [1, ->(x) { Fn.new(:log, [one + x]) / x }, (r * (k + 1) / k).cancel, :negated]
      candidates << [0, ->(x) { Fn.new(:atan, [x]) / x }, (r * (2 * k + 3) / (2 * k + 1)).cancel, :neg_square]
      [true, false].each do |exact_roots_only|
        candidates.each do |m0, template, p, kind|
          next if p.variables.include?(k.name)
          x =
            case kind
            when :direct then p
            when :negated then (-p).simplify
            when :square then root_of(p, exact_roots_only)
            when :neg_square then root_of((-p).simplify, exact_roots_only)
            end
          next if x.nil? || (x.is_a?(Num) && x.zero?)
          value = template.call(x).simplify
          next if divergent?(value) # log(1 + x) at x = -1: the harmonic series
          return [m0, value]
        end
      end
      # binomial theorem: r = (n - k) x / (k + 1)
      p = (r * (k + 1)).cancel
      coeffs = Solve.polynomial_coefficients(p, k)
      if coeffs && coeffs.size == 2
        x = (-coeffs[1]).simplify
        n = (coeffs[0] / x).cancel
        if [n, x].none? { |v| v.variables.include?(k.name) } && binomial_series_converges?(n, x)
          return [0, ((one + x)**n).simplify]
        end
      end
      _ = two
      nil
    end
  end
end
