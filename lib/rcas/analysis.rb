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
      sort_points(Solve.solve(f.diff(x), x, principal: true).select { |p| real_point?(p) })
    rescue NotImplementedError, ArgumentError
      []
    end

    def sort_points(points)
      points.sort_by { |p| [numeric(p) ? 0 : 1, numeric(p) || 0.0, p.to_s] }
    end

    # A curve discussion is about a real function, so a complex root of the
    # derivative is not a critical point of its graph: critical_points of
    # x**3 + x reported the two roots of 3*x**2 + 1. A point rcas cannot
    # evaluate stays, since not knowing is not the same as knowing it is
    # complex - but one whose imaginary unit is written into it goes.
    def real_point?(point)
      return true if point.is_a?(ImageSet)
      return false if Expression.lift(point).each_node.any? { |n| Simplify.imaginary_unit?(n) }
      value = Expression.lift(point).evalf
      value = value.value if value.is_a?(Num)
      return true unless value.is_a?(Numeric)
      !value.is_a?(Complex) || value.imaginary.abs < 1e-12
    rescue StandardError
      true
    end

    # [[x, f(x), :minimum | :maximum | :saddle], ...] by the second derivative,
    # falling back to the sign of the first derivative on either side.
    # `points` supplies the critical points, for a caller that knows them
    # (or can find more of them) already.
    def extrema(f, var = nil, points: nil)
      f = Expression.lift(f)
      x = variable(f, var)
      second = f.diff(x, 2)
      (points || critical_points(f, x)).filter_map do |point|
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

    # Where the curvature changes sign; `points` supplies the zeros of the
    # second derivative, as for extrema.
    def inflections(f, var = nil, points: nil)
      f = Expression.lift(f)
      x = variable(f, var)
      second = f.diff(x, 2)
      candidates = points || begin
        Solve.solve(second, x, principal: true)
      rescue NotImplementedError, ArgumentError
        []
      end
      third = f.diff(x, 3)
      # f''' != 0 at a zero of f'' settles it. Where the third derivative
      # vanishes too - x**4 and x**5 both have f'' = f''' = 0 at the origin
      # - only the sign of f'' on the two sides decides, and it has to
      # really change: sign_change answers :saddle when it does *not*, and
      # accepting that case reported an inflection of x**4 at 0 and none of
      # x**5 (22 Sept 2026, from a review). An undecided third derivative
      # goes the same way rather than counting as a change by itself.
      sort_points(candidates.select { |p| real_point?(p) }.select do |point|
        value = numeric(third.subs(x => point).simplify)
        value && value.abs > 1e-12 ? true : %i[minimum maximum].include?(sign_change(second, x, point))
      end)
    end

    # { vertical: [...], horizontal: [...], oblique: [...] }; the horizontal
    # and oblique lines are the limits at minus and plus infinity. `at` names
    # the ends to look at, for a function that only reaches one of them.
    def asymptotes(f, var = nil, at: nil)
      f = Expression.lift(f)
      x = variable(f, var)
      ends = at || infinities
      { vertical: vertical_asymptotes(f, x), horizontal: horizontal_asymptotes(f, x, at: ends), oblique: oblique_asymptotes(f, x, at: ends) }
    end

    def infinities = [OO, Neg.new(OO).simplify]

    def vertical_asymptotes(f, x)
      poles = denominators(f, x).flat_map do |denominator|
        Solve.solve(denominator, x)
      rescue NotImplementedError, ArgumentError
        []
      end
      sort_points(poles.uniq.select { |p| runs_away?(f, x, p) })
    end

    # A whole family of asymptotes is reported as the family: tan has one
    # at every odd multiple of pi/2, and a member of the set stands for all
    # of them when the limit is taken.
    def runs_away?(f, x, point)
      probe = point.is_a?(ImageSet) ? point.at(0) : point
      Limits.infinite?(Limits.limit(f, x, probe, :right)) || Limits.infinite?(Limits.limit(f, x, probe, :left))
    rescue StandardError
      false
    end

    # The denominators f divides by: the one of its normal form, the ones it
    # is written with, which the normal form may have cancelled away
    # ((x**2 - 1)/(x - 1) is still undefined at 1), and the one tan hides -
    # tan(u) is sin(u)/cos(u), so it has a pole wherever cos(u) vanishes,
    # and without that a tangent had no asymptotes and no gaps at all.
    def denominators(f, x)
      found = [RationalFunction.denom(f)]
      f.each_node do |node|
        case node
        when Div then found << node.right
        when Fn then found << Fn.new(:cos, [node.args.first]) if node.name == :tan
        when Pow
          exponent = node.exponent
          found << node.base if exponent.is_a?(Num) && exponent.value.is_a?(Numeric) &&
                                !exponent.value.is_a?(Complex) && exponent.value.negative?
        end
      end
      found.select { |d| d.variables.include?(x.name) }.uniq
    end

    def horizontal_asymptotes(f, x, at: nil)
      (at || infinities).filter_map do |point|
        value = Limits.limit(f, x, point)
        next nil if value.is_a?(Limit) || Limits.infinite?(value)
        value.simplify
      end.uniq
    end

    # y = m*x + c with m the limit of f/x and c the limit of f - m*x.
    def oblique_asymptotes(f, x, at: nil)
      (at || infinities).filter_map do |point|
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
      conditions = domain_conditions(f, x)
      return RealSet.reals if conditions.empty?
      conditions.map { |c| solved_condition(c, x) }.reduce(:&)
    end

    # A condition rcas cannot solve is not an empty one: dropping it would
    # claim the function is defined where nobody has looked. The message
    # says which condition it was, in rcas's own words rather than as a
    # backtrace out of Inequalities.
    def solved_condition(condition, x)
      Inequalities.solve(condition, x)
    rescue NotImplementedError => e
      # cause: nil, or irb prints this backtrace and the one underneath it
      raise NotImplementedError, "real_domain: where #{condition} holds is not decided here (#{e.message})", cause: nil
    end

    # The inverse functions whose real argument has to stay in [-1, 1].
    # Past that they do have a value, off the real line (Functions
    # .real_branch), which is exactly why the condition has to be named
    # here: real_domain(asin(x), x) answered with the whole line before
    # (20 Sept 2026, after the tenth pass of the review).
    BOUNDED_INVERSES = %i[asin acos].freeze

    # A condition is worth recording when its argument moves with x, and
    # also when it moves with nothing at all: log(-1) + x is real nowhere,
    # and skipping the constant condition claimed the whole line (22 Sept
    # 2026, from a review). An argument in a *parameter* is left alone,
    # because the answer would then be a case split on the parameter rather
    # than a domain.
    def condition_argument?(u, x) = u.variables.include?(x.name) || u.variables.empty?

    # The conditions behind that domain, so that a caller can name them:
    # one per denominator, even root and logarithm, and two for each
    # asin or acos.
    def domain_conditions(f, x)
      conditions = denominators(f, x).map { |d| Inequality.new(d, :!=, 0) }
      f.each_node do |node|
        if node.is_a?(Pow) && node.exponent.is_a?(Num) && node.exponent.value.is_a?(Rational) &&
           node.exponent.value.denominator.even? && condition_argument?(node.base, x)
          conditions << Inequality.new(node.base, :>=, 0)
        elsif node.is_a?(Fn) && node.name == :log && condition_argument?(node.args.first, x)
          conditions << Inequality.new(node.args.first, :>, 0)
        elsif node.is_a?(Fn) && BOUNDED_INVERSES.include?(node.name) && condition_argument?(node.args.first, x)
          conditions << Inequality.new(node.args.first, :>=, Num.new(-1))
          conditions << Inequality.new(node.args.first, :<=, Num.new(1))
        end
      end
      conditions
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

    # ---- lengths, areas, volumes ---------------------------------------------

    # The length of a curve: integral(sqrt(1 + f'**2)) for a graph and
    # integral(sqrt(x'**2 + y'**2)) for [x(t), y(t)], in space too. The integral is
    # rarely elementary and then stays an integral(...) node, which evalf
    # or nintegrate finishes.
    def arclength(f, var, from, to)
      var = Expression.lift(var)
      integrand =
        if f.is_a?(Array)
          raise ArgumentError, "arclength: a parametric curve needs two or three components" unless [2, 3].include?(f.size)
          f.map { |c| Expression.lift(c).diff(var)**2 }.reduce(:+)
        else
          Num.new(1) + Expression.lift(f).diff(var)**2
        end
      Integrate.definite(root(integrand), var, from, to)
    end

    # The volume of the solid the graph of f sweeps out: pi*integral(f**2)
    # about the x-axis, and 2*pi*integral(x*f) (cylindrical shells) about
    # the y-axis. Radius and height are distances, so the shell integrand
    # takes both of them in absolute value - the cylinder of radius and
    # height one came out as -pi over x: -1..0 before (22 Sept 2026, from a
    # review).
    def revolution_volume(f, var, from, to, axis: :x)
      f = Expression.lift(f)
      var = Expression.lift(var)
      integrand =
        if axis == :y
          one_side!(var, from, to, "revolution_volume")
          2 * PI * distance(var, var, from, to) * distance(f, var, from, to)
        else
          PI * f**2
        end
      Integrate.definite(integrand.simplify, var, from, to)
    end

    # The area of the surface of revolution: 2*pi*integral(f*sqrt(1 + f'**2))
    # about the x-axis, 2*pi*integral(x*sqrt(1 + f'**2)) about the y-axis.
    # The radius is the distance to the axis, abs(f) or abs(x), and not the
    # signed value: the cylinder of radius one had area -2*pi for f = -1.
    def revolution_surface(f, var, from, to, axis: :x)
      f = Expression.lift(f)
      var = Expression.lift(var)
      one_side!(var, from, to, "revolution_surface") if axis == :y
      radius = axis == :y ? distance(var, var, from, to) : distance(f, var, from, to)
      line = root(Num.new(1) + f.diff(var)**2)
      Integrate.definite((2 * PI * radius * line).simplify, var, from, to)
    end

    # |u| on the interval, written without the abs where the sign of u is
    # decided there (VectorCalculus.sign_on samples it), because an abs the
    # integrator cannot see through would leave the answer formal.
    def distance(u, var, from, to)
      u = Expression.lift(u)
      case VectorCalculus.sign_on(u, [[var, from, to]])
      when :positive then u
      when :negative then Neg.new(u).simplify
      else Fn.new(:abs, [u])
      end
    end

    # Shells about the y-axis stand on one side of it; a range that crosses
    # the axis would have the two halves sweeping the same shells, which
    # abs(x) would then count twice. Splitting the range is the reader's
    # call, so rcas says so instead of answering.
    def one_side!(var, from, to, who)
      a = numeric(from)
      b = numeric(to)
      return if a.nil? || b.nil? || a * b >= 0
      raise ArgumentError, "#{who}: the range #{var} = #{from}..#{to} crosses the axis of revolution; take the two sides separately"
    end

    def root(u) = Pow.new(u.simplify, Num.new(Rational(1, 2))).simplify

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
      solutions = Solve.solve(equations + gs, xs + multipliers, principal: true)
      solutions.map { |s| xs.to_h { |x| [x, s[x]] } }
    end
  end
end
