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

    def numeric(value) = RCAS.real_float(value)

    # ---- one variable ----------------------------------------------------------

    # Where the derivative vanishes, sorted where they can be compared.
    #
    # An equation solve cannot do is a refusal, not "no critical points":
    # cos(x) + x**2/4 has its maximum at 0 all the same (third review,
    # S11). Points where f itself has no value are not points of its graph.
    def critical_points(f, var = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      found = Solve.solve(f.diff(x), x, principal: true)
      raise RCAS::Unsupported, "critical points of #{f}: the derivative vanishes on a whole interval" unless found.is_a?(Array)
      sort_points(found.select { |p| real_point?(p) && defined_at?(f, x, p) })
    end

    # f has a real value at the point (a family counts as defined).
    def defined_at?(f, x, point)
      return true if point.is_a?(ImageSet)
      value = f.subs(x => point).simplify
      return false unless Integrate.defined_value?(value)
      real = Inequalities.real?(value)
      real != false
    rescue ZeroDivisionError
      false
    rescue NotImplementedError, RCAS::Unsupported
      true # realness undecided: the point is kept, and says so nowhere else
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      true
    end

    def sort_points(points)
      points.sort_by { |p| [numeric(p) ? 0 : 1, numeric(p) || 0.0, p.to_s] }
    end

    # A curve discussion is about a real function, so a complex root of the
    # derivative is not a critical point of its graph: critical_points of
    # x**3 + x reported the two roots of 3*x**2 + 1. A point rcas cannot
    # evaluate stays, since not knowing is not the same as knowing it is
    # complex - but one whose imaginary unit is written into it goes.
    # Decided exactly (Inequalities.real?): 1 + 10**-13*i is not real,
    # however small its imaginary part (third review, Q1); an unevaluated
    # log(-1) is not either.
    def real_point?(point)
      return true if point.is_a?(ImageSet)
      Inequalities.real?(point)
    rescue NotImplementedError, RCAS::Unsupported
      true # not knowing is not knowing it is complex
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      true
    end

    # [[x, f(x), :minimum | :maximum | :saddle], ...] by the second derivative,
    # falling back to the sign of the first derivative on either side.
    # `points` supplies the critical points, for a caller that knows them
    # (or can find more of them) already.
    #
    # The kind is decided by the first derivative of f that does not vanish
    # at the point, which is exact: an even order is an extremum, an odd
    # one a saddle. The old test read f'' against 1e-12 and then sampled f'
    # at +-1e-4, which stepped over a zero of f' at 10**-5 and called a
    # saddle a minimum (third review, S10).
    def extrema(f, var = nil, points: nil)
      f = Expression.lift(f)
      x = variable(f, var)
      first = f.diff(x)
      candidates = points || critical_points(f, x)
      candidates.filter_map do |point|
        next nil unless defined_at?(f, x, point)
        value = (f.subs(x => point)).simplify
        kind = extremum_kind(first, x, point, candidates)
        kind ? [point, value, kind] : nil
      end
    end

    def extremum_kind(first, x, point, others)
      found = vanishing(first, x, point)
      if found
        order, sign = found
        return :saddle if order.even? # f' vanishes to an even order: f has an odd one
        return sign == :positive ? :minimum : :maximum
      end
      sign_change(first, x, point, step: safe_step(point, others))
    end

    # [k, sign] for the smallest k >= 1 with g^(k)(point) != 0 decided, or
    # nil when that cannot be told within the budget.
    def vanishing(g, x, point, limit = nil)
      limit ||= vanishing_limit(g, x)
      limit.times do |k|
        g = g.diff(x)
        value = g.subs(x => point).simplify
        if value.variables.empty?
          sign = Decide.sign(value)
          return nil if sign.nil?
          next if sign == :zero
          return [k + 1, sign]
        end
        next if Scalar.zero?(value)
        # 6*a at 0 for a*x**3 + x**4: whether it vanishes depends on a
        raise RCAS::Unsupported, "whether #{value} is zero decides the shape at #{point}; assume something about #{value.variables.join(', ')}"
      end
      nil
    rescue ArgumentError
      nil
    end

    # The shape of a critical point from the sign of g on both sides. The
    # step must stay inside the point's own neighbourhood: with a zero of g
    # at 10**-5 next door, the default 10**-4 samples the far side of it and
    # reads the wrong sign (22 Sept 2026, from the second review).
    # The signs are decided exactly at rational points (Decide), so an
    # underflow is not read as a zero (T4a).
    def sign_change(g, x, point, step: nil)
      centre = numeric(point) or return nil
      step ||= 1e-4 * [1.0, centre.abs].max
      return nil unless step&.positive?
      exact = Expression.lift(point)
      delta = Num.new(Rational(step).rationalize(Rational(step) / 1000))
      left = Decide.sign(g.subs(x => (exact - delta).simplify).simplify)
      right = Decide.sign(g.subs(x => (exact + delta).simplify).simplify)
      return nil unless %i[positive negative].include?(left) && %i[positive negative].include?(right)
      return :minimum if left == :negative && right == :positive
      return :maximum if left == :positive && right == :negative
      :saddle
    end

    # Where the curvature changes sign; `points` supplies the zeros of the
    # second derivative, as for extrema.
    #
    # "Cannot solve f'' = 0" is a refusal, never "no inflections": x*sin(x)
    # has f''(0) = 2 and f''(pi) = -2, so there is one in between (T4b).
    # A point outside the domain of f is no point of the graph (S14).
    def inflections(f, var = nil, points: nil)
      f = Expression.lift(f)
      x = variable(f, var)
      second = f.diff(x, 2)
      candidates = points || Solve.solve(second, x, principal: true)
      raise RCAS::Unsupported, "inflections of #{f}: f'' vanishes on a whole interval" unless candidates.is_a?(Array)
      real = candidates.select { |p| real_point?(p) && defined_at?(f, x, p) }
      sort_points(real.select { |point| inflection_at?(second, x, point, real) })
    end

    # How far a derivative of g has to be taken before it stops vanishing,
    # for anything that is not a polynomial; a polynomial has its degree as
    # the bound, so x**17 is decided however small its coefficient (T4a).
    MAX_VANISHING = 12

    def vanishing_limit(g, x)
      coefficients = Solve.polynomial_coefficients(g.expand, x)
      coefficients ? [coefficients.size, 1].max : MAX_VANISHING
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      MAX_VANISHING
    end

    # f'' changes sign at one of its zeros exactly when it vanishes there to
    # an *odd* order [Spi08, ch. 11], and that order is the first derivative of f'' that
    # does not vanish - which `Scalar.zero?` decides exactly for a rational
    # point of a polynomial. This replaces the old test, which asked whether
    # f''' was numerically above 10**-12 and fell back to a sign chart: with
    # f'' = x**2*(x - a) and a = 10**-5 the chart stepped over a and
    # reported an inflection at 0, and with f'' = x**3*(x - a) the exactly
    # non-zero f'''(a) = a**3 = 10**-15 was read as zero (22 Sept 2026, the
    # second review). The chart is now the fallback, on a step that stays
    # inside the point's own neighbourhood; when even that cannot decide,
    # the answer is "undecided" and not "no inflection".
    def inflection_at?(second, x, point, others)
      found = begin
        vanishing(second, x, point)
      rescue NotImplementedError, RCAS::Unsupported
        # a parameter decides the order, but maybe not its parity: f'' =
        # 6*a*x + 20*x**3 vanishes to order 1 for a != 0 and 3 for a = 0,
        # an inflection either way (the review's S22 had "6*a decides")
        parities = possible_orders(second, x, point)&.map(&:odd?)&.uniq
        return parities.first if parities&.size == 1
        raise
      end
      return found.first.odd? if found
      change = sign_change(second, x, point, step: safe_step(point, others))
      return change != :saddle if change
      raise RCAS::Unsupported, "inflections: whether the curvature changes at #{point} is not decided here"
    end

    # The orders g could vanish to at the point, over the parameters: each
    # derivative whose value there depends on a parameter is where it
    # stops if that value is not 0, and the search goes on for the case
    # that it is; a constant that is not 0 ends it. nil when undecided.
    def possible_orders(g, x, point)
      orders = []
      vanishing_limit(g, x).times do |k|
        g = g.diff(x)
        value = g.subs(x => point).simplify
        if value.variables.empty?
          sign = Decide.sign(value)
          return nil if sign.nil?
          next if sign == :zero
          return orders << k + 1
        end
        orders << k + 1 unless Scalar.zero?(value)
      end
      nil
    end

    # The smallest k >= 1 with g^(k)(point) != 0, or nil.
    def vanishing_order(g, x, point, limit = nil) = vanishing(g, x, point, limit)&.first

    # Half the way to the nearest other candidate, at most the default step:
    # no sample may cross a neighbouring zero.
    def safe_step(point, others)
      centre = numeric(point) or return nil
      step = 1e-4 * [1.0, centre.abs].max
      gaps = others.filter_map { |q| (v = numeric(q)) && (v - centre).abs }.reject { |d| d < 1e-15 }
      gaps.empty? ? step : [step, gaps.min / 2].min
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

    # The candidates are the zeros of the denominators and the edges of the
    # logarithms' domains - log(x) runs to -oo at 0, which a search of the
    # denominators alone never saw (S12). A denominator whose zeros solve
    # cannot name is a refusal: 1/(exp(x) - x - 2) has two poles (S11).
    def vertical_asymptotes(f, x)
      edges = []
      f.each_node { |n| edges << n.args.first if n.is_a?(Fn) && n.name == :log && n.args.first.variables.include?(x.name) }
      poles = (denominators(f, x) + edges).uniq.flat_map do |g|
        found = Solve.solve(g, x, domain: RR)
        raise RCAS::Unsupported, "vertical asymptotes of #{f}: #{g} = 0 vanishes on a whole interval" unless found.is_a?(Array)
        found
      end
      sort_points(poles.uniq.select { |p| real_point?(p) && runs_away?(f, x, p) })
    end

    # A whole family of asymptotes is reported as the family: tan has one
    # at every odd multiple of pi/2, and a member of the set stands for all
    # of them when the limit is taken.
    # Either side infinite is an asymptote, both finite is none, and a limit
    # rcas cannot take is neither: a refusal (fourth review, S11). A side
    # where f has no real values (left of 0 for 1/log(x)) does not count.
    def runs_away?(f, x, point)
      probe = point.is_a?(ImageSet) ? point.at(0) : point
      sides = %i[right left].map { |side| Limits.limit(f, x, probe, side) }
      return true if sides.any? { |v| Limits.infinite?(v) }
      sides = sides.zip([1, -1]).reject { |v, side| v.is_a?(Limit) && !real_beside?(f, x, probe, side) }.map(&:first)
      return false if sides.none? { |v| v.is_a?(Limit) }
      raise RCAS::Unsupported, "vertical asymptotes of #{f}: the limit at #{probe} is not decided here"
    rescue ZeroDivisionError
      false
    end

    # f has real values out towards an infinity: false only when that is
    # decided at +-1000.
    def real_toward?(f, x, point)
      value = f.subs(x => Num.new(point == OO ? 1000 : -1000)).simplify
      Inequalities.real?(value) != false
    rescue ZeroDivisionError, NotImplementedError, RCAS::Unsupported
      true
    end

    # f has real values just to one side of the point: false only when that
    # is decided at a point 1/1000 away.
    def real_beside?(f, x, point, side)
      value = f.subs(x => (Expression.lift(point) + Num.new(Rational(side, 1000))).simplify).simplify
      Inequalities.real?(value) != false
    rescue ZeroDivisionError, NotImplementedError, RCAS::Unsupported
      true
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
        next nil if value.is_a?(Limit) && !real_toward?(f, x, point) # 1/log(x) towards -oo
        raise RCAS::Unsupported, "horizontal asymptotes of #{f}: the limit at #{point} is not decided here" if value.is_a?(Limit)
        next nil if Limits.infinite?(value) || value == UNDEFINED
        value.simplify
      end.uniq
    end

    # y = m*x + c with m the limit of f/x and c the limit of f - m*x.
    def oblique_asymptotes(f, x, at: nil)
      (at || infinities).filter_map do |point|
        # only a function that runs away has an oblique asymptote there
        value = Limits.limit(f, x, point)
        next nil if value.is_a?(Limit) && !real_toward?(f, x, point)
        raise RCAS::Unsupported, "oblique asymptotes of #{f}: the limit at #{point} is not decided here" if value.is_a?(Limit)
        next nil unless Limits.infinite?(value)
        slope = Limits.limit((f / x).cancel, x, point)
        raise RCAS::Unsupported, "oblique asymptotes of #{f}: the limit of f/x at #{point} is not decided here" if slope.is_a?(Limit)
        next nil if Limits.infinite?(slope) || slope == UNDEFINED || Scalar.zero?(slope)
        offset = Limits.limit((f - slope * x).cancel, x, point)
        raise RCAS::Unsupported, "oblique asymptotes of #{f}: the limit of f - #{slope}*x at #{point} is not decided here" if offset.is_a?(Limit)
        next nil if Limits.infinite?(offset) || offset == UNDEFINED
        (slope * x + offset).simplify
      end.uniq
    end

    # The tangent and the normal to the graph at a point.
    # A vertical tangent (sqrt(x) at 0) is no line y = m*x + c: refused
    # with a message rather than a ZeroDivisionError (S17).
    def tangent(f, var = nil, at = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      a = Expression.lift(at)
      slope = begin
        f.diff(x).subs(x => a).simplify
      rescue ZeroDivisionError
        raise ArgumentError, "tangent: #{f} has no finite slope at #{x} = #{a}; the tangent there is vertical or does not exist"
      end
      raise ArgumentError, "tangent: #{f} has no finite slope at #{x} = #{a}" if Limits.infinite?(slope) || slope == UNDEFINED
      differentiable!(f, x, a, "tangent")
      value = f.subs(x => a).simplify
      (value + slope * (x - a)).simplify
    end

    # A kink of abs, sign, floor, ceil or round at the point: the formula
    # for f' there says sign(0) = 0, and |x| got the tangent y = 0 at its
    # corner (fourth review). The one-sided limits of f' decide - they have
    # to exist and agree - and what they cannot decide is refused.
    def differentiable!(f, x, a, name)
      kinks = f.each_node.select { |n| n.is_a?(Fn) && Limits::KINKED.include?(n.name) && n.args.first.variables.include?(x.name) }
      at_kink = kinks.any? do |n|
        u = n.args.first.subs(x => a).simplify
        case n.name
        when :abs, :sign then Decide.zero?(u) != false
        else Decide.zero?((u - Fn.new(:round, [u])).simplify) != false || n.name == :round
        end
      end
      return unless at_kink
      derivative = f.diff(x)
      left, right = %i[left right].map { |side| Limits.limit(derivative, x, a, side) }
      return if [left, right].none? { |v| v.is_a?(Limit) || Limits.infinite?(v) || v == UNDEFINED } && Scalar.zero?((left - right).simplify)
      raise ArgumentError, "#{name}: #{f} has no tangent at #{x} = #{a}: the slopes from the left (#{left}) and the right (#{right}) differ there"
    end

    def normal(f, var = nil, at = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      a = Expression.lift(at)
      slope = f.diff(x).subs(x => a).simplify
      differentiable!(f, x, a, "normal")
      raise ArgumentError, "normal: the tangent is horizontal at #{a}" if Scalar.zero?(slope)
      (f.subs(x => a) - (x - a) / slope).simplify
    end

    # Where a real expression is defined: denominators non-zero, even roots
    # and logarithms of positive arguments. => a RealSet.
    def real_domain(f, var = nil)
      f = Expression.lift(f)
      x = variable(f, var)
      parameters, conditions = domain_conditions(f, x).partition { |c| parameter_condition?(c, x) }
      parameters.each do |c|
        decided = decide_without_x(c)
        raise RCAS::Unsupported, "real_domain: whether #{c} holds depends on #{c.lhs.variables.join(', ')}; assume a sign for it" if decided.nil?
        return RealSet.empty unless decided
      end
      set = conditions.empty? ? RealSet.reals : conditions.map { |c| solved_condition(c, x) }.reduce(:&)
      real = real_locus(f, x)
      real ? set & real : set
    end

    # A condition about parameters alone. It cannot be solved for x, so it
    # is decided instead: with `assume(a < 0)` the logarithm in log(a) + x
    # has no real value anywhere, and skipping the condition claimed the
    # whole line (22 Sept 2026, from the second review).
    def parameter_condition?(c, x) = !c.lhs.variables.empty? && !c.lhs.variables.include?(x.name)

    # true, false, or nil when the assumptions do not settle it.
    def decide_without_x(c)
      return nil unless c.rhs.is_a?(Num) && c.rhs.zero?
      sign = RCAS.sign_of(c.lhs)
      case c.op
      when :> then POSITIVE.include?(sign) ? true : (NONPOSITIVE.include?(sign) ? false : nil)
      when :>= then NONNEGATIVE.include?(sign) ? true : (sign == :negative ? false : nil)
      when :!= then sign == :zero ? false : (SIGNED.include?(sign) ? true : nil)
      end
    end

    POSITIVE = %i[positive].freeze
    NONPOSITIVE = %i[negative nonpositive zero].freeze
    NONNEGATIVE = %i[positive nonnegative zero].freeze
    SIGNED = %i[positive negative].freeze

    # Where an expression carrying i is real at all: its imaginary part has
    # to vanish, so real_domain(I*x, x) is {0} and not the whole line, and
    # x + i is real nowhere (22 Sept 2026, from the second review; the first
    # review had asked for this and the answer then was that it was a gap).
    # Only an explicit complex number puts the question, so nothing without
    # one pays for it. => a RealSet, or nil when there is no condition.
    #
    # "Explicit" was too narrow: (-1)**sqrt(2) is exp(i*pi*sqrt(2)), complex
    # without an i in sight, and real_domain((-1)**sqrt(2) + x) said the whole
    # line (third review, T5a). A constant part shown not to be real puts the
    # question too.
    # A point is in the real domain when every subexpression is real and
    # defined there - Mathematica's rule for FunctionDomain, and the fifth
    # review's decision - so a subexpression that is a non-real constant
    # leaves nothing: i*sqrt(x) and x*log(-2) are real nowhere, however
    # their values fall. "Where is the value real" is another question, asked
    # as solve(im(f) == 0, x). The expression is simplified first, so that
    # (1 + i)*(1 - i)*x, which is 2*x, keeps its line.
    def real_locus(f, x)
      scattered = scattered_set(f, x)
      g = f.simplify
      nonreal = g.each_node.any? do |n|
        (n.is_a?(Num) && n.value.is_a?(Complex) && !n.value.imaginary.zero?) ||
          ((n.is_a?(Pow) || n.is_a?(Fn)) && n.variables.empty? && nonreal_constant?(n))
      end
      nonreal ? RealSet.empty : scattered
    end

    def nonreal_constant?(n)
      Inequalities.real?(n) == false
    rescue NotImplementedError, RCAS::Unsupported
      false
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    # b**u with u moving with x and b possibly negative is real on a
    # scattered set, and gamma(u) off one: (-2)**x at the integers, x**x on
    # (0, oo) and at the negative integers, gamma(x) off 0, -1, -2, ... No
    # finite union of intervals is that (S15), so the answer is a
    # ScatteredSet, for a linear argument or exponent; nil when f has no
    # such part, and a refusal for a shape that is not named here or for
    # more than one of them.
    def scattered_set(f, x)
      found = []
      f.each_node do |n|
        if n.is_a?(Fn) && %i[gamma factorial].include?(n.name) && n.args.first.variables.include?(x.name)
          found << poles_of_gamma(n, x)
          next
        end
        next unless n.is_a?(Pow) && n.exponent.variables.include?(x.name)
        base = n.base
        sign = base.variables.empty? ? Decide.sign(base) : RCAS.assume(x.name => RR) { RCAS.sign_of(base) }
        next if sign == :positive
        found << scattered_power(n, x)
      end
      found = found.uniq
      return nil if found.empty?
      raise RCAS::Unsupported, "real_domain: #{f} is real on the meeting of several scattered sets, which is not written here" if found.size > 1
      found.first
    end

    # gamma(a*x + b) has a pole where a*x + b is 0, -1, -2, ...; factorial(u)
    # where u is -1, -2, ...
    def poles_of_gamma(n, x)
      coefficients = Solve.polynomial_coefficients(n.args.first, x)
      unless coefficients&.size == 2 && coefficients.none? { |c| c.variables.any? }
        raise RCAS::Unsupported, "real_domain: #{n} has a pole at every point where its argument is a non-positive integer"
      end
      b, a = coefficients
      k = Var.new(:k)
      top = n.name == :gamma ? Neg.new(k) : Neg.new(k) - 1
      ScatteredSet.new(RealSet.reals, minus: [ImageSet.new(((top - b) / a).simplify, [k], NN)])
    end

    # c**(a*x + b) for a negative constant c is real where the exponent is a
    # whole number, since it is |c|**u*exp(i*pi*u); x**x (principal powers
    # all through) is real for x > 0 and at the negative integers.
    def scattered_power(n, x)
      k = Var.new(:k)
      if n.base.variables.empty? && Decide.sign(n.base) == :negative
        coefficients = Solve.polynomial_coefficients(n.exponent, x)
        if coefficients&.size == 2 && coefficients.none? { |c| c.variables.any? }
          b, a = coefficients
          return ScatteredSet.new(RealSet.empty, plus: [ImageSet.new(((k - b) / a).simplify, [k], ZZ)])
        end
      elsif n.base == x && n.exponent == x
        return ScatteredSet.new(RealSet.new([Interval.open(Num.new(0), OO)]), plus: [ImageSet.new((Neg.new(k) - 1).simplify, [k], NN)])
      end
      raise RCAS::Unsupported, "real_domain: #{n} is real only on a scattered set of points where its base is negative"
    end

    # A condition rcas cannot solve is not an empty one: dropping it would
    # claim the function is defined where nobody has looked. The message
    # says which condition it was, in rcas's own words rather than as a
    # backtrace out of Inequalities.
    def off_zeros(d, x)
      zeros = Solve.solve(d, x, domain: RR)
      return nil unless zeros.is_a?(Array) && zeros.all? { |z| z.is_a?(Expression) && z.variables.empty? }
      real = zeros.select { |z| Inequalities.real?(z) }.map { |z| Inequalities.real_part(z) }
      real.empty? ? RealSet.reals : RealSet.reals - RealSet.new(real.map { |z| Interval.point(z) })
    rescue NotImplementedError, RCAS::Unsupported, ArgumentError
      nil
    end

    def solved_condition(condition, x)
      Inequalities.solve(condition, x)
    rescue NotImplementedError, RCAS::Unsupported => e
      # d != 0 is the line less the zeros of d, which solve names for more
      # than polynomials (log(x) != 0 is every x but 1)
      if condition.op == :!= && (off = off_zeros(condition.lhs - condition.rhs, x))
        return off
      end
      # cause: nil, or irb prints this backtrace and the one underneath it
      raise RCAS::Unsupported, "real_domain: where #{condition} holds is not decided here (#{e.message})", cause: nil
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
    def condition_argument?(u, x) = true

    # The conditions behind that domain, so that a caller can name them:
    # one per denominator, even root and logarithm, and two for each
    # asin or acos.
    def domain_conditions(f, x)
      conditions = denominators(f, x).map { |d| Inequality.new(d, :!=, 0) }
      f.each_node do |node|
        # every fractional power is the principal one, real only for a base
        # that is not negative - x**(1/3) too; surd(x, 3) is the real root
        # (the fifth review's decision on odd roots)
        if node.is_a?(Pow) && node.exponent.is_a?(Num) && node.exponent.value.is_a?(Rational) &&
           node.exponent.value.denominator > 1 && condition_argument?(node.base, x)
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

    # A word for a reader who wrote x**(1/3) and meant the real cube root:
    # ** is the principal root, which has no real value for a negative base
    # (the fifth review's decision), and surd is the real one. One hint per
    # such power whose base moves with x.
    def root_hints(f, x)
      Expression.lift(f).each_node.select do |n|
        n.is_a?(Pow) && n.exponent.is_a?(Num) && n.exponent.value.is_a?(Rational) &&
          n.exponent.value.denominator.odd? && n.exponent.value.denominator > 1 && n.base.variables.include?(x.name)
      end.uniq.map do |n|
        q = n.exponent.value.denominator
        name = q == 3 ? "cube" : "#{q}th"
        "#{n} has no real value where #{n.base} < 0; surd(#{n.base}, #{q}) is the real #{name} root"
      end
    end

    COORDINATES = %i[x y z].freeze

    # The coordinates, named rather than guessed (the fifth review's
    # decision, as Mathematica and MuPAD ask for the list): the ones given,
    # or the free names when they are among x, y and z, or - for a field in
    # names of its own - when there are as many of them as components
    # (line_integral's rule).
    # Anything else is refused with the name that is in the way: in
    # x**2 + a*y, a is a parameter, and the gradient had a third component.
    def variables_of(f, vars, components: nil, name: "gradient")
      return Array(vars).map { |v| Expression.lift(v) } if vars && !Array(vars).empty?
      names = Array(f).flat_map { |g| Expression.lift(g).variables }.uniq.sort
      raise ArgumentError, "name the variables, e.g. #{name}(f, [x, y])" if names.empty?
      # the count rule is for a field in names of its own (u, v); a field
      # that uses x or y and one more name has a parameter in it
      counted = names.size == components && (names & COORDINATES).empty?
      return names.map { |n| Var.new(n) } if (names - COORDINATES).empty? || counted
      extra = names - COORDINATES
      coordinates = names & COORDINATES
      suggestion = coordinates.empty? ? names : coordinates
      raise ArgumentError, "#{name}: #{extra.join(', ')} #{extra.size == 1 ? 'is' : 'are'} not a coordinate; " \
                           "pass the coordinates, e.g. #{name}(f, [#{suggestion.join(', ')}])"
    end

    def gradient(f, vars = nil)
      f = Expression.lift(f)
      xs = variables_of(f, vars)
      VectorSpace.new(RR, xs.size).unchecked(xs.map { |x| f.diff(x) })
    end

    def hessian(f, vars = nil)
      f = Expression.lift(f)
      xs = variables_of(f, vars, name: "hessian")
      rows = xs.map { |a| xs.map { |b| f.diff(a).diff(b) } }
      MatrixSpace.new(RR, xs.size, xs.size).unchecked(rows)
    end

    def jacobian(fs, vars = nil)
      fs = Array(fs).map { |f| Expression.lift(f) }
      xs = variables_of(fs, vars, components: fs.size, name: "jacobian")
      MatrixSpace.new(RR, fs.size, xs.size).unchecked(fs.map { |f| xs.map { |x| f.diff(x) } })
    end

    def divergence(field, vars = nil)
      fs = Array(field).map { |f| Expression.lift(f) }
      xs = variables_of(fs, vars, components: fs.size, name: "divergence")
      raise ArgumentError, "divergence: #{fs.size} components for #{xs.size} variables" unless fs.size == xs.size
      fs.each_with_index.map { |f, i| f.diff(xs[i]) }.reduce(:+).simplify
    end

    def laplacian(f, vars = nil)
      f = Expression.lift(f)
      xs = variables_of(f, vars, name: "laplacian")
      xs.map { |x| f.diff(x, 2) }.reduce(:+).simplify
    end

    def curl(field, vars = nil)
      fs = Array(field).map { |f| Expression.lift(f) }
      xs = variables_of(fs, vars, components: fs.size, name: "curl")
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

    # |u| on the interval, written without the abs only where the sign of u
    # there has been *proved*. Sampling five points said x - 1/10 was
    # positive on 0..1 and dropped the abs, which understated the surface of
    # revolution by 2.4% (22 Sept 2026, from the second review); an abs the
    # integrator can see through is a far smaller price.
    def distance(u, var, from, to)
      u = Expression.lift(u)
      case sign_on_interval(u, var, from, to)
      when :positive then u
      when :negative then Neg.new(u).simplify
      else Fn.new(:abs, [u])
      end
    end

    # An interval [lo, hi] of Rationals that contains every value of u on
    # the box {name => [lo, hi]} - interval arithmetic, so a proof: x**2 +
    # y**2 lies in [2, 8] on [1, 2]x[1, 2] and never vanishes there. nil for
    # anything it does not enclose (a function, a denominator that may be 0).
    def enclosure(u, box)
      case u
      when Num
        v = u.value
        v.is_a?(Integer) || v.is_a?(Rational) ? [v.to_r, v.to_r] : nil
      when Var then box[u.name]
      when Const then u.name == :pi ? [Rational(314_159_265, 100_000_000), Rational(314_159_266, 100_000_000)] : nil
      when Neg
        a = enclosure(u.arg, box) or return nil
        [-a[1], -a[0]]
      when Add, Sub
        a = enclosure(u.left, box) or return nil
        b = enclosure(u.right, box) or return nil
        u.is_a?(Add) ? [a[0] + b[0], a[1] + b[1]] : [a[0] - b[1], a[1] - b[0]]
      when Mul
        a = enclosure(u.left, box) or return nil
        b = enclosure(u.right, box) or return nil
        products = a.product(b).map { |p, q| p * q }
        [products.min, products.max]
      when Div
        a = enclosure(u.left, box) or return nil
        b = enclosure(u.right, box) or return nil
        return nil if b[0] <= 0 && b[1] >= 0
        enclosure_product(a, [1 / b[1], 1 / b[0]])
      when Pow
        n = u.exponent
        return nil unless n.is_a?(Num) && n.value.is_a?(Integer) && n.value.abs <= 64
        a = enclosure(u.base, box) or return nil
        n = n.value
        if n.negative?
          return nil if a[0] <= 0 && a[1] >= 0
          a = [1 / a[1], 1 / a[0]]
          n = -n
        end
        low, high = a.map { |e| e**n }.minmax
        low = 0r if n.even? && a[0] <= 0 && a[1] >= 0
        [low, high]
      end
    end

    def enclosure_product(a, b)
      products = a.product(b).map { |p, q| p * q }
      [products.min, products.max]
    end

    # The box of a list of ranges, innermost first, each bound enclosed
    # over the ranges outside it; nil when a bound is not enclosed.
    def box_of(ranges)
      box = {}
      ranges.reverse_each do |var, from, to|
        lo = enclosure(Expression.lift(from).simplify, box) or return nil
        hi = enclosure(Expression.lift(to).simplify, box) or return nil
        box[Expression.lift(var).name] = [[lo[0], hi[0]].min, [lo[1], hi[1]].max]
      end
      box
    end

    # :positive, :negative, :nonnegative, :nonpositive or nil for u on the
    # box, by its enclosure.
    def sign_on_box(u, ranges)
      box = box_of(ranges) or return nil
      lo, hi = enclosure(Expression.lift(u).simplify, box)
      return nil if lo.nil?
      return :positive if lo.positive?
      return :negative if hi.negative?
      return :nonnegative if lo.zero?
      return :nonpositive if hi.zero?
      nil
    end

    # The sign of u on the interval, or nil. A continuous u keeps one sign
    # on an interval in which it has no zero, so the zeros are what decides
    # it - *all* of them: Solve names them completely (a family is counted
    # out member by member; cos(16*pi*x) has sixteen zeros in 1..2, of which
    # the principal ones showed none), a zero strictly inside means there is
    # no single sign, and a zero rcas cannot place means it does not know.
    # "No zero" is only half the argument: u has to be continuous there, so
    # a pole, a place where u stops being real, or a function with jumps
    # inside the interval also leaves the question open (1/((x - 1/100)*
    # (x - 1/50)) has no zero on 0..1 and is negative between its poles;
    # third review, T1). The interior samples are decided exactly and are a
    # veto, never the proof.
    def sign_on_interval(u, var, from, to)
      u = Expression.lift(u)
      var = Expression.lift(var)
      return constant_sign(u) unless u.variables.include?(var.name)
      return nil unless u.variables == [var.name]
      lo, hi = [Expression.lift(from), Expression.lift(to)].sort { |p, q| Inequalities.compare(p, q) || 0 }
      return nil unless Inequalities.compare(lo, hi) == -1 && numeric(lo) && numeric(hi)
      return nil if u.each_node.any? { |n| n.is_a?(Piecewise) || (n.is_a?(Fn) && JUMPS.include?(n.name)) }
      breaks = [u] + denominators(u, var) + domain_conditions(u, var).map { |c| (c.lhs - c.rhs).simplify }
      return nil if breaks.any? { |g| zero_inside?(g, var, lo, hi) != false }
      signs_on(u, var, lo, hi)
    end

    # Functions that jump: no zero does not mean one sign across them.
    JUMPS = %i[floor ceil round sign].freeze

    # true when g has a zero strictly between lo and hi, false when it is
    # shown to have none, nil when that cannot be told.
    def zero_inside?(g, var, lo, hi)
      return false unless g.variables.include?(var.name)
      roots = begin
        Solve.solve(g, var, domain: RR)
      rescue StandardError, NotImplementedError, RCAS::Unsupported => rescued
        RCAS.guard!(rescued, refused: true)
        return nil
      end
      return nil unless roots.is_a?(Array) # an identity or a set: no single sign to read
      found = false
      roots.each do |r|
        members =
          if r.is_a?(ImageSet)
            r.between(numeric(lo) - 1, numeric(hi) + 1) or return nil
          else
            [r]
          end
        members.each do |m|
          inside = strictly_between?(m, lo, hi)
          return nil if inside.nil?
          found ||= inside
        end
      end
      found
    end

    # Is the real point m strictly inside (lo, hi)? false for a point off
    # the real line, nil when that or its position cannot be decided.
    def strictly_between?(m, lo, hi)
      real = begin
        Inequalities.real?(m)
      rescue NotImplementedError, RCAS::Unsupported
        return nil
      end
      return false unless real
      m = Inequalities.real_part(m)
      below = Inequalities.compare(lo, m)
      above = Inequalities.compare(m, hi)
      return nil if below.nil? || above.nil?
      below.negative? && above.negative?
    end

    # Kept for callers that ask about one root.
    def splits?(root, lo, hi) = strictly_between?(root, Expression.lift(lo), Expression.lift(hi)) != false

    def constant_sign(u)
      sign = Decide.sign(u.simplify)
      %i[positive negative].include?(sign) ? sign : nil
    end

    # The interior read at several points, each sign decided; they must
    # agree, and the middle one carries the answer.
    INTERIOR = [1, 2, 3, 4, 5, 6, 7].map { |i| Rational(i, 8) }.freeze

    def signs_on(u, var, lo, hi)
      signs = INTERIOR.map do |t|
        point = (lo + (hi - lo) * Num.new(t)).simplify
        sign = Decide.sign(u.subs(var => point).simplify)
        return nil unless %i[positive negative].include?(sign)
        sign
      end
      signs.uniq.size == 1 ? signs.first : nil
    end

    # Shells about the y-axis stand on one side of it; a range that crosses
    # the axis would have the two halves sweeping the same shells, which
    # abs(x) would then count twice. Splitting the range is the reader's
    # call, so rcas says so instead of answering - and says too that the two
    # halves are a union and not a sum wherever they overlap.
    def one_side!(var, from, to, who)
      a = numeric(from)
      b = numeric(to)
      return if a.nil? || b.nil? || a * b >= 0
      raise ArgumentError, "#{who}: the range #{var} = #{from}..#{to} crosses the axis of revolution; " \
                           "take the two sides separately - where their shells overlap the two answers are not to be added"
    end

    def root(u) = Pow.new(u.simplify, Num.new(Rational(1, 2))).simplify

    # Stationary points of f under the constraints g = 0, by the multiplier
    # rule: grad f = sum(lambda_i grad g_i) together with the constraints.
    def lagrange(f, constraints, vars = nil)
      f = Expression.lift(f)
      gs = Array(constraints).map { |g| Solve.to_zero(g) }
      xs = variables_of([f] + gs, vars, name: "lagrange")
      multipliers = gs.each_index.map { |i| Var.new(gs.size == 1 ? :lambda : :"lambda#{i + 1}") }
      equations = xs.map do |x|
        gs.each_with_index.reduce(f.diff(x)) { |acc, (g, i)| acc - multipliers[i] * g.diff(x) }.simplify
      end
      solutions = Solve.solve(equations + gs, xs + multipliers, principal: true)
      solutions.map { |s| xs.to_h { |x| [x, s[x]] } }
    end
  end
end
