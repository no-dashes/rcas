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
      return false unless a.is_a?(Expression) && a.variables.empty? && a.each_node.none? { |n| n.is_a?(Integral) || n.is_a?(Derivative) }
      exact = Algebraic.exact(a)
      return exact.zero? if exact
      v = begin
        a.evalf
      rescue StandardError
        return false
      end
      return false unless v.is_a?(Numeric) && v.abs < 1e-12
      vanishes?(a)
    end

    # 1e-12 is not zero. exp(-100) is 3.7e-44, and a determinant built from
    # it used to come out as 0. A true zero is cancellation and shrinks as
    # the precision rises; a small number sits where it is.
    def vanishes?(expr)
      coarse = decimal(expr, 20)
      return true if coarse.nil? || coarse.zero?
      fine = decimal(expr, 40)
      return true if fine.nil? || fine.zero?
      fine < coarse * BigDecimal("1e-15")
    end

    # nil when arbitrary precision has nothing to say (a complex value, an
    # unsupported function): the float verdict then stands.
    def decimal(expr, digits)
      value = Precision.evalf(expr, digits)
      value.respond_to?(:to_d) ? value.to_d.abs : nil
    rescue StandardError, NotImplementedError
      nil # no more precision to be had: the float verdict stands
    end
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
