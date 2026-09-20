# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/math"

module RCAS
  # A decimal number that knows how many significant digits it is good for.
  #
  #   evalf(pi, 50)   # => 3.1415926535897932384626433832795028841971693993751
  #
  # It is a Numeric, so it goes back into an expression and through Scalar,
  # Printer and the domains like any other number; what it adds is an
  # honest `digits` and a `to_s` that prints the digits instead of
  # BigDecimal's own 0.31415e1.
  class Decimal < Numeric
    attr_reader :value, :digits

    def initialize(value, digits)
      @value = value.is_a?(BigDecimal) ? value : BigDecimal(value, digits)
      @digits = digits
      freeze
    end

    def to_s
      return "0.0" if value.zero?
      rounded = value.mult(1, digits) # rounded to `digits` significant digits, still a BigDecimal
      exponent = rounded.exponent
      return scientific(rounded) if exponent > digits + 6 || exponent < -5 # 1.0e-20, not 0.1e-19
      whole, fraction = rounded.to_s("F").split(".")
      integer_digits = whole.delete("-").sub(/\A0\z/, "").size
      # The zeros after the point of a number below 1 are not significant
      # digits and must not be charged to the budget: evalf(1/3000, 20) lost
      # one digit per leading zero.
      keep = digits - integer_digits + (integer_digits.zero? ? fraction[/\A0*/].size : 0)
      fraction = fraction[0, [keep, 1].max].to_s
      "#{whole}.#{fraction.empty? ? '0' : fraction}"
    end

    # One digit before the point, the exponent after the e.
    def scientific(rounded = value)
      sign, mantissa, _, exponent = rounded.split
      mantissa = mantissa[0, digits]
      tail = mantissa[1..].to_s.sub(/0+\z/, "")
      "#{'-' if sign.negative?}#{mantissa[0]}.#{tail.empty? ? '0' : tail}e#{exponent - 1}"
    end
    alias inspect to_s
    def to_latex(wrap: nil) = to_s

    def to_f = value.to_f
    def to_i = value.to_i
    def to_r = value.to_r
    def to_d = value
    def to_c = Complex(self, 0)

    def zero? = value.zero?
    def negative? = value.negative?
    def positive? = value.positive?
    def finite? = value.finite?
    def real? = true
    def real = self
    def imaginary = 0
    def abs = Decimal.new(value.abs, digits)
    def -@ = Decimal.new(-value, digits)
    def round(n = 0) = Decimal.new(value.round(n), digits)
    def truncate(n = 0) = value.truncate(n)
    def floor(n = 0) = value.floor(n)
    def ceil(n = 0) = value.ceil(n)
    def integer? = false

    # Arithmetic keeps the smaller number of digits: a sum is no better than
    # its worst summand.
    %i[+ - *].each do |op|
      define_method(op) do |other|
        d = Decimal.wrap(other, digits) or return coerce_fallback(op, other)
        Decimal.new(value.public_send(op, d.value), [digits, d.digits].min)
      end
    end

    def /(other)
      d = Decimal.wrap(other, digits) or return coerce_fallback(:/, other)
      raise ZeroDivisionError, "divided by 0" if d.value.zero?
      keep = [digits, d.digits].min
      Decimal.new(value.div(d.value, keep + Precision::GUARD).mult(1, keep), keep)
    end

    def **(other)
      d = Decimal.wrap(other, digits) or return coerce_fallback(:**, other)
      keep = [digits, d.digits].min
      Decimal.new(Precision.power_of(value, d.value, keep + Precision::GUARD).mult(1, keep), keep)
    end

    def <=>(other)
      d = Decimal.wrap(other, digits)
      d ? value <=> d.value : nil
    end

    def ==(other)
      d = Decimal.wrap(other, digits)
      d ? value == d.value : false
    end
    alias eql? ==
    def hash = [Decimal, value].hash

    def coerce(other)
      d = Decimal.wrap(other, digits) or raise TypeError, "can't coerce #{other.class} into a Decimal"
      [d, self]
    end

    # The precedence hook Printer asks for: only the sign matters.
    def printer_precedence = negative? ? Printer::UNARY : Printer::ATOM

    # A Numeric as a Decimal of at most +digits+ digits, or nil.
    def self.wrap(other, digits)
      case other
      when Decimal then other
      when Integer then new(BigDecimal(other), digits)
      when Rational then new(BigDecimal(other.numerator).div(other.denominator, digits + Precision::GUARD), digits)
      when Float then new(BigDecimal(other, Precision::FLOAT_DIGITS), [digits, Precision::FLOAT_DIGITS].min)
      when BigDecimal then new(other, digits)
      end
    end

    private

    def coerce_fallback(op, other)
      a, b = other.coerce(to_f)
      a.public_send(op, b)
    end
  end

  # evalf with as many digits as you ask for.
  #
  #   evalf(pi, 50)                     # 3.14159265358979323846264338327950288419716939937510
  #   evalf(sqrt(2), 40)
  #   evalf(exp(1) - 1, x: 2, digits: 30)
  #
  # The tree is walked in BigDecimal with ten guard digits and rounded once
  # at the end. Everything elementary is there (the constants, exp, log, the
  # trigonometric and hyperbolic functions and their inverses, roots, and a
  # real RootOf refined by Newton's method); anything that exists only in
  # double precision - erf, Si, Ci, Ei, li, zeta, an unevaluated integral -
  # raises Precision::Unsupported instead of dressing up sixteen good digits
  # as fifty.
  #
  # A Float in the expression does the same in miniature: it carries only
  # its own sixteen digits, so the answer is reported with sixteen. Ask for
  # more and you get what is true, not what was requested.
  #
  # Sources (keys: MANUAL.md, Sources): the series behind BigMath are the
  # standard ones [AS64, §4.1, §4.3]; Newton's method for the roots
  # [PTVF07, §9.4].
  module Precision
    # Raised for anything that has no arbitrary-precision implementation.
    class Unsupported < ArgumentError; end

    # The quadrature ran out of levels: the integrand is too hard for the
    # digits asked, or the integral diverges. Told apart from Unsupported so
    # that a caller knows retrying in Floats would not help either.
    class NoConvergence < Unsupported; end

    GUARD = 10
    FLOAT_DIGITS = Float::DIG + 1
    MAX_TERMS = 100_000
    MAX_NEWTON = 200

    module_function

    def evalf(expr, digits, bindings = {})
      digits = Integer(digits)
      raise ArgumentError, "evalf: digits must be positive, got #{digits}" unless digits.positive?
      state = { limit: digits }
      value = walk(Expression.lift(expr), digits + GUARD, table_of(bindings), state)
      keep = [digits, state[:limit]].min
      Decimal.new(value.mult(1, keep), keep)
    end

    def table_of(bindings) = bindings.to_h { |name, value| [name.to_sym, value] }

    # ---- the walk -----------------------------------------------------------

    def walk(node, prec, bindings, state)
      case node
      when Num     then number(node.value, prec, state)
      when Const   then constant(node, prec, state)
      when Var     then variable(node, prec, bindings, state)
      when Neg     then -walk(node.arg, prec, bindings, state)
      when Add     then walk(node.left, prec, bindings, state) + walk(node.right, prec, bindings, state)
      when Sub     then walk(node.left, prec, bindings, state) - walk(node.right, prec, bindings, state)
      when Mul     then walk(node.left, prec, bindings, state).mult(walk(node.right, prec, bindings, state), prec)
      when Div     then divide(walk(node.left, prec, bindings, state), walk(node.right, prec, bindings, state), prec)
      when Pow     then power(node, prec, bindings, state)
      when Fn      then function(node, prec, bindings, state)
      when RootOf  then root_of(node, prec)
      when Sum     then series_sum(node, prec, bindings, state)
      when Integral then integral(node, prec, bindings, state)
      when Piecewise then piecewise(node, prec, bindings, state)
      else unsupported!(node.class.name.split("::").last.downcase, node)
      end
    end

    def unsupported!(what, node)
      raise Unsupported, "evalf: no arbitrary-precision #{what} (#{node}); " \
                         "evalf without digits: gives the double-precision value"
    end

    def number(value, prec, state)
      case value
      when Integer  then BigDecimal(value)
      when Rational then BigDecimal(value.numerator).div(value.denominator, prec)
      when Float    then float(value, state)
      when BigDecimal then value
      when Decimal  then lower(state, value.digits) { value.value }
      when Complex  then raise Unsupported, "evalf: #{value} is not real, and only the real numbers are arbitrary-precision here"
      else unsupported!("value", value)
      end
    end

    # A Float knows sixteen digits and no more; the answer says so.
    def float(value, state)
      raise Unsupported, "evalf: #{value} is not finite" unless value.finite?
      lower(state, FLOAT_DIGITS) { BigDecimal(value, FLOAT_DIGITS) }
    end

    def lower(state, digits)
      state[:limit] = [state[:limit], digits].min
      yield
    end

    def constant(node, prec, state)
      return BigMath.PI(prec) if node.name == :pi
      unsupported!("undefined", node) if node.name == :undefined
      unsupported!("constant", node) unless node.value.is_a?(Numeric) && node.value.finite?
      float(node.value, state)
    end

    def variable(node, prec, bindings, state)
      value = bindings[node.name]
      raise ArgumentError, "evalf: #{node.name} has no value" if value.nil?
      value.is_a?(Numeric) ? number(value, prec, state) : walk(Expression.lift(value), prec, bindings, state)
    end

    def divide(a, b, prec)
      raise ZeroDivisionError, "divided by 0" if b.zero?
      a.div(b, prec)
    end

    # ---- powers and roots ---------------------------------------------------

    def power(node, prec, bindings, state)
      base = walk(node.base, prec, bindings, state)
      exponent = node.exponent
      if exponent.is_a?(Num) && exponent.value.is_a?(Integer)
        return integer_power(base, exponent.value, prec)
      end
      # (-8)**(1/3) is -2: a negative base has a real odd root, and only
      # the exact exponent of the node can say whether this is one.
      if base.negative? && (root = odd_root(exponent))
        value = power_of(-base, walk(exponent, prec, bindings, state), prec, node)
        return root.negative? ? -value : value
      end
      power_of(base, walk(exponent, prec, bindings, state), prec, node)
    end

    def integer_power(base, n, prec)
      raise ZeroDivisionError, "divided by 0" if base.zero? && n.negative?
      base.power(n, prec)
    end

    # b**e for decimals: exact roots where they are exact, exp(e*log(b))
    # otherwise. A negative base is a real number only for an odd root.
    def power_of(base, exponent, prec, node = nil)
      return BigDecimal(1) if exponent.zero?
      return integer_power(base, exponent.to_i, prec) if exponent.frac.zero?
      if base.negative?
        raise Unsupported, "evalf: #{node || "#{base}**#{exponent}"} is not real"
      end
      return BigDecimal(0) if base.zero?
      return base.sqrt(prec) if exponent == BigDecimal("0.5")
      BigMath.exp(exponent.mult(BigMath.log(base, prec), prec), prec)
    end

    # p/q with an odd q, as -1 or 1 for the sign of the result; nil when the
    # power of a negative number is not real.
    def odd_root(exponent)
      return nil unless exponent.is_a?(Num) && exponent.value.is_a?(Rational) && exponent.value.denominator.odd?
      exponent.value.numerator.odd? ? -1 : 1
    end

    # ---- functions ----------------------------------------------------------

    ELEMENTARY = %i[exp log sin cos tan atan asin acos sinh cosh tanh abs sign floor ceil round factorial gamma].freeze

    # The ones BigMath does not have, written out below.
    SPECIAL = %i[erf erfc Si Ci Ei li zeta].freeze

    def function(node, prec, bindings, state)
      unless (ELEMENTARY + SPECIAL).include?(node.name) && node.args.size == 1
        unsupported!("#{node.name}", node)
      end
      x = walk(node.args.first, prec, bindings, state)
      SPECIAL.include?(node.name) ? special(node.name, x, prec, node) : apply(node.name, x, prec, node)
    end

    def apply(name, x, prec, node)
      case name
      when :exp   then exponential(x, prec)
      when :log   then positive!(x, node) && BigMath.log(x, prec)
      when :sin   then BigMath.sin(x, prec)
      when :cos   then BigMath.cos(x, prec)
      when :tan   then divide(BigMath.sin(x, prec), BigMath.cos(x, prec), prec)
      when :atan  then BigMath.atan(x, prec)
      when :asin  then arcsin(x, prec, node)
      when :acos  then BigMath.PI(prec).div(2, prec) - arcsin(x, prec, node)
      when :sinh  then (BigMath.exp(x, prec) - BigMath.exp(-x, prec)).div(2, prec)
      when :cosh  then (BigMath.exp(x, prec) + BigMath.exp(-x, prec)).div(2, prec)
      when :tanh  then divide(BigMath.exp(x, prec) - BigMath.exp(-x, prec), BigMath.exp(x, prec) + BigMath.exp(-x, prec), prec)
      when :abs   then x.abs
      when :sign  then BigDecimal(x <=> 0)
      when :floor then BigDecimal(x.floor)
      when :ceil  then BigDecimal(x.ceil)
      when :round then BigDecimal(x.round)
      when :factorial, :gamma then whole_factorial(x, name, node)
      end
    end

    # Beyond this the exponential is not a number anyone is waiting for,
    # and BigMath would grind for a very long time on the way to saying so.
    EXP_LIMIT = 1_000_000

    def exponential(x, prec)
      raise Unsupported, "evalf: exp(#{x.to_f}) is beyond arbitrary precision" if x.abs > EXP_LIMIT
      BigMath.exp(x, prec)
    end

    def positive!(x, node)
      raise Unsupported, "evalf: log of #{node.args.first} is not real" unless x.positive?
      true
    end

    # asin(x) = atan(x/sqrt(1 - x**2)), and the two ends by hand.
    def arcsin(x, prec, node)
      raise Unsupported, "evalf: #{node} is not real" if x.abs > 1
      return BigMath.PI(prec).div(2, prec).mult(x <=> 0, prec) if x.abs == 1
      BigMath.atan(x.div((BigDecimal(1) - x.mult(x, prec)).sqrt(prec), prec), prec)
    end

    # gamma and factorial of a whole number are exact integers; anything
    # else would need Lanczos or Spouge at this precision.
    def whole_factorial(x, name, node)
      n = x.to_i
      n -= 1 if name == :gamma
      raise Unsupported, "evalf: #{node} is only available for whole numbers" unless x.frac.zero? && n >= 0
      BigDecimal((1..n).reduce(1, :*))
    end

    # ---- the functions BigMath does not have ---------------------------------

    # An alternating series whose terms grow to e**growth before they shrink
    # cancels away that many digits; the working precision has to make them
    # up. Past MAX_CANCELLATION the series is the wrong method and saying so
    # is better than running it.
    MAX_CANCELLATION = 400

    def cancellation(growth, prec)
      extra = (growth * Math.log10(Math::E)).ceil
      if extra > MAX_CANCELLATION
        raise Unsupported, "evalf: the argument is too large for the series (it would cancel " \
                           "#{extra} digits away); the asymptotic expansion is not implemented"
      end
      prec + [extra, 0].max + 5
    end

    def tolerance(prec) = BigDecimal("1e-#{prec}")

    # Euler's constant by Brent and McMillan's algorithm B1 [BM80]: the two
    # Bessel-like sums U and V, whose ratio is gamma up to exp(-4*n).
    def euler_gamma(prec)
      work = prec + 10
      n = (work * Math.log(10) / 4).ceil + 1
      squared = BigDecimal(n * n)
      a = -BigMath.log(BigDecimal(n), work)
      b = BigDecimal(1)
      u = a
      v = b
      k = 1
      limit = 20 * n + 100
      loop do
        b = b.mult(squared, work).div(k * k, work)
        a = (a.mult(squared, work).div(k, work) + b).div(k, work)
        u += a
        v += b
        break if k > n && a.abs < tolerance(work) * u.abs
        k += 1
        break if k > limit
      end
      u.div(v, work)
    end

    def special(name, x, prec, node)
      case name
      when :erf  then erf(x, prec)
      when :erfc then BigDecimal(1) - erf(x, prec)
      when :Si   then sine_integral(x, prec)
      when :Ci   then cosine_integral(x, prec, node)
      when :Ei   then exponential_integral(x, prec, node)
      when :li   then logarithmic_integral(x, prec, node)
      when :zeta then zeta(x, prec, node)
      end
    end

    # erf(x) = 2/sqrt(pi) * sum (-1)**n x**(2n+1)/(n!*(2n+1)), which is the
    # whole story until the cancellation bites; beyond the point where erfc
    # is below the last digit, erf is 1.
    def erf(x, prec)
      return -erf(-x, prec) if x.negative?
      return BigDecimal(1) if x > Math.sqrt((prec + 5) * Math.log(10))
      work = cancellation(x.to_f**2, prec)
      squared = x.mult(x, work)
      term = x
      sum = x
      n = 1
      loop do
        term = term.mult(squared, work).div(n, work)
        piece = term.div(2 * n + 1, work)
        sum += n.odd? ? -piece : piece
        break if piece.abs < tolerance(work)
        n += 1
      end
      sum.mult(2, work).div(BigMath.PI(work).sqrt(work), work)
    end

    # Si(x) = sum (-1)**k x**(2k+1)/((2k+1)*(2k+1)!)
    def sine_integral(x, prec)
      return -sine_integral(-x, prec) if x.negative?
      work = cancellation(x.to_f, prec)
      squared = x.mult(x, work)
      term = x
      sum = x
      k = 1
      loop do
        term = term.mult(squared, work).div((2 * k) * (2 * k + 1), work)
        piece = term.div(2 * k + 1, work)
        sum += k.odd? ? -piece : piece
        break if piece.abs < tolerance(work)
        k += 1
      end
      sum
    end

    # Ci(x) = gamma + log(x) + sum (-1)**k x**(2k)/(2k*(2k)!)
    def cosine_integral(x, prec, node)
      raise Unsupported, "evalf: #{node} is real only for a positive argument" unless x.positive?
      work = cancellation(x.to_f, prec)
      squared = x.mult(x, work)
      term = BigDecimal(1)
      sum = BigDecimal(0)
      k = 1
      loop do
        term = term.mult(squared, work).div((2 * k - 1) * (2 * k), work)
        piece = term.div(2 * k, work)
        sum += k.odd? ? -piece : piece
        break if piece.abs < tolerance(work)
        k += 1
      end
      euler_gamma(work) + BigMath.log(x, work) + sum
    end

    # Ei(x) = gamma + log|x| + sum x**k/(k*k!)
    def exponential_integral(x, prec, node)
      raise Unsupported, "evalf: #{node} is infinite at 0" if x.zero?
      work = cancellation(x.negative? ? x.abs.to_f : 0.0, prec)
      term = BigDecimal(1)
      sum = BigDecimal(0)
      k = 1
      loop do
        term = term.mult(x, work).div(k, work)
        piece = term.div(k, work)
        sum += piece
        break if piece.abs < tolerance(work) && k > x.abs
        k += 1
      end
      euler_gamma(work) + BigMath.log(x.abs, work) + sum
    end

    def logarithmic_integral(x, prec, node)
      raise Unsupported, "evalf: #{node} needs a positive argument" unless x.positive?
      return BigDecimal(0) if x.zero?
      raise Unsupported, "evalf: li(1) is infinite" if x == 1
      exponential_integral(BigMath.log(x, prec + GUARD), prec, node)
    end

    # zeta(s) for a whole s > 1: the even ones are a rational multiple of
    # pi**s, the odd ones come from Euler-Maclaurin [AS64, §23.2] with the
    # exact Bernoulli numbers rcas already has.
    def zeta(s, prec, node)
      unless s.frac.zero? && s > 1
        raise Unsupported, "evalf: #{node} is only available for a whole s > 1"
      end
      s = s.to_i
      work = prec + GUARD
      return even_zeta(s, work) if s.even?
      n = [prec, 20].max
      head = (1...n).reduce(BigDecimal(0)) { |acc, i| acc + BigDecimal(1).div(BigDecimal(i)**s, work) }
      power = BigDecimal(n)**s
      total = head + BigDecimal(n).div(power.mult(s - 1, work), work) + BigDecimal(1).div(power.mult(2, work), work)
      product = BigDecimal(s)
      (1..work).each do |k|
        bernoulli = Summation.bernoulli(2 * k)
        piece = BigDecimal(bernoulli.numerator).div(bernoulli.denominator, work)
                                               .mult(product, work)
                                               .div(factorial(2 * k).mult(power.mult(BigDecimal(n)**(2 * k - 1), work), work), work)
        total += piece
        break if piece.abs < tolerance(work)
        product = product.mult((s + 2 * k - 1) * (s + 2 * k), work)
      end
      total
    end

    def even_zeta(s, work)
      value = Summation.zeta_even(s) # a rational times pi**s
      coefficient, = Simplify.factorize(value)
      BigDecimal(coefficient.numerator).div(coefficient.denominator, work).mult(BigMath.PI(work)**s, work)
    end

    def factorial(n) = BigDecimal((1..n).reduce(1, :*))

    # ---- quadrature ----------------------------------------------------------

    MAX_LEVELS = 8

    # Double-exponential (tanh-sinh) quadrature [TM74]: the substitution
    # x = tanh(pi/2*sinh(t)) makes the integrand and all its derivatives die
    # away so fast at the ends that the trapezoidal rule in t converges
    # doubly exponentially - and an endpoint singularity is smothered with
    # them. The two infinite ranges use exp(pi/2*sinh(t)) and
    # sinh(pi/2*sinh(t)) in the same skeleton.
    def quadrature(integrand, var, from, to, prec, bindings = {}, state = { limit: prec })
      work = prec + 2 * GUARD
      map = transformation(from, to, work, bindings, state)
      f = ->(point) { walk(integrand, work, bindings.merge(var.name => point), state) }
      half = BigMath.PI(work).div(2, work)
      step = BigDecimal(1)
      total = level_sum(f, map, half, step, work, 0)
      previous = nil
      (1..MAX_LEVELS).each do |level|
        step = step.div(2, work)
        # halving the step keeps every point of the level before it
        total = total.div(2, work) + level_sum(f, map, half, step, work, 1)
        settled = previous && (total - previous).abs < tolerance(prec) * [total.abs, BigDecimal(1)].max
        return total.mult(1, prec) if settled && level > 1
        previous = total
      end
      raise NoConvergence, "evalf: the quadrature did not settle to #{prec} digits; " \
                           "the integral may diverge, or oscillate faster than the rule resolves"
    end

    # One trapezoidal sum in t, over every k (parity 0) or only the odd ones
    # (parity 1), stopping when the weights have died away.
    def level_sum(f, map, half, step, work, parity)
      total = BigDecimal(0)
      k = parity.zero? ? 0 : 1
      loop do
        contribution = BigDecimal(0)
        [1, -1].each do |sign|
          next if k.zero? && sign.negative?
          t = step.mult(sign * k, work)
          point, weight = map.call(t, half, work)
          next if weight.zero?
          value = begin
            f.call(point)
          rescue ZeroDivisionError, Unsupported
            next
          end
          contribution += weight.mult(value, work)
        end
        total += contribution
        break if k.positive? && contribution.abs < tolerance(work) && k * step > 2
        k += parity.zero? ? 1 : 2
        break if k * step > 8 # the weights are below any precision by here
      end
      total.mult(step, work)
    end

    # [point, weight] as a function of t, for the three shapes of range.
    def transformation(from, to, work, bindings, state)
      lower = Limits.infinite?(from)
      upper = Limits.infinite?(to)
      if lower && upper then sinh_sinh
      elsif upper then exp_sinh(walk(from, work, bindings, state), 1)
      elsif lower then exp_sinh(walk(to, work, bindings, state), -1)
      else finite(walk(from, work, bindings, state), walk(to, work, bindings, state))
      end
    end

    # The point is measured from the near end, never as centre + span*tanh(u):
    # 1 - tanh(u) is 2/(1 + exp(2*u)) and loses nothing, while the difference
    # would cancel away every digit that an endpoint singularity needs.
    def finite(a, b)
      lambda do |t, half, work|
        span = (b - a).div(2, work)
        u = half.mult(sinh(t, work), work)
        next [a, BigDecimal(0)] if u.abs > EXP_LIMIT
        gap = span.mult(2, work).div(BigDecimal(1) + BigMath.exp(u.mult(2, work).abs, work), work)
        point = t.negative? ? a + gap : b - gap
        [point, half.mult(cosh(t, work), work).div(cosh(u, work)**2, work).mult(span, work)]
      end
    end

    def exp_sinh(edge, direction)
      lambda do |t, half, work|
        u = half.mult(sinh(t, work), work)
        next [edge, BigDecimal(0)] if u.abs > EXP_LIMIT || u > Math.log(10) * (work + 30)
        growth = BigMath.exp(u, work)
        [edge + growth.mult(direction, work), half.mult(cosh(t, work), work).mult(growth, work)]
      end
    end

    def sinh_sinh
      lambda do |t, half, work|
        u = half.mult(sinh(t, work), work)
        next [BigDecimal(0), BigDecimal(0)] if u.abs > Math.log(10) * (work + 30)
        [sinh(u, work), half.mult(cosh(t, work), work).mult(cosh(u, work), work)]
      end
    end

    def sinh(t, work) = (exponential(t, work) - exponential(-t, work)).div(2, work)
    def cosh(t, work) = (exponential(t, work) + exponential(-t, work)).div(2, work)

    def tanh(t, work)
      up = BigMath.exp(t, work)
      down = BigMath.exp(-t, work)
      (up - down).div(up + down, work)
    end

    # ---- the rest -----------------------------------------------------------

    # A real root of a polynomial, refined from its double-precision value
    # by Newton's method: the number of correct digits doubles each step.
    def root_of(node, prec)
      raise Unsupported, "evalf: #{node} is not real" unless node.real?
      coefficients = (0..node.poly.degree).map { |k| Rational(node.poly.coeff(k)) }
      derivative = coefficients.each_with_index.drop(1).map { |c, k| c * k }
      x = BigDecimal(node.value, FLOAT_DIGITS)
      tolerance = BigDecimal("1e-#{prec}")
      MAX_NEWTON.times do
        slope = horner(derivative, x, prec)
        break if slope.zero?
        step = horner(coefficients, x, prec).div(slope, prec)
        x -= step
        break if step.abs < tolerance
      end
      x
    end

    def horner(coefficients, x, prec)
      coefficients.reverse.reduce(BigDecimal(0)) do |acc, c|
        acc.mult(x, prec) + BigDecimal(c.numerator).div(c.denominator, prec)
      end
    end

    # A definite integral is quadrature; an indefinite one is not a number.
    def integral(node, prec, bindings, state)
      unsupported!("indefinite integral", node) unless node.definite?
      quadrature(node.integrand, node.var, node.from, node.to, prec, bindings, state)
    end

    # A root to the digits asked for: Newton from the double-precision one,
    # or the secant method when there is no derivative to be had [PTVF07,
    # §9.4, §9.2]. The number of correct digits doubles at every step, so a
    # handful of them is the whole cost.
    def refine(expr, var, guess, digits, bindings = {})
      work = digits + 2 * GUARD
      state = { limit: work }
      f = ->(point) { walk(expr, work, bindings.merge(var.name => point), state) }
      slope = begin
        derivative = Expression.lift(expr).diff(var)
        ->(point) { walk(derivative, work, bindings.merge(var.name => point), state) }
      rescue StandardError
        nil
      end
      x = BigDecimal(guess, FLOAT_DIGITS)
      x = slope ? newton_steps(f, slope, x, work) : secant_steps(f, x, work)
      Decimal.new(x.mult(1, digits), digits)
    end

    def newton_steps(f, slope, x, work)
      MAX_NEWTON.times do
        divisor = slope.call(x)
        raise Unsupported, "evalf: the derivative is zero at the root" if divisor.zero?
        step = f.call(x).div(divisor, work)
        x -= step
        break if step.abs < tolerance(work) * [x.abs, BigDecimal(1)].max
      end
      x
    end

    def secant_steps(f, x, work)
      previous = x + tolerance(FLOAT_DIGITS)
      before = f.call(previous)
      MAX_NEWTON.times do
        value = f.call(x)
        divisor = value - before
        break if divisor.zero?
        step = value.mult(x - previous, work).div(divisor, work)
        previous = x
        before = value
        x -= step
        break if step.abs < tolerance(work) * [x.abs, BigDecimal(1)].max
      end
      x
    end

    # A sum with whole bounds, term by term.
    def series_sum(node, prec, bindings, state)
      from = walk(node.from, prec, bindings, state)
      to = walk(node.to, prec, bindings, state)
      unless from.frac.zero? && to.frac.zero? && from.finite? && to.finite?
        unsupported!("sum", node)
      end
      count = to.to_i - from.to_i + 1
      raise Unsupported, "evalf: #{count} terms is too many for #{node}" if count > MAX_TERMS
      (from.to_i..to.to_i).reduce(BigDecimal(0)) do |acc, k|
        acc + walk(node.term, prec, bindings.merge(node.var.name => k), state)
      end
    end

    # The branch is chosen the ordinary way and then evaluated to the digits
    # asked for; only a point exactly on a breakpoint could be decided
    # differently at higher precision.
    def piecewise(node, prec, bindings, state)
      chosen = node.subs(bindings.to_h { |name, value| [Var.new(name), Expression.lift(value)] }).simplify
      unsupported!("piecewise", node) if chosen.is_a?(Piecewise)
      walk(chosen, prec, bindings, state)
    end
  end
end
