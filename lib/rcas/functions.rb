# frozen_string_literal: true

module RCAS
  # A bare name that may become an indeterminate: a Ruby local/method name
  # that does not start with an uppercase ASCII letter. Ruby treats every
  # non-ASCII character as an identifier character, so α, β₁ and ∞ qualify.
  IDENTIFIER = /\A(?:[a-z_]|[^\x00-\x7F])(?:[a-zA-Z0-9_]|[^\x00-\x7F])*\z/

  # Elementary functions. Available as RCAS.sin(:x) or, after
  # `include RCAS::Functions`, as bare sin(:x).
  module Functions
    NAMES = %i[sin cos tan exp log atan asin acos sinh cosh zeta factorial gamma abs sign erf erfc].freeze

    # Symbolic arguments build an Fn node; constant arguments fold right
    # away, the way Ruby folds 1 + 2: sin(PI/6) is 1/2, sin(x) stays sin(x).
    NAMES.each do |name|
      define_method(name) do |arg|
        fn = Fn.new(name, [arg])
        fn.args.first.variables.empty? ? Functions.fold(fn) : fn
      end
    end

    # sqrt(8) is 2*sqrt(2); sqrt(-4) is 2*i; sqrt(x) stays sqrt(x)
    def sqrt(arg)
      root = Expression.lift(arg)**Rational(1, 2)
      root.variables.empty? ? root.simplify : root
    end

    def pi = PI
    def oo = OO
    def π = PI
    def ∞ = OO

    # root(2, 3) is the exact cube root; Ruby would turn 2**(1/3r) into a float.
    def root(x, n)
      r = Expression.lift(x)**Rational(1, n)
      r.variables.empty? ? r.simplify : r
    end

    # cbrt(8) is 2; cbrt(2) stays 2**(1/3)
    def cbrt(x) = root(x, 3)

    # binomial(5, 2) is 10; binomial(n, 2) stays symbolic (expand it with expand)
    def binomial(n, k) = Functions.fold(Fn.new(:binomial, [n, k]))

    # GF(7), GF(8), GF(9, :b), GF(3, 4): finite fields
    def GF(q, gen_or_n = :a, n = nil)
      gen_or_n.is_a?(Integer) ? FiniteField.of(q, :a, gen_or_n) : FiniteField.of(q, gen_or_n, n)
    end

    # series(sin(x), x, 0, 6) or series(sin(x), x: 0, n: 6); taylor likewise
    def series(f, x = nil, a = 0, n = 6, **opts)
      x, a, n = Functions.point_arguments(x, a, n, opts, "series")
      Limits.series(f, x, a, n)
    end

    def taylor(f, x = nil, a = 0, n = 6, **opts)
      x, a, n = Functions.point_arguments(x, a, n, opts, "taylor")
      Limits.taylor(f, x, a, n)
    end

    # limit(sin(x)/x, x, 0) or limit(sin(x)/x, x: 0, dir: :right); oo for infinity
    def limit(f, x = nil, a = nil, dir = nil, **opts)
      dir = opts.delete(:dir) || dir
      x, a, = Functions.point_arguments(x, a, nil, opts, "limit")
      Limits.limit(f, x, a, dir)
    end

    # product(k, k, 1, n) or product(k, k: 1..n): n!; closed forms through factorials and gamma
    def product(f, k = nil, from = nil, to = nil, **range)
      k, from, to = Functions.range_arguments(k, from, to, range, "product", discrete: true)
      Products.product(f, k, from, to)
    end

    # sum(k**2, k, 1, n) or sum(k**2, k: 1..n); an endless range means infinity
    def sum(f, k = nil, from = nil, to = nil, **range)
      k, from, to = Functions.range_arguments(k, from, to, range, "sum", discrete: true)
      Summation.sum(f, k, from, to)
    end

    def self.point_arguments(x, a, n, opts, name)
      n = opts.delete(:n) || n
      unless opts.empty?
        raise ArgumentError, "#{name}: give one variable, e.g. #{name}(f, x: 0)" unless opts.size == 1 && x.nil?
        x, a = opts.first
      end
      raise ArgumentError, "#{name}: which variable?" if x.nil?
      [x, infinity(a), n]
    end

    def self.range_arguments(k, from, to, range, name, discrete:)
      unless range.empty?
        raise ArgumentError, "#{name}: give one variable, e.g. #{name}(f, k: 1..n)" unless range.size == 1 && k.nil?
        k, r = range.first
        raise ArgumentError, "#{name}: expected a range, got #{r.inspect}" unless r.is_a?(Range)
        raise ArgumentError, "#{name}: the range needs a start" if r.begin.nil?
        from = r.begin
        to = r.end
        to = Expression.lift(to) - 1 if discrete && r.exclude_end? && !to.nil?
      end
      raise ArgumentError, "#{name}: which variable?" if k.nil?
      [k, infinity(from), infinity(to.nil? ? OO : to)]
    end

    def self.infinity(v)
      return v unless v.is_a?(Float) && v.infinite?
      v.positive? ? OO : Neg.new(OO)
    end

    # factor(x**2 - 1), factor(360), factor(f, extension: sqrt(2))
    def factor(obj, extension: nil)
      value = obj.is_a?(Num) ? obj.value : obj
      return NumberTheory.factor(value) if value.is_a?(Integer) || value.is_a?(Rational)
      obj.is_a?(Polynomial) ? obj.factor(extension: extension) : Expression.lift(obj).factor(extension: extension)
    end
    # minpoly(sqrt(2) + 1, x): the minimal polynomial of an algebraic number
    def minpoly(expr, var = :x) = Expression.lift(expr).minpoly(var)

    # diff(f, x) or diff(f, x, 2): derivatives
    def diff(f, x, n = 1) = Expression.lift(f).diff(x, n)
    # subs(f, x => 2), subs(f, x: 2) or subs(f, x**2, z): substitution
    def subs(f, pattern, replacement = nil) = Expression.lift(f).subs(pattern, replacement)
    # evalf(pi), evalf(sqrt(2)*x, x: 3): the numeric value as a Float
    def evalf(f, **bindings) = Expression.lift(f).evalf(**bindings)

    # integrate(x**2 * exp(x), x); definite: integrate(x**2, x, 0, 1) or integrate(x**2, x: 0..1)
    def integrate(expr, var = nil, from = nil, to = nil, **range)
      var, from, to = Functions.range_arguments(var, from, to, range, "integrate", discrete: false) if var.nil? || from
      from.nil? ? Integrate.integrate(expr, var) : Integrate.definite(expr, var, from, to)
    end

    # polynomial structure: degree(f, x), lcoeff(f, x), coeff(f, x, 2), collect(f, x)
    def degree(f, x = nil) = Coefficients.degree(f, x)
    def ldegree(f, x = nil) = Coefficients.ldegree(f, x)
    def lcoeff(f, x = nil) = Coefficients.lcoeff(f, x)
    def tcoeff(f, x = nil) = Coefficients.tcoeff(f, x)
    # coeff(f, x, k) or coeff(f, x**k): the coefficient of x**k
    def coeff(f, x, k = 1) = Coefficients.coeff(f, x, k)
    # coeffs(f, x): coefficients of x**0 .. x**degree; coeffs(f): of every term
    def coeffs(f, x = nil) = Coefficients.coeffs(f, x)
    # collect(f, x): f as a sum of coefficient * x**k
    def collect(f, x) = Coefficients.collect(f, x)

    # simplify(f), expand(f), cancel(f), rationalize(f): the methods as functions
    def simplify(f) = Expression.lift(f).simplify
    def expand(f) = Expression.lift(f).expand
    def cancel(f) = Expression.lift(f).cancel
    def rationalize(f) = Expression.lift(f).rationalize

    # resultant(f, g, x), discriminant(f, x): via the Sylvester matrix; other symbols are parameters
    def resultant(f, g, x = nil)
      _, (pf, pg) = Groebner.lift([f, g], x && [x])
      pf.resultant(pg, x && Expression.lift(x).name).to_expr
    end

    def discriminant(f, x = nil)
      pf = Groebner.lift([f], x && [x]).last.first
      pf.discriminant(x && Expression.lift(x).name).to_expr
    end

    # interpolate([[0, 1], [1, 3], [2, 7]], x): the polynomial through the points (Newton)
    def interpolate(points, x) = Interpolate.newton(points, x)

    # numer(f), denom(f): numerator and denominator of the normal form
    def numer(f) = RationalFunction.numer(f)
    def denom(f) = RationalFunction.denom(f)
    # apart(f, x): partial fractions over QQ; other indeterminates are parameters
    def apart(f, x = nil) = RationalFunction.apart(f, x)
    # gcd(f, g), lcm(f, g) of integers or polynomials
    def gcd(f, g) = RationalFunction.gcd(f, g)
    def lcm(f, g) = RationalFunction.lcm(f, g)
    # quo(f, g), rem(f, g), divmod(f, g): polynomial division; quo(f, g, x) divides by x with parameters
    def quo(f, g, x = nil) = RationalFunction.quo(f, g, x)
    def rem(f, g, x = nil) = RationalFunction.rem(f, g, x)
    def divmod(f, g, x = nil) = RationalFunction.divmod(f, g, x)

    # ifactor(360): prime factorization; factor(360) does the same
    def ifactor(n) = NumberTheory.factor(n)
    # isprime(n): Miller-Rabin, exact below 3.3e24
    def isprime(n) = NumberTheory.prime?(n)
    def nextprime(n) = NumberTheory.nextprime(n)
    def prevprime(n) = NumberTheory.prevprime(n)
    # divisors(12) => [1, 2, 3, 4, 6, 12]; totient(n) is Euler's phi
    def divisors(n) = NumberTheory.divisors(n)
    def totient(n) = NumberTheory.totient(n)
    # invmod(3, 7): inverse modulo; chrem([2, 3], [3, 5]): Chinese remainder theorem
    def invmod(a, m) = NumberTheory.invmod(a, m)
    def chrem(residues, moduli) = NumberTheory.chrem(residues, moduli)

    # trigonometric and logarithmic rewriting
    def trigsimp(expr) = Trigonometry.trigsimp(expr)
    def expand_trig(expr) = Trigonometry.expand_trig(expr)
    def expand_log(expr) = Trigonometry.expand_log(expr)
    def logcombine(expr) = Trigonometry.logcombine(expr)

    # hold { 1 + 2 } keeps the block's source as an unevaluated expression;
    # evaluate(expr) computes the formal integrals, derivatives, sums and limits in it.
    def hold(&block) = Hold.hold(block)
    def evaluate(expr) = Expression.lift(expr).evaluate
    alias doit evaluate

    # eq(x**2, 4) builds an equation; solve(eq(x**2, 4), x) solves it.
    def eq(lhs, rhs) = Equation.new(lhs, rhs)
    def solve(target, vars = nil) = Solve.solve(target, vars)

    # groebner([x**2 + y**2 - 1, x - y], [x, y]): reduced Gröbner basis; order: :lex (default), :grlex, :grevlex
    def groebner(polys, vars = nil, order: :lex) = Groebner.groebner(polys, vars, order: order)
    # reduce(f, basis, [x, y]): normal form of f modulo the basis; 0 exactly when f lies in the ideal
    def reduce(f, basis, vars = nil, order: :lex) = Groebner.normal_form(f, basis, vars, order: order)

    # rsolve(eq(u(n + 2), u(n + 1) + u(n)), u, n, init: {0 => 0, 1 => 1}): linear recurrences with constant coefficients
    def rsolve(equation, u, n, init: {}) = Recurrence.rsolve(equation, u, n, init: init)

    # re(z), im(z), conj(z), arg(z): real part, imaginary part, conjugate, argument (variables count as real once assumed so)
    def re(z) = ComplexParts.re(z)
    def im(z) = ComplexParts.im(z)
    def conj(z) = ComplexParts.conj(z)
    def arg(z) = ComplexParts.arg(z)

    # floor(7/2r), ceil(x), round(x): rounding; mod(a, m): a modulo m. Symbolic arguments stay unevaluated.
    def floor(x) = Functions.fold(Fn.new(:floor, [x]))
    def ceil(x) = Functions.fold(Fn.new(:ceil, [x]))
    def round(x) = Functions.fold(Fn.new(:round, [x]))
    def mod(a, m) = Functions.fold(Fn.new(:mod, [a, m]))

    # bernoulli(n), fibonacci(n), harmonic(n): exact values of the classical sequences
    def bernoulli(n) = Functions.fold(Fn.new(:bernoulli, [n]))
    def fibonacci(n) = Functions.fold(Fn.new(:fibonacci, [n]))
    def harmonic(n) = Functions.fold(Fn.new(:harmonic, [n]))

    # Normal(0, 1), Uniform(a, b), Exponential(l), Bernoulli(p), Binomial(n, p), Poisson(l), Geometric(p), DiscreteUniform(1, 6): distributions
    def Normal(mu = 0, sigma = 1) = Distributions::Normal.new(mu, sigma)
    def Uniform(a = 0, b = 1) = Distributions::Uniform.new(a, b)
    def Exponential(rate = 1) = Distributions::Exponential.new(rate)
    def Bernoulli(p) = Distributions::Bernoulli.new(p)
    def Binomial(n, p) = Distributions::Binomial.new(n, p)
    def Poisson(rate) = Distributions::Poisson.new(rate)
    def Geometric(p) = Distributions::Geometric.new(p)
    def DiscreteUniform(a, b) = Distributions::DiscreteUniform.new(a, b)
    # StudentT(nu), ChiSquare(k), FRatio(d1, d2): the sampling distributions of the tests
    def StudentT(nu) = Distributions::StudentT.new(nu)
    def ChiSquare(k) = Distributions::ChiSquare.new(k)
    def FRatio(d1, d2) = Distributions::FRatio.new(d1, d2)
    # pdf(X, x), cdf(X, x), probability(X, x > 1): the methods as functions
    def pdf(dist, x) = dist.pdf(x)
    def cdf(dist, x) = dist.cdf(x)
    def probability(dist, event) = dist.probability(event)

# ttest(data, mu: 0), ttest(xs, ys), ttest(xs, ys, paired: true), ztest(data, sigma: 2, mu: 0):
# tests of location; alternative: :two_sided (default), :less, :greater
def ttest(data, other = nil, **opts) = Hypothesis.ttest(data, other, **opts)
def ztest(data, sigma:, mu: 0, alternative: :two_sided) = Hypothesis.ztest(data, sigma: sigma, mu: mu, alternative: alternative)
# chisquare_test(counts, expected: nil): goodness of fit; chisquare_test(rows): independence
def chisquare_test(observed, **opts) = Hypothesis.chisquare_test(observed, **opts)
# ftest(xs, ys): the ratio of two sample variances
def ftest(xs, ys, alternative: :two_sided) = Hypothesis.ftest(xs, ys, alternative: alternative)
# binomial_test(9, 10, p: 1/2r): exact, the p value stays a rational
def binomial_test(successes, trials, p: Rational(1, 2), alternative: :two_sided) = Hypothesis.binomial_test(successes, trials, p: p, alternative: alternative)
# confidence_interval(data, level: 0.95, sigma: nil, parameter: :mean|:variance|:stdev), proportion_interval(k, n)
def confidence_interval(data, **opts) = Hypothesis.confidence_interval(data, **opts)
def proportion_interval(successes, trials, level: 0.95) = Hypothesis.proportion_interval(successes, trials, level: level)

    # mean(data), median, mode, variance(data, sample: true), stdev, quantile(data, p), quartiles, iqr,
    # moment(data, k), skewness, kurtosis, geometric_mean, harmonic_mean, frequencies: on a list or a distribution
    def mean(obj) = obj.is_a?(Distributions::Distribution) ? obj.mean : Statistics.mean(obj)
    def median(obj) = obj.is_a?(Distributions::Distribution) ? obj.median : Statistics.median(obj)
    def mode(data) = Statistics.mode(data)
    def variance(obj, sample: true) = obj.is_a?(Distributions::Distribution) ? obj.variance : Statistics.variance(obj, sample: sample)
    def stdev(obj, sample: true) = obj.is_a?(Distributions::Distribution) ? obj.stdev : Statistics.stdev(obj, sample: sample)
    def quantile(obj, p) = obj.is_a?(Distributions::Distribution) ? obj.quantile(p) : Statistics.quantile(obj, p)
    def quartiles(data) = Statistics.quartiles(data)
    def iqr(data) = Statistics.iqr(data)
    def moment(obj, k, central: true) = obj.is_a?(Distributions::Distribution) ? obj.moment(k) : Statistics.moment(obj, k, central: central)
    def skewness(obj) = obj.is_a?(Distributions::Distribution) ? obj.skewness : Statistics.skewness(obj)
    def kurtosis(obj) = obj.is_a?(Distributions::Distribution) ? obj.kurtosis : Statistics.kurtosis(obj)
    def geometric_mean(data) = Statistics.geometric_mean(data)
    def harmonic_mean(data) = Statistics.harmonic_mean(data)
    def frequencies(data) = Statistics.frequencies(data)
    # covariance(xs, ys), correlation(xs, ys), linreg(xs, ys, x): two data lists; linreg is the least squares line a + b*x
    def covariance(xs, ys, sample: true) = Statistics.covariance(xs, ys, sample: sample)
    def correlation(xs, ys) = Statistics.correlation(xs, ys)
    def linreg(xs, ys, x = :x) = Statistics.linreg(xs, ys, x)

    # D(y, x) is the derivative of the unknown function y; dsolve solves ODEs.
    def D(expr, var, order = 1) = Derivative.new(expr, var, order)
    def dsolve(equation, y, x) = ODE.dsolve(equation, y, x)

    # assume(x: ZZ, y: RR) declares variable domains; assumptions lists them.
    def assume(table) = RCAS.assume(table)
    def forget(*names) = RCAS.forget(*names)
    def assumptions = RCAS.assumptions

    # vector(QQ, 1, 2, 3), vector(1, 2, 3) or vector([1, 2, 3]) with the domain inferred.
    def vector(*args)
      domain = args.first.is_a?(Domain) ? args.shift : nil
      args = args.first if args.size == 1 && args.first.is_a?(Array)
      domain ||= Functions.infer_domain(args)
      domain.vector(*args)
    end

    # matrix(QQ, [[1, 2], [3, 4]]) or matrix([[1, 2], [3, 4]]) with the domain inferred.
    def matrix(*args)
      domain = args.first.is_a?(Domain) ? args.shift : Functions.infer_domain(args.flatten)
      rows = args.size == 1 ? args.first : args
      domain.matrix(rows)
    end

    def self.infer_domain(entries)
      entries.reduce(ZZ) do |d, e|
        ed = Scalar.domain(Expression.lift(e))
        raise DomainError, "can't infer a domain for #{e}; pass one explicitly or declare its variables" unless ed
        d.join(ed)
      end
    end

    ODD = %i[sin tan atan asin sinh sign erf].freeze
    EVEN = %i[cos cosh abs].freeze

    # Constant folding for function applications; called by Simplify.
    def self.fold(fn)
      if fn.name == :binomial && fn.args.size == 2
        n, k = fn.args
        return Combinatorics.binomial_value(n, k) || fn
      end
      if fn.name == :mod && fn.args.size == 2
        a, m = fn.args
        return fn unless a.is_a?(Num) && m.is_a?(Num) && a.value.real? && m.value.real? && !m.value.zero?
        return Num.new(Simplify.normalize_number(a.value % m.value))
      end
      return fn unless fn.args.size == 1
      arg = fn.args.first

      # odd / even symmetry: sin(-u) = -sin(u), cos(-u) = cos(u)
      if (ODD.include?(fn.name) || EVEN.include?(fn.name)) && !arg.is_a?(Num)
        coeff, factors = Simplify.factorize(arg)
        negative = Simplify.negative?(coeff)
        if !negative && (pair = factors.find { |b, e| e == 1 && Simplify.negative_sum?(b) })
          factors = factors.dup
          factors.delete(pair.first)
          factors[Simplify.simplify(Neg.new(pair.first))] = 1
          negative = true
        end
        if negative
          flipped = Fn.new(fn.name, [Simplify.rebuild_product(Simplify.negative?(coeff) ? -coeff : coeff, factors)])
          return ODD.include?(fn.name) ? Neg.new(fold(flipped)) : fold(flipped)
        end
      end

      exact = exact_value(fn.name, arg)
      return exact if exact

      case [fn.name, arg]
      in [_, Num => n] if n.value.is_a?(Float) && Math.respond_to?(fn.name) then Num.new(Math.public_send(fn.name, n.value))
      in [_, Num => n] if n.value.is_a?(Complex) && (n.value.real.is_a?(Float) || n.value.imaginary.is_a?(Float)) && %i[exp sin cos].include?(fn.name)
        Num.new(CMath_lite.public_send(fn.name, n.value))
      in [:sin, Num => n] if n.zero? then Num.new(0)
      in [:cos, Num => n] if n.zero? then Num.new(1)
      in [:tan, Num => n] if n.zero? then Num.new(0)
      in [:atan, Num => n] if n.zero? then Num.new(0)
      in [:sinh, Num => n] if n.zero? then Num.new(0)
      in [:cosh, Num => n] if n.zero? then Num.new(1)
      in [:exp, Num => n] if n.zero? then Num.new(1)
      in [:log, Num => n] if n.one?  then Num.new(0)
      in [:floor, Num => n] if n.value.real? then Num.new(n.value.floor)
      in [:ceil, Num => n] if n.value.real? then Num.new(n.value.ceil)
      in [:round, Num => n] if n.value.real? then Num.new(n.value.round)
      in [:re, Num => n] then Num.new(Simplify.normalize_number(n.value.real))
      in [:im, Num => n] then Num.new(Simplify.normalize_number(n.value.imaginary))
      in [:conj, Num => n] then Num.new(Simplify.normalize_number(n.value.conj))
      in [:arg, Num => n] then ComplexParts.arg(n)
      in [:bernoulli, Num => n] if n.value.is_a?(Integer) && n.value >= 0 then Num.new(Simplify.normalize_number(Summation.bernoulli(n.value)))
      in [:fibonacci, Num => n] if n.value.is_a?(Integer) then Num.new(Combinatorics.fibonacci(n.value))
      in [:harmonic, Num => n] if n.value.is_a?(Integer) && n.value >= 0 then Num.new(Simplify.normalize_number((1..n.value).sum(0r) { |k| Rational(1, k) }))
      in [:erf, Num => n] if n.zero? then Num.new(0)
      in [:erfc, Num => n] if n.zero? then Num.new(1)
      in [:erf, Const => c] if c.name == :oo then Num.new(1)
      in [:erfc, Const => c] if c.name == :oo then Num.new(0)
      in [:erfc, Neg => e] if e.arg.is_a?(Const) && e.arg.name == :oo then Num.new(2)
      in [:exp, Fn => inner] if inner.name == :log then inner.args.first
      in [:log, Fn => inner] if inner.name == :exp then inner.args.first
      else fn
      end
    end
  end

  # Exact special values: sin(pi/6), exp(i*pi), atan(1), asin(1/2), log(8)...
  module Functions
    def self.exact_value(name, arg)
      case name
      when :sin, :cos, :tan
        r = Trig.pi_multiple(arg) or return nil
        Trig.public_send(:"#{name}_pi", r)
      when :exp
        r = Trig.imaginary_pi_multiple(arg) or return nil
        Trig.exp_i_pi(r)
      when :asin, :atan
        return nil unless arg.is_a?(Num) || arg.is_a?(Pow) || arg.is_a?(Mul) || arg.is_a?(Div)
        if arg.is_a?(Num) && arg.value.real? && arg.value.negative? # asin(-1/2) = -asin(1/2)
          v = exact_value(name, Num.new(-arg.value)) or return nil
          return Neg.new(v).simplify
        end
        name == :asin ? Trig.asin_exact(arg) : Trig.atan_exact(arg)
      when :acos
        if arg.is_a?(Num) && arg.value.real? && arg.value.negative? # acos(-v) = pi - acos(v)
          v = exact_value(:acos, Num.new(-arg.value)) or return nil
          return (PI - v).simplify
        end
        v = Trig.asin_exact(arg) or return nil
        (PI / 2 - v).simplify
      when :abs
        return Num.new(arg.value.abs) if arg.is_a?(Num)
        d = arg.domain
        d && d <= NN ? arg : nil
      when :sign
        return nil unless arg.is_a?(Num) && arg.value.real?
        Num.new(arg.value <=> 0)
      when :factorial then arg.is_a?(Num) ? Combinatorics.factorial_value(arg.value) : nil
      when :gamma then arg.is_a?(Num) ? Combinatorics.gamma_value(arg.value) : nil
      when :zeta
        return nil unless arg.is_a?(Num)
        v = arg.value
        return OO if v == 1
        return Num.new(Summation.zeta_numeric(v)) if v.is_a?(Float)
        return nil unless v.is_a?(Integer) && v > 1 && v.even?
        Summation.zeta_even(v)
      when :log
        return nil unless arg.is_a?(Num) && arg.value.is_a?(Integer) && arg.value > 1 && arg.value.bit_length <= 64
        division = Prime.prime_division(arg.value)
        k = division.map(&:last).reduce(:gcd)
        return nil if k < 2
        root = division.reduce(1) { |acc, (p, e)| acc * p**(e / k) }
        Mul.new(Num.new(k), Fn.new(:log, [Num.new(root)]))
      end
    end
  end

  # Complex-valued exp/sin/cos on floats without the deprecated CMath gem.
  module CMath_lite
    module_function

    def exp(z) = Complex(Math.exp(z.real) * Math.cos(z.imaginary), Math.exp(z.real) * Math.sin(z.imaginary))
    def sin(z) = Complex(Math.sin(z.real) * Math.cosh(z.imaginary), Math.cos(z.real) * Math.sinh(z.imaginary))
    def cos(z) = Complex(Math.cos(z.real) * Math.cosh(z.imaginary), -Math.sin(z.real) * Math.sinh(z.imaginary))
  end

  extend Functions

  # u(n + 1), f(x) in a session: an undefined name applied to expressions is
  # an unknown function (the notation rsolve uses); nil for other arguments,
  # so the caller can raise NoMethodError as usual.
  def self.unknown_function(name, args)
    return nil unless args.all? { |a| a.is_a?(Expression) || a.is_a?(Numeric) || a.is_a?(Symbol) }
    Fn.new(name, args.map { |a| Expression.lift(a) })
  end

  # Kernel's one- and two-letter printers (p, pp, and j, jj from the JSON
  # library) would otherwise capture the short names most wanted as
  # indeterminates (p for a prime!). A session's main object undefines
  # them, so the bare name reaches the auto-symbol hook like any other;
  # print with puts, print or Kernel.p(expr) instead.
  UNDEFINED_KERNEL_METHODS = %i[p pp j jj].freeze

  def self.undefine_kernel_printers(main)
    UNDEFINED_KERNEL_METHODS.each do |name|
      main.singleton_class.undef_method(name) if main.respond_to?(name, true)
    end
  end
end
