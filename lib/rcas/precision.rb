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
      exponent = value.exponent
      return scientific if exponent > digits + 6 || exponent < -5 # 1.0e-20, not 0.1e-19
      whole, fraction = value.to_s("F").split(".")
      keep = digits - whole.delete("-").sub(/\A0\z/, "").size
      fraction = fraction[0, [keep, 1].max].to_s
      "#{whole}.#{fraction.empty? ? '0' : fraction}"
    end

    # One digit before the point, the exponent after the e.
    def scientific
      sign, mantissa, _, exponent = value.split
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

    def function(node, prec, bindings, state)
      unless ELEMENTARY.include?(node.name) && node.args.size == 1
        unsupported!("#{node.name}", node)
      end
      x = walk(node.args.first, prec, bindings, state)
      apply(node.name, x, prec, node)
    end

    def apply(name, x, prec, node)
      case name
      when :exp   then BigMath.exp(x, prec)
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
