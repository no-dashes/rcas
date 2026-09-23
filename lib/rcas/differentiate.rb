# frozen_string_literal: true

module RCAS
  # Symbolic differentiation. Produces an unsimplified tree; Expression#diff
  # simplifies the result.
  module Differentiate
    module_function

    def diff(expr, var)
      # an expression without var (free) is a constant in it: sqrt(y - y)
      # has derivative 0, and the chain rule divided by sqrt(0) on the way
      # (third review, C11)
      return Num.new(0) if expr.is_a?(Expression) && !expr.is_a?(Derivative) && !expr.variables.include?(var.name) &&
                           !(expr.is_a?(Const) && expr.name == :undefined)
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
      when Fn
        if %i[re im conj].include?(expr.name) then Fn.new(expr.name, [diff(expr.args.first, var)])
        elsif expr.name == :surd && expr.args.size == 2 then surd(expr, var)
        else chain(expr, var)
        end
      when Integral then integral(expr, var)
      when Derivative then derivative(expr, var)
      when Piecewise then Piecewise.new(expr.branches.map { |cond, value| [cond, diff(value, var)] })
      else raise ArgumentError, "can't differentiate #{expr.class}"
      end
    end

    # A derivative with respect to another variable. D(y, x) of an unknown
    # function y stands for y(x), which depends on x alone, so its
    # derivative in anything else is 0. An explicit expression is another
    # matter: D(x*y, x) is y, and its y-derivative is 1, not the 0 this
    # returned for every other variable (a review, 23 Sept 2026). It is
    # taken first and differentiated again; one that cannot be taken stays
    # a formal mixed derivative rather than becoming 0.
    def derivative(d, var)
      return Derivative.new(d.expr, d.var, d.order + 1) if d.var == var
      return Num.new(0) if d.expr.is_a?(Var) || !d.expr.variables.include?(var.name)
      taken = begin
        d.evaluate
      rescue ArgumentError => e
        raise unless e.message.start_with?(Integrate::NO_DERIVATIVE) # floor(x*y)
        d
      end
      return diff(taken, var) unless taken.each_node.any? { |n| n.is_a?(Derivative) }
      Derivative.new(d, var)
    end

    # A definite integral is a number, but a number that still depends on
    # the parameters of its integrand: d/dx integral(x*t, t, 0, 1) is 1/2,
    # not 0. Only the *integration* variable is bound, and looking at the
    # bounds alone answered every such derivative with zero (22 Sept 2026,
    # from a review). Bounds that move add Leibniz's two boundary terms.
    #
    # The rule is applied, not checked: differentiating under the integral
    # sign needs the integrand and its parameter derivative continuous on
    # the rectangle (and, over an infinite range, the differentiated
    # integral uniformly convergent) - [DLMF, 1.5(iv)]. rcas does not verify
    # that, which is why the answer is another integral rather than a value:
    # what comes out is the derivative wherever the rule applies, and the
    # caller keeps the hypotheses.
    def integral(expr, var)
      unless expr.definite?
        return expr.var == var ? expr.integrand : Integral.new(differentiated(expr, var), expr.var)
      end
      moving = [expr.from, expr.to].any? { |c| c.variables.include?(var.name) }
      # A name bound by the integral is not the free one outside it, even
      # where the two are spelled alike: integral(sin(x), x, 0, x) is the
      # integral(sin(t), t, 0, x) that renaming the bound variable gives, so
      # the integrand contributes nothing and only the bound moves. Refusing
      # it as ambiguous was wrong (22 Sept 2026, the second review).
      bound = expr.var == var
      inside = !bound && expr.integrand.variables.include?(var.name) ? Integral.new(differentiated(expr, var), expr.var, expr.from, expr.to) : Num.new(0)
      return inside unless moving
      at = ->(edge) { Mul.new(expr.integrand.subs(expr.var => edge), diff(edge, var)) }
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
        # d(u**n) = n * u**(n-1) * u' - and 0 when u does not move: sqrt(x - x)
        # is the zero function, and 0**(-1/2)*0 divided by zero (fourth review)
        du = diff(u, var)
        flat = du.is_a?(Num) ? du : du.simplify
        return Num.new(0) if flat.is_a?(Num) && flat.value.is_a?(Numeric) && flat.value.zero?
        Mul.new(Mul.new(n, Pow.new(u, Sub.new(n, Num.new(1)))), du)
      elsif !u.variables.include?(var.name)
        # d(a**v) = a**v * log(a) * v'
        Mul.new(Mul.new(expr, Fn.new(:log, [u])), diff(n, var))
      else
        # general case: u**v * (v' * log(u) + v * u' / u)
        Mul.new(expr, Add.new(Mul.new(diff(n, var), Fn.new(:log, [u])), Div.new(Mul.new(n, diff(u, var)), u)))
      end
    end

    # surd(u, n)**n = u, so surd(u, n)' = u'/(n*surd(u, n)**(n - 1)) where u != 0
    def surd(expr, var)
      u, n = expr.args
      Div.new(diff(u, var), Mul.new(n, Pow.new(expr, Sub.new(n, Num.new(1)))))
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
