# frozen_string_literal: true

module RCAS
  # The integrals that are not elementary but have names: the exponential
  # integral Ei, the sine and cosine integrals Si and Ci, and the
  # logarithmic integral li.
  #
  #   Ei(x) = integral(exp(t)/t, t, -oo, x)   (principal value)
  #   Si(x) = integral(sin(t)/t, t, 0, x)
  #   Ci(x) = gamma + log(x) + integral((cos(t) - 1)/t, t, 0, x)
  #   li(x) = Ei(log(x))
  #
  # With them `integrate(sin(x)/x, x)` has an answer instead of staying an
  # integral(...) node, which is the point: a student who meets sin(x)/x
  # should be told that its antiderivative has a name, not that rcas gave up.
  #
  # The numbers are Floats. Ei by its series for moderate arguments and by
  # the asymptotic expansion beyond; Si and Ci by the series below 2 and by
  # a complex continued fraction (modified Lentz) above it.
  #
  # Sources (keys: MANUAL.md, Sources): [AS64, §5.1, §5.2] for the
  # definitions and the series; [PTVF07, §6.3] for the two routines;
  # Lentz's method [Len76].
  module IntegralFunctions
    NAMES = %i[Ei Si Ci li].freeze
    EULER = 0.5772156649015328606
    EPSILON = 1e-16
    TINY = 1e-300
    MAX_ITERATIONS = 200
    SERIES_LIMIT = 36.0 # beyond this the series for Ei loses to cancellation

    module_function

    # ---- numerics -----------------------------------------------------------

    # Ei(x), the principal value of integral(exp(t)/t, t, -oo, x).
    def ei(x)
      x = x.to_f
      raise ArgumentError, "Ei(0) is infinite" if x.zero?
      return Math.log(x.abs) + EULER if x.abs < TINY
      x.abs <= SERIES_LIMIT ? ei_series(x) : ei_asymptotic(x)
    end

    # Ei(x) = gamma + log|x| + sum_k x**k/(k*k!)
    def ei_series(x)
      sum = 0.0
      fact = 1.0
      (1..MAX_ITERATIONS).each do |k|
        fact *= x / k
        term = fact / k
        sum += term
        break if term.abs < EPSILON * sum.abs
      end
      sum + Math.log(x.abs) + EULER
    end

    # Ei(x) ~ exp(x)/x * sum_k k!/x**k, summed while the terms shrink.
    def ei_asymptotic(x)
      sum = 0.0
      term = 1.0
      (1..MAX_ITERATIONS).each do |k|
        previous = term
        term *= k / x
        break if term.abs < EPSILON
        if term.abs < previous.abs
          sum += term
        else
          sum -= previous
          break
        end
      end
      Math.exp(x) * (1.0 + sum) / x
    end

    def si(x) = cisi(x).last
    def ci(x) = cisi(x).first

    # [Ci(x), Si(x)] for a real x; Ci is real only for x > 0.
    def cisi(x)
      x = x.to_f
      return [-Float::INFINITY, 0.0] if x.zero?
      return cisi(-x).then { |c, s| [c, -s] } if x.negative? # Si is odd, Ci is not real
      return [Math.log(x) + EULER, x] if x < Math.sqrt(TINY)
      x <= 2.0 ? cisi_series(x) : cisi_fraction(x)
    end

    def cisi_series(x)
      sum = 0.0
      sums = 0.0
      sumc = 0.0
      sign = 1.0
      fact = 1.0
      odd = true
      (1..MAX_ITERATIONS).each do |k|
        fact *= x / k
        term = fact / k
        sum += sign * term
        error = term / sum.abs
        if odd
          sign = -sign
          sums = sum
          sum = sumc
        else
          sumc = sum
          sum = sums
        end
        break if error < EPSILON
        odd = !odd
      end
      [sumc + Math.log(x) + EULER, sums]
    end

    # The continued fraction for exp(i*x)*(Ci + i*(Si - pi/2)) [PTVF07, §6.3].
    def cisi_fraction(x)
      b = Complex(1.0, x)
      c = Complex(1.0 / TINY, 0.0)
      d = 1.0 / b
      h = d
      (2..MAX_ITERATIONS).each do |i|
        a = -((i - 1)**2).to_f
        b += 2.0
        d = 1.0 / (a * d + b)
        c = b + a / c
        delta = c * d
        h *= delta
        break if (delta.real - 1.0).abs + delta.imaginary.abs < EPSILON
      end
      h = Complex(Math.cos(x), -Math.sin(x)) * h
      [-h.real, Math::PI / 2 + h.imaginary]
    end

    # li(x) = Ei(log(x)), the count of primes' companion.
    def li(x)
      x = x.to_f
      return 0.0 if x.zero?
      raise ArgumentError, "li: a positive argument is needed, got #{x}" unless x.positive?
      raise ArgumentError, "li(1) is infinite" if x == 1.0
      ei(Math.log(x))
    end

    def evaluate(name, value)
      case name
      when :Ei then ei(value)
      when :Si then si(value)
      when :Ci then ci(value)
      when :li then li(value)
      end
    end

    # ---- exact values -------------------------------------------------------

    # The values a table lists, and Floats; nil when there is nothing to say.
    def value(name, arg)
      return Num.new(evaluate(name, arg.value)) if arg.is_a?(Num) && arg.value.is_a?(Float)
      return infinite_value(name, arg) if arg == OO || arg == Neg.new(OO).simplify
      return nil unless arg.is_a?(Num) && arg.value.is_a?(Numeric) && arg.value.real?
      zero = arg.value.zero?
      case name
      when :Si then zero ? Num.new(0) : nil
      when :Ci, :Ei then zero ? Neg.new(OO).simplify : nil
      when :li
        return Num.new(0) if zero
        arg.value == 1 ? Neg.new(OO).simplify : nil
      end
    end

    def infinite_value(name, arg)
      positive = arg == OO
      case name
      when :Si then positive ? (PI / 2).simplify : Neg.new(PI / 2).simplify
      when :Ci then positive ? Num.new(0) : nil
      when :Ei then positive ? OO : Num.new(0)
      when :li then positive ? OO : nil
      end
    end

    # ---- calculus -----------------------------------------------------------

    # The derivatives: the integrands these functions were named for.
    def derivative(name, u)
      case name
      when :Ei then Div.new(Fn.new(:exp, [u]), u)
      when :Si then Div.new(Fn.new(:sin, [u]), u)
      when :Ci then Div.new(Fn.new(:cos, [u]), u)
      when :li then Div.new(Num.new(1), Fn.new(:log, [u]))
      end
    end

    # exp(u)/u, sin(u)/u, cos(u)/u and 1/log(u) with u = a*x + b.
    # Everything else (exp(x)/(x + 1), say) reaches this through the linear
    # substitution Integrate.shift makes.
    INTEGRANDS = { exp: :Ei, sin: :Si, cos: :Ci }.freeze

    def antiderivative(f, x)
      coeff, factors = Simplify.factorize(f)
      return nil unless coeff == 1
      log_case = logarithmic(factors, x)
      return log_case if log_case
      return nil unless factors.size == 2
      name, u = numerator_of(factors)
      return nil if name.nil?
      denominator = factors.find { |_, exp| exp == -1 }&.first
      return nil if denominator.nil?
      a, = Integrate.linear(u, x)
      return nil if a.nil?
      return Div.new(Fn.new(name, [u]), a) if denominator == u || Scalar.zero?(denominator - u)
      shifted_exponential(name, u, denominator, x)
    end

    # integral(exp(a*x + b)/(c*x + d)) = exp(b - a*d/c)/c * Ei(a*x + a*d/c):
    # the substitution t = c*x + d leaves a constant factor behind. Only the
    # exponential has this form; sin and cos would need both Si and Ci.
    def shifted_exponential(name, u, denominator, x)
      return nil unless name == :Ei
      a, b = Integrate.linear(u, x)
      c, d = Integrate.linear(denominator, x)
      return nil if a.nil? || c.nil?
      factor = Fn.new(:exp, [(b - a * d / c).simplify])
      argument = (a * x + a * d / c).simplify
      (factor * Fn.new(:Ei, [argument]) / c).simplify
    end

    # [the function to name the integral, its argument]. An exponential is
    # kept as exp_base**u in a factor table (simplify.rb), not as Fn(:exp).
    def numerator_of(factors)
      factors.each do |base, exp|
        return [:Ei, Expression.lift(exp)] if base == Simplify.exp_base
        next unless exp == 1 && base.is_a?(Fn) && INTEGRANDS.key?(base.name) && base.args.size == 1
        return [INTEGRANDS[base.name], base.args.first]
      end
      nil
    end

    # 1/log(a*x + b) = li(a*x + b)/a
    def logarithmic(factors, x)
      return nil unless factors.size == 1
      base, exp = factors.first
      return nil unless exp == -1 && base.is_a?(Fn) && base.name == :log && base.args.size == 1
      u = base.args.first
      a, = Integrate.linear(u, x)
      a.nil? ? nil : Div.new(Fn.new(:li, [u]), a)
    end

    # The limits at the ends of the real line, which is what a definite
    # integral over an infinite range needs. nil when this is not one of ours.
    def limit(f, x, point)
      return nil unless f.is_a?(Fn) && NAMES.include?(f.name) && f.args.size == 1
      return nil unless Limits.infinite?(point)
      inner = Limits.limit(f.args.first, x, point)
      return nil unless inner == OO || inner == Neg.new(OO).simplify
      value(f.name, inner)
    end
  end
end
