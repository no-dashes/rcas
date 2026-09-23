# frozen_string_literal: true

module RCAS
  # Arithmetic on matrix/vector/polynomial entries. Entries are Expressions;
  # purely numeric ones take an exact fast path (Integer/Rational stay exact).
  module Scalar
    module_function

    def lift(x) = Expression.lift(x)

    def add(a, b) = nums?(a, b) ? Num.new(a.value + b.value) : (a + b).expand
    def sub(a, b) = nums?(a, b) ? Num.new(a.value - b.value) : (a - b).expand
    def mul(a, b) = nums?(a, b) ? Num.new(a.value * b.value) : (a * b).expand
    def neg(a) = a.is_a?(Num) ? Num.new(-a.value) : Simplify.negate(a)

    def div(a, b)
      if nums?(a, b)
        raise ZeroDivisionError, "division by zero" if b.value.zero?
        Num.new(a.value.quo(b.value))
      else
        (a / b).simplify
      end
    end

    # Exact for numbers; for constant expressions such as (1 + sqrt(5))/2 - phi
    # a numeric evaluation decides (algebraic numbers have no canonical form here).
    def zero?(a)
      return a.value.zero? if a.is_a?(Num)
      return identically_zero?(a) if a.is_a?(Expression) && !a.constant?
      return false unless a.is_a?(Expression) && a.constant? && a.each_node.none? { |n| n.is_a?(Integral) || n.is_a?(Derivative) }
      exact = Algebraic.exact(a)
      return exact.zero? if exact
      v = begin
        a.evalf
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        return false
      end
      return false unless v.is_a?(Numeric) && v.abs < 1e-12
      vanishes?(a)
    end

    # An expression in indeterminates is zero when it is the zero polynomial
    # or rational function: (a**2 - 1)/(a - 1) - a - 1 is, and a symbolic
    # pivot that vanishes identically is no pivot - rank said 2 for a
    # singular matrix (third review, L9). This is not the generic-pivot
    # assumption, which is about pivots that vanish only for special values.
    def identically_zero?(a)
      return false if a.each_node.any? { |n| n.is_a?(Integral) || n.is_a?(Derivative) || n.is_a?(Sum) || n.is_a?(Limit) }
      expanded = a.expand
      return true if expanded.is_a?(Num) && expanded.value.zero?
      if expanded.each_node.any? { |n| n.is_a?(Div) || (n.is_a?(Pow) && n.exponent.is_a?(Num) && Simplify.negative?(n.exponent.value)) }
        cancelled = expanded.cancel
        return true if cancelled.is_a?(Num) && cancelled.value.zero?
      end
      trigonometric_zero?(expanded)
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    # sin(2*x) - 2*sin(x)*cos(x) and sin(x)**2 + cos(x)**2 - 1: zero by an
    # identity, which the addition formulas and trigsimp show. Only for
    # small expressions - this runs inside elimination.
    def trigonometric_zero?(e)
      return false unless e.each_node.any? { |n| n.is_a?(Fn) && Trigonometry::SQUARES.key?(n.name) }
      return false if e.each_node.count > 200
      rewritten = Trigonometry.expand_trig(e).expand
      return true if rewritten.is_a?(Num) && rewritten.value.zero?
      reduced = Trigonometry.trigsimp(rewritten).simplify
      reduced.is_a?(Num) && reduced.value.zero?
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    # 1e-12 is not zero. exp(-100) is 3.7e-44, and a determinant built from
    # it used to come out as 0; i*exp(-40) is complex and has no
    # arbitrary-precision value, so it went on the float verdict and was
    # zero too. Decide takes the parts apart and asks each at two
    # precisions, and a normal form proves the zeros. What it leaves
    # undecided is not zero: that is the generic-pivot assumption (the
    # fourth review: exp(-30)*gamma(1/3) was a zero determinant).
    def vanishes?(expr) = Decide.zero?(expr) == true
    def one?(a) = a.is_a?(Num) && a.value == 1
    def negative?(a) = a.is_a?(Num) && Simplify.negative?(a.value)
    def numeric?(a) = a.is_a?(Num)

    def nums?(a, b) = a.is_a?(Num) && b.is_a?(Num)

    # Domain of a scalar for result-space bookkeeping; nil when unknown.
    def domain(a) = a.is_a?(Expression) ? a.domain : nil
  end

  # Returned by Vector#coerce / Matrix#coerce so `2 * v` works but `2 - v` raises.
  class ScalarProxy
    def initialize(value) = @value = value
    def *(other) = other * @value

    def method_missing(name, *_args)
      raise TypeError, "can't apply #{name} to a scalar and a #{@other_class || 'vector'}"
    end

    def respond_to_missing?(*) = false
  end
end
