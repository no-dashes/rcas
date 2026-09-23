# frozen_string_literal: true

module RCAS
  # The Laplace transform and its inverse.
  #
  #   laplace(exp(3*t), t, s)            # => 1/(s - 3)
  #   laplace(t**2, t, s)                # => 2/s**3
  #   laplace(exp(-t)*sin(2*t), t, s)    # => 2/((1 + s)**2 + 4)
  #   inverse_laplace(1/(s**2 + 1), s, t) # => sin(t)
  #
  # The transform turns differentiation into multiplication by s, which is
  # why it solves linear differential equations by algebra. rcas computes it
  # from the table plus two rules: the first shift, exp(a*t)*f(t) at s - a,
  # and multiplication by t, which differentiates in s. The inverse goes
  # through partial fractions, so it covers the rational transforms a course
  # produces.
  #
  # Sources (keys: MANUAL.md, Sources): the table and the shift rules as in
  # [BD12, ch. 6]; partial fractions from rational_function.rb.
  module Laplace
    class Error < ArgumentError; end

    module_function

    # ---- the transform -----------------------------------------------------------

    def transform(f, t, s)
      t = Expression.lift(t)
      s = Expression.lift(s)
      f = Expression.lift(f).simplify
      constant, terms = Simplify.termize(f, simplify: true)
      result = Scalar.zero?(Num.new(constant)) ? Num.new(0) : (Num.new(constant) / s)
      terms.each do |factors, coefficient|
        # a factor free of t is a constant of the transform: a*sin(t) is
        # a/(1 + s**2) (the fourth review, L7, found it refused)
        constants, moving = factors.partition { |base, exp| !base.variables.include?(t.name) && !Expression.lift(exp).variables.include?(t.name) }
        term = Simplify.rebuild_product(1, moving.to_h)
        scale = Simplify.rebuild_product(coefficient, constants.to_h)
        result += scale * term_transform(term, t, s)
      end
      result.simplify
    end

    # A single term: t**n times something the table knows.
    def term_transform(term, t, s)
      power, rest = split_power(term, t)
      base = table_transform(rest, t, s)
      raise Error, "laplace: no transform known for #{term}" if base.nil?
      return base if power.zero?
      (Num.new((-1)**power) * base.diff(s, power)).simplify
    end

    # t**n * rest => [n, rest]
    def split_power(term, t)
      coefficient, factors = Simplify.factorize(term)
      power = factors[t]
      return [0, term] unless power.is_a?(Integer) && power.positive?
      rest = factors.reject { |base, _| base == t }
      [power, Simplify.rebuild_product(coefficient, rest)]
    end

    # 1, exp(a t), sin/cos(w t), sinh/cosh(w t), and exp(a t) times those.
    def table_transform(f, t, s)
      f = f.simplify
      return f / s unless Solve.depends?(f, t) # a constant a is a/s, not 1/s
      shift, rest = split_exponential(f, t)
      shifted = shift ? s - shift : s
      value =
        if !Solve.depends?(rest, t) then rest / shifted
        elsif rest.is_a?(Fn) && (rate = linear_rate(rest.args.first, t))
          case rest.name
          when :sin  then rate / (shifted**2 + rate**2)
          when :cos  then shifted / (shifted**2 + rate**2)
          when :sinh then rate / (shifted**2 - rate**2)
          when :cosh then shifted / (shifted**2 - rate**2)
          end
        end
      value&.simplify
    end

    # exp(a*t) * rest => [a, rest]
    def split_exponential(f, t)
      coefficient, factors = Simplify.factorize(f)
      exponent = factors[Simplify.exp_base]
      return [nil, f] if exponent.nil?
      rate = linear_rate(Expression.lift(exponent), t) or return [nil, f]
      rest = factors.reject { |base, _| base == Simplify.exp_base }
      [rate, Simplify.rebuild_product(coefficient, rest)]
    end

    # a*t => a, anything else => nil
    def linear_rate(u, t)
      coefficients = Solve.polynomial_coefficients(u, t)
      return nil unless coefficients && coefficients.size == 2 && Scalar.zero?(coefficients[0])
      coefficients[1]
    end

    # ---- the inverse --------------------------------------------------------------

    def inverse(f, s, t)
      s = Expression.lift(s)
      t = Expression.lift(t)
      f = Expression.lift(f).simplify
      pieces = begin
        RationalFunction.apart(f, s)
      rescue DomainError
        f
      end
      constant, terms = Simplify.termize(pieces, simplify: true)
      raise Error, "inverse_laplace: #{f} has a constant part, which is a delta" unless constant.zero?
      terms.map { |factors, coefficient| Num.new(coefficient) * piece_inverse(Simplify.rebuild_product(1, factors), s, t) }
           .reduce(Num.new(0)) { |a, b| a + b }.simplify
    end

    def piece_inverse(piece, s, t)
      numerator = RationalFunction.numer(piece)
      denominator = RationalFunction.denom(piece)
      raise Error, "inverse_laplace: #{piece} is not a proper rational function of #{s}" unless Solve.depends?(denominator, s)
      factorization = denominator.to_poly(QQ[s.name]).factor
      raise Error, "inverse_laplace: #{piece} has more than one kind of factor; give it as partial fractions" unless factorization.factors.size == 1

      factor, multiplicity = factorization.factors.first
      unit = factorization.unit
      degree = factor.degree
      coefficients = (0..degree).map { |k| factor.coeff(k).value }
      case degree
      when 1 then linear_inverse(numerator, coefficients, multiplicity, unit, s, t)
      when 2 then quadratic_inverse(numerator, coefficients, multiplicity, unit, s, t)
      else raise Error, "inverse_laplace: the denominator factor #{factor} has degree #{degree}"
      end
    end

    # c/(a*s + b)**n  =>  c * t**(n-1) * exp(-b/a * t) / (a**n * (n-1)!)
    def linear_inverse(numerator, coefficients, multiplicity, unit, s, t)
      raise Error, "inverse_laplace: the numerator #{numerator} is not constant" if Solve.depends?(numerator, s)
      b, a = coefficients
      rate = Num.new(Simplify.normalize_number(Rational(-b, a)))
      scale = (numerator / (unit * Num.new(a)**multiplicity * RCAS.factorial(multiplicity - 1))).simplify
      (scale * t**(multiplicity - 1) * Fn.new(:exp, [rate * t])).simplify
    end

    # (A*s + B) / ((s - p)**2 + w**2)  =>  exp(p*t) * (A*cos(w*t) + (B + A*p)/w * sin(w*t))
    def quadratic_inverse(numerator, coefficients, multiplicity, unit, s, t)
      raise Error, "inverse_laplace: a repeated quadratic factor is not supported" unless multiplicity == 1
      c, b, a = coefficients
      centre = Num.new(Simplify.normalize_number(Rational(-b, 2 * a)))
      square = Num.new(Simplify.normalize_number(Rational(c, a) - Rational(b, 2 * a)**2))
      raise Error, "inverse_laplace: the quadratic factor is not irreducible" unless square.value.positive?
      omega = RCAS.sqrt(square).simplify
      linear = Solve.polynomial_coefficients(numerator, s) or raise Error, "inverse_laplace: #{numerator} is not linear in #{s}"
      slope = linear[1] || Num.new(0)
      offset = linear[0]
      scale = (Num.new(1) / (unit * Num.new(a))).simplify
      cosine = slope
      sine = ((offset + slope * centre) / omega).simplify
      (scale * Fn.new(:exp, [centre * t]) * (cosine * Fn.new(:cos, [omega * t]) + sine * Fn.new(:sin, [omega * t]))).simplify
    end
  end
end
