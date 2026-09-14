# frozen_string_literal: true

module RCAS
  # Curve sketching and several variables: the calculus a course actually
  # asks for, built from diff, solve and limit.
  #
  #   extrema(x**3 - 3*x, x)        # => [[-1, 2, :maximum], [1, -2, :minimum]]
  #   inflections(x**3 - 3*x, x)    # => [0]
  #   asymptotes((x**2 + 1)/x, x)   # vertical, horizontal and oblique
  #   tangent(x**2, x, 1)           # => -1 + 2*x
  #   gradient(x**2*y, [x, y])      # => (2*x*y, x**2)
  #   hessian(x**2*y, [x, y])       # the second derivatives as a matrix
  #   lagrange(x + y, [x**2 + y**2 - 1], [x, y])
  #
  # Sources (keys: MANUAL.md, Sources): the second-derivative test, the
  # asymptote limits and Lagrange multipliers are the textbook ones
  # [Spi08, ch. 11, 17]; the Hessian and Jacobian follow [Rud76, ch. 9].
  module Analysis
    module_function

    def variable(f, var)
      return Expression.lift(var) if var
      names = Expression.lift(f).variables
      raise ArgumentError, "which variable? give one, e.g. extrema(f, x)" unless names.size == 1
      Var.new(names.first)
    end

    def numeric(value)
      v = Expression.lift(value).evalf
      v.is_a?(Numeric) && !v.is_a?(Complex) && v.finite? ? v.to_f : nil
    rescue StandardError
      nil
    end

    # ---- one variable ----------------------------------------------------------

    # Where the derivative vanishes, sorted where they can be compared.
    def critical_points(f, var = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      sort_points(Solve.solve(f.diff(x), x))
    rescue NotImplementedError, ArgumentError
      []
    end

    def sort_points(points)
      points.sort_by { |p| [numeric(p) ? 0 : 1, numeric(p) || 0.0, p.to_s] }
    end

    # [[x, f(x), :minimum | :maximum | :saddle], ...] by the second derivative,
    # falling back to the sign of the first derivative on either side.
    def extrema(f, var = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      second = f.diff(x, 2)
      critical_points(f, x).filter_map do |point|
        value = (f.subs(x => point)).simplify
        curvature = numeric(second.subs(x => point).simplify)
        kind =
          if curvature.nil? || curvature.abs < 1e-12 then sign_change(f.diff(x), x, point)
          elsif curvature.positive? then :minimum
          else :maximum
          end
        kind ? [point, value, kind] : nil
      end
    end

    # The shape of a critical point from the sign of g on both sides.
    def sign_change(g, x, point)
      centre = numeric(point) or return nil
      step = 1e-4 * [1.0, centre.abs].max
      left = numeric(g.subs(x => Num.new(centre - step)))
      right = numeric(g.subs(x => Num.new(centre + step)))
      return nil if left.nil? || right.nil?
      return :minimum if left.negative? && right.positive?
      return :maximum if left.positive? && right.negative?
      :saddle
    end

    # Where the curvature changes sign.
    def inflections(f, var = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      second = f.diff(x, 2)
      candidates = begin
        Solve.solve(second, x)
      rescue NotImplementedError, ArgumentError
        []
      end
      third = f.diff(x, 3)
      sort_points(candidates.select do |point|
        value = numeric(third.subs(x => point).simplify)
        value.nil? || value.abs > 1e-12 ? true : sign_change(second, x, point) == :saddle
      end)
    end

    # { vertical: [...], horizontal: [...], oblique: [...] }; the horizontal
    # and oblique lines are the limits at minus and plus infinity.
    def asymptotes(f, var = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      { vertical: vertical_asymptotes(f, x), horizontal: horizontal_asymptotes(f, x), oblique: oblique_asymptotes(f, x) }
    end

    def vertical_asymptotes(f, x)
      denominator = RationalFunction.denom(f)
      return [] if denominator.variables.empty?
      poles = begin
        Solve.solve(denominator, x)
      rescue NotImplementedError, ArgumentError
        []
      end
      sort_points(poles.select { |p| Limits.infinite?(Limits.limit(f, x, p, :right)) || Limits.infinite?(Limits.limit(f, x, p, :left)) })
    end

    def horizontal_asymptotes(f, x)
      [OO, Neg.new(OO).simplify].filter_map do |point|
        value = Limits.limit(f, x, point)
        next nil if value.is_a?(Limit) || Limits.infinite?(value)
        value.simplify
      end.uniq
    end

    # y = m*x + c with m the limit of f/x and c the limit of f - m*x.
    def oblique_asymptotes(f, x)
      [OO, Neg.new(OO).simplify].filter_map do |point|
        slope = Limits.limit((f / x).cancel, x, point)
        next nil if slope.is_a?(Limit) || Limits.infinite?(slope) || Scalar.zero?(slope)
        offset = Limits.limit((f - slope * x).cancel, x, point)
        next nil if offset.is_a?(Limit) || Limits.infinite?(offset)
        (slope * x + offset).simplify
      end.uniq
    end

    # The tangent and the normal to the graph at a point.
    def tangent(f, var = nil, at = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      a = Expression.lift(at)
      (f.subs(x => a) + f.diff(x).subs(x => a) * (x - a)).simplify
    end

    def normal(f, var = nil, at = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      a = Expression.lift(at)
      slope = f.diff(x).subs(x => a).simplify
      raise ArgumentError, "normal: the tangent is horizontal at #{a}" if Scalar.zero?(slope)
      (f.subs(x => a) - (x - a) / slope).simplify
    end

    # Where a real expression is defined: denominators non-zero, even roots
    # and logarithms of positive arguments. => a RealSet.
    def real_domain(f, var = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      conditions = []
      denominator = RationalFunction.denom(f)
      conditions << Inequality.new(denominator, :!=, 0) if denominator.variables.include?(x.name)
      f.each_node do |node|
        if node.is_a?(Pow) && node.exponent.is_a?(Num) && node.exponent.value.is_a?(Rational) &&
           node.exponent.value.denominator.even? && node.base.variables.include?(x.name)
          conditions << Inequality.new(node.base, :>=, 0)
        elsif node.is_a?(Fn) && node.name == :log && node.args.first.variables.include?(x.name)
          conditions << Inequality.new(node.args.first, :>, 0)
        end
      end
      return RealSet.reals if conditions.empty?
      conditions.map { |c| Inequalities.solve(c, x) }.reduce(:&)
    end

    # ---- several variables ---------------------------------------------------------

    def variables_of(f, vars)
      return Array(vars).map { |v| Expression.lift(v) } if vars && !Array(vars).empty?
      names = Array(f).flat_map { |g| Expression.lift(g).variables }.uniq.sort
      raise ArgumentError, "name the variables, e.g. gradient(f, [x, y])" if names.empty?
      names.map { |n| Var.new(n) }
    end

    def gradient(f, vars = nil)
      f = Expression.lift(f)
      xs = variables_of(f, vars)
      VectorSpace.new(RR, xs.size).unchecked(xs.map { |x| f.diff(x) })
    end

    def hessian(f, vars = nil)
      f = Expression.lift(f)
      xs = variables_of(f, vars)
      rows = xs.map { |a| xs.map { |b| f.diff(a).diff(b) } }
      MatrixSpace.new(RR, xs.size, xs.size).unchecked(rows)
    end

    def jacobian(fs, vars = nil)
      fs = Array(fs).map { |f| Expression.lift(f) }
      xs = variables_of(fs, vars)
      MatrixSpace.new(RR, fs.size, xs.size).unchecked(fs.map { |f| xs.map { |x| f.diff(x) } })
    end

    def divergence(field, vars = nil)
      fs = Array(field).map { |f| Expression.lift(f) }
      xs = variables_of(fs, vars)
      raise ArgumentError, "divergence: #{fs.size} components for #{xs.size} variables" unless fs.size == xs.size
      fs.each_with_index.map { |f, i| f.diff(xs[i]) }.reduce(:+).simplify
    end

    def laplacian(f, vars = nil)
      f = Expression.lift(f)
      xs = variables_of(f, vars)
      xs.map { |x| f.diff(x, 2) }.reduce(:+).simplify
    end

    def curl(field, vars = nil)
      fs = Array(field).map { |f| Expression.lift(f) }
      xs = variables_of(fs, vars)
      raise ArgumentError, "curl: three components and three variables are needed" unless fs.size == 3 && xs.size == 3
      components = [
        fs[2].diff(xs[1]) - fs[1].diff(xs[2]),
        fs[0].diff(xs[2]) - fs[2].diff(xs[0]),
        fs[1].diff(xs[0]) - fs[0].diff(xs[1])
      ]
      VectorSpace.new(RR, 3).unchecked(components.map(&:simplify))
    end

    # Stationary points of f under the constraints g = 0, by the multiplier
    # rule: grad f = sum(lambda_i grad g_i) together with the constraints.
    def lagrange(f, constraints, vars = nil)
      f = Expression.lift(f)
      gs = Array(constraints).map { |g| Solve.to_zero(g) }
      xs = variables_of([f] + gs, vars)
      multipliers = gs.each_index.map { |i| Var.new(gs.size == 1 ? :lambda : :"lambda#{i + 1}") }
      equations = xs.map do |x|
        gs.each_with_index.reduce(f.diff(x)) { |acc, (g, i)| acc - multipliers[i] * g.diff(x) }.simplify
      end
      solutions = Solve.solve(equations + gs, xs + multipliers)
      solutions.map { |s| xs.to_h { |x| [x, s[x]] } }
    end
  end
end
