# frozen_string_literal: true

module RCAS
  # An unevaluated integral, returned for pieces no method could integrate.
  class Integral < Expression
    attr_reader :integrand, :var, :from, :to

    def initialize(integrand, var, from = nil, to = nil)
      @integrand = integrand
      @var = var
      @from = from
      @to = to
      freeze
    end

    def definite? = !from.nil?
    def children = definite? ? [integrand, var, from, to] : [integrand, var]
    def rebuild(integrand, var, from = nil, to = nil) = Integral.new(integrand, var, from, to)
    def to_sexp = [:integral, *children.map(&:to_sexp)]
  end

  # Indefinite integration.
  #
  # 1. linearity, constant factors, a table of elementary forms with a
  #    linear argument, abs/sign of a linear argument, derivative-divides
  #    substitution, integration by parts
  # 2. rational functions exactly: Hermite reduction for the rational part,
  #    Lazard-Rioboo-Trager for the logarithmic part (log and atan terms
  #    with roots of degree <= 2 of the Rothstein-Trager resultant), and
  #    partial fractions over the real quadratic factors of a biquadratic
  #    denominator for what that leaves (1/(x**4 + 1))
  # 3. a Risch-Norman heuristic: an ansatz that is a Laurent polynomial in x
  #    and the transcendental/algebraic atoms of the integrand, plus log
  #    terms, whose undetermined coefficients are found by linear algebra
  # 4. rationalizing substitutions (integrate_substitutions.rb): square roots
  #    of quadratics, roots of linear forms and of ratios of them, exponentials, sin/cos
  #
  # Sources (keys: MANUAL.md, Sources): Hermite reduction [Her72] in Mack's
  # linear form [Mac75], [Bro05, §2.2]; Rothstein-Trager resultant [RT76],
  # [Bro05, §2.4]; Lazard-Rioboo-Trager [LR90], [Bro05, §2.5]; the whole
  # rational case also [GCL92, ch. 11]; Risch-Norman [NM77], [GS89];
  # decomposition into real quadratic factors [Har16, ch. II].
  module Integrate
    MAX_DEPTH = 8
    MAX_UNKNOWNS = 400
    ATOM_FUNCTIONS = %i[exp log sin cos sinh cosh atan asin acos].freeze
    TABLE_FUNCTIONS = %i[exp log sin cos tan sinh cosh atan].freeze

    module_function

    def integrate(expr, var)
      x = Expression.lift(var)
      raise ArgumentError, "integration variable must be a symbol" unless x.is_a?(Var)
      f = Piecewises.hoist(Expression.lift(expr).simplify)
      return Piecewises.integrate(f, x) if f.is_a?(Piecewise)
      constant, terms = Simplify.termize(f)
      parts = []
      parts << Num.new(constant) * x unless constant.zero?
      terms.each do |factors, coeff|
        term = Simplify.rebuild_product(coeff, factors)
        parts << (attempt(term, x, 0) || Integral.new(term, x))
      end
      Substitutions.unwind(parts.reduce(Num.new(0)) { |a, b| a + b }).simplify
    end

    # Definite integral from a to b: F(b) - F(a), with limits at infinite or
    # singular endpoints. Stays an Integral node when no antiderivative is found.
    def definite(expr, var, from, to)
      x = Expression.lift(var)
      f = Expression.lift(expr)
      from = Expression.lift(from)
      to = Expression.lift(to)
      f = Piecewises.hoist(f.simplify)
      return Piecewises.definite(f, x, from, to) if f.is_a?(Piecewise)
      antiderivative = integrate(f, x)
      return Integral.new(f, x, from, to) unless complete?(antiderivative)
      upper = endpoint(antiderivative, x, to, :left)
      lower = endpoint(antiderivative, x, from, :right)
      return Integral.new(f, x, from, to) if upper.nil? || lower.nil?
      (upper - lower).simplify
    end

    def endpoint(antiderivative, x, point, dir)
      unless Limits.infinite?(point)
        value = begin
          antiderivative.subs(x => point).simplify
        rescue ZeroDivisionError
          nil
        end
        return value if value && value.each_node.none? { |n| n.is_a?(Fn) && n.name == :log && n.args.first.is_a?(Num) && n.args.first.zero? }
      end
      value = Limits.limit(antiderivative, x, point, dir)
      value.is_a?(Limit) ? nil : value
    end

    # => antiderivative or nil
    def attempt(f, x, depth)
      return nil if depth > MAX_DEPTH
      f = f.simplify
      return f * x unless depends?(f, x)

      if f.is_a?(Add) || f.is_a?(Sub)
        constant, terms = Simplify.termize(f)
        total = Num.new(constant) * x
        terms.each do |factors, coeff|
          r = attempt(Simplify.rebuild_product(coeff, factors), x, depth)
          return nil if r.nil?
          total += r
        end
        return total.simplify
      end

      coeff, rest = split_constant(f, x)
      unless Scalar.one?(coeff)
        r = attempt(rest, x, depth)
        return r && (coeff * r).simplify
      end

      result = begin
        table(f, x) || IntegralFunctions.antiderivative(f, x) || piecewise(f, x, depth) || rational(f, x) || substitution(f, x, depth) ||
          by_parts(f, x, depth) || Substitutions.radical(f, x, depth) || Substitutions.gaussian(f, x) || heurisch(f, x) ||
          Substitutions.root_of_linear(f, x, depth) || Substitutions.root_of_ratio(f, x, depth) ||
          Substitutions.exponential(f, x, depth) ||
          Substitutions.trigonometric(f, x, depth) || shift(f, x, depth)
      rescue ArgumentError => e
        raise unless e.message.start_with?(NO_DERIVATIVE) # floor(x), an unknown function
        nil
      end
      result&.simplify
    end

    # Cancel with each radical held as an atom, so that for example
    # x*(1 + x/sqrt(1 + x**2))/(sqrt(1 + x**2) + x) collapses to x/sqrt(1 + x**2).
    def atom_cancel(g, x)
      roots = g.each_node.select do |n|
        n.is_a?(Pow) && n.exponent.is_a?(Num) && n.exponent.value.is_a?(Rational) &&
          !n.exponent.value.integer? && depends?(n.base, x)
      end.uniq
      return g if roots.empty?
      forward = roots.each_with_index.to_h { |r, i| [r, Var.new(:"_rad#{i}")] }
      forward.invert.then { |back| g.subs(forward).cancel.subs(back) }
    end

    # Differentiating is how the rules look for substitutions, so an integrand
    # with no derivative rule stays an unevaluated integral instead of raising.
    NO_DERIVATIVE = "don't know the derivative"

    def depends?(expr, x) = expr.variables.include?(x.name)
    def complete?(expr) = expr.each_node.none? { |n| n.is_a?(Integral) }

    # [constant factor, x-dependent factor]
    def split_constant(f, x)
      coeff, factors = Simplify.factorize(f)
      const = factors.reject { |b, e| depends?(b, x) || (e.is_a?(Expression) && depends?(e, x)) }
      return [Num.new(1), f] if const.empty? && coeff == 1
      [Simplify.rebuild_product(coeff, const), Simplify.rebuild_product(1, factors.reject { |b, _| const.key?(b) })]
    end

    # a*x + b => [a, b], else nil
    def linear(u, x)
      a = begin
        u.diff(x)
      rescue ArgumentError
        return nil
      end
      return nil if depends?(a, x) || Scalar.zero?(a)
      b = (u - a * x).simplify
      return nil if depends?(b, x)
      [a, b]
    end

    # ---- layer 1: the table -------------------------------------------------

    # f is a single factor base**exp (constants already split off).
    def table(f, x)
      coeff, factors = Simplify.factorize(f)
      return nil unless coeff == 1 && factors.size == 1
      base, exp = factors.first
      if base == Simplify.exp_base
        base = Fn.new(:exp, [Expression.lift(exp)])
        exp = 1
      end
      exp_e = Expression.lift(exp)

      if depends?(exp_e, x)
        return nil if depends?(base, x)
        ab = linear(exp_e, x) or return nil
        return Simplify.power_node(base, exp) / (ab.first * Fn.new(:log, [base]))
      end

      if base == x
        return exp == -1 ? Fn.new(:log, [x]) : x**(exp_e + 1) / (exp_e + 1)
      elsif (ab = linear(base, x))
        a = ab.first
        return exp == -1 ? Fn.new(:log, [base]) / a : base**(exp_e + 1) / ((exp_e + 1) * a)
      elsif base.is_a?(Fn) && base.args.size == 1 && TABLE_FUNCTIONS.include?(base.name) && (ab = linear(base.args.first, x))
        u = base.args.first
        a = ab.first
        if exp == 1
          case base.name
          when :exp  then base / a
          when :sin  then -Fn.new(:cos, [u]) / a
          when :cos  then Fn.new(:sin, [u]) / a
          when :tan  then -Fn.new(:log, [Fn.new(:cos, [u])]) / a
          when :log  then (u * base - u) / a
          when :atan then (u * base - Fn.new(:log, [1 + u**2]) / 2) / a
          when :sinh then Fn.new(:cosh, [u]) / a
          when :cosh then Fn.new(:sinh, [u]) / a
          end
        elsif exp == -1
          case base.name
          when :cos  then Fn.new(:log, [(1 + Fn.new(:sin, [u])) / base]) / a
          when :sin  then Fn.new(:log, [(1 - Fn.new(:cos, [u])) / base]) / a
          when :cosh then Fn.new(:atan, [Fn.new(:sinh, [u])]) / a
          when :sinh then Fn.new(:log, [(Fn.new(:cosh, [u]) - 1) / base]) / a
          end
        elsif exp == -2
          case base.name
          when :cos  then Fn.new(:tan, [u]) / a
          when :sin  then -Fn.new(:cos, [u]) / (Fn.new(:sin, [u]) * a)
          when :cosh then Fn.new(:sinh, [u]) / (Fn.new(:cosh, [u]) * a)
          when :sinh then -Fn.new(:cosh, [u]) / (Fn.new(:sinh, [u]) * a)
          end
        end
      end
    end

    # ---- layer 1: derivative-divides ------------------------------------------

    def substitution(f, x, depth)
      candidates = f.each_node.select { |n| !n.equal?(f) && !n.is_a?(Var) && !n.is_a?(Num) && depends?(n, x) }.uniq
      candidates = candidates.sort_by { |n| -n.each_node.count }.first(12)
      t = Var.new(:"_u#{depth}")
      candidates.each do |u|
        du = u.diff(x)
        next if Scalar.zero?(du)
        g = (f / du).simplify.subs(u => t).simplify
        next if depends?(g, x)
        r = attempt(g, t, depth + 1)
        return r.subs(t => u).simplify if r && complete?(r)
      end
      nil
    end

    # ---- layer 1: integration by parts ----------------------------------------

    # Functions that get simpler when differentiated, so u in u*dv.
    BY_PARTS = %i[log atan asin acos erf erfc].freeze

    def by_parts(f, x, depth)
      _, factors = Simplify.factorize(f)
      parts = factors.map { |b, e| Simplify.power_node(b, e) }
      u = parts.find { |g| g.is_a?(Fn) && BY_PARTS.include?(g.name) } ||
          parts.find { |g| g.is_a?(Pow) && g.base.is_a?(Fn) && BY_PARTS.include?(g.base.name) && g.exponent.is_a?(Num) && g.exponent.integer? && g.exponent.value.positive? }
      if u.nil?
        u = parts.find { |g| polynomial_in?(g, x) }
        rest = parts - [u]
        return nil if u.nil? || rest.size != 1
        return nil unless (g = rest.first) && ((g.is_a?(Fn) && %i[exp sin cos sinh cosh].include?(g.name)) || (g.is_a?(Pow) && !depends?(g.base, x)))
      end
      dv = Simplify.product_node(parts - [u])
      v = attempt(dv, x, depth + 1)
      return nil unless v && complete?(v) && !harder?(v, dv)
      rest = integrate_forms((u.diff(x) * v).simplify, x, depth + 1)
      return nil unless rest
      (u * v - rest).simplify
    end

    # v brings in a function dv did not have, so integrating u' * v would be a
    # step backwards (x**2*exp(-x**2): v = erf, and u'*v is the original problem).
    SPECIAL = %i[erf erfc Ei Si Ci li].freeze

    def harder?(v, dv)
      names = ->(e) { e.each_node.filter_map { |n| n.name if n.is_a?(Fn) } }
      (names.call(v) & SPECIAL).any? && (names.call(dv) & SPECIAL).empty?
    end

    # u' * v often needs a normal form before it can be integrated: a common
    # denominator for u = atan(1/x), a rationalized one for u = log(x + sqrt(x**2 + 1)).
    def integrate_forms(g, x, depth)
      seen = []
      [-> { g }, -> { g.cancel }, -> { atom_cancel(g, x) }, -> { g.rationalize.cancel }].each do |form|
        h = form.call.simplify
        next if seen.include?(h)
        seen << h
        r = attempt(h, x, depth)
        return r if r && complete?(r)
      rescue ArgumentError, DomainError, ZeroDivisionError
        next
      end
      nil
    end

    # ---- layer 1: absolute values and signs -------------------------------------

    # |u| is u*sign(u), and sign(u) is constant on each side of the root of u,
    # so it can be treated as a constant factor: with g = A(x) + B(x)*sign(u)
    # the integral is INT A + sign(u)*(F - F(x0)), F the integral of B and x0
    # the root of u. The constant makes the antiderivative continuous there,
    # which is what a definite integral across the root needs. Only a linear u
    # (one sign change, at a point we can name) is handled. [Zor15, ch. 6]
    def piecewise(f, x, depth)
      nodes = f.each_node.select { |n| n.is_a?(Fn) && %i[abs sign].include?(n.name) && depends?(n.args.first, x) }.uniq
      return nil if nodes.empty?
      u = nodes.first.args.first
      return nil unless nodes.all? { |n| n.args.first == u }
      a, b = linear(u, x)
      return nil if a.nil?

      sgn = Var.new(:"_sg#{depth}")
      g = f.subs(nodes.to_h { |n| [n, n.name == :abs ? (u * sgn) : sgn] })
      plus = g.subs(sgn => Num.new(1)).simplify
      minus = g.subs(sgn => Num.new(-1)).simplify
      even = ((plus + minus) / 2).simplify   # sign(u)**2 == 1
      odd = ((plus - minus) / 2).simplify

      total = Num.new(0)
      unless Scalar.zero?(even)
        r = attempt(even, x, depth + 1)
        return nil unless r && complete?(r)
        total += r
      end
      return total.simplify if Scalar.zero?(odd)

      r = attempt(odd, x, depth + 1)
      return nil unless r && complete?(r)
      root = (-b / a).simplify
      value = begin
        r.subs(x => root).simplify
      rescue StandardError
        return nil
      end
      return nil if value.each_node.any? { |n| n.is_a?(Num) && !n.value.finite? } || depends?(value, x)
      (total + Fn.new(:sign, [u]) * (r - value)).simplify
    end

    # Substitute x = (v - b)/a for a linear sub-expression a*x + b, so that
    # e.g. x*exp(x)/(x + 1)**2 becomes a problem in v = x + 1 alone.
    def shift(f, x, depth)
      candidates = f.each_node.select { |n| (n.is_a?(Add) || n.is_a?(Sub)) && (ab = linear(n, x)) && !Scalar.zero?(ab.last) }.uniq
      candidates.first(3).each do |u|
        a, b = linear(u, x)
        v = Var.new(:"_v#{depth}")
        g = f.subs(x => (v - b) / a).simplify
        r = attempt(g, v, depth + 1)
        return (r.subs(v => u) / a).simplify if r && complete?(r)
      end
      nil
    end

    def polynomial_in?(g, x)
      _, table = Expand.table(g)
      table.each_key.all? do |factors|
        factors.all? do |b, e|
          next false if e.is_a?(Expression) && depends?(e, x)
          depends?(b, x) ? (b == x && e.is_a?(Integer) && e >= 0) : true
        end
      end
    rescue ArgumentError
      false
    end

    # ---- layer 2: rational functions --------------------------------------------

    def rational(f, x)
      pair = as_rational(f, x) or return nil
      rational_integrate(*pair, x)
    end

    # f as num/den in QQ[x], or nil when f is not a rational function of x
    # with rational coefficients.
    def as_rational(f, x)
      ring = QQ[x.name]
      constant, table = Expand.table(f)
      return nil unless exact?(constant)
      num = ring.call(constant)
      den = ring.one
      table.each do |factors, coeff|
        return nil unless exact?(coeff)
        n = ring.call(coeff)
        d = ring.one
        factors.each do |base, exp|
          return nil unless exp.is_a?(Integer)
          poly = begin
            ring.call(base)
          rescue DomainError
            return nil
          end
          exp.positive? ? n *= poly**exp : d *= poly**(-exp)
        end
        num = num * d + n * den
        den *= d
      end
      g = num.gcd(den)
      num = num.exact_div(g)
      den = den.exact_div(g)
      lc = den.leading_coefficient
      [num * Scalar.div(Num.new(1), lc), den.monic]
    end

    def exact?(v) = v.is_a?(Integer) || v.is_a?(Rational)

    def rational_integrate(num, den, x)
      q, r = num.divmod(den)
      result = q.integrate.to_expr
      return result if r.zero?

      g, a, dstar = hermite(r, den)
      result += g
      return result.simplify if a.zero?

      q2, a = a.divmod(dstar)
      result += q2.integrate.to_expr
      return result.simplify if a.zero?

      common = a.gcd(dstar)
      a = a.exact_div(common)
      dstar = dstar.exact_div(common)
      logs = log_part(a, dstar, x) || real_log_part(a, dstar, x)
      result += logs || Integral.new((a.to_expr / dstar.to_expr).simplify, x)
      result.simplify
    end

    # ---- layer 2: real quadratic factors ----------------------------------------

    # What Lazard-Rioboo-Trager leaves when a root of the Rothstein-Trager
    # resultant has degree higher than two: split a/d into partial fractions
    # over the irreducible factors of d and integrate each one. Factors of
    # degree at most two go back to the resultant method; a biquadratic
    # x**4 + a*x**2 + b is split into the real quadratics the textbook uses,
    # (x**2 + s*x + t)(x**2 - s*x + t) with t = sqrt(b) and s = sqrt(2*t - a).
    # That is the classical decomposition into real factors [Har16, ch. II],
    # and it is what makes 1/(x**4 + 1) come out in logs and arc tangents.
    def real_log_part(a, d, x)
      pieces = partial_fractions(a, d) or return nil
      total = Num.new(0)
      pieces.each do |n, f|
        part = f.degree <= 2 ? log_part(n, f, x) : biquadratic_logs(n, f, x)
        return nil if part.nil?
        total += part
      end
      total.simplify
    end

    # a/d with d squarefree => [[numerator, irreducible factor], ...], from
    # n_i = a * (d/f_i)**(-1) mod f_i (the factors are pairwise coprime).
    def partial_fractions(a, d)
      factors = d.factor.factors.map { |f, _| f }
      return nil if factors.size < 2 && d.degree < 3
      factors.map do |f|
        rest = d.exact_div(f)
        g, s, = rest.xgcd(f)
        return nil unless g.constant?
        [((a * s) % f) * Scalar.div(Num.new(1), g.leading_coefficient), f]
      end
    end

    # n/(x**4 + a*x**2 + b), the quartic irreducible over QQ: with the real
    # split above, n/(q+ * q-) = (A*x + B)/q+ + (C*x + D)/q- and each piece is
    # a logarithm plus an arc tangent.
    def biquadratic_logs(n, f, x)
      cs = Solve.polynomial_coefficients(f.to_expr, x)
      return nil unless cs && cs.size == 5 && Scalar.zero?(cs[1]) && Scalar.zero?(cs[3]) && Scalar.one?(cs[4])
      b = cs[0]
      a = cs[2]
      ns = Solve.polynomial_coefficients(n.to_expr, x) or return nil
      n0, n1, n2, n3 = Array.new(4) { |i| ns[i] || Num.new(0) }
      disc = (a**2 - 4 * b).simplify
      return even_split(n0, n1, n2, n3, a, disc, x) if positive?(disc)
      t = RCAS.sqrt(b)
      s2 = (2 * t - a).simplify
      w2 = (2 * t + a).simplify
      return nil unless positive?(s2) && positive?(w2)
      sq = RCAS.sqrt(s2)
      w = RCAS.sqrt(w2)

      k = ((n1 - t * n3) / sq).simplify   # D - B
      m = (n0 / t).simplify               # B + D
      j = ((n2 - m) / sq).simplify        # C - A
      bb = ((m - k) / 2).simplify
      dd = ((m + k) / 2).simplify
      aa = ((n3 - j) / 2).simplify
      cc = ((n3 + j) / 2).simplify

      qplus = (x**2 + sq * x + t).simplify
      qminus = (x**2 - sq * x + t).simplify
      (aa / 2 * Fn.new(:log, [qplus]) + (2 * bb - aa * sq) / w * Fn.new(:atan, [((2 * x + sq) / w).simplify]) +
        cc / 2 * Fn.new(:log, [qminus]) + (2 * dd + cc * sq) / w * Fn.new(:atan, [((2 * x - sq) / w).simplify])).simplify
    end

    # The other real split of x**4 + a*x**2 + b: when a**2 - 4*b is positive the
    # quartic is (x**2 + p)*(x**2 + q) with p, q = (a +- sqrt(a**2 - 4*b))/2,
    # both irrational (a rational pair would have factored over QQ already).
    def even_split(n0, n1, n2, n3, a, disc, x)
      r = RCAS.sqrt(disc)
      p = ((a + r) / 2).simplify
      q = ((a - r) / 2).simplify
      gap = (q - p).simplify
      return nil if Scalar.zero?(gap)
      aa = ((n1 - p * n3) / gap).simplify
      bb = ((n0 - p * n2) / gap).simplify
      first = quadratic_log(aa, bb, p, x) or return nil
      second = quadratic_log((n3 - aa).simplify, (n2 - bb).simplify, q, x) or return nil
      (first + second).simplify
    end

    # INT (A*x + B)/(x**2 + c) dx, an arc tangent for c > 0 and a logarithm
    # for c < 0 (where x**2 + c has the two real roots +-sqrt(-c)).
    def quadratic_log(aa, bb, c, x)
      log = (aa / 2 * Fn.new(:log, [(x**2 + c).simplify])).simplify
      return log if Scalar.zero?(bb)
      if positive?(c)
        root = RCAS.sqrt(c)
        (log + bb / root * Fn.new(:atan, [(x / root).simplify])).simplify
      elsif positive?((-c).simplify)
        m = RCAS.sqrt((-c).simplify)
        (log + bb / (2 * m) * (Fn.new(:log, [(x - m).simplify]) - Fn.new(:log, [(x + m).simplify]))).simplify
      end
    end

    # A constant expression that is definitely positive (radicals included).
    def positive?(e)
      v = e.evalf
      v.is_a?(Numeric) && v.real? && v > 1e-12
    rescue StandardError
      false
    end

    # Mack's linear Hermite reduction: a/d = g' + a2/d* with d* squarefree.
    def hermite(a, d)
      g = Num.new(0)
      dminus = d.gcd(d.derivative)
      dstar = d.exact_div(dminus)
      while dminus.degree.positive?
        dminus2 = dminus.gcd(dminus.derivative)
        dminusstar = dminus.exact_div(dminus2)
        lhs = -(dstar * dminus.derivative).exact_div(dminus)
        gcd, s, = lhs.xgcd(dminusstar)
        raise "Hermite reduction: unexpected common factor" unless gcd.constant?
        b = (a * s) % dminusstar
        c = (a - b * lhs).exact_div(dminusstar)
        a = c - b.derivative * dstar.exact_div(dminusstar)
        g += b.to_expr / dminus.to_expr
        dminus = dminus2
      end
      [g, a, dstar]
    end

    # Logarithmic part of a/d (d squarefree, deg a < deg d, gcd(a, d) = 1):
    # sum over the roots c of the Rothstein-Trager resultant of
    # c * log(gcd(a - c*d', d)). Roots of degree 1 give plain logs, complex
    # conjugate pairs give log + atan; roots of higher degree return nil.
    def log_part(a, d, x)
      t = Var.new(:_t)
      ring2 = QQ[x.name, :_t]
      tring = QQ[:_t]
      dp = ring2.call(d.to_expr)
      ap = ring2.call(a.to_expr) - ring2.call(t) * ring2.call(d.derivative.to_expr)

      resultant = sylvester_resultant(dp, ap, x, tring)
      return nil if resultant.degree(:_t) < 1

      dprime = d.derivative
      total = Num.new(0)
      resultant.factor.factors.map(&:first).each do |ri|
        if ri.degree == 1
          c = Rational(-ri.coeff(0).value, ri.coeff(1).value)
          v = (a - dprime * c).gcd(d)
          next if v.constant?
          total += Num.new(c) * Fn.new(:log, [pretty(v)])
        else
          v = NumberFieldGcd.new(ri, tring).gcd(a, dprime, d)
          next if v.size <= 1
          return nil unless ri.degree == 2
          xring = QQ[x.name]
          p0 = xring.zero
          p1 = xring.zero
          v.each_with_index do |e, k|
            mono = xring.call(Var.new(x.name)**k)
            p0 += mono * e.coeff(0).value
            p1 += mono * e.coeff(1).value
          end
          total += quadratic_logs(ri, p0, p1)
        end
      end
      total
    end

    # gcd(a - θ*d', d) in K[x] for K = QQ[t]/(ri), θ the class of t.
    # Polynomials over K are arrays of K elements (QQ[t] polynomials reduced
    # modulo ri), index = degree in x.
    # res_x(p, q) for p, q in QQ[x, t], as an element of QQ[t], by
    # fraction-free (Bareiss) elimination on the Sylvester matrix.
    def sylvester_resultant(p, q, x, tring)
      m = p.degree(x.name)
      n = q.degree(x.name)
      pc = (0..m).map { |k| tring.call(p.coefficient_in(x.name, k).to_expr) }
      qc = (0..n).map { |k| tring.call(q.coefficient_in(x.name, k).to_expr) }
      size = m + n
      rows = []
      n.times { |i| rows << Array.new(size) { |j| (j - i).between?(0, m) ? pc[m - (j - i)] : tring.zero } }
      m.times { |i| rows << Array.new(size) { |j| (j - i).between?(0, n) ? qc[n - (j - i)] : tring.zero } }
      bareiss(rows, tring)
    end

    def bareiss(rows, ring)
      n = rows.size
      m = rows.map(&:dup)
      prev = ring.one
      sign = 1
      (0...n - 1).each do |k|
        if m[k][k].zero?
          swap = (k + 1...n).find { |i| !m[i][k].zero? }
          return ring.zero unless swap
          m[k], m[swap] = m[swap], m[k]
          sign = -sign
        end
        (k + 1...n).each do |i|
          (k + 1...n).each do |j|
            m[i][j] = (m[i][j] * m[k][k] - m[i][k] * m[k][j]).exact_div(prev)
          end
        end
        prev = m[k][k]
      end
      m[n - 1][n - 1] * sign
    end

    class NumberFieldGcd
      def initialize(ri, tring)
        @ri = ri
        @tring = tring
        @t = tring.call(Var.new(:_t))
      end

      # => monic gcd as an array of K elements
      def gcd(a, dprime, d)
        f = (0..[a.degree, dprime.degree].max).map do |k|
          (@tring.call(a.coeff(k).value) - @t * @tring.call(dprime.coeff(k).value)) % @ri
        end
        g = (0..d.degree).map { |k| @tring.call(d.coeff(k).value) }
        f = trim(f)
        g = trim(g)
        f, g = g, rem(f, g) until g.empty?
        monic(f)
      end

      private

      def trim(p)
        p = p.dup
        p.pop while !p.empty? && p.last.zero?
        p
      end

      def inv(e)
        g, s, = e.xgcd(@ri)
        raise DomainError, "#{e} is not invertible mod #{@ri}" unless g.constant? && !g.zero?
        (s * Scalar.div(Num.new(1), g.constant_term)) % @ri
      end

      def monic(p)
        return p if p.empty?
        i = inv(p.last)
        p.map { |e| (e * i) % @ri }
      end

      def rem(f, g)
        r = f.dup
        i = inv(g.last)
        while r.size >= g.size && !r.empty?
          c = (r.last * i) % @ri
          shift = r.size - g.size
          g.each_with_index { |ge, k| r[shift + k] -= c * ge }
          r = trim(r.map { |e| e % @ri })
        end
        r
      end
    end

    # Sum over the two roots c of A t^2 + B t + C of c*log(p0 + c*p1), written
    # with real logs and atan when the roots are complex.
    def quadratic_logs(ri, p0, p1)
      qa, qb, qc = ri.coeff(2).value, ri.coeff(1).value, ri.coeff(0).value
      a0 = Rational(-qb, 2 * qa)
      disc = Rational(qb * qb - 4 * qa * qc)
      p = p0 + p1 * a0
      scale = [p, p1].map { |q| q.terms.values.map { |c| c.value.is_a?(Rational) ? c.value.denominator : 1 }.reduce(1, :lcm) }.reduce(1, :lcm)
      p *= scale
      p1 *= scale
      common = Polynomial.rational_gcd(p.content, p1.content)
      unless common.zero? || common == 1
        p *= Rational(1, common)
        p1 *= Rational(1, common)
      end
      if disc.negative?
        b = RCAS.sqrt(Num.new(-disc)) / (2 * qa)
        b2 = -disc / (4 * qa * qa)
        modulus = pretty(p * p + p1 * p1 * b2)
        # atan(u) = -atan(1/u) + const: pick the orientation whose argument is a polynomial
        arctan =
          if p.degree > p1.degree
            2 * b * Fn.new(:atan, [p.to_expr / (b * p1.to_expr)])
          else
            -2 * b * Fn.new(:atan, [b * p1.to_expr / p.to_expr])
          end
        Num.new(a0) * Fn.new(:log, [modulus]) + arctan
      else
        beta = RCAS.sqrt(Num.new(disc)) / (2 * qa)
        (Num.new(a0) + beta) * Fn.new(:log, [p.to_expr + beta * p1.to_expr]) +
          (Num.new(a0) - beta) * Fn.new(:log, [p.to_expr - beta * p1.to_expr])
      end
    end

    # Integer primitive version of a QQ[x] polynomial (a constant factor
    # inside a log only shifts the integration constant).
    def pretty(poly)
      poly.clear_denominators.to_ring(ZZ[*poly.ring.vars]).primitive_part.to_expr
    end

    # ---- layer 3: Risch-Norman heuristic ---------------------------------------

    def heurisch(f, x)
      Heurisch.new(f, x).run
    rescue DomainError, ZeroDivisionError, NotImplementedError
      nil
    end

    class Heurisch
      def initialize(f, x)
        @x = x
        @f = rewrite_tan(f).simplify
        @atoms = [] # Expressions; index i+1 in exponent vectors (0 is x)
        @roots = {} # [base, q] => root atom index
      end

      def run
        collect(@f)
        return nil if @atoms.size > 8
        closure
        ftab = laurent(@f) or return nil
        @derivatives = @atoms.map { |a| atom_derivative(a) or return nil }
        @trig_pairs = trig_pairs
        ftab = normalize(ftab)

        monomials = ansatz(ftab)
        return nil if monomials.empty? || monomials.size > MAX_UNKNOWNS
        logs = log_candidates(ftab)
        unknown_tables = monomials.map { |m| normalize(monomial_derivative(m)) } +
                         logs.map { |l| normalize(log_derivative(l)) }

        keys = (unknown_tables.flat_map(&:keys) + ftab.keys).uniq
        rows = keys.map { |k| unknown_tables.map { |t| t[k] || Num.new(0) } }
        rhs = keys.map { |k| ftab[k] || Num.new(0) }
        matrix = MatrixSpace.new(QQ, rows.size, unknown_tables.size).unchecked(rows)
        solution = begin
          matrix.solve(rhs)
        rescue DomainError
          return nil
        end

        result = Num.new(0)
        monomials.each_with_index do |m, i|
          c = solution[i]
          next if Scalar.zero?(c)
          result += c * monomial_expr(m)
        end
        logs.each_with_index do |l, j|
          c = solution[monomials.size + j]
          next if Scalar.zero?(c)
          result += c * Fn.new(:log, [l])
        end
        result.simplify
      end

      private

      def x = @x
      def depends?(e) = Integrate.depends?(e, x)
      def zeros = Array.new(@atoms.size + 1, 0)

      def rewrite_tan(e)
        e = e.map_children { |c| rewrite_tan(c) }
        e.is_a?(Fn) && e.name == :tan ? Fn.new(:sin, e.args) / Fn.new(:cos, e.args) : e
      end

      # Register every transcendental / algebraic / polynomial atom of e.
      def collect(e)
        _, table = Expand.table(e)
        table.each_key do |factors|
          factors.each do |base, exp|
            if exp.is_a?(Expression) && depends?(exp)
              register(Simplify.power_node(base, exp))
              collect(exp)
            elsif exp.is_a?(Rational) && depends?(base)
              register_root(base, exp.denominator)
              collect(base) unless base == x
            elsif depends?(base) && base != x
              register(base)
              collect(base) if base.is_a?(Add) || base.is_a?(Sub) || base.is_a?(Neg)
              collect(base.args.first) if base.is_a?(Fn)
            end
          end
        end
      end

      def register(atom)
        return if atom == x || @atoms.include?(atom)
        raise DomainError, "unsupported atom #{atom}" if atom.is_a?(Fn) && !ATOM_FUNCTIONS.include?(atom.name)
        @atoms << atom
      end

      def register_root(base, q)
        register(base) unless base == x
        key = [base, q]
        return @roots[key] if @roots.key?(key)
        atom = Pow.new(base, Num.new(Rational(1, q)))
        @atoms << atom
        @roots[key] = @atoms.size - 1
      end

      # Atoms appearing in derivatives of atoms are atoms too.
      def closure
        10.times do
          before = @atoms.size
          @atoms.dup.each do |a|
            next if @roots.value?(@atoms.index(a))
            collect(a.diff(x).simplify)
          end
          break if @atoms.size == before
        end
        raise DomainError, "too many atoms" if @atoms.size > 12
      end

      # Expression => { exponent_vector => coefficient } or nil
      def laurent(e)
        constant, table = Expand.table(e.simplify)
        out = {}
        add(out, zeros, Num.new(constant)) unless constant.zero?
        table.each do |factors, coeff|
          exps = zeros
          c = Num.new(coeff)
          factors.each do |base, exp|
            if exp.is_a?(Expression) && depends?(exp)
              i = @atoms.index(Simplify.power_node(base, exp)) or return nil
              exps[i + 1] += 1
            elsif exp.is_a?(Rational) && depends?(base)
              i = @roots[[base, exp.denominator]] or return nil
              exps[i + 1] += exp.numerator
            elsif base == x
              return nil unless exp.is_a?(Integer)
              exps[0] += exp
            elsif depends?(base)
              return nil unless exp.is_a?(Integer)
              i = @atoms.index(base) or return nil
              exps[i + 1] += exp
            else
              c *= Simplify.power_node(base, exp)
            end
          end
          add(out, exps, c.simplify)
        end
        out
      end

      def atom_derivative(a)
        if (root = @roots.key(@atoms.index(a)))
          base, q = root
          inner = base == x ? { zeros => Num.new(1) } : laurent(base.diff(x).simplify)
          return nil unless inner
          exps = zeros
          exps[@atoms.index(a) + 1] = 1 - q
          scale(multiply(inner, { exps => Num.new(1) }), Num.new(Rational(1, q)))
        else
          laurent(a.diff(x).simplify)
        end
      end

      # ---- tables ---------------------------------------------------------

      def add(table, key, coeff)
        v = Scalar.add(table[key] || Num.new(0), coeff)
        Scalar.zero?(v) ? table.delete(key) : table[key] = v
      end

      def merge(a, b)
        out = a.dup
        b.each { |k, c| add(out, k, c) }
        out
      end

      def scale(table, c)
        table.transform_values { |v| Scalar.mul(v, c) }
      end

      def multiply(a, b)
        out = {}
        a.each do |ka, ca|
          b.each { |kb, cb| add(out, ka.zip(kb).map(&:sum), Scalar.mul(ca, cb)) }
        end
        out
      end

      def monomial_derivative(exps)
        out = {}
        exps.each_with_index do |e, i|
          next if e.zero?
          lowered = exps.dup
          lowered[i] -= 1
          d = i.zero? ? { zeros => Num.new(1) } : @derivatives[i - 1]
          out = merge(out, scale(multiply(d, { lowered => Num.new(1) }), Num.new(e)))
        end
        out
      end

      def log_derivative(l)
        i = @atoms.index(l)
        inverse = zeros
        if i.nil?
          inverse[0] = -1
          multiply({ zeros => Num.new(1) }, { inverse => Num.new(1) })
        else
          inverse[i + 1] = -1
          multiply(@derivatives[i], { inverse => Num.new(1) })
        end
      end

      def monomial_expr(exps)
        factors = {}
        factors[x] = exps[0] unless exps[0].zero?
        exps.drop(1).each_with_index { |e, i| factors[@atoms[i]] = e unless e.zero? }
        Simplify.rebuild_product(1, factors)
      end

      # ---- trig relations ---------------------------------------------------

      # [[sin_index, cos_index, sign]] with cos^2 = 1 + sign*sin^2
      def trig_pairs
        pairs = []
        @atoms.each_with_index do |a, i|
          next unless a.is_a?(Fn) && %i[sin sinh].include?(a.name)
          partner = a.name == :sin ? :cos : :cosh
          j = @atoms.index { |b| b.is_a?(Fn) && b.name == partner && b.args == a.args }
          pairs << [i + 1, j + 1, a.name == :sin ? -1 : 1] if j
        end
        pairs
      end

      # Reduce cos^k (k >= 2) via cos^2 = 1 - sin^2 (cosh^2 = 1 + sinh^2), and
      # sin^2 via sin^2 = 1 - cos^2 where cos has a negative exponent.
      def normalize(table)
        @trig_pairs.each do |si, ci, sign|
          loop do
            key = table.keys.find { |k| k[ci] >= 2 }
            break unless key
            c = table.delete(key)
            k1 = key.dup
            k1[ci] -= 2
            add(table, k1, c)
            k2 = k1.dup
            k2[si] += 2
            add(table, k2, Scalar.mul(c, Num.new(sign)))
          end
          loop do
            key = table.keys.find { |k| k[ci].negative? && k[si] >= 2 }
            break unless key
            c = table.delete(key)
            k1 = key.dup
            k1[si] -= 2
            add(table, k1, Scalar.mul(c, Num.new(sign)))
            k2 = k1.dup
            k2[ci] += 2
            add(table, k2, Scalar.mul(c, Num.new(-sign)))
          end
        end
        table
      end

      # ---- the ansatz -------------------------------------------------------

      def ansatz(ftab)
        keys = ftab.keys
        ranges = (0..@atoms.size).map do |i|
          values = keys.map { |k| k[i] }
          lo, hi = values.min, values.max
          if i.zero?
            [[lo, 0].min, hi + 1]
          else
            a = @atoms[i - 1]
            if @roots.value?(i - 1)               then [[lo, 0].min, hi + 2]
            elsif a.is_a?(Fn) && a.name == :exp   then [lo, hi]
            elsif a.is_a?(Pow)                    then [lo, hi]
            elsif a.is_a?(Fn) && %i[sin cos sinh cosh].include?(a.name)
              m = @trig_pairs.select { |p| p[0] == i || p[1] == i }.flat_map { |si, ci, _| keys.map { |k| k[si] + k[ci] } }.max || hi
              [[lo, 0].min, [m, hi].max + 1]
            else                                  [[lo + (lo.negative? ? 1 : 0), 0].min, hi + 1]
            end
          end
        end
        count = ranges.reduce(1) { |acc, (lo, hi)| acc * (hi - lo + 1) }
        return [] if count > MAX_UNKNOWNS
        ranges.map { |lo, hi| (lo..hi).to_a }.reduce([[]]) { |acc, r| acc.product(r).map(&:flatten) }
              .reject { |m| m.all?(&:zero?) }
      end

      def log_candidates(ftab)
        cands = []
        cands << x if ftab.keys.any? { |k| k[0].negative? }
        @atoms.each do |a|
          next if @roots.value?(@atoms.index(a))
          cands << a if a.is_a?(Add) || a.is_a?(Sub) || (a.is_a?(Fn) && %i[sin cos sinh cosh].include?(a.name))
        end
        cands
      end
    end
  end
end
