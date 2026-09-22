# frozen_string_literal: true

module RCAS
  # Symbolic differentiation. Produces an unsimplified tree; Expression#diff
  # simplifies the result.
  module Differentiate
    module_function

    def diff(expr, var)
      case expr
      when Const then expr.name == :undefined ? expr : Num.new(0)
      when Num, RootOf then Num.new(0)
      when Var then Num.new(expr == var ? 1 : 0)
      when Neg then Neg.new(diff(expr.arg, var))
      when Add then Add.new(diff(expr.left, var), diff(expr.right, var))
      when Sub then Sub.new(diff(expr.left, var), diff(expr.right, var))
      when Mul then Add.new(Mul.new(diff(expr.left, var), expr.right), Mul.new(expr.left, diff(expr.right, var)))
      when Div then quotient(expr, var)
      when Pow then power(expr, var)
      when Fn  then %i[re im conj].include?(expr.name) ? Fn.new(expr.name, [diff(expr.args.first, var)]) : chain(expr, var)
      when Integral then integral(expr, var)
      when Derivative then expr.var == var ? Derivative.new(expr.expr, expr.var, expr.order + 1) : Num.new(0)
      when Piecewise then Piecewise.new(expr.branches.map { |cond, value| [cond, diff(value, var)] })
      else raise ArgumentError, "can't differentiate #{expr.class}"
      end
    end

    # A definite integral is a number, but a number that still depends on
    # the parameters of its integrand: d/dx integral(x*t, t, 0, 1) is 1/2,
    # not 0. Only the *integration* variable is bound, and looking at the
    # bounds alone answered every such derivative with zero (22 Sept 2026,
    # from a review). Bounds that move add Leibniz's two boundary terms.
    def integral(expr, var)
      unless expr.definite?
        return expr.var == var ? expr.integrand : Integral.new(differentiated(expr, var), expr.var)
      end
      moving = [expr.from, expr.to].any? { |c| c.variables.include?(var.name) }
      # integral(f(x), x, 0, x) names one thing twice: bound inside, free in
      # the bound. Which of the two is meant is the reader's business.
      raise NotImplementedError, "derivative of a definite integral whose bound repeats its variable" if moving && expr.var == var
      return Num.new(0) if expr.var == var
      inside = expr.integrand.variables.include?(var.name) ? Integral.new(differentiated(expr, var), expr.var, expr.from, expr.to) : Num.new(0)
      return inside unless moving
      at = ->(bound) { Mul.new(expr.integrand.subs(expr.var => bound), diff(bound, var)) }
      Add.new(inside, Sub.new(at[expr.to], at[expr.from]))
    end

    # The new integrand is simplified on the way in: an Integral is an atom
    # to Simplify, so nothing would tidy it afterwards.
    def differentiated(expr, var) = diff(expr.integrand, var).simplify

    def quotient(expr, var)
      u, v = expr.left, expr.right
      Div.new(Sub.new(Mul.new(diff(u, var), v), Mul.new(u, diff(v, var))), Pow.new(v, Num.new(2)))
    end

    def power(expr, var)
      u, n = expr.base, expr.exponent
      if !n.variables.include?(var.name)
        # d(u**n) = n * u**(n-1) * u'
        Mul.new(Mul.new(n, Pow.new(u, Sub.new(n, Num.new(1)))), diff(u, var))
      elsif !u.variables.include?(var.name)
        # d(a**v) = a**v * log(a) * v'
        Mul.new(Mul.new(expr, Fn.new(:log, [u])), diff(n, var))
      else
        # general case: u**v * (v' * log(u) + v * u' / u)
        Mul.new(expr, Add.new(Mul.new(diff(n, var), Fn.new(:log, [u])), Div.new(Mul.new(n, diff(u, var)), u)))
      end
    end

    def chain(expr, var)
      raise ArgumentError, "#{expr.name} takes one argument" unless expr.args.size == 1
      u = expr.args.first
      outer =
        case expr.name
        when :sin then Fn.new(:cos, [u])
        when :cos then Neg.new(Fn.new(:sin, [u]))
        when :tan then Add.new(Num.new(1), Pow.new(Fn.new(:tan, [u]), Num.new(2)))
        when :exp then expr
        when :log then Div.new(Num.new(1), u)
        when :atan then Div.new(Num.new(1), Add.new(Num.new(1), Pow.new(u, Num.new(2))))
        when :abs then Fn.new(:sign, [u])
        when :sign then Num.new(0)
        when :asin then Pow.new(Sub.new(Num.new(1), Pow.new(u, Num.new(2))), Num.new(Rational(-1, 2)))
        when :acos then Neg.new(Pow.new(Sub.new(Num.new(1), Pow.new(u, Num.new(2))), Num.new(Rational(-1, 2))))
        when :sinh then Fn.new(:cosh, [u])
        when :cosh then Fn.new(:sinh, [u])
        when :erf then Div.new(Mul.new(Num.new(2), Fn.new(:exp, [Neg.new(Pow.new(u, Num.new(2)))])), Pow.new(PI, Num.new(Rational(1, 2))))
        when :erfc then Neg.new(Div.new(Mul.new(Num.new(2), Fn.new(:exp, [Neg.new(Pow.new(u, Num.new(2)))])), Pow.new(PI, Num.new(Rational(1, 2)))))
        else IntegralFunctions.derivative(expr.name, u) || raise(ArgumentError, "don't know the derivative of #{expr.name}")
        end
      Mul.new(outer, diff(u, var))
    end
  end
end
