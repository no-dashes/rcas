# frozen_string_literal: true

module RCAS
  # Numbers where symbols run out: a root of an equation no formula solves,
  # the value of an integral with no elementary antiderivative.
  #
  #   nsolve(cos(x) - x, x: 0..1)        # => 0.7390851332151607
  #   nsolve(cos(x) - x, x, 1)           # from a starting point (Newton)
  #   nintegrate(sin(x)/x, x: 0..1)      # => 0.9460830703671831
  #   integrate(sin(x)/x, x: 0..1).evalf # the same, from the unevaluated integral
  #
  # Results are Floats and are labelled as numeric wherever they appear; rcas
  # never quietly replaces an exact answer with one of these.
  #
  # Sources (keys: MANUAL.md, Sources): bisection with the Newton-Raphson
  # refinement and Brent's guarded step [PTVF07, §9.1-9.4]; adaptive Simpson
  # quadrature [PTVF07, §4.2]; the infinite range is mapped to a finite one by
  # the substitutions of [PTVF07, §4.5].
  module Numerics
    TOLERANCE = 1e-12
    FLOAT_DIGITS = 17 # one more than a Float carries, so the last one is right
    # Simpson accepts at this much, relative to the size of the integral.
    # It decides how nearly the fast path agrees with the slow one: over ten
    # smooth integrands, 1e-12 leaves three of them 1 to 23 ulp out, 1e-13
    # one of them 1 ulp out, and 1e-15 none - at 0.22 s, 0.41 s and 1.17 s
    # against the 0.70 s the doubly exponential quadrature takes for all
    # ten. 1e-13 is where the two paths agree to the digit a Float carries
    # and the fast one is still the fast one.
    SIMPSON_TOLERANCE = 1e-13
    SIMPSON_DEPTH = 20
    MAX_STEPS = 200
    MAX_DEPTH = 50

    module_function

    # ---- evaluation ------------------------------------------------------------

    # A float from an expression with at most the one free variable bound.
    def caller_for(expr, var)
      tree = Expression.floatify_tree(Expression.lift(expr))
      name = Expression.lift(var).name
      lambda do |value|
        result = tree.call(name => value)
        result = result.value if result.is_a?(Num)
        unless result.is_a?(Numeric)
          # Folding puts an exact constant back after floatify: exp(-1.0) is
          # 1/e again, which is not a number until evalf looks at it. Without
          # this the integrand has a hole at every such point - x = 1 for
          # exp(-x**2) - and the quadrature chases a discontinuity that is
          # not there.
          result = Expression.lift(result).evalf
          result = result.value if result.is_a?(Num)
        end
        result.is_a?(Numeric) && !result.is_a?(Complex) && result.finite? ? result.to_f : nil
      rescue StandardError
        nil
      end
    end

    # ---- roots -------------------------------------------------------------------

    # nsolve(f, x: a..b) brackets a sign change; nsolve(f, x, guess) starts
    # Newton's method there. Returns a Float, or raises when no root is found.
    def nsolve(f, var = nil, guess = nil, **range)
      digits = range.delete(:digits)
      expr = Solve.to_zero(f)
      var, from, to = arguments(var, guess, range, expr)
      g = caller_for(expr, var)
      derivative = caller_for(Expression.lift(expr).diff(var), var)
      root = to.nil? ? newton(g, derivative, from, var, expr) : bisect(g, derivative, from, to, var, expr)
      if pole?(g, root)
        raise ArgumentError, "nsolve: #{expr} has a pole at #{root}, not a root; give a range on one side of it"
      end
      digits ? Precision.refine(expr, var, root, digits) : root
    end

    # A function changes sign across a pole as it does across a root, and
    # bisection walks straight into it: nsolve(1/x, x: -1..1) used to come
    # back with 0.0. Closer in, a root gets smaller and a pole gets bigger.
    def pole?(g, x)
      return true if g.call(x).nil?
      near, closer = [1e-6, 1e-10].map do |d|
        [g.call(x - d), g.call(x + d)].compact.map(&:abs).max
      end
      return true if near.nil? || closer.nil? # undefined arbitrarily close by
      closer > near && closer > 1.0
    end

    def arguments(var, guess, range, expr)
      unless range.empty?
        raise ArgumentError, "nsolve: give one variable, e.g. nsolve(f, x: 0..1)" unless range.size == 1 && var.nil?
        name, value = range.first
        raise ArgumentError, "nsolve: expected a range or a number, got #{value.inspect}" unless value.is_a?(Range) || value.is_a?(Numeric)
        return [Var.new(name), Float(value.begin), Float(value.end)] if value.is_a?(Range)
        return [Var.new(name), Float(value), nil]
      end
      if var.nil?
        names = Expression.lift(expr).variables
        raise ArgumentError, "nsolve: which variable? give a range, e.g. nsolve(f, x: 0..1)" unless names.size == 1
        var = Var.new(names.first)
      end
      [Expression.lift(var), guess.nil? ? 0.0 : Float(Expression.lift(guess).evalf), nil]
    end

    # Bisection, taking a Newton step whenever it stays inside the bracket.
    def bisect(g, derivative, lo, hi, var, expr)
      flo = g.call(lo)
      fhi = g.call(hi)
      raise ArgumentError, "nsolve: #{expr} is not defined at both ends of #{lo}..#{hi}" if flo.nil? || fhi.nil?
      return lo if flo.abs < TOLERANCE
      return hi if fhi.abs < TOLERANCE
      raise ArgumentError, "nsolve: #{expr} has the same sign at #{lo} and #{hi}; give a range that brackets a root" if flo * fhi > 0

      x = (lo + hi) / 2.0
      MAX_STEPS.times do
        value = defined_near(g, x, lo, hi)
        return x if value.nil? # undefined right across the bracket
        slope = derivative.call(x)
        step = slope && !slope.zero? ? x - value / slope : nil
        x = step && step > lo && step < hi ? step : (lo + hi) / 2.0
        value = defined_near(g, x, lo, hi)
        return x if value.nil?
        value * flo > 0 ? (lo = x; flo = value) : (hi = x; fhi = value)
        return x if (hi - lo).abs < TOLERANCE || value.abs < TOLERANCE
      end
      x
    end

    # The value at x, or at the nearest point inside the bracket where the
    # function is defined. Reading an undefined value as zero (which is what
    # `g.call(x) || 0.0` did) hands the sign test a root that is not there.
    def defined_near(g, x, lo, hi)
      value = g.call(x)
      return value unless value.nil?
      span = (hi - lo).abs
      [1e-3, 1e-2, 1e-1].each do |fraction|
        [x + span * fraction, x - span * fraction].each do |y|
          next unless y > lo && y < hi
          value = g.call(y)
          return value unless value.nil?
        end
      end
      nil
    end

    # Newton's method from a starting point, with a bracketed retry.
    def newton(g, derivative, start, var, expr)
      x = start
      MAX_STEPS.times do
        value = g.call(x)
        break if value.nil?
        return x if value.abs < TOLERANCE
        slope = derivative.call(x)
        break if slope.nil? || slope.abs < 1e-300
        step = value / slope
        x -= step
        return x if step.abs < TOLERANCE * [1.0, x.abs].max
      end
      widened = scan(g, start)
      return bisect(g, derivative, widened.first, widened.last, var, expr) if widened
      raise ArgumentError, "nsolve: no root found near #{start}; give a range that brackets one"
    end

    # Look for a sign change around the starting point.
    def scan(g, start)
      step = 0.5
      previous = g.call(start)
      (1..60).each do |i|
        [start + i * step, start - i * step].each do |x|
          value = g.call(x)
          next if value.nil? || previous.nil?
          return [[x, start].min, [x, start].max] if value * previous <= 0
        end
      end
      nil
    end

    # ---- quadrature ---------------------------------------------------------------

    # nintegrate(f, x: a..b), with infinite ends mapped to a finite range.
    def nintegrate(f, var = nil, from = nil, to = nil, **range)
      digits = range.delete(:digits)
      var, from, to = Functions.range_arguments(var, from, to, range, "nintegrate", discrete: false) if var.nil? || from
      var = Expression.lift(var)
      if digits
        value = Precision.quadrature(Expression.lift(f), var, Expression.lift(from), Expression.lift(to), digits)
        return Decimal.new(value, digits)
      end
      lo = bound(from)
      hi = bound(to)
      return -nintegrate(f, var, to, from) if lo > hi
      return 0.0 if lo == hi
      # Adaptive Simpson first: on a smooth integrand it settles in a
      # millisecond, and to the digit the slower quadrature would give (see
      # SIMPSON_TOLERANCE for how nearly), where the doubly exponential one
      # pays 100 ms for its guard digits. Its budget is bounded, so a
      # singular integrand fails fast and goes there instead of subdividing
      # for ever (MAX_DEPTH = 50 was 2**50 subintervals and never came
      # back). The price of the fast path is paid on the slow road: a
      # divergent integrand takes a second or two longer to be refused.
      unless lo.infinite? || hi.infinite?
        quick = bounded_simpson(caller_for(f, var), lo, hi)
        return quick if quick
      end
      exact = tanh_sinh(f, var, from, to)
      return exact if exact
      if lo.infinite? || hi.infinite?
        transformed(f, var, lo, hi)
      else
        simpson(caller_for(f, var), lo, hi)
      end
    end

    # nil when the budget runs out before the estimate settles: the caller
    # then asks the slower quadrature, which is the one that copes with a
    # singularity. The tolerance follows the size of the integral, so a
    # large smooth one is not driven to the end of the budget for nothing.
    def bounded_simpson(g, lo, hi)
      g = patch_ends(g, lo, hi)
      whole = simpson_rule(g, lo, hi)
      return nil unless whole.finite?
      value = refine(g, lo, hi, whole, SIMPSON_TOLERANCE * [1.0, whole.abs].max, SIMPSON_DEPTH)
      value.nil? || resonant?(g, lo, hi, value) ? nil : value
    end

    # Gauss-Legendre on [-1, 1], seven nodes: irrational positions, which is
    # the whole point of them here.
    GAUSS_NODES = [0.0, -0.4058451513773972, 0.4058451513773972, -0.7415311855993945,
                   0.7415311855993945, -0.9491079123427585, 0.9491079123427585].freeze
    GAUSS_WEIGHTS = [0.4179591836734694, 0.3818300505051189, 0.3818300505051189, 0.2797053914892766,
                     0.2797053914892766, 0.1294849661688697, 0.1294849661688697].freeze
    GAUSS_PANELS = 8
    GAUSS_ESCALATIONS = 3 # 8, 32, 128, 512 panels
    GAUSS_TOLERANCE = 1e-9

    # A second opinion, from nodes that are not on the halving grid.
    # Adaptive Simpson refines by halving, so an integrand whose period
    # divides the interval puts every sample on the same phase: the
    # refinement then agrees with itself all the way down and returns a
    # confident wrong number. sin(x)**2 over 0..100*pi came back as 0, and
    # 1/(2 + cos(x)) over 0..1000*pi as 1047 where the answer is 1814. No
    # period lines up with the Gauss nodes, so the two answers part company
    # there - by half and more - while on a smooth integrand they agree to
    # the last digit (5.6e-16 at worst over the ten measured for
    # SIMPSON_TOLERANCE). No second opinion (the integrand is undefined at
    # one of the nodes) is not a veto.
    # An integrand that really does oscillate is not resonant, and Gauss on
    # eight panels cannot see 500 periods either: when the two disagree the
    # panels are multiplied until the second opinion settles. Settling on
    # Simpson's answer clears it; settling anywhere else, or not settling
    # at all inside the budget, does not.
    def resonant?(g, lo, hi, value)
      panels = GAUSS_PANELS
      previous = nil
      (GAUSS_ESCALATIONS + 1).times do
        estimate = gauss_legendre(g, lo, hi, panels) or return false
        return false if agree?(estimate, value)
        return true if previous && agree?(estimate, previous)
        previous = estimate
        panels *= 4
      end
      true
    end

    def agree?(a, b) = (a - b).abs <= GAUSS_TOLERANCE * [1.0, a.abs, b.abs].max

    def gauss_legendre(g, lo, hi, panels = GAUSS_PANELS)
      width = (hi - lo) / panels.to_f
      half = width / 2
      total = 0.0
      panels.times do |i|
        centre = lo + width * (i + 0.5)
        GAUSS_NODES.each_with_index do |node, j|
          value = g.call(centre + half * node)
          return nil if value.nil?
          total += GAUSS_WEIGHTS[j] * value * half
        end
      end
      total.finite? ? total : nil
    end

    # An end the caller cannot evaluate takes the value just inside it -
    # sin(x)/x at 0 is a hole in the caller, not in the integral, and
    # reading it as 0 (which is what simpson_rule does with a nil) invents
    # a discontinuity. The interval itself is not moved, so no area is
    # lost. An end that is genuinely singular gives a huge value here, does
    # not settle, and goes to the quadrature below as before.
    def patch_ends(g, lo, hi)
      step = (hi - lo) * 1e-8
      ends = {}
      ends[lo] = g.call(lo + step) if g.call(lo).nil?
      ends[hi] = g.call(hi - step) if g.call(hi).nil?
      return g if ends.empty? || ends.value?(nil)
      ->(t) { ends.key?(t) ? ends[t] : g.call(t) }
    end

    def refine(g, lo, hi, whole, tolerance, depth)
      middle = (lo + hi) / 2.0
      left = simpson_rule(g, lo, middle)
      right = simpson_rule(g, middle, hi)
      return nil unless (left + right).finite?
      return left + right + (left + right - whole) / 15.0 if (left + right - whole).abs <= 15 * tolerance
      return nil if depth.zero?
      a = refine(g, lo, middle, left, tolerance / 2, depth - 1) or return nil
      b = refine(g, middle, hi, right, tolerance / 2, depth - 1) or return nil
      a + b
    end

    # The same tanh-sinh quadrature the digits: form uses, at Float
    # precision: the one that copes with an endpoint singularity, and the
    # one that says when an integral does not settle at all. nil hands the
    # integrand back to Simpson when arbitrary precision has no route for
    # it (an unknown function, a value that is not real).
    def tanh_sinh(f, var, from, to)
      value = Precision.quadrature(Expression.lift(f), var, Expression.lift(from), Expression.lift(to), FLOAT_DIGITS)
      value.to_f
    rescue Precision::NoConvergence => e
      raise ArgumentError, "nintegrate: #{e.message.sub('evalf: ', '')}"
    rescue Precision::Unsupported, ZeroDivisionError
      nil
    end

    def bound(value)
      return Float::INFINITY if value == OO
      return -Float::INFINITY if value == Neg.new(OO).simplify || value == Neg.new(OO)
      v = Expression.lift(value).evalf
      raise ArgumentError, "nintegrate: #{value} is not a real bound" unless v.is_a?(Numeric) && !v.is_a?(Complex)
      v.to_f
    end

    # x = t/(1 - t**2) on (-1, 1) for a doubly infinite range, x = a + t/(1 - t)
    # for one that is infinite on one side only.
    def transformed(f, var, lo, hi)
      g = caller_for(f, var)
      if lo.infinite? && hi.infinite?
        integrand = ->(t) { value = g.call(t / (1 - t * t)); value && value * (1 + t * t) / (1 - t * t)**2 }
        quadrature(integrand, -1.0, 1.0)
      elsif hi.infinite?
        integrand = ->(t) { value = g.call(lo + t / (1 - t)); value && value / (1 - t)**2 }
        quadrature(integrand, 0.0, 1.0)
      else
        integrand = ->(t) { value = g.call(hi - t / (1 - t)); value && value / (1 - t)**2 }
        -quadrature(integrand, 0.0, 1.0)
      end
    end

    # Simpson on an open interval: the ends may be singular, so they are skipped.
    def quadrature(g, lo, hi)
      inset = (hi - lo) * 1e-10
      simpson(g, lo + inset, hi - inset)
    end

    def simpson(g, lo, hi)
      whole = simpson_rule(g, lo, hi)
      adaptive(g, lo, hi, whole, 1e-11, MAX_DEPTH)
    end

    def simpson_rule(g, lo, hi)
      middle = (lo + hi) / 2.0
      values = [g.call(lo), g.call(middle), g.call(hi)].map { |v| v || 0.0 }
      (hi - lo) / 6.0 * (values[0] + 4 * values[1] + values[2])
    end

    def adaptive(g, lo, hi, whole, tolerance, depth)
      middle = (lo + hi) / 2.0
      left = simpson_rule(g, lo, middle)
      right = simpson_rule(g, middle, hi)
      return left + right + (left + right - whole) / 15.0 if depth.zero? || (left + right - whole).abs <= 15 * tolerance
      adaptive(g, lo, middle, left, tolerance / 2, depth - 1) + adaptive(g, middle, hi, right, tolerance / 2, depth - 1)
    end

    # ---- evalf on unevaluated nodes --------------------------------------------------

    # Replace every definite integral that has no free variables left by its
    # numeric value; evalf calls this, so an integral rcas cannot do in closed
    # form still gives a number.
    def resolve(expr)
      return expr unless expr.is_a?(Expression)
      expr = expr.map_children { |c| resolve(c) }
      return expr unless expr.is_a?(Integral) && expr.definite?
      free = expr.integrand.variables - [expr.var.name]
      return expr unless free.empty?
      value = nintegrate(expr.integrand, expr.var, expr.from, expr.to)
      value.is_a?(Numeric) && value.finite? ? Num.new(value) : expr
    rescue StandardError
      expr
    end
  end
end
