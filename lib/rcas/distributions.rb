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
          lo = Expression.lift(event.begin || Neg.new(OO))
          hi = Expression.lift(event.end || OO)
          hi = hi - 1 if event.exclude_end? && !event.end.nil? && discrete?
          return (cdf(hi) - cdf(lo) + pdf(lo)).simplify if discrete? && !Limits.infinite?(lo) # inclusive lower end
          return (cdf(hi) - cdf(lo)).simplify unless event.exclude_end? && !discrete? # continuous: endpoints have measure zero
          (cdf(hi) - cdf(lo)).simplify
        when Inequality
          c = event.rhs
          if discrete?
            case event.op
            when :<= then cdf(c)
            when :< then (cdf(c) - pdf(c)).simplify
            when :>= then (1 - cdf(c) + pdf(c)).simplify
            when :> then (1 - cdf(c)).simplify
            else raise ArgumentError, "probability: use <, <=, > or >="
            end
          else
            case event.op
            when :<, :<= then cdf(c)
            when :>, :>= then (1 - cdf(c)).simplify
            else raise ArgumentError, "probability: use <, <=, > or >="
            end
          end
        else raise ArgumentError, "probability: give a range (a..b) or an inequality (x > 1)"
        end
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

      # Generic quantile: bisection on the numeric CDF (continuous) or a scan (discrete).
      def quantile(p)
        pv = numeric(p, "quantile")
        raise ArgumentError, "quantile: p must be in (0, 1)" unless pv > 0 && pv < 1
        if discrete?
          lo, = support
          k = lo.evalf.to_i
          k += 1 while cdf(k).evalf < pv - 1e-12
          Num.new(k)
        else
          lo, hi = numeric_bracket
          40.times do
            mid = (lo + hi) / 2.0
            cdf(mid).evalf < pv ? lo = mid : hi = mid
          end
          x = (lo + hi) / 2.0
          3.times { x -= (cdf(x).evalf - pv) / pdf(x).evalf } # Newton polish
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
      def cdf(x) = ((1 + RCAS.erf((Expression.lift(x) - mu) / (sigma * RCAS.sqrt(2)))) / 2).simplify
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

      # The density on the support; 0 outside for a number.
      def pdf(x)
        x = Expression.lift(x)
        return Num.new(0) if x.is_a?(Num) && (v = numeric_params) && !x.value.between?(v[0], v[1])
        (1 / (b - a)).simplify
      end

      def cdf(x)
        x = Expression.lift(x)
        if x.is_a?(Num)
          lo, hi = numeric_params
          return Num.new(0) if x.value < lo
          return Num.new(1) if x.value > hi
        end
        ((x - a) / (b - a)).simplify
      end

      def quantile(p) = (a + Expression.lift(p) * (b - a)).simplify
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
        (rate * Fn.new(:exp, [-rate * x])).simplify
      end

      def cdf(x)
        x = Expression.lift(x)
        return Num.new(0) if x.is_a?(Num) && x.value.negative?
        (1 - Fn.new(:exp, [-rate * x])).simplify
      end

      def quantile(p) = (Fn.new(:log, [1 / (1 - Expression.lift(p))]) / rate).simplify
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

      # Sum of pdf over the support up to k, exactly for numeric k; else a formal sum.
      def cdf(k)
        k = Expression.lift(k)
        lo, hi = support
        if k.is_a?(Num) && k.value.real?
          return Num.new(0) if k.value < lo.value
          return Num.new(1) if hi.is_a?(Num) && k.value >= hi.value
          top = k.value.floor
          return (lo.value.to_i..top).map { |j| pdf(j) }.reduce(:+).simplify
        end
        j = Var.new(:j)
        Summation.sum(pdf(j), j, lo, k)
      end

      def draw(values, random)
        u = random.rand
        k = support.first.evalf.to_i
        total = pdf(k).evalf
        while total < u
          k += 1
          total += pdf(k).evalf
        end
        k
      end
    end

    class Bernoulli < Discrete
      def validate = probability_in(p, "the probability")
      def p = params[0]
      def support = [Num.new(0), Num.new(1)]

      def pdf(k)
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

      def pdf(k)
        k = Expression.lift(k)
        return Num.new(0) if k.is_a?(Num) && n.is_a?(Num) && (k.value.negative? || k.value > n.value || !k.value.integer?)
        (RCAS.binomial(n, k) * p**k * (1 - p)**(n - k)).simplify
      end

      def mean = (n * p).simplify
      def variance = (n * p * (1 - p)).simplify
      def skewness = ((1 - 2 * p) / RCAS.sqrt(n * p * (1 - p))).simplify
      def kurtosis = (3 + (1 - 6 * p * (1 - p)) / (n * p * (1 - p))).simplify
    end

    class Poisson < Discrete
      def validate = positive(rate, "the rate")
      def rate = params[0]
      def support = [Num.new(0), OO]

      def pdf(k)
        k = Expression.lift(k)
        return Num.new(0) if k.is_a?(Num) && (k.value.negative? || !k.value.integer?)
        (Fn.new(:exp, [-rate]) * rate**k / RCAS.factorial(k)).simplify
      end

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

      def pdf(k)
        k = Expression.lift(k)
        return Num.new(0) if k.is_a?(Num) && (k.value.negative? || !k.value.integer?)
        ((1 - p)**k * p).simplify
      end

      def cdf(k)
        k = Expression.lift(k)
        return super if k.is_a?(Num)
        (1 - (1 - p)**(k + 1)).simplify
      end

      def mean = ((1 - p) / p).simplify
      def variance = ((1 - p) / p**2).simplify
      def skewness = ((2 - p) / RCAS.sqrt(1 - p)).simplify
      def kurtosis = (9 + p**2 / (1 - p)).simplify
    end

# ---- sampling helpers ------------------------------------------------------------

module_function

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
    v = numeric(nu, "cdf")
    t = numeric(x, "cdf")
    tail = Special.beta_i(v / (v + t * t), v / 2.0, 0.5) / 2.0
    Num.new(t.negative? ? tail : 1.0 - tail)
  end

  def mean = Num.new(0)          # nu > 1
  def median = Num.new(0)
  def variance = (nu / (nu - 2)).simplify   # nu > 2
  def skewness = Num.new(0)      # nu > 3
  def kurtosis = (3 + 6 / (nu - 4)).simplify # nu > 4
  def numeric_bracket = [-1.0e4, 1.0e4]
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
    if k.is_a?(Num) && k.value.is_a?(Integer) && k.value.even? && k.value.positive?
      j = Var.new(:j)
      half = (x / 2).simplify
      tail = (0...k.value / 2).map { |m| half**m / RCAS.factorial(m) }.reduce(:+)
      return (1 - Fn.new(:exp, [-half]) * tail).simplify
    end
    Num.new(Special.gamma_p(numeric(k, "cdf") / 2.0, numeric(x, "cdf") / 2.0))
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

  def mean = (d2 / (d2 - 2)).simplify # d2 > 2
  def variance = (2 * d2**2 * (d1 + d2 - 2) / (d1 * (d2 - 2)**2 * (d2 - 4))).simplify # d2 > 4
  def numeric_bracket = [0.0, 1.0e6]

  def draw(values, random)
    a, b = values
    (2.0 * Distributions.gamma_variate(a / 2.0, random) / a) / (2.0 * Distributions.gamma_variate(b / 2.0, random) / b)
  end
end

    class DiscreteUniform < Discrete
      def validate
        return unless a.is_a?(Num) && b.is_a?(Num) && a.value.real? && b.value.real?
        raise ArgumentError, "DiscreteUniform: the range is empty (#{a} to #{b})" unless a.value <= b.value
      end
      def a = params[0]
      def b = params[1]
      def support = [a, b]
      def count = (b - a + 1).simplify

      def pdf(k)
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
