# frozen_string_literal: true

module RCAS
  # Probability distributions as objects, with exact and symbolic answers.
  #
  #   X = Normal(0, 1)          X.pdf(x), X.cdf(1), X.quantile(0.975), X.mean
  #   B = Binomial(10, 1/2r)    B.pdf(3)  # => 15/128
  #   Poisson(l).pdf(k)         # => exp(-l)*l**k/k!
  #   X.probability(x > 1)      X.probability(-1..1)     X.expectation(x**2, x)
  #   D = DiscreteUniform(1, 6) D.mean  # => 7/2    D.sample(5, random: Random.new(1))
  #
  # Continuous: Normal, Uniform, Exponential. Discrete: Bernoulli, Binomial,
  # Poisson, Geometric (failures before the first success, k >= 0, as in Maple
  # and Mathematica), DiscreteUniform. Parameters may be symbolic. The normal
  # CDF is expressed with erf; its quantile is numeric except at p = 1/2.
  #
  # Sources (keys: MANUAL.md, Sources): [Ros14, ch. 4-5]; erf [AS64, §7.1].
  module Distributions
    class Distribution
      attr_reader :params

      def initialize(*params)
        @params = params.map { |p| Expression.lift(p) }
        validate
        freeze
      end

      # What the parameters have to be. A symbolic parameter is left alone -
      # Normal(mu, sigma) is a legitimate object - but a number that cannot
      # be one is refused here rather than returning a negative probability
      # later (Binomial(10, 1.5).pdf(3) was -3.1640625).
      def validate; end

      # Raise unless the numeric value of the parameter passes the block.
      def positive(param, what) = requires(param, what, "positive") { |v| v.positive? }
      def nonnegative(param, what) = requires(param, what, "not negative") { |v| !v.negative? }
      def probability_in(param, what) = requires(param, what, "between 0 and 1") { |v| v >= 0 && v <= 1 }

      def whole(param, what)
        requires(param, what, "a non-negative whole number") { |v| v.integer? && !v.negative? }
      end

      def requires(param, what, description)
        value = param.is_a?(Num) ? param.value : nil
        return if value.nil? || !value.real?
        raise ArgumentError, "#{name}: #{what} must be #{description}, got #{param}" unless yield(value)
      end

      def name = self.class.name.split("::").last
      def to_s = "#{name}(#{params.join(', ')})"
      def inspect = to_s
      def to_latex(wrap: nil) = "\\mathrm{#{name}}\\left(#{params.map { |p| LaTeX.of(p) }.join(', ')}\\right)"
      def discrete? = false
      def stdev = RCAS.sqrt(variance).simplify
      def median = quantile(Rational(1, 2))
      def ==(other) = other.class == self.class && other.params == params
      alias eql? ==
      def hash = [self.class, params].hash

      # P(a <= X <= b) for a range, P(X > c) etc. for an inequality x > c.
      def probability(event)
        case event
        when Range
          lo = Expression.lift(event.begin || Neg.new(OO)).simplify
          hi = Expression.lift(event.end || OO).simplify
          # 3/4..1/4 is empty, not a negative probability (T6); an
          # exclusive end is an open end, 2...9/2 includes 4 (P-9)
          order = Inequalities.compare(lo, hi)
          return Num.new(0) if order == 1 || (order&.zero? && event.exclude_end?)
          interval = Interval.new(lo, hi, right_open: event.exclude_end? && !event.end.nil?)
          found = set_probability(interval)
          return found unless order.nil?
          # a symbolic range may turn out reversed, and then it is empty, not
          # cdf(b) - cdf(a) < 0 (fourth review, T6)
          Piecewise.new([[Inequality.new(lo, event.exclude_end? ? :< : :<=, hi), found], [Piecewise::OTHERWISE, Num.new(0)]])
        when Inequality
          # The direct route is for "X op c" alone: both that the left side
          # is the variable and that the right side is free of it. P(X <= X)
          # is 1, not X (22 Sept 2026, the second review). Everything else is
          # solved for the variable and the probability taken over the set
          # that comes out - reading the operator and the right side alone
          # answered P(-X <= 0) with 0.
          return bound_probability(event.op, event.rhs) if direct_event?(event)
          set_probability(event_set(event))
        else raise ArgumentError, "probability: give a range (a..b) or an inequality (x > 1)"
        end
      end

      def direct_event?(event) = event.lhs.is_a?(Var) && !event.rhs.variables.include?(event.lhs.name)

      # P(X > c), which a distribution with a better formula for its upper
      # tail overrides: 1 - cdf(8) cancels every digit of Normal's 6e-16
      # (third review, P-11).
      def survival(c) = (1 - cdf_at(c)).simplify

      # P(X op c) with the bound c, the shape every event is reduced to.
      def bound_probability(op, c)
        c = Expression.lift(c)
        if discrete?
          case op
          when :<= then cdf_at(c)
          when :< then (cdf_at(c) - pdf_at(c)).simplify
          when :>= then (survival(c) + pdf_at(c)).simplify
          when :> then survival(c)
          else raise ArgumentError, "probability: use <, <=, > or >="
          end
        else
          case op
          when :<, :<= then cdf_at(c)
          when :>, :>= then Limits.infinite?(c) ? (1 - cdf_at(c)).simplify : survival(c)
          else raise ArgumentError, "probability: use <, <=, > or >="
          end
        end
      end

      # The set of values of the random variable that the event describes.
      def event_set(event)
        names = event.lhs.variables | event.rhs.variables
        raise ArgumentError, "probability: name one random variable, got #{event}" unless names.size == 1
        set = Inequalities.solve(event, Var.new(names.first))
        raise ArgumentError, "probability: cannot decide #{event}" unless set.is_a?(RealSet) || set.is_a?(Interval)
        set
      end

      # The cdf at a bound. At the two infinities it is 1 and 0, which the
      # closed form does not reach on its own - Normal's erf(2**(1/2)*oo)
      # does not fold, and Uniform's (x - a)/(b - a) runs away.
      def cdf_at(v)
        v = Expression.lift(v)
        return cdf(v) unless Limits.infinite?(v)
        Num.new(v == OO ? 1 : 0)
      end

      # No mass sits at an infinite point, whatever the closed form says.
      def pdf_at(v)
        v = Expression.lift(v)
        Limits.infinite?(v) ? Num.new(0) : pdf(v)
      end

      def set_probability(set)
        intervals = set.is_a?(Interval) ? [set] : set.intervals
        intervals.map { |i| piece_probability(i) }.reduce(Num.new(0)) { |a, b| a + b }.simplify
      end

      # P over one interval. A discrete distribution counts the closed ends
      # in, which the cdf alone does not: cdf(hi) - cdf(lo) leaves out lo.
      def piece_probability(interval)
        lo, hi = interval.low, interval.high
        total =
          if hi == OO && !Limits.infinite?(lo) then survival(lo)
          elsif !Limits.infinite?(lo) && !Limits.infinite?(hi) then between(lo, hi)
          else cdf_at(hi) - cdf_at(lo)
          end
        return total unless discrete?
        total += pdf_at(interval.low) unless interval.left_open
        total -= pdf_at(interval.high) if interval.right_open
        total
      end

      # P(lo < X <= hi) for finite ends: in the upper tail as a difference of
      # survival functions, where cdf(10) - cdf(9) of the standard normal
      # cancelled to 0 (fourth review, P-11); the cdf elsewhere.
      def between(lo, hi)
        upper = !discrete? && lo.variables.empty? && (c = RCAS.real_float(cdf_at(lo))) && c > 0.5
        upper ? (survival(lo) - survival(hi)).simplify : (cdf_at(hi) - cdf_at(lo)).simplify
      end

      # E[f(X)]: an integral or sum over the support (formal when rcas cannot do it).
      def expectation(expr, var = :x)
        x = Expression.lift(var)
        lo, hi = support
        f = (Expression.lift(expr) * pdf(x)).simplify
        discrete? ? Summation.sum(f, x, lo, hi) : Integrate.definite(f, x, lo, hi)
      end

      def moment(k, var = :x) = expectation(Expression.lift(var)**k, var)

      # Random draws (Float, or Integer for discrete distributions); numeric
      # parameters only. Without `random:` the session's RCAS.random draws,
      # so RCAS.random = 42 pins these as it pins every other random object.
      def sample(n = nil, random: nil)
        values = numeric_params
        rng = random || RCAS.random
        n.nil? ? draw(values, rng) : Array.new(n) { draw(values, rng) }
      end

      def numeric_params
        params.map do |p|
          v = p.evalf
          raise ArgumentError, "#{self}: numeric parameters are needed here" unless v.is_a?(Numeric) && !v.is_a?(Complex)
          v
        end
      end

      def numeric(x, what)
        v = Expression.lift(x).evalf
        raise ArgumentError, "#{what}: a number is needed, got #{x}" unless v.is_a?(Numeric) && !v.is_a?(Complex)
        v
      end

      def float?(param) = param.is_a?(Num) && param.value.is_a?(Float)
      def exact?(e) = (e = Expression.lift(e)).variables.empty? && e.each_node.none? { |n| n.is_a?(Num) && n.value.is_a?(Float) }

      # The least k with cdf(k) >= p, the mass added up exactly and compared
      # exactly (Decide for the constants a rate like 1 brings: e**-1/k!).
      def exact_quantile(p, k, hi)
        total = mass(Num.new(k))
        10_000.times do
          order = Inequalities.compare(total, p)
          raise NotImplementedError, "quantile: cannot compare cdf(#{k}) with #{p}" if order.nil?
          return Num.new(k) if order >= 0 || (hi.is_a?(Num) && k >= hi.value)
          k += 1
          total = (total + mass(Num.new(k))).simplify
        end
        raise NotImplementedError, "quantile: the #{p}-quantile lies beyond 10000 steps from the start"
      end

      # A quantile is defined for a probability; a number outside [0, 1] is
      # refused rather than answered with log(-2) (third review, P-13).
      # A constant is compared exactly: 2*sqrt(2) and pi are no probabilities
      # either (only a Num was checked: fourth review, P-13).
      def probability!(p)
        v = Expression.lift(p)
        return unless v.variables.empty?
        below = Inequalities.compare(v, Num.new(0))
        above = Inequalities.compare(v, Num.new(1))
        return unless below == -1 || above == 1
        raise ArgumentError, "quantile: #{p} is not a probability, it must lie in [0, 1]"
      end

      # Generic quantile: bisection on the numeric CDF (continuous) or a scan (discrete).
      def quantile(p)
        probability!(p)
        pv = numeric(p, "quantile")
        raise ArgumentError, "quantile: p must be in (0, 1)" unless pv > 0 && pv < 1
        if discrete?
          # the mass added up once, k by k, rather than an exact cdf rebuilt
          # for every k (quadratic, and it overflowed for Poisson(200))
          lo, hi = support
          k = lo.evalf.to_i
          target = Expression.lift(p)
          return exact_quantile(target, k, hi) if exact?(target) && params.all? { |q| exact?(q) }
          values = params.all? { |q| q.is_a?(Num) } ? numeric_params : nil
          weight = ->(j) { values && respond_to?(:float_pmf) ? float_pmf(j, values) : pdf(j).evalf.to_f }
          total = weight.call(k)
          # the least k with cdf(k) >= p, allowing only the rounding the Float
          # sum itself has made (a slack of 1e-12 answered 0 for
          # Binomial(3, 1/2) at 1/8 + 1e-14: fourth review)
          while total < pv * (1 - 4 * (k - lo.evalf.to_i + 1) * Float::EPSILON)
            break if hi.is_a?(Num) && k >= hi.value
            k += 1
            total += weight.call(k)
          end
          Num.new(k)
        else
          lo, hi = numeric_bracket
          # the bracket grows until it holds the quantile: the Cauchy
          # quantile at 0.99999 is 31831, past a fixed 10**4 (P-6)
          lower = support.first
          60.times do
            break if cdf(hi).evalf >= pv
            lo = hi
            hi = hi.positive? ? hi * 4 : hi + 1.0
          end
          60.times do
            break if lo <= (Limits.infinite?(lower) ? -Float::INFINITY : lower.evalf) || cdf(lo).evalf <= pv
            hi = lo
            lo = lo.negative? ? lo * 4 : lo - 1.0
          end
          # in the upper half the survival function is the one to solve: the
          # cdf near 1 moves in steps of 1.1e-16, and the normal quantile at
          # 1 - 1e-15 came out as 7.9364 for 7.9414 (fourth review, P-6)
          upper = pv > 0.5
          tail = 1.0 - pv
          below = ->(v) { upper ? survival(Num.new(v)).evalf > tail : cdf(v).evalf < pv }
          200.times do
            mid = (lo + hi) / 2.0
            break if mid == lo || mid == hi
            below.call(mid) ? lo = mid : hi = mid
          end
          x = (lo + hi) / 2.0
          3.times do # Newton polish, kept only while it is a small correction
            density = pdf(x).evalf
            break unless density.is_a?(Numeric) && density.positive?
            miss = upper ? tail - survival(Num.new(x)).evalf : cdf(x).evalf - pv
            step = x - miss / density
            break unless step.finite? && (step - x).abs <= 1e-6 * [1.0, x.abs].max
            x = step
          end
          Num.new(x)
        end
      end
    end

    # ---- continuous ----------------------------------------------------------------

    class Normal < Distribution
      def validate = positive(sigma, "the standard deviation")
      def mu = params[0]
      def sigma = params[1]
      def support = [Neg.new(OO), OO]
      def pdf(x) = (Fn.new(:exp, [-((Expression.lift(x) - mu)**2) / (2 * sigma**2)]) / (sigma * RCAS.sqrt(2 * PI))).simplify
      # Left of the mean the cdf is erfc(...)/2, which keeps the digits of a
      # far tail; 1/2 + erf(...)/2 cancels them all at -8 sigma (P-11).
      def cdf(x)
        z = ((Expression.lift(x) - mu) / (sigma * RCAS.sqrt(2))).simplify
        return (RCAS.erfc(Neg.new(z).simplify) / 2).simplify if Decide.sign(z) == :negative
        ((1 + RCAS.erf(z)) / 2).simplify
      end

      def survival(c)
        z = ((Expression.lift(c) - mu) / (sigma * RCAS.sqrt(2))).simplify
        return (RCAS.erfc(z) / 2).simplify if Decide.sign(z) == :positive
        super
      end

      # Both ends in one tail: erfc there, which keeps the digits; across
      # the mean: (erf(b) - erf(a))/2, so P(-1 <= X <= 1) is erf(sqrt(2)/2).
      def between(lo, hi)
        a, b = [lo, hi].map { |v| ((Expression.lift(v) - mu) / (sigma * RCAS.sqrt(2))).simplify }
        sa, sb = [a, b].map { |z| Decide.sign(z) }
        return ((RCAS.erfc(a) - RCAS.erfc(b)) / 2).simplify if sa == :positive && %i[positive zero].include?(sb)
        return ((RCAS.erfc(Neg.new(b).simplify) - RCAS.erfc(Neg.new(a).simplify)) / 2).simplify if sb == :negative
        return ((RCAS.erf(b) - RCAS.erf(a)) / 2).simplify if sa && sb
        super
      end

      def mean = mu
      def variance = (sigma**2).simplify
      def median = mu
      def skewness = Num.new(0)
      def kurtosis = Num.new(3)

      # E[X^k] = sum_j binomial(k, 2j) mu^(k-2j) sigma^(2j) (2j - 1)!!
      def moment(k, _var = :x)
        return super unless k.is_a?(Integer) && k >= 0
        total = (0..k / 2).map do |j|
          double_factorial = (1..2 * j - 1).step(2).reduce(1, :*)
          RCAS.binomial(k, 2 * j) * mu**(k - 2 * j) * sigma**(2 * j) * double_factorial
        end.reduce(:+)
        total.expand.simplify
      end

      def quantile(p)
        probability!(p)
        pv = Expression.lift(p)
        return mu if pv.is_a?(Num) && pv.value == Rational(1, 2)
        super
      end

      def numeric_bracket
        m, s = numeric_params
        [m - 40.0 * s, m + 40.0 * s]
      end

      def draw(values, random)
        m, s = values
        u1 = 1.0 - random.rand
        u2 = random.rand
        m + s * Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
      end
    end

    class Uniform < Distribution
      def validate
        return unless a.is_a?(Num) && b.is_a?(Num) && a.value.real? && b.value.real?
        raise ArgumentError, "Uniform: the range is empty (#{a} to #{b})" unless a.value < b.value
      end
      def a = params[0]
      def b = params[1]
      def support = [a, b]

      # The density on the support; 0 outside. A symbolic point gets the
      # case split, which is what makes a later substitution right:
      # P(X <= a) at a = 2 is 1, and a bare (a - 0)/(1 - 0) said 2 (T6).
      def pdf(x)
        x = Expression.lift(x)
        return Num.new(0) if x.is_a?(Num) && (v = numeric_params) && !x.value.between?(v[0], v[1])
        return (1 / (b - a)).simplify if x.is_a?(Num)
        RCAS.piecewise(x < a => 0, x <= b => (1 / (b - a)).simplify, :else => 0)
      end

      def cdf(x)
        x = Expression.lift(x)
        if x.is_a?(Num)
          lo, hi = numeric_params
          return Num.new(0) if x.value < lo
          return Num.new(1) if x.value > hi
          return ((x - a) / (b - a)).simplify
        end
        RCAS.piecewise(x < a => 0, x <= b => ((x - a) / (b - a)).simplify, :else => 1)
      end

      def quantile(p)
        probability!(p)
        (a + Expression.lift(p) * (b - a)).simplify
      end
      def moment(k, _var = :x) = k.is_a?(Integer) && k >= 0 ? ((b**(k + 1) - a**(k + 1)) / ((k + 1) * (b - a))).cancel : super
      def mean = ((a + b) / 2).simplify
      def variance = ((b - a)**2 / 12).simplify
      def skewness = Num.new(0)
      def kurtosis = Num.new(Rational(9, 5))
      def draw(values, random) = values[0] + random.rand * (values[1] - values[0])
    end

    class Exponential < Distribution
      def validate = positive(rate, "the rate")
      def rate = params[0]
      def support = [Num.new(0), OO]

      def pdf(x)
        x = Expression.lift(x)
        return Num.new(0) if x.is_a?(Num) && x.value.negative?
        density = (rate * Fn.new(:exp, [-rate * x])).simplify
        symbolic_support?(x) ? RCAS.piecewise(x < 0 => 0, :else => density) : density
      end

      def cdf(x)
        x = Expression.lift(x)
        return Num.new(0) if x.is_a?(Num) && x.value.negative?
        value = (1 - Fn.new(:exp, [-rate * x])).simplify
        symbolic_support?(x) ? RCAS.piecewise(x < 0 => 0, :else => value) : value
      end

      # A point whose side of 0 is not known: the support has to show.
      def symbolic_support?(x) = !x.variables.empty? && !%i[positive nonnegative].include?(RCAS.sign_of(x))

      def quantile(p)
        probability!(p)
        p = Expression.lift(p)
        return OO if p.is_a?(Num) && p.value == 1 # the whole mass lies below oo alone
        (Fn.new(:log, [1 / (1 - p)]) / rate).simplify
      end
      def moment(k, _var = :x) = k.is_a?(Integer) && k >= 0 ? (RCAS.factorial(k) / rate**k).simplify : super
      def mean = (1 / rate).simplify
      def variance = (1 / rate**2).simplify
      def skewness = Num.new(2)
      def kurtosis = Num.new(9)
      def draw(values, random) = -Math.log(1.0 - random.rand) / values[0]
    end

    # ---- discrete ---------------------------------------------------------------------

    class Discrete < Distribution
      def discrete? = true

      # P(X > c) past the mean as the sum of the tail itself: 1 - cdf in
      # Floats gave Binomial(100, 0.5) the probability -3.2e-14 of X > 95
      # (fourth review, P-11). Exact parameters keep 1 - cdf, which is exact
      # and which evalf now evaluates without cancelling.
      def survival(c)
        c = Expression.lift(c)
        lo, hi = support
        return super unless c.variables.empty? && params.all? { |q| q.is_a?(Num) } && params.any? { |q| float?(q) }
        top = floor_of(c) or return super
        mean_value = RCAS.real_float(mean)
        return super if mean_value.nil? || top < mean_value
        values = numeric_params
        weight = ->(j) { respond_to?(:float_pmf) ? float_pmf(j, values) : mass(Num.new(j)).evalf.to_f }
        last = Limits.infinite?(hi) ? nil : hi.value.to_i
        total = 0.0
        k = [top + 1, lo.value.to_i].max
        100_000.times do
          break if last && k > last
          term = weight.call(k)
          total += term
          break if last.nil? && term <= total * Float::EPSILON / 4
          k += 1
        end
        Num.new(total)
      end

      # The mass at a point. At a symbolic point the formula holds only on
      # the support and at whole numbers, so it comes as a piecewise that
      # says so (the pmf of Binomial(10, 1/2) at 5/2 was not 0, and the cdf
      # of a die was 3/2 at 9: fourth review, T6) - unless the assumptions
      # already put the point there.
      def pdf(k)
        k = Expression.lift(k)
        return mass(k) if k.variables.empty? || on_support?(k)
        lo, hi = support
        branches = [[Inequality.new(k, :<, lo), Num.new(0)]]
        branches << [Inequality.new(hi, :<, k), Num.new(0)] unless Limits.infinite?(hi)
        branches << [Membership.new(k, ZZ), mass(k)]
        Piecewise.new(branches + [[Piecewise::OTHERWISE, Num.new(0)]])
      end

      # k is a whole number between the ends of the support, by the
      # assumptions.
      def on_support?(k)
        domain = Infer.domain(k)
        return false unless domain && domain <= ZZ
        lo, hi = support
        above = Limits.infinite?(lo) || %i[positive nonnegative].include?(RCAS.sign_of((k - lo).simplify)) ||
                (domain <= NN && lo.is_a?(Num) && lo.value <= 0)
        below = Limits.infinite?(hi) || %i[positive nonnegative].include?(RCAS.sign_of((hi - k).simplify))
        above && below
      end

      # Sum of the mass over the support up to k, exactly for numeric k; at a
      # symbolic k the sum up to floor(k), inside the support.
      def cdf(k)
        k = Expression.lift(k)
        return symbolic_cdf(k) unless k.variables.empty?
        lo, hi = support
        # a constant bound that is not a number: the values are integers, so
        # X <= sqrt(5) is X <= 2 (a formal sum up to sqrt(5) summed
        # binomial(10, sqrt(5)): third review, P-9)
        k = Num.new(floor_of(k)) if !k.is_a?(Num) && k.variables.empty? && floor_of(k)
        if k.is_a?(Num) && k.value.real? && lo.is_a?(Num)
          return Num.new(0) if k.value < lo.value
          return Num.new(1) if hi.is_a?(Num) && k.value >= hi.value
          top = k.value.floor
          return (lo.value.to_i..top).map { |j| mass(Num.new(j)) }.reduce(:+).simplify
        end
        j = Var.new(:j)
        Summation.sum(mass(j), j, lo, k)
      end

      def symbolic_cdf(k)
        integer = (d = Infer.domain(k)) && d <= ZZ
        top = integer ? k : Fn.new(:floor, [k])
        formula = respond_to?(:cdf_formula) ? cdf_formula(top) : Summation.sum(mass(Var.new(:j)), Var.new(:j), support.first, top)
        return formula if on_support?(k)
        lo, hi = support
        branches = [[Inequality.new(k, :<, lo), Num.new(0)]]
        branches << [Inequality.new(hi, :<=, k), Num.new(1)] unless Limits.infinite?(hi)
        Piecewise.new(branches + [[Piecewise::OTHERWISE, formula]])
      end

      # floor of a real constant, decided exactly; nil when it cannot be.
      def floor_of(v)
        f = Analysis.numeric(v) or return nil
        n = f.floor
        n -= 1 if Inequalities.compare(v, Num.new(n)) == -1
        n += 1 if Inequalities.compare(v, Num.new(n + 1)) != -1
        Inequalities.compare(v, Num.new(n)) != -1 && Inequalities.compare(v, Num.new(n + 1)) == -1 ? n : nil
      end

      # No mass at a point that is not an integer.
      def pdf_at(v)
        v = Expression.lift(v)
        return Num.new(0) if Limits.infinite?(v)
        if !v.is_a?(Num) && v.variables.empty? && (f = floor_of(v)) && Inequalities.compare(v, Num.new(f)) != 0
          return Num.new(0)
        end
        pdf(v)
      end

      def draw(values, random)
        u = random.rand
        k = support.first.evalf.to_i
        weight = ->(j) { respond_to?(:float_pmf) ? float_pmf(j, values) : mass(Num.new(j)).evalf }
        total = weight.call(k)
        while total < u
          k += 1
          total += weight.call(k)
        end
        k
      end
    end

    class Bernoulli < Discrete
      def validate = probability_in(p, "the probability")
      def p = params[0]
      def support = [Num.new(0), Num.new(1)]

      def mass(k)
        k = Expression.lift(k)
        if k.is_a?(Num)
          return p if k.value == 1
          return (1 - p).simplify if k.value.zero?
          return Num.new(0)
        end
        (p**k * (1 - p)**(1 - k)).simplify
      end

      def mean = p
      def variance = (p * (1 - p)).simplify
      def skewness = ((1 - 2 * p) / RCAS.sqrt(p * (1 - p))).simplify
      def kurtosis = ((1 - 3 * p * (1 - p)) / (p * (1 - p))).simplify
    end

    class Binomial < Discrete
      def validate
        whole(n, "the number of trials")
        probability_in(p, "the probability")
      end
      def n = params[0]
      def p = params[1]
      def support = [Num.new(0), n]

      def mass(k)
        k = Expression.lift(k)
        return Num.new(0) if k.is_a?(Num) && n.is_a?(Num) && (k.value.negative? || k.value > n.value || !k.value.integer?)
        # a Float probability is a numeric question, and the exact binomial
        # coefficient times p**k overflows long before the product does
        # (C(1100, 550)/2**1100 was Infinity: third review, P-4)
        if float?(p) && k.is_a?(Num) && n.is_a?(Num) && n.value.is_a?(Integer)
          return Num.new(Distributions.binomial_pmf(n.value, k.value.to_i, p.value))
        end
        (RCAS.binomial(n, k) * p**k * (1 - p)**(n - k)).simplify
      end

      def float_pmf(k, values) = Distributions.binomial_pmf(values[0].to_i, k, values[1].to_f)

      def mean = (n * p).simplify
      def variance = (n * p * (1 - p)).simplify
      def skewness = ((1 - 2 * p) / RCAS.sqrt(n * p * (1 - p))).simplify
      def kurtosis = (3 + (1 - 6 * p * (1 - p)) / (n * p * (1 - p))).simplify
    end

    class Poisson < Discrete
      def validate = positive(rate, "the rate")
      def rate = params[0]
      def support = [Num.new(0), OO]

      def mass(k)
        k = Expression.lift(k)
        return Num.new(0) if k.is_a?(Num) && (k.value.negative? || !k.value.integer?)
        return Num.new(Distributions.poisson_pmf(k.value.to_i, rate.value)) if float?(rate) && k.is_a?(Num)
        (Fn.new(:exp, [-rate]) * rate**k / RCAS.factorial(k)).simplify
      end

      def float_pmf(k, values) = Distributions.poisson_pmf(k, values[0].to_f)

      def mean = rate
      def variance = rate
      def skewness = (1 / RCAS.sqrt(rate)).simplify
      def kurtosis = (3 + 1 / rate).simplify
    end

    # Failures before the first success: P(X = k) = (1 - p)**k p, k = 0, 1, ...
    class Geometric < Discrete
      def validate
        positive(p, "the probability")
        probability_in(p, "the probability")
      end

      def p = params[0]
      def support = [Num.new(0), OO]

      def mass(k)
        k = Expression.lift(k)
        return Num.new(0) if k.is_a?(Num) && (k.value.negative? || !k.value.integer?)
        ((1 - p)**k * p).simplify
      end

      # at a whole k >= 0
      def cdf_formula(k) = (1 - (1 - p)**(k + 1)).simplify

      def mean = ((1 - p) / p).simplify
      def variance = ((1 - p) / p**2).simplify
      def skewness = ((2 - p) / RCAS.sqrt(1 - p)).simplify
      def kurtosis = (9 + p**2 / (1 - p)).simplify
    end

# ---- sampling helpers ------------------------------------------------------------

module_function

# The pmfs in logarithms, for Float parameters: C(n, k) p**k (1 - p)**(n - k)
# and exp(-l) l**k/k! without the overflow of their parts.
# The exact binomial coefficient times the powers where the Floats hold
# them - C(10, 5)/2**10 is 0.24609375 to the last bit, which lgamma's
# exp(log ...) was not (fourth review) - and the logarithms where a
# product under- or overflows.
def binomial_pmf(n, k, p)
  return 0.0 if k.negative? || k > n
  return (k == 0 ? 1.0 : 0.0) if p.zero?
  return (k == n ? 1.0 : 0.0) if p == 1.0
  coefficient = (1..k).reduce(1) { |c, i| c * (n - k + i) / i }.to_f if [k, n - k].min <= 2000
  if coefficient&.finite?
    rest = p < 1e-4 ? Math.exp((n - k) * log_one_minus(p)) : (1.0 - p)**(n - k)
    direct = coefficient * p**k * rest
    return direct if direct.finite? && direct > 1e-290
  end
  Math.exp(Math.lgamma(n + 1).first - Math.lgamma(k + 1).first - Math.lgamma(n - k + 1).first +
           k * Math.log(p) + (n - k) * log_one_minus(p))
end

# log(1 - p) without losing a small p to the 1 (Ruby's Math has no log1p)
def log_one_minus(p) = p.abs < 1e-4 ? -(p + p * p / 2 + p**3 / 3) : Math.log(1 - p)

def poisson_pmf(k, rate)
  return 0.0 if k.negative?
  if k <= 170
    direct = Math.exp(-rate) * rate**k / (1..k).reduce(1, :*).to_f
    return direct if direct.finite? && direct > 1e-290
  end
  Math.exp(-rate + k * Math.log(rate) - Math.lgamma(k + 1).first)
end

def normal_variate(random) = Math.sqrt(-2.0 * Math.log(1.0 - random.rand)) * Math.cos(2 * Math::PI * random.rand)

# Marsaglia-Tsang squeeze method for Gamma(shape, 1) [MT00].
def gamma_variate(shape, random)
  return gamma_variate(shape + 1.0, random) * random.rand**(1.0 / shape) if shape < 1.0
  d = shape - 1.0 / 3.0
  c = 1.0 / Math.sqrt(9.0 * d)
  loop do
    x = normal_variate(random)
    v = (1.0 + c * x)**3
    next if v <= 0
    u = random.rand
    return d * v if u < 1.0 - 0.0331 * x**4
    return d * v if Math.log(u) < 0.5 * x * x + d * (1.0 - v + Math.log(v))
  end
end

# ---- the sampling distributions ---------------------------------------------------

# Student's t with nu degrees of freedom. The CDF is exact for nu = 1
# (Cauchy) and nu = 2, numeric otherwise (regularized incomplete beta).
class StudentT < Distribution
  def validate = positive(nu, "the degrees of freedom")
  def nu = params[0]
  def support = [Neg.new(OO), OO]

  def pdf(x)
    x = Expression.lift(x)
    (RCAS.gamma((nu + 1) / 2) / (RCAS.sqrt(nu * PI) * RCAS.gamma(nu / 2)) * (1 + x**2 / nu)**(-(nu + 1) / 2)).simplify
  end

  def cdf(x)
    x = Expression.lift(x)
    return ((1 + 2 * Fn.new(:atan, [x]) / PI) / 2).simplify if nu == Num.new(1)
    return (Num.new(1) / 2 + x / (2 * RCAS.sqrt(2 + x**2))).simplify if nu == Num.new(2)
    Num.new(1.0 - upper_tail(numeric(nu, "cdf"), numeric(x, "cdf")))
  end

  # The upper tail directly: atan(1/t)/pi for the Cauchy distribution and
  # 1/(s*(s + t)) with s = sqrt(2 + t**2) for two degrees of freedom, where
  # 1 - cdf cancelled (fourth review, P-11); the incomplete beta otherwise.
  def survival(c)
    c = Expression.lift(c)
    if (nu == Num.new(1) || nu == Num.new(2)) && Decide.sign(c) == :positive
      return (Fn.new(:atan, [1 / c]) / PI).simplify if nu == Num.new(1)
      root = RCAS.sqrt(2 + c**2)
      return (1 / (root * (root + c))).simplify
    end
    return super if [1, 2].any? { |n| nu == Num.new(n) } || !c.variables.empty?
    Num.new(upper_tail(numeric(nu, "cdf"), numeric(c, "cdf")))
  end

  # P(T > t) in Floats. Near 0 the tail is 1/2 - I_y(1/2, nu/2)/2 with
  # y = t**2/(nu + t**2) computed directly - through x = nu/(nu + t**2)
  # the digits of cdf(1e-9) were lost to the rounding of x; far out it is
  # I_x(nu/2, 1/2)/2. For a huge nu the incomplete beta does not settle,
  # and the normal limit with its 1/nu correction is exact to 1/nu**2.
  def upper_tail(v, t)
    if v > 1e7
      phi = Math.exp(-t * t / 2) / Math.sqrt(2 * Math::PI)
      return Math.erfc(t / Math.sqrt(2)) / 2 + phi * (t**3 + t) / (4 * v)
    end
    if t * t < v
      half = Special.beta_i(t * t / (v + t * t), 0.5, v / 2.0) / 2.0
      return t.negative? ? 0.5 + half : 0.5 - half
    end
    tail = Special.beta_i(v / (v + t * t), v / 2.0, 0.5) / 2.0
    t.positive? ? tail : 1.0 - tail
  end

  # symmetric about 0: the median is 0, not the -2e-8 a bisection stops at
  def quantile(p)
    probability!(p)
    q = Expression.lift(p)
    return Num.new(0) if q.is_a?(Num) && q.value == Rational(1, 2)
    super
  end

  # A moment exists only for enough degrees of freedom: the Cauchy
  # distribution (nu = 1) has no mean, and its "variance" came out as -1
  # (third review, P-7). For a number below the threshold the answer is
  # oo where the integral diverges to it and undefined where it has no
  # value; a symbolic nu keeps the formula, which holds above it.
  def mean = moment_exists(1, UNDEFINED) { Num.new(0) }
  def median = Num.new(0)
  def variance = moment_exists(2, nu_above?(1) ? OO : UNDEFINED) { (nu / (nu - 2)).simplify }
  def skewness = moment_exists(3, UNDEFINED) { Num.new(0) }
  def kurtosis = moment_exists(4, nu_above?(2) ? OO : UNDEFINED) { (3 + 6 / (nu - 4)).simplify }

  # The formula only where the moment exists: it is taken after the test,
  # nu/(nu - 2) at nu = 2 divided by zero before oo was ever answered
  # (fourth review, P-7).
  def moment_exists(order, otherwise)
    return yield unless nu.is_a?(Num) && nu.value.real?
    nu.value > order ? yield : otherwise
  end

  def nu_above?(threshold) = nu.is_a?(Num) && nu.value.real? && nu.value > threshold
  def numeric_bracket = [-10.0, 10.0]
  def draw(values, random) = Distributions.normal_variate(random) / Math.sqrt(2.0 * Distributions.gamma_variate(values[0] / 2.0, random) / values[0])
end

# Chi-square with k degrees of freedom; the CDF is exact for even k.
class ChiSquare < Distribution
  def validate = positive(k, "the degrees of freedom")
  def k = params[0]
  def support = [Num.new(0), OO]

  def pdf(x)
    x = Expression.lift(x)
    return Num.new(0) if x.is_a?(Num) && x.value.real? && x.value.negative?
    (x**(k / 2 - 1) * Fn.new(:exp, [-x / 2]) / (2**(k / 2) * RCAS.gamma(k / 2))).simplify
  end

  def cdf(x)
    x = Expression.lift(x)
    return Num.new(0) if x.is_a?(Num) && x.value.real? && !x.value.positive?
    # a Float point is a numeric question: the closed form's terms
    # (x/2)**149/149! overflow at k = 300 (P-4)
    return Num.new(Special.gamma_p(numeric(k, "cdf") / 2.0, x.value / 2.0)) if x.is_a?(Num) && x.value.is_a?(Float)
    if k.is_a?(Num) && k.value.is_a?(Integer) && k.value.even? && k.value.positive?
      half = (x / 2).simplify
      tail = (0...k.value / 2).map { |m| half**m / RCAS.factorial(m) }.reduce(:+)
      return (1 - Fn.new(:exp, [-half]) * tail).simplify
    end
    Num.new(Special.gamma_p(numeric(k, "cdf") / 2.0, numeric(x, "cdf") / 2.0))
  end

  def survival(c)
    c = Expression.lift(c)
    return super unless c.variables.empty? && !(k.is_a?(Num) && k.value.is_a?(Integer) && k.value.even? && !c.is_a?(Num))
    return super if k.is_a?(Num) && k.value.is_a?(Integer) && k.value.even? && c.is_a?(Num) && !c.value.is_a?(Float)
    Num.new(Special.gamma_q(numeric(k, "cdf") / 2.0, numeric(c, "cdf") / 2.0))
  end

  def mean = k
  def variance = (2 * k).simplify
  def skewness = RCAS.sqrt(8 / k).simplify
  def kurtosis = (3 + 12 / k).simplify

  def numeric_bracket
    v = numeric_params.first
    [0.0, v + 20.0 * Math.sqrt(2.0 * v) + 40.0]
  end

  def draw(values, random) = 2.0 * Distributions.gamma_variate(values[0] / 2.0, random)
end

# The F (variance ratio) distribution with d1 and d2 degrees of freedom.
class FRatio < Distribution
  def validate
    positive(d1, "the numerator degrees of freedom")
    positive(d2, "the denominator degrees of freedom")
  end
  def d1 = params[0]
  def d2 = params[1]
  def support = [Num.new(0), OO]

  def pdf(x)
    x = Expression.lift(x)
    return Num.new(0) if x.is_a?(Num) && x.value.real? && !x.value.positive?
    beta = (RCAS.gamma(d1 / 2) * RCAS.gamma(d2 / 2) / RCAS.gamma((d1 + d2) / 2)).simplify
    ((d1 / d2)**(d1 / 2) * x**(d1 / 2 - 1) * (1 + d1 * x / d2)**(-(d1 + d2) / 2) / beta).simplify
  end

  def cdf(x)
    x = Expression.lift(x)
    return Num.new(0) if x.is_a?(Num) && x.value.real? && !x.value.positive?
    a = numeric(d1, "cdf")
    b = numeric(d2, "cdf")
    v = numeric(x, "cdf")
    Num.new(Special.beta_i(a * v / (a * v + b), a / 2.0, b / 2.0))
  end

  # The mean exists for d2 > 2 and is infinite below; the variance needs
  # d2 > 4, is infinite for 2 < d2 <= 4 and undefined below (P-7).
  def mean = numeric_d2 && numeric_d2 <= 2 ? OO : (d2 / (d2 - 2)).simplify
  def variance
    return (numeric_d2 > 2 ? OO : UNDEFINED) if numeric_d2 && numeric_d2 <= 4
    (2 * d2**2 * (d1 + d2 - 2) / (d1 * (d2 - 2)**2 * (d2 - 4))).simplify
  end

  def numeric_d2 = d2.is_a?(Num) && d2.value.real? ? d2.value : nil
  def numeric_bracket = [0.0, 10.0]

  # I_x(a/2, b/2) has its upper tail as I_(1-x)(b/2, a/2), without 1 - it.
  def survival(c)
    return super unless Expression.lift(c).variables.empty?
    a = numeric(d1, "cdf")
    b = numeric(d2, "cdf")
    v = numeric(c, "cdf")
    return Num.new(1.0) unless v.positive?
    Num.new(Special.beta_i(b / (a * v + b), b / 2.0, a / 2.0))
  end

  def draw(values, random)
    a, b = values
    (2.0 * Distributions.gamma_variate(a / 2.0, random) / a) / (2.0 * Distributions.gamma_variate(b / 2.0, random) / b)
  end
end

    class DiscreteUniform < Discrete
      def validate
        [a, b].each do |e|
          next unless e.is_a?(Num) && e.value.real?
          raise ArgumentError, "DiscreteUniform: the ends must be whole numbers, got #{e}" unless e.value == e.value.round
        end
        return unless a.is_a?(Num) && b.is_a?(Num) && a.value.real? && b.value.real?
        raise ArgumentError, "DiscreteUniform: the range is empty (#{a} to #{b})" unless a.value <= b.value
      end
      def a = params[0]
      def b = params[1]
      def support = [a, b]
      def count = (b - a + 1).simplify

      # With symbolic ends the cdf is the count of the integers from a to k
      # over the count of all of them, and the case split says where
      # (sum from a symbolic a crashed: P-15).
      def cdf(k)
        return super if a.is_a?(Num) && b.is_a?(Num)
        k = Expression.lift(k)
        top = k.is_a?(Num) ? Num.new(k.value.floor) : Fn.new(:floor, [k])
        RCAS.piecewise(k < a => 0, k < b => ((top - a + 1) / count).simplify, :else => 1)
      end

      def mass(k)
        k = Expression.lift(k)
        if k.is_a?(Num) && a.is_a?(Num) && b.is_a?(Num)
          return Num.new(0) unless k.value.integer? && k.value.between?(a.value, b.value)
        end
        (1 / count).simplify
      end

      def mean = ((a + b) / 2).simplify
      def variance = ((count**2 - 1) / 12).simplify
      def skewness = Num.new(0)
      def kurtosis = (Num.new(Rational(3, 5)) * (3 - 4 / (count**2 - 1))).simplify
    end
  end
end
