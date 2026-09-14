# frozen_string_literal: true

module RCAS
  # D(y, x, n): the n-th derivative of an unknown function y of x, used to
  # write differential equations.
  class Derivative < Expression
    attr_reader :expr, :var, :order

    def initialize(expr, var, order = 1)
      @expr = Expression.lift(expr)
      @var = Expression.lift(var)
      @order = order
      freeze
    end

    def children = [expr, var]
    def rebuild(expr, var) = Derivative.new(expr, var, order)
    def ==(other) = other.is_a?(Derivative) && other.order == order && other.children == children
    alias eql? ==
    def hash = [Derivative, order, expr, var].hash
    def to_sexp = [:D, expr.to_sexp, var.to_sexp, order]
  end

  # Ordinary differential equations:
  #
  #   dsolve(eq(D(y, x), 2*x*y), y, x)              # separable
  #   dsolve(eq(D(y, x) + 2*y, exp(x)), y, x)       # first-order linear
  #   dsolve(D(y, x, 2) - 3*D(y, x) + 2*y, y, x)    # constant coefficients
  #
  # Returns Equation(s) y = ... with constants C1, C2 (or an implicit
  # equation when the separable case cannot be solved for y).
  #
  # Source: the three textbook methods as in [BD12, ch. 2-3] (keys:
  # MANUAL.md, Sources).
  module ODE
    module_function

    def dsolve(equation, y, x)
      yv = Expression.lift(y)
      xv = Expression.lift(x)
      f = Solve.to_zero(equation).simplify
      order = f.each_node.select { |n| n.is_a?(Derivative) && n.expr == yv }.map(&:order).max
      raise ArgumentError, "#{equation} contains no derivative of #{yv}" if order.nil?
      case order
      when 1 then first_order(f, yv, xv)
      when 2 then second_order(f, yv, xv)
      else raise NotImplementedError, "order #{order} equations are not supported"
      end
    end

    # ---- first order ---------------------------------------------------------

    def first_order(f, y, x)
      dy = Var.new(:_dy)
      coeffs = Solve.polynomial_coefficients(f.subs(Derivative.new(y, x) => dy), dy)
      raise NotImplementedError, "the equation must be linear in D(#{y}, #{x})" unless coeffs && coeffs.size == 2
      rhs = (-coeffs[0] / coeffs[1]).simplify # y' = rhs(x, y)
      separable(rhs, y, x) || linear(rhs, y, x) ||
        raise(NotImplementedError, "#{y}' = #{rhs} is neither separable nor linear")
    end

    # y' = g(x) * h(y)
    def separable(rhs, y, x)
      coeff, factors = Simplify.factorize(rhs)
      gx = {}
      hy = {}
      factors.each do |base, exp|
        in_y = Solve.depends?(base, y) || (exp.is_a?(Expression) && Solve.depends?(exp, y))
        in_x = Solve.depends?(base, x) || (exp.is_a?(Expression) && Solve.depends?(exp, x))
        return nil if in_x && in_y
        (in_y ? hy : gx)[base] = exp
      end
      g = Simplify.rebuild_product(coeff, gx)
      h = Simplify.rebuild_product(1, hy)
      left = Integrate.integrate(1 / h, y)
      right = Integrate.integrate(g, x)
      return nil unless Integrate.complete?(left) && Integrate.complete?(right)

      c1 = Var.new(:C1)
      implicit = (left - right - c1).simplify
      begin
        Solve.univariate(implicit, y, 1).map { |s| Equation.new(y, s.simplify) }
      rescue NotImplementedError, ArgumentError
        [Equation.new(left.simplify, (right + c1).simplify)]
      end
    end

    # y' = q(x) - p(x) * y
    def linear(rhs, y, x)
      coeffs = Solve.polynomial_coefficients(rhs, y)
      return nil unless coeffs && coeffs.size == 2
      q = coeffs[0]
      p = (-coeffs[1]).simplify
      mu = Fn.new(:exp, [Integrate.integrate(p, x)]).simplify
      integral = Integrate.integrate((q * mu).simplify, x)
      c1 = Var.new(:C1)
      [Equation.new(y, ((integral + c1) / mu).simplify)]
    end

    # ---- second order, constant coefficients, homogeneous ------------------

    def second_order(f, y, x)
      d1 = Var.new(:_d1)
      d2 = Var.new(:_d2)
      yy = Var.new(:_y)
      g = f.subs(Derivative.new(y, x, 2) => d2, Derivative.new(y, x) => d1, y => yy)
      unknowns = [d2, d1, yy]
      raise NotImplementedError, "only linear equations with constant coefficients are supported" unless Solve.linear_in?(g, unknowns)

      a = Solve.polynomial_coefficients(g, d2)[1] || Num.new(0)
      b = Solve.polynomial_coefficients(g, d1)[1] || Num.new(0)
      c = Solve.polynomial_coefficients(g, yy)[1] || Num.new(0)
      raise ArgumentError, "no second derivative in the equation" if Scalar.zero?(a)
      forcing = g.subs(d2 => 0, d1 => 0, yy => 0).simplify
      [a, b, c].each do |k|
        raise NotImplementedError, "coefficient #{k} is not constant" if Solve.depends?(k, x) || Solve.depends?(k, y)
      end
      raise NotImplementedError, "non-homogeneous equations are not supported (forcing term #{forcing})" unless Scalar.zero?(forcing)

      c1 = Var.new(:C1)
      c2 = Var.new(:C2)
      numeric = [a, b, c].all? { |k| k.is_a?(Num) && !k.value.is_a?(Complex) }
      solution =
        if numeric
          disc = (b**2 - 4 * a * c).simplify
          if Scalar.zero?(disc)
            (c1 + c2 * x) * Fn.new(:exp, [-b / (2 * a) * x])
          elsif Scalar.negative?(disc)
            alpha = (-b / (2 * a)).simplify
            beta = (RCAS.sqrt(-disc) / (2 * a)).simplify
            Fn.new(:exp, [alpha * x]) * (c1 * Fn.new(:cos, [beta * x]) + c2 * Fn.new(:sin, [beta * x]))
          else
            r1, r2 = Solve.quadratic(a, b, c)
            c1 * Fn.new(:exp, [r1 * x]) + c2 * Fn.new(:exp, [r2 * x])
          end
        else
          r1, r2 = Solve.quadratic(a, b, c)
          c1 * Fn.new(:exp, [r1 * x]) + c2 * Fn.new(:exp, [r2 * x])
        end
      [Equation.new(y, solution.simplify)]
    end
  end
end
