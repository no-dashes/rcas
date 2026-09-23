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
    # Compiled to a lambda over Floats when every node is one the compiler
    # knows, which is a hundred times faster than substituting into the
    # tree: adaptive Simpson over sin(1000*x) wants 300000 values and took
    # ten seconds (third review, section 5). Anything else takes the tree.
    # The integrand as a Float function: the compiled lambda where it has a
    # value, the tree evaluator where it does not - asin(1.5) is complex, and
    # |asin(x)| is still real (the compiled lambda said nil and nintegrate
    # refused: fourth review) - and, for a tree whose exact constants are
    # beyond the Floats (10**400), evalf with its wide fallback.
    def caller_for(expr, var)
      expr = Expression.lift(expr)
      name = Expression.lift(var).name
      huge = beyond_floats?(expr)
      expr = expr.simplify if huge
      huge &&= beyond_floats?(expr)
      compiled = compile(expr, name)
      tree = tree_caller(expr, name)
      exact = huge ? exact_caller(expr, name) : nil
      return tree if compiled.nil? && exact.nil?
      lambda do |value|
        compiled&.call(value) || tree.call(value) || exact&.call(value)
      end
    end

    def beyond_floats?(expr)
      expr.each_node.any? do |n|
        n.is_a?(Num) && (v = n.value).is_a?(Numeric) && v.real? && !v.is_a?(Float) && !v.zero? && !v.abs.to_f.between?(1e-300, 1e300)
      end
    end

    def exact_caller(expr, name)
      lambda do |value|
        result = expr.subs(name => Num.new(value)).evalf
        RCAS.real_float(result)
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        nil
      end
    end

    def tree_caller(expr, name)
      tree = Expression.floatify_tree(expr)
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
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        nil
      end
    end

    COMPILED = { sin: Math.method(:sin), cos: Math.method(:cos), tan: Math.method(:tan), exp: Math.method(:exp),
                 atan: Math.method(:atan), sinh: Math.method(:sinh), cosh: Math.method(:cosh), erf: Math.method(:erf),
                 erfc: Math.method(:erfc) }.freeze
    # real only inside their domain: nil outside, as the tree gives
    GUARDED = { log: ->(v) { v.positive? ? Math.log(v) : nil },
                asin: ->(v) { v.abs <= 1 ? Math.asin(v) : nil },
                acos: ->(v) { v.abs <= 1 ? Math.acos(v) : nil },
                abs: ->(v) { v.abs }, sign: ->(v) { (v <=> 0).to_f },
                floor: ->(v) { v.floor.to_f }, ceil: ->(v) { v.ceil.to_f } }.freeze

    # A lambda x -> Float (nil where the value is not a finite real), or nil
    # when some node is not one of the kinds above.
    def compile(expr, name)
      body = compiled_node(expr, name) or return nil
      lambda do |value|
        v = body.call(value.to_f)
        v.is_a?(Float) && v.finite? ? v : nil
      rescue ZeroDivisionError, Math::DomainError, FloatDomainError
        nil
      end
    end

    def compiled_node(e, name)
      case e
      when Num
        v = e.value
        return nil unless v.is_a?(Numeric) && v.real?
        f = v.to_f
        ->(_) { f }
      when Const
        return nil unless e.value.is_a?(Numeric) && e.value.real? && e.value.to_f.finite?
        f = e.value.to_f
        ->(_) { f }
      when Var then e.name == name ? ->(x) { x } : nil
      when Neg then (a = compiled_node(e.arg, name)) && ->(x) { (v = a.call(x)) && -v }
      when Add, Sub, Mul, Div
        a = compiled_node(e.left, name) or return nil
        b = compiled_node(e.right, name) or return nil
        op = { Add => :+, Sub => :-, Mul => :*, Div => :/ }[e.class]
        lambda do |x|
          l = a.call(x) or return nil
          r = b.call(x) or return nil
          return nil if op == :/ && r.zero?
          l.public_send(op, r)
        end
      when Pow then compiled_power(e, name)
      when Fn
        return nil unless e.args.size == 1
        a = compiled_node(e.args.first, name) or return nil
        if (f = COMPILED[e.name]) then ->(x) { (v = a.call(x)) && f.call(v) }
        elsif (g = GUARDED[e.name]) then ->(x) { (v = a.call(x)) && g.call(v) }
        end
      end
    end

    # A negative base has a real power only for an integer exponent here -
    # the principal value of (-8)**(1/3) is not real, which is what the tree
    # says too.
    def compiled_power(e, name)
      a = compiled_node(e.base, name) or return nil
      exponent = e.exponent
      if exponent.is_a?(Num) && exponent.value.is_a?(Integer)
        n = exponent.value
        return lambda do |x|
          v = a.call(x) or return nil
          return nil if v.zero? && n.negative?
          v**n
        end
      end
      b = compiled_node(exponent, name) or return nil
      lambda do |x|
        v = a.call(x) or return nil
        w = b.call(x) or return nil
        return nil if v.negative? && w != w.round
        return nil if v.zero? && w.negative?
        v**w
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
      # bisection needs no derivative, and x + floor(x) has none to give
      derivative = begin
        caller_for(Expression.lift(expr).diff(var), var)
      rescue ArgumentError
        ->(_) { nil }
      end
      root = to.nil? ? newton(g, derivative, from, var, expr) : bisect(g, derivative, from, to, var, expr)
      case crossing(g, root, from, to)
      when :pole
        raise ArgumentError, "nsolve: #{expr} has a pole at #{root}, not a root; give a range on one side of it"
      when :jump
        raise ArgumentError, "nsolve: #{expr} changes sign at #{root} without passing through 0 - a jump, not a root"
      end
      digits ? Precision.refine(expr, var, root, digits) : root
    end

    # What the function does where the sign changes, read off |f| at
    # distances growing tenfold from 40 units in the last place to a
    # hundred million of them, on each side and inside the range: towards
    # a root |f| shrinks, however steeply (the real cube root of x - 3/10 is
    # 4e-6 an ulp away, which the old size test took for a jump), towards a
    # pole it grows, across a jump it stays put. :root, :pole or :jump; a
    # root when f is exactly 0 there or the sides disagree.
    def crossing(g, x, from, to)
      value = g.call(x)
      return :root if value&.zero?
      low, high = [from, to.nil? ? from : to].minmax
      low, high = -Float::INFINITY, Float::INFINITY if to.nil?
      unit = 4 * Float::EPSILON * [x.abs, 1e-300].max
      ratios = [-1, 1].filter_map do |side|
        values = (1..8).filter_map do |j|
          t = x + side * unit * 10**j
          next unless t >= low && t <= high
          g.call(t)&.abs
        end
        next nil if values.size < 3
        near, far = values.first, values.last
        near.zero? ? Float::INFINITY : far / near
      end
      return value.nil? ? :pole : :root if ratios.empty?
      return :pole if ratios.all? { |r| r < 0.5 }
      return :jump if ratios.all? { |r| r.between?(0.5, 2.0) }
      return :pole if value.nil? && ratios.none? { |r| r > 2.0 }
      :root
    end

    # Converged when the bracket is a few units in the last place wide: a
    # small value of f is not a root - (x - 3/10)/10**12 is -3e-13 at 0 and
    # exp(-50*x)*(x - 1/2) is 1e-22 at 1, and |f| < 1e-12 answered with
    # those (third review, S20).
    def narrow?(lo, hi) = (hi - lo).abs <= 4 * Float::EPSILON * [lo.abs, hi.abs, Float::MIN].max

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

    # Bisection, taking a Newton step whenever it stays inside the bracket
    # and shrinks it; stopping when the bracket is as narrow as Floats go,
    # or f is exactly 0.
    def bisect(g, derivative, lo, hi, var, expr)
      flo = g.call(lo)
      fhi = g.call(hi)
      raise ArgumentError, "nsolve: #{expr} is not defined at both ends of #{lo}..#{hi}" if flo.nil? || fhi.nil?
      return lo if flo.zero?
      return hi if fhi.zero?
      raise ArgumentError, "nsolve: #{expr} has the same sign at #{lo} and #{hi}; give a range that brackets a root" if flo * fhi > 0

      x = (lo + hi) / 2.0
      steps = 0
      until narrow?(lo, hi) || steps > 4 * MAX_STEPS
        steps += 1
        value = defined_near(g, x, lo, hi)
        return x if value.nil? # undefined right across the bracket
        slope = derivative.call(x)
        step = slope && !slope.zero? ? x - value / slope : nil
        # Newton only while it lands strictly inside and the bracket keeps
        # halving at least every other step
        x = step && step > lo && step < hi && steps.odd? ? step : (lo + hi) / 2.0
        value = defined_near(g, x, lo, hi)
        return x if value.nil?
        return x if value.zero?
        value * flo > 0 ? (lo = x; flo = value) : (hi = x; fhi = value)
      end
      flo.abs <= fhi.abs ? lo : hi # the caller tells a root from a pole or a jump
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
    # Converged when the step is small relative to x and a sign change or
    # an exact zero confirms the point: x*exp(-x) from 5 runs off to where
    # exp underflows, and a small value there is no root.
    def newton(g, derivative, start, var, expr)
      x = start
      MAX_STEPS.times do
        value = g.call(x)
        break if value.nil?
        return x if value.zero? && confirmed?(g, x)
        slope = derivative.call(x)
        break if slope.nil? || slope.abs < 1e-300
        step = value / slope
        x -= step
        return x if step.abs <= 1e-14 * [1.0, x.abs].max && confirmed?(g, x)
      end
      widened = scan(g, start)
      return bisect(g, derivative, widened.first, widened.last, var, expr) if widened
      raise ArgumentError, "nsolve: no root found near #{start}; give a range that brackets one"
    end

    # A root found by Newton is believed when f changes sign across it, or
    # f is small beside its neighbours as it is at a double root.
    def confirmed?(g, x)
      d = 1e-7 * [1.0, x.abs].max
      left = g.call(x - d)
      right = g.call(x + d)
      here = g.call(x)
      return false if left.nil? || right.nil? || here.nil?
      return true if left * right <= 0
      here.abs <= 1e-6 * [left.abs, right.abs].min && [left.abs, right.abs].min.positive?
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
    #
    # Three promises, each broken once (third review, 22 Sept 2026): an
    # integrand that is not a number (an unknown function, a free
    # parameter) is refused rather than integrated as 0; the range is cut
    # at the kinks, jumps and poles rcas can name, so abs(x - 1) is no
    # harder than x and 1/x over -1..1 is two divergent pieces rather than
    # a principal value of 0; and a sample with no value inside the range
    # is a removable hole or a refusal, never a zero.
    def nintegrate(f, var = nil, from = nil, to = nil, **range)
      digits = range.delete(:digits)
      var, from, to = Functions.range_arguments(var, from, to, range, "nintegrate", discrete: false) if var.nil? || from
      var = Expression.lift(var)
      f = Expression.lift(f)
      from = Expression.lift(from)
      to = Expression.lift(to)
      lo = bound(from)
      hi = bound(to)
      return(digits ? Decimal.new(BigDecimal(0), digits) : 0.0) if lo == hi
      numeric_integrand!(f, var, lo, hi)
      inside = breakpoints(f, var, lo, hi)
      ends = lo > hi ? [from, *inside.reverse, to] : [from, *inside, to]
      not_integrable!(f, var, ends)
      pieces = ends.each_cons(2).map { |a, b| piece(f, var, a, b, digits) }
      return pieces.sum if digits.nil?
      Decimal.new(pieces.map { |d| d.is_a?(Decimal) ? d.value : BigDecimal(d.to_s) }.sum, digits)
    end

    # One piece: no kink, jump or pole inside, whatever the ends do.
    def piece(f, var, from, to, digits)
      if digits
        return Decimal.new(Precision.quadrature(f, var, from, to, digits), digits)
      end
      lo = bound(from)
      hi = bound(to)
      return -piece(f, var, to, from, nil) if lo > hi
      return 0.0 if lo == hi
      # Adaptive Simpson first: on a smooth integrand it settles in a
      # millisecond, and to the digit the slower quadrature would give (see
      # SIMPSON_TOLERANCE for how nearly), where the doubly exponential one
      # pays 100 ms for its guard digits. Its budget is bounded, so a
      # singular integrand fails fast and goes there instead of subdividing
      # for ever.
      unless lo.infinite? || hi.infinite?
        quick = bounded_simpson(caller_for(f, var), lo, hi)
        return quick if quick
      end
      exact = tanh_sinh(f, var, from, to)
      return exact if exact
      # no arbitrary-precision route (a function Precision lacks): Simpson
      # again, on a larger budget, and a refusal when it does not settle
      value = lo.infinite? || hi.infinite? ? transformed(f, var, lo, hi) : checked_simpson(caller_for(f, var), lo, hi)
      value or raise ArgumentError, "nintegrate: the quadrature of #{f} over #{from}..#{to} did not settle; it may diverge"
    end

    # Where the integrand has no value at an end of a piece, it may not be
    # integrable there at all: when (x - p)*f(x) does not tend to 0, f is
    # at least as large as c/(x - p) and the integral diverges [Rud76, th.
    # 6.20 by comparison]. Saying so from the limit is quick; letting the
    # quadrature fail to settle took seconds. A limit of 0 proves nothing
    # either way, and the quadrature decides then.
    def not_integrable!(f, var, ends)
      g = caller_for(f, var)
      ends.each_with_index do |p, i|
        next if Limits.infinite?(p)
        value = Analysis.numeric(p)
        next if value.nil? || g.call(value)
        sides = []
        sides << :left if i.positive?
        sides << :right if i < ends.size - 1
        sides.each do |side|
          limit = begin
            Limits.limit((var - p) * f, var, p, side)
          rescue StandardError => rescued
            RCAS.guard!(rescued)
            nil
          end
          next if limit.nil? || limit.is_a?(Limit)
          next if limit.is_a?(Num) && limit.value.is_a?(Numeric) && limit.value.zero?
          next unless Limits.infinite?(limit) || limit.is_a?(Num) || limit.variables.empty?
          raise ArgumentError, "nintegrate: #{f} is not integrable at #{var} = #{p}; it grows like 1/(#{(var - p).simplify}) or faster there, so the integral diverges"
        end
      end
    end

    # A number at some point of the range, or a refusal naming why not.
    def numeric_integrand!(f, var, lo, hi)
      free = f.variables - [var.name]
      raise ArgumentError, "nintegrate: #{f} has the free variables #{free.join(', ')}; give them values first" unless free.empty?
      g = caller_for(f, var)
      probes = [0.2113, 0.5, 0.7887, 0.3719, 0.6281].map do |s|
        if lo.infinite? && hi.infinite? then (s - 0.5) * 10
        elsif hi.infinite? then lo + s * 10
        elsif lo.infinite? then hi - s * 10
        else lo + (hi - lo) * s
        end
      end
      return if probes.any? { |t| g.call(t) }
      raise ArgumentError, "nintegrate: #{f} has no numeric value on the range (an unknown function, or a value that is not real)"
    end

    # The points strictly inside the range where the integrand has a kink,
    # a jump or a pole that rcas can name: the zeros of the argument of an
    # abs or sign, the integers a linear argument of floor, ceil or round
    # crosses, the edges of a piecewise branch, and the poles
    # Integrate.singular_points finds. Sorted ascending; [] on an infinite
    # range, where they cannot be counted out.
    MAX_BREAKPOINTS = 256

    def breakpoints(f, var, lo, hi)
      a, b = [lo, hi].minmax
      return [] if a.infinite? || b.infinite?
      found = []
      f.each_node do |node|
        if node.is_a?(Fn) && %i[abs sign].include?(node.name) && node.args.first.variables.include?(var.name)
          found.concat(zeros_between(node.args.first, var, a, b))
        elsif node.is_a?(Fn) && %i[floor ceil round].include?(node.name) && node.args.first.variables.include?(var.name)
          found.concat(integer_crossings(node, var, a, b))
        elsif node.is_a?(Piecewise)
          node.conditions.each do |c|
            case c
            when Inequality, Equation then found.concat(zeros_between((c.lhs - c.rhs).simplify, var, a, b))
            when Interval then found.push(c.low, c.high)
            when RealSet then c.intervals.each { |i| found.push(i.low, i.high) }
            end
          end
        end
      end
      poles = begin
        Integrate.singular_points(f, var, Num.new(Rational(a)), Num.new(Rational(b)))
      rescue StandardError, NotImplementedError => rescued
        RCAS.guard!(rescued)
        nil
      end
      found.concat(poles) if poles
      values = found.filter_map do |p|
        v = Analysis.numeric(p)
        v && v > a && v < b ? [v, p] : nil
      end
      values.uniq { |v, _| v }.sort_by(&:first).first(MAX_BREAKPOINTS).map(&:last)
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      []
    end

    def zeros_between(u, var, a, b)
      return [] unless u.variables.include?(var.name)
      roots = Solve.solve(u, var)
      return [] unless roots.is_a?(Array)
      roots.flat_map { |r| r.is_a?(ImageSet) ? (r.between(a, b, limit: MAX_BREAKPOINTS) || []) : [r] }
    rescue StandardError, NotImplementedError => rescued
      RCAS.guard!(rescued)
      []
    end

    def integer_crossings(node, var, a, b)
      ab = Integrate.linear(node.args.first, var) or return []
      slope, offset = ab.map { |v| Analysis.numeric(v) }
      return [] if slope.nil? || offset.nil? || slope.zero?
      ends = [slope * a + offset, slope * b + offset].minmax
      shift = node.name == :round ? 0.5 : 0
      first = (ends[0] - shift).floor + 1
      last = (ends[1] - shift).ceil - 1
      return [] if last - first > MAX_BREAKPOINTS
      (first..last).map { |n| ((Num.new(n) + Num.new(Rational(shift)) - ab[1]) / ab[0]).simplify }
    end

    # Adaptive Simpson with a convergence test and no free zeros: nil when
    # a sample has no value or the refinement does not settle.
    def checked_simpson(g, lo, hi)
      g = patch_ends(g, lo, hi)
      whole = simpson_rule(g, lo, hi)
      return nil unless whole&.finite?
      refine(g, lo, hi, whole, 1e-11 * [1.0, whole.abs].max, 30)
    end

    # nil when the budget runs out before the estimate settles: the caller
    # then asks the slower quadrature, which is the one that copes with a
    # singularity. The tolerance follows the size of the integral, so a
    # large smooth one is not driven to the end of the budget for nothing.
    def bounded_simpson(g, lo, hi)
      g = patch_ends(g, lo, hi)
      whole = simpson_rule(g, lo, hi)
      return nil unless whole&.finite?
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
      return nil if left.nil? || right.nil? || !(left + right).finite?
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
    # for one that is infinite on one side only; checked Simpson on the
    # open interval (the ends are skipped), nil when it does not settle.
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
        (v = quadrature(integrand, 0.0, 1.0)) && -v
      end
    end

    def quadrature(g, lo, hi)
      inset = (hi - lo) * 1e-10
      checked_simpson(g, lo + inset, hi - inset)
    end

    # nil when a sample has no value: an undefined point is not a zero.
    def simpson_rule(g, lo, hi)
      middle = (lo + hi) / 2.0
      values = [g.call(lo), g.call(middle), g.call(hi)]
      return nil if values.any?(&:nil?)
      (hi - lo) / 6.0 * (values[0] + 4 * values[1] + values[2])
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
      # evalf floated the bounds, and oo became Float::INFINITY on the way:
      # give nintegrate the infinity back, or it takes the finite route
      value = nintegrate(expr.integrand, expr.var, infinite_bound(expr.from), infinite_bound(expr.to))
      value.is_a?(Numeric) && value.finite? ? Num.new(value) : expr
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      expr
    end

    def infinite_bound(b)
      return b unless b.is_a?(Num) && b.value.is_a?(Float) && b.value.infinite?
      b.value.positive? ? OO : Neg.new(OO).simplify
    end
  end
end
