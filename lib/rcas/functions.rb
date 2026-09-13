# frozen_string_literal: true

module RCAS
  # A bare name that may become an indeterminate: a Ruby local/method name
  # that does not start with an uppercase ASCII letter. Ruby treats every
  # non-ASCII character as an identifier character, so α, β₁ and ∞ qualify.
  IDENTIFIER = /\A(?:[a-z_]|[^\x00-\x7F])(?:[a-zA-Z0-9_]|[^\x00-\x7F])*\z/

  # Elementary functions. Available as RCAS.sin(:x) or, after
  # `include RCAS::Functions`, as bare sin(:x).
  module Functions
    NAMES = %i[sin cos tan exp log atan asin acos sinh cosh zeta factorial gamma abs sign].freeze

    # Symbolic arguments build an Fn node; constant arguments fold right
    # away, the way Ruby folds 1 + 2: sin(PI/6) is 1/2, sin(x) stays sin(x).
    NAMES.each do |name|
      define_method(name) do |arg|
        fn = Fn.new(name, [arg])
        fn.args.first.variables.empty? ? Functions.fold(fn) : fn
      end
    end

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

    def cbrt(x) = root(x, 3)

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

    def factor(obj, extension: nil) = obj.is_a?(Polynomial) ? obj.factor(extension: extension) : Expression.lift(obj).factor(extension: extension)
    def minpoly(expr, var = :x) = Expression.lift(expr).minpoly(var)

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

    # D(y, x) is the derivative of the unknown function y; dsolve solves ODEs.
    def D(expr, var, order = 1) = Derivative.new(expr, var, order)
    def dsolve(equation, y, x) = ODE.dsolve(equation, y, x)

    # assume(x: ZZ, y: RR) declares variable domains; assumptions lists them.
    def assume(table) = RCAS.assume(table)
    def forget(*names) = RCAS.forget(*names)
    def assumptions = RCAS.assumptions

    # vector(QQ, 1, 2, 3) or vector(1, 2, 3) with the domain inferred.
    def vector(*args)
      domain = args.first.is_a?(Domain) ? args.shift : Functions.infer_domain(args)
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

    ODD = %i[sin tan atan asin sinh sign].freeze
    EVEN = %i[cos cosh abs].freeze

    # Constant folding for function applications; called by Simplify.
    def self.fold(fn)
      if fn.name == :binomial && fn.args.size == 2
        n, k = fn.args
        return Combinatorics.binomial_value(n, k) || fn
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
      when :asin then Trig.asin_exact(arg)
      when :acos
        v = Trig.asin_exact(arg) or return nil
        (PI / 2 - v).simplify
      when :atan then Trig.atan_exact(arg)
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
