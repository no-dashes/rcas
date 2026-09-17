# frozen_string_literal: true

module RCAS
  # A bare name that may become an indeterminate: a Ruby local/method name
  # that does not start with an uppercase ASCII letter. Ruby treats every
  # non-ASCII character as an identifier character, so α, β₁ and ∞ qualify.
  IDENTIFIER = /\A(?:[a-z_]|[^\x00-\x7F])(?:[a-zA-Z0-9_]|[^\x00-\x7F])*\z/

  # Elementary functions. Available as RCAS.sin(:x) or, after
  # `include RCAS::Functions`, as bare sin(:x).
  module Functions
    NAMES = %i[sin cos tan exp log atan asin acos sinh cosh zeta factorial gamma abs sign erf erfc Ei Si Ci li].freeze

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

    # pi and oo (also π and ∞): the constants PI and OO under bare names
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

    # series(sin(x), x, 0, 6) or series(sin(x), x: 0, n: 6); formal: true for the general coefficient
    def series(f, x = nil, a = 0, n = 6, **opts)
      formal = opts.delete(:formal)
      x, a, n = Functions.point_arguments(x, a, n, opts, "series")
      formal ? Functions.formal_series(f, x, a) : Limits.series(f, x, a, n)
    end

    # fps(exp(x), x): the formal power series, sum(x**k/k!, k, 0, oo), coefficient and all
    def fps(f, x = nil, a = 0, **opts)
      x, a, = Functions.point_arguments(x, a, nil, opts, "fps")
      Functions.formal_series(f, x, a)
    end

    # fourier(x, x: -pi..pi, n: 4): the Fourier partial sum; formal: true gives
    # the general coefficient, kind: :sine or :cosine the half-range expansion
    def fourier(f, x = nil, from = nil, to = nil, **opts)
      n = opts.delete(:n) || Fourier::DEFAULT_TERMS
      kind = opts.delete(:kind) || :full
      formal = opts.delete(:formal) || false
      index = opts.delete(:k)
      x, from, to = Functions.range_arguments(x, from, to, opts, "fourier", discrete: false)
      Fourier.series(f, x, from, to, n: n, kind: kind, formal: formal, index: index)
    end

    # taylor(exp(x), x, 0, 5): the series without the O term
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

    # The formal power series, or the reason there is none: the truncated
    # expansion stays available, and saying so is more use than a bare nil.
    def self.formal_series(f, x, a)
      FPS.expansion(f, x, a) ||
        raise(SeriesError, "no formal power series for #{Expression.lift(f)}: " \
                           "its coefficients are not hypergeometric, or the equation for it is too long. " \
                           "series(f, #{x}) gives the expansion up to an order.")
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

    # boxplot("a" => xs, width: 40): Ruby hands both over as keywords, so the
    # named series and the plot options have to be told apart here.
    PLOT_OPTIONS = %i[title label labels x y bins density fit width height].freeze

    def self.split_plot_options(opts)
      [opts.select { |k, _| PLOT_OPTIONS.include?(k) }, opts.reject { |k, _| PLOT_OPTIONS.include?(k) }]
    end

    # One definite integral per range, innermost first.
    def self.iterated_integral(expr, ranges)
      ranges.reduce(Expression.lift(expr)) do |acc, (name, r)|
        var, from, to = range_arguments(nil, nil, nil, { name => r }, "integrate", discrete: false)
        Integrate.definite(acc, Expression.lift(var), from, to)
      end
    end

    # The ranges of an integral over a region, in the order they were given,
    # which is the order they are integrated in: the first one innermost.
    def self.range_list(ranges, count, name)
      wanted = count.is_a?(Range) ? count : (count..count)
      unless wanted.cover?(ranges.size)
        example = name == "green" ? "#{name}(f, x: 0..1, y: 0..1)" : "#{name}(f, s, u: 0..1, v: 0..1)"
        raise ArgumentError, "#{name}: give #{wanted.to_a.join(' or ')} ranges, e.g. #{example}"
      end
      ranges.map { |k, r| range_arguments(nil, nil, nil, { k => r }, name, discrete: false) }
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
    # evalf(pi), evalf(sqrt(2)*x, x: 3): the numeric value as a Float;
    # evalf(pi, 50) or evalf(pi, digits: 50) for as many digits as you like
    def evalf(f, digits = nil, **bindings) = Expression.lift(f).evalf(digits, **bindings)

    # congruence(3*x - 4, x, 7) solves modulo 7; legendre(a, p), jacobi(a, n), order(a, m),
    # primitive_root(m), continued_fraction(x, n), convergents(x, n)
    def congruence(f, x, m) = NumberTheory.congruence(f, x, m)
    def legendre(a, p) = NumberTheory.legendre(a, p)
    def jacobi(a, n) = NumberTheory.jacobi(a, n)
    def order(a, m) = NumberTheory.order(a, m)
    def primitive_root(m) = NumberTheory.primitive_root(m)
    def continued_fraction(x, terms = 10) = NumberTheory.continued_fraction(x, terms)
    def convergents(x, terms = 10) = NumberTheory.convergents(x, terms)

    # laplace(exp(3*t), t, s) and inverse_laplace(1/(s - 3), s, t): the transform
    # that turns differentiation into multiplication by s
    def laplace(f, t = :t, s = :s) = Laplace.transform(f, t, s)
    def inverse_laplace(f, s = :s, t = :t) = Laplace.inverse(f, s, t)

    # gram_schmidt(vectors, normalize: false), least_squares(A, b), project(v, onto: u),
    # orthogonal?(u, v): orthogonality and the normal equations
    def gram_schmidt(vectors, normalize: false) = LinearAlgebra.gram_schmidt(vectors, normalize: normalize)
    def least_squares(matrix, target) = LinearAlgebra.least_squares(matrix, target)
    def project(v, onto:) = LinearAlgebra.project(v, onto: onto)
    def orthogonal?(u, v) = LinearAlgebra.orthogonal?(u, v)

    # lu(a) gives [l, u, p] with p*a = l*u; qr(a) gives [q, r] with a = q*r
    def lu(matrix) = Decompositions.lu(matrix)
    def qr(matrix) = Decompositions.qr(matrix)
    # cholesky(a) is the l with a = l*l.transpose, for a symmetric positive definite a
    def cholesky(matrix) = Decompositions.cholesky(matrix)
    # diagonalize(a) gives [p, d] and jordan(a) gives [p, j] with a = p*d*p**-1
    def diagonalize(matrix) = Decompositions.diagonalize(matrix)
    def jordan(matrix) = Decompositions.jordan(matrix)

    # point(0, 0), line(p, q) or line(p, slope: 2), circle(centre, r): plane geometry
    def point(x, y = nil) = Geometry.point(x, y)
    def line(first, second = nil, slope: nil) = Geometry.line(first, second, slope: slope)
    def circle(centre, radius) = Geometry.circle(centre, radius)
    # distance(a, b) between points, a point and a line or parallel lines; midpoint, angle(a, b, c),
    # area(a, b, c), perimeter, collinear?, centroid, intersect(a, b), circumcircle(a, b, c),
    # perpendicular_bisector(p, q), parallel_through(l, p), perpendicular_through(l, p)
    def distance(a, b) = Geometry.distance(a, b)
    def midpoint(p, q) = Geometry.midpoint(p, q)
    def angle(a, b, c = nil) = b.is_a?(Geometry::Line) ? Geometry.line_angle(a, b) : Geometry.angle(a, b, c)
    def area(a, b = nil, c = nil) = Geometry.area(a, b, c)
    def perimeter(a, b = nil, c = nil) = Geometry.perimeter(a, b, c)
    def collinear?(a, b, c) = Geometry.collinear?(a, b, c)
    def centroid(*points) = Geometry.centroid(*points)
    def intersect(a, b) = Geometry.intersect(a, b)
    def circumcircle(a, b, c) = Geometry.circumcircle(a, b, c)
    def perpendicular_bisector(p, q) = Geometry.perpendicular_bisector(p, q)
    def parallel_through(l, p) = Geometry.parallel_through(l, p)
    def perpendicular_through(l, p) = Geometry.perpendicular_through(l, p)

    # critical_points(f, x), extrema(f, x) => [[x, f(x), :minimum|:maximum|:saddle], ...],
    # inflections(f, x), asymptotes(f, x), tangent(f, x, a), normal(f, x, a), real_domain(f, x)
    def critical_points(f, var = nil) = Analysis.critical_points(f, var)
    def extrema(f, var = nil) = Analysis.extrema(f, var)
    def inflections(f, var = nil) = Analysis.inflections(f, var)
    def asymptotes(f, var = nil, at: nil) = Analysis.asymptotes(f, var, at: at)
    def tangent(f, var = nil, at = nil) = Analysis.tangent(f, var, at)
    def normal(f, var = nil, at = nil) = Analysis.normal(f, var, at)
    def real_domain(f, var = nil) = Analysis.real_domain(f, var)

    # discuss(f, x): the whole curve discussion - domain, symmetry, zeros,
    # gaps, behaviour at infinity, extrema, monotonicity, inflections, curvature
    def discuss(f, var = nil) = Discussion.discuss(f, var)

    # gradient(f, [x, y]), hessian(f, vars), jacobian([f, g], vars), divergence(field, vars),
    # curl(field, [x, y, z]), laplacian(f, vars), lagrange(f, [g], vars): several variables
    def gradient(f, vars = nil) = Analysis.gradient(f, vars)
    def hessian(f, vars = nil) = Analysis.hessian(f, vars)
    def jacobian(fs, vars = nil) = Analysis.jacobian(fs, vars)
    def divergence(field, vars = nil) = Analysis.divergence(field, vars)
    def curl(field, vars = nil) = Analysis.curl(field, vars)
    def laplacian(f, vars = nil) = Analysis.laplacian(f, vars)
    def lagrange(f, constraints, vars = nil) = Analysis.lagrange(f, constraints, vars)

    # arclength(x**2, x: 0..1) or arclength([cos(t), sin(t)], t: 0..pi): the length of a curve
    def arclength(f, var = nil, from = nil, to = nil, **range)
      var, from, to = Functions.range_arguments(var, from, to, range, "arclength", discrete: false)
      Analysis.arclength(f, var, from, to)
    end

    # revolution_volume(sqrt(x), x: 0..1): the volume swept out around the x-axis (axis: :y for the other)
    def revolution_volume(f, var = nil, from = nil, to = nil, axis: :x, **range)
      var, from, to = Functions.range_arguments(var, from, to, range, "revolution_volume", discrete: false)
      Analysis.revolution_volume(f, var, from, to, axis: axis)
    end

    # revolution_surface(sqrt(x), x: 0..1): the area of that surface of revolution
    def revolution_surface(f, var = nil, from = nil, to = nil, axis: :x, **range)
      var, from, to = Functions.range_arguments(var, from, to, range, "revolution_surface", discrete: false)
      Analysis.revolution_surface(f, var, from, to, axis: axis)
    end

    # line_integral(x*y, [cos(t), sin(t)], t: 0..pi/2): a scalar field along a curve,
    # the integral of f ds; with a vector field, line_integral([-y, x], curve, t: 0..2*pi)
    # is the integral of F.dr, the work done along it. The field is read in x, y, z
    # unless vars: names other coordinates.
    def line_integral(f, curve, var = nil, from = nil, to = nil, vars: nil, **range)
      var, from, to = Functions.range_arguments(var, from, to, range, "line_integral", discrete: false)
      VectorCalculus.line_integral(f, curve, var, from, to, vars: vars)
    end

    # surface_integral(1, [u, v, u + v], u: 0..1, v: 0..1): a scalar field over a
    # parametrized surface, the integral of f dS; a vector field is integrated
    # against the normal, F.dS, which is the flux through it
    def surface_integral(f, surface, vars: nil, **ranges)
      VectorCalculus.surface_integral(f, surface, Functions.range_list(ranges, 2, "surface_integral"), vars: vars)
    end

    # flux([x, y], [cos(t), sin(t)], t: 0..2*pi) across a plane curve (outwards when
    # it runs anticlockwise), or flux(field, surface, u: .., v: ..) through a surface
    def flux(field, boundary, vars: nil, **ranges)
      list = Functions.range_list(ranges, (1..2), "flux")
      return VectorCalculus.surface_integral(field, boundary, list, vars: vars) if list.size == 2
      VectorCalculus.curve_flux(field, boundary, *list.first, vars: vars)
    end

    # enclosed_area([cos(t)**3, sin(t)**3], t: 0..2*pi): the area a closed plane curve
    # encloses, as the line integral Green's theorem turns it into
    def enclosed_area(curve, var = nil, from = nil, to = nil, **range)
      var, from, to = Functions.range_arguments(var, from, to, range, "enclosed_area", discrete: false)
      VectorCalculus.enclosed_area(curve, var, from, to)
    end

    # green([-y, x], x: 0..1, y: 0..1): Green's theorem, the circulation of a plane
    # field around the boundary of a region as the double integral of Q_x - P_y over
    # it. The ranges describe the region, innermost first, as for integrate.
    def green(field, vars: nil, **ranges)
      VectorCalculus.green(field, Functions.range_list(ranges, 2, "green"), vars: vars)
    end

    # stokes([-y, x, 0], [u*cos(v), u*sin(v), 0], u: 0..1, v: 0..2*pi): Stokes's theorem,
    # the circulation around the edge of a surface as the flux of the curl through it
    def stokes(field, surface, vars: nil, **ranges)
      VectorCalculus.stokes(field, surface, Functions.range_list(ranges, 2, "stokes"), vars: vars)
    end

    # divergence_theorem([x, y, z], x: 0..1, y: 0..1, z: 0..1): Gauss's theorem, the flux
    # out of the boundary of a solid as the triple integral of the divergence over it
    def divergence_theorem(field, vars: nil, **ranges)
      VectorCalculus.divergence_theorem(field, Functions.range_list(ranges, 3, "divergence_theorem"), vars: vars)
    end

    # conservative?([2*x*y, x**2]) asks whether a field is a gradient; potential(field)
    # is the function it is the gradient of, up to a constant
    def conservative?(field, vars = nil) = VectorCalculus.conservative?(field, vars)
    def potential(field, vars = nil) = VectorCalculus.potential(field, vars)

    # nsolve(cos(x) - x, x: 0..1) or nsolve(f, x, guess): a root as a Float when no formula applies
    def nsolve(f, var = nil, guess = nil, **range) = Numerics.nsolve(f, var, guess, **range)
    # nintegrate(sin(x)/x, x: 0..1): a definite integral as a Float, infinite bounds included
    def nintegrate(f, var = nil, from = nil, to = nil, **range) = Numerics.nintegrate(f, var, from, to, **range)

    # integrate(x**2 * exp(x), x); definite: integrate(x**2, x, 0, 1) or integrate(x**2, x: 0..1);
    # iterated: integrate(x*y, x: 0..1, y: 0..2) integrates over x first
    def integrate(expr, var = nil, from = nil, to = nil, **range)
      return Functions.iterated_integral(expr, range) if range.size > 1
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

    # discriminant(x**2 + b*x + c, x): the discriminant of a polynomial
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

    # The working, not only the answer: steps { diff(x**2*sin(x), x) },
    # steps(x**2 - 5*x + 6, :solve), steps(m, :rref)
    def steps(*args, &block) = Steps.of(*args, &block)
    def evaluate(expr) = Expression.lift(expr).evaluate
    alias doit evaluate

    # interval(0, 1) is [0, 1]; interval(0, 1, right_open: true) is [0, 1)
    def interval(low, high, **open) = Interval.new(low, high, **open)

    # A function defined case by case: piecewise(x < 0 => -x, :else => x**2)
    def piecewise(*branches, **rest) = Piecewises.build(*branches, **rest)

    # The points where f jumps: discontinuities(piecewise(x < 0 => 0, :else => 1))
    def discontinuities(f, var = nil) = Piecewises.discontinuities(Expression.lift(f), var)

    # The corners of f: points where it is continuous but the one-sided derivatives differ.
    def kinks(f, var = nil) = Piecewises.kinks(Expression.lift(f), var)

    # eq(x**2, 4) builds an equation; solve(eq(x**2, 4), x) solves it.
    def eq(lhs, rhs) = Equation.new(lhs, rhs)
    def solve(target, vars = nil, all: false) = Solve.solve(target, vars, all: all)

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

    # qpochhammer(a, q, n): (a; q)_n = (1 - a)(1 - a*q)...(1 - a*q**(n - 1))
    def qpochhammer(a, q, n) = QFunctions.qpochhammer(a, q, n)
    # qbracket(n, q): [n]_q = 1 + q + ... + q**(n - 1), the q-analogue of n
    def qbracket(n, q) = QFunctions.qbracket(n, q)
    # qfactorial(n, q): [n]_q! = [1]_q*[2]_q*...*[n]_q
    def qfactorial(n, q) = QFunctions.qfactorial(n, q)
    # qbinomial(n, k, q): the Gaussian binomial coefficient, a polynomial in q
    def qbinomial(n, k, q) = QFunctions.qbinomial(n, k, q)

    # qgosper(q**k, q, k): the q-antidifference S with S(k + 1) - S(k) = f(k), or nil
    def qgosper(term, q, k) = QSummation.qgosper(term, Expression.lift(k), Expression.lift(q))

    # qsum(q**k, q, k: 0..n-1): a definite q-hypergeometric sum, or the sum unevaluated
    def qsum(term, q, k = nil, from = nil, to = nil, **range)
      k, from, to = Functions.range_arguments(k, from, to, range, "qsum", discrete: true)
      k = Expression.lift(k)
      from = Expression.lift(from)
      to = Expression.lift(to)
      QSummation.qsum(term, k, from, to, Expression.lift(q)) || Sum.new(Expression.lift(term), k, from, to)
    end

    # sumrecursion(binomial(n, k)**2, k, S(n)): the recurrence a definite sum obeys (Zeilberger)
    def sumrecursion(term, k, s, **opts) = Zeilberger.sumrecursion(term, k, s, **opts)

    # sumcertificate(binomial(n, k)**2, k, S(n)): the rational certificate that proves it
    def sumcertificate(term, k, s, **opts) = Zeilberger.sumcertificate(term, k, s, **opts)

    # qsumrecursion(qbinomial(n, k, q), k, q, S(n)): the recurrence a definite q-sum obeys
    def qsumrecursion(term, k, q, s, **opts) = QZeilberger.qsumrecursion(term, k, q, s, **opts)

    # qsumcertificate(qbinomial(n, k, q), k, q, S(n)): the certificate that proves it
    def qsumcertificate(term, k, q, s, **opts) = QZeilberger.qsumcertificate(term, k, q, s, **opts)

    # qsolve(eq(f(q*x), (1 - a*x)*f(x)), f, x, q): a linear q-difference equation, at x = q**n
    def qsolve(equation, f, x, q, **opts) = QDifference.qsolve(equation, f, x, q, **opts)

    # qhyper(eq(f(q*x), (1 - a*x)*f(x)), f, x, q): the ratios f(q*x)/f(x) of its solutions
    def qhyper(equation, f, x, q) = QDifference.qhyper(equation, f, x, q)

    # hyper(eq(u(n + 1), n*u(n)), u, n): the hypergeometric solutions of a recurrence
    def hyper(equation, u, n) = Recurrence.hyper(equation, u, n)

    # doc(:factor), doc("ZZ"), doc(:Matrix): what a name does, from the source
    def doc(name) = Docs.doc(name)

    # plot(sin(x)), plot(f, x: -3..3), plot([f, g], x: 0..1), plot(Normal(0, 1)): a Plot,
    # shown as braille art; .show for a picture, .save("f.svg"), .to_svg, .to_png
    def plot(f, var = nil, from = nil, to = nil, **opts) = Plotting.plot(f, var, from, to, **opts)
    # scatter(xs, ys) or scatter(points), fit: true adds the least squares line
    def scatter(xs, ys = nil, **opts) = Plotting.scatter(xs, ys, **opts)

    # parametric([cos(t), sin(t)], t: 0..2*pi): a curve given by its two components
    def parametric(pair, var = nil, from = nil, to = nil, **opts) = Plotting.parametric(pair, var, from, to, **opts)

    # polar(1 + cos(t), t: 0..2*pi): a curve in polar coordinates
    def polar(r, var = nil, from = nil, to = nil, **opts) = Plotting.polar(r, var, from, to, **opts)
    # histogram(data, bins: 8), boxplot(data) or boxplot("a" => xs, "b" => ys), barchart(frequencies(data))
    def histogram(data, **opts) = Plotting.histogram(data, **opts)
    def boxplot(data = nil, **opts)
      options, series = Functions.split_plot_options(opts)
      Plotting.boxplot(data || series, **options)
    end

    # barchart(frequencies(data)) or barchart(names, counts): one bar per category
    def barchart(categories = nil, counts = nil, **opts)
      options, series = Functions.split_plot_options(opts)
      Plotting.barchart(categories || series, counts, **options)
    end

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
    # dsolve(eq, y, x); a system: dsolve([eq(D(x, t), y), eq(D(y, t), -x)], [x, y], t)
    def dsolve(equation, y, x) = ODE.dsolve(equation, y, x)

    # assume(x: ZZ, y: RR) declares variable domains; assumptions lists them.
    # assume(x: ZZ) declares a domain, assume(x > 0) a sign; assumptions lists both
    def assume(*facts, **table) = RCAS.assume(*facts, **table)
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

    ODD = %i[sin tan atan asin sinh sign erf Si].freeze
    EVEN = %i[cos cosh abs].freeze

    # Constant folding for function applications; called by Simplify.
    def self.fold(fn)
      if QFunctions::NAMES.include?(fn.name)
        folded = QFunctions.fold(fn)
        return folded if folded
      end
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
        if (n = Trig.integer_pi_multiple(arg))
          return name == :cos ? Pow.new(Num.new(-1), n) : Num.new(0)
        end
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
        return arg if RCAS.nonnegative?(arg)
        return Simplify.negate(arg).simplify if %i[negative nonpositive].include?(RCAS.sign_of(arg))
        d = arg.domain
        d && d <= NN ? arg : nil
      when *IntegralFunctions::NAMES
        IntegralFunctions.value(name, arg)
      when :sign
        return Num.new(arg.value <=> 0) if arg.is_a?(Num) && arg.value.real?
        case RCAS.sign_of(arg)
        when :positive then Num.new(1)
        when :negative then Num.new(-1)
        end
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
