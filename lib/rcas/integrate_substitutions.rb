# frozen_string_literal: true

module RCAS
  module Integrate
    # Substitutions that turn an integrand into a rational function of a new
    # variable, which the exact rational integrator then finishes:
    #
    #   R(x, sqrt(a x^2 + b x + c))   split into R0(x) + N(x) / (D(x) sqrt(Q));
    #       after partial fractions, P(x)/sqrt(Q) = d/dx[S(x) sqrt(Q)] +
    #       lambda/sqrt(Q) and x - alpha = 1/t for linear denominators
    #   R(x, (a x + b)^(1/n))         t = (a x + b)^(1/n)
    #   R(exp(k x)), R(sinh, cosh)    t = exp(r x), r the gcd of the rates
    #   R(sin u, cos u)               t = tan(u/2)
    #
    # The results are formal antiderivatives: differentiating them gives the
    # integrand wherever both are defined, but across a singularity of the
    # integrand the constant may jump, as in every CAS.
    #
    # Sources (keys: MANUAL.md, Sources): [Zor15, §5.7]; [Har16, ch. V-VI].
    module Substitutions
      module_function

      def depends?(e, x) = Integrate.depends?(e, x)
      def exact_num?(e) = e.is_a?(Num) && Integrate.exact?(e.value)

      # ---- R(x, sqrt(Q)), Q quadratic with rational coefficients ------------

      def radical(f, x, depth)
        ring = QQ[x.name]
        root = radicand(f, x, ring) or return nil
        even = Num.new(0) # R0(x)
        odd = Num.new(0)  # R1(x), to be multiplied by sqrt(Q)
        constant, table = Expand.table(f)
        even += Num.new(constant)
        table.each do |factors, coeff|
          return nil unless Integrate.exact?(coeff)
          rest = Num.new(coeff)
          k = 0 # power of sqrt(Q)
          factors.each do |base, e|
            if base == root
              return nil unless e.is_a?(Integer) || (e.is_a?(Rational) && e.denominator == 2)
              k += e.is_a?(Integer) ? 2 * e : e.numerator
            elsif e.is_a?(Integer) && polynomial?(base, ring)
              rest *= base**e
            else
              return nil
            end
          end
          q, r = k.divmod(2)
          rest *= root**q
          r.zero? ? even += rest : odd += rest
        end

        result = Num.new(0)
        even = even.simplify
        unless Scalar.zero?(even)
          part = Integrate.attempt(even.cancel, x, depth + 1)
          return nil unless part && Integrate.complete?(part)
          result += part
        end
        odd = odd.simplify
        unless Scalar.zero?(odd)
          part = over_root((odd * root).cancel, root, ring, x, depth) or return nil
          result += part
        end
        result.simplify
      end

      # The quadratic under a square root in f, or nil.
      def radicand(f, x, ring)
        bases = f.each_node.select { |n| n.is_a?(Pow) && n.exponent.is_a?(Num) && n.exponent.value.is_a?(Rational) && depends?(n.base, x) }
                 .map(&:base).uniq
        return nil unless bases.size == 1
        base = bases.first
        poly = polynomial?(base, ring) or return nil
        poly.degree == 2 ? base : nil
      end

      def polynomial?(e, ring)
        ring.call(e)
      rescue DomainError, ArgumentError
        nil
      end

      def quadratic_coefficients(root, ring)
        poly = ring.call(root)
        [2, 1, 0].map { |k| poly.coeff(k).value } # [a, b, c]
      end

      # int m / sqrt(Q) dx for m rational in x.
      def over_root(m, root, ring, x, depth)
        a, b, c = quadratic_coefficients(root, ring)
        return nil if (b * b - 4 * a * c).zero?
        parts = begin
          RationalFunction.apart(m, x)
        rescue DomainError
          return nil if depends?(m, x) # not a rational function of x
          m
        end
        constant, terms = Simplify.termize(parts, simplify: true)
        polynomial = Hash.new(0)
        polynomial[0] = constant
        result = Num.new(0)
        terms.each do |factors, coeff|
          base, e = factors.first
          if factors.size == 1 && base == x && e.is_a?(Integer) && e.positive?
            polynomial[e] += coeff
          elsif factors.size == 1 && e.is_a?(Integer) && e.negative? && (ab = Integrate.linear(base, x)) && ab.all? { |v| exact_num?(v) }
            slope, offset = ab.map(&:value)
            alpha = (-offset).quo(slope) # Integers: -1/2 is not -1
            part = linear_denominator(alpha, -e, root, [a, b, c], x, depth) or return nil
            result += Num.new(coeff.quo(slope**(-e))) * part
          else
            return nil # an irreducible quadratic denominator: not covered
          end
        end
        part = polynomial_over_root(polynomial, root, [a, b, c], x) or return nil
        (result + part).simplify
      end

      # int P(x)/sqrt(Q) dx = S(x) sqrt(Q) + lambda int dx/sqrt(Q), deg S = deg P - 1,
      # from P = S' Q + S Q'/2 + lambda by comparing coefficients.
      def polynomial_over_root(polynomial, root, abc, x)
        a, b, c = abc
        n = polynomial.keys.max
        base = base_integral(root, abc, x) or return nil
        return (Num.new(polynomial[0]) * base).simplify if n.zero?

        rows = (0..n).map do |i|
          row = (0...n).map do |j| # coefficient of x^i in j x^(j-1) Q + x^j (a x + b/2)
            v = 0r
            v += a * (j + 1) if i == j + 1
            v += b * (j + Rational(1, 2)) if i == j
            v += c * j if i == j - 1
            Num.new(v)
          end
          row << Num.new(i.zero? ? 1 : 0) # lambda
          row << Num.new(polynomial[i])
          row
        end
        reduced, pivots = Elimination.rref(rows)
        return nil unless pivots == (0..n).to_a
        s = (0...n).map { |j| reduced[j][n + 1] }
        lambda = reduced[n][n + 1]
        shape = s.each_with_index.map { |v, j| v * x**j }.reduce(:+)
        (shape * root**Rational(1, 2) + lambda * base).simplify
      end

      # int dx / sqrt(a x^2 + b x + c)
      def base_integral(root, abc, x)
        a, b, c = abc
        y = root**Rational(1, 2)
        disc = b * b - 4 * a * c
        if a.positive?
          sa = RCAS.sqrt(Num.new(a))
          Fn.new(:log, [sa * y + Num.new(a) * x + Num.new(b.quo(2))]) / sa
        elsif disc.positive?
          sa = RCAS.sqrt(Num.new(-a))
          Fn.new(:asin, [(Num.new(-2 * a) * x - Num.new(b)) / RCAS.sqrt(Num.new(disc))]) / sa
        end
      end

      # int dx / ((x - alpha)^k sqrt(Q)) with x - alpha = 1/t:
      #   Q(x) = (Q(alpha) t^2 + Q'(alpha) t + a) / t^2 =: Qt(t) / t^2
      #   integrand -> -t^(k-1) / sqrt(Qt) dt, and sqrt(Qt) = sqrt(Q) / (x - alpha) afterwards.
      def linear_denominator(alpha, k, root, abc, x, depth)
        a, b, c = abc
        t = Var.new(:"_t#{depth}")
        q0 = a * alpha * alpha + b * alpha + c
        q1 = 2 * a * alpha + b
        qt = (Num.new(q0) * t**2 + Num.new(q1) * t + Num.new(a)).simplify
        g = (-t**(k - 1) / qt**Rational(1, 2)).simplify
        r = Integrate.attempt(g, t, depth + 1)
        return nil unless r && Integrate.complete?(r)
        shifted = (x - Num.new(alpha)).simplify
        r = replace_root(r, qt, root**Rational(1, 2) / shifted, 2)
        r.subs(t => 1 / shifted).simplify
      end

      # Replace base**e by root**(n e) (root stands for base**(1/n)) and a bare
      # base by root**n, comparing canonical forms.
      def replace_root(expr, base, root, n)
        if expr.is_a?(Pow) && expr.exponent.is_a?(Num) && expr.base.simplify == base
          return root**Num.new(n * expr.exponent.value)
        end
        return root**n if (expr.is_a?(Add) || expr.is_a?(Sub) || expr.is_a?(Fn)) && expr.simplify == base
        expr.map_children { |c| replace_root(c, base, root, n) }
      end

      # ---- exp(a x^2 + b x + c), a < 0: the error function ---------------------------
      #
      #   int exp(q) dx = exp(c - b^2/(4a)) * sqrt(pi) / (2 sqrt(-a)) * erf(sqrt(-a) x - b / (2 sqrt(-a)))
      def gaussian(f, x)
        return gaussian_moment(f, x) unless f.is_a?(Fn)
        return nil unless f.name == :exp && f.args.size == 1
        cs = Solve.polynomial_coefficients(f.args.first, x)
        return nil unless cs && cs.size == 3 && cs[2].is_a?(Num) && cs[2].value.real? && cs[2].value.negative?
        c, b, a = cs
        s = RCAS.sqrt(Num.new(-a.value))
        argument = (s * x - b / (2 * s)).simplify
        scale = (Fn.new(:exp, [c - b**2 / (4 * a)]) * RCAS.sqrt(PI) / (2 * s)).simplify
        (scale * RCAS.erf(argument)).simplify
      end

      # int x^n e^q = x^(n-1) e^q / (2a) - b/(2a) int x^(n-1) e^q - (n-1)/(2a) int x^(n-2) e^q
      def gaussian_moment(f, x)
        _, factors = Simplify.factorize(f)
        return nil unless factors.size == 2 && factors[x].is_a?(Integer) && factors[x].positive? && factors.key?(Simplify.exp_base)
        n = factors[x]
        q = Expression.lift(factors[Simplify.exp_base])
        cs = Solve.polynomial_coefficients(q, x)
        return nil unless cs && cs.size == 3 && cs[2].is_a?(Num) && cs[2].value.real? && cs[2].value.negative?
        _, b, a = cs
        e = Fn.new(:exp, [q])
        lower = ->(k) { k.zero? ? gaussian(e, x) : gaussian_moment((x**k * e).simplify, x) }
        first = lower.call(n - 1) or return nil
        result = x**(n - 1) * e / (2 * a) - b / (2 * a) * first
        if n >= 2
          second = lower.call(n - 2) or return nil
          result -= Num.new(n - 1) / (2 * a) * second
        end
        result.simplify
      end

      # ---- R(x, (a x + b)^(1/n)) -------------------------------------------------

      def root_of_linear(f, x, depth)
        powers = f.each_node.select { |n| n.is_a?(Pow) && n.exponent.is_a?(Num) && n.exponent.value.is_a?(Rational) && depends?(n.base, x) }
        return nil if powers.empty?
        bases = powers.map(&:base).uniq
        return nil unless bases.size == 1
        base = bases.first
        ab = Integrate.linear(base, x)
        return nil unless ab && ab.all? { |v| exact_num?(v) }
        slope, offset = ab
        n = powers.map { |p| p.exponent.value.denominator }.reduce(1) { |l, d| l.lcm(d) }
        t = Var.new(:"_w#{depth}")
        g = replace_root(f, base.simplify, t, n).subs(x => (t**n - offset) / slope)
        g = (g * Num.new(n) * t**(n - 1) / slope).cancel
        return nil if depends?(g, x)
        r = Integrate.attempt(g, t, depth + 1)
        return nil unless r && Integrate.complete?(r)
        r.subs(t => base**Rational(1, n)).simplify
      end

      # ---- R(x, ((a x + b)/(c x + d))^(1/n)) -------------------------------------

      # The Moebius substitution: t = ((a*x + b)/(c*x + d))**(1/n) turns
      # x = (d*t**n - b)/(a - c*t**n) and the whole integrand into a rational
      # function of t. Covers sqrt((1 - x)/(1 + x)) and its relatives, which
      # the root-of-a-linear-form rule above cannot reach. [Har16, ch. III]
      def root_of_ratio(f, x, depth)
        powers = f.each_node.select { |n| n.is_a?(Pow) && n.exponent.is_a?(Num) && n.exponent.value.is_a?(Rational) && !n.exponent.value.integer? && depends?(n.base, x) }
        bases = powers.map(&:base).uniq
        return nil unless bases.size == 1
        base = bases.first.simplify
        a, b = Integrate.linear(RationalFunction.numer(base), x)
        c, d = Integrate.linear(RationalFunction.denom(base), x)
        return nil unless [a, b, c, d].all? { |v| v && exact_num?(v) }
        return nil if Scalar.zero?(c) # a linear form: root_of_linear did that
        det = (a * d - b * c).simplify
        return nil if Scalar.zero?(det)

        n = powers.map { |p| p.exponent.value.denominator }.reduce(1) { |l, e| l.lcm(e) }
        t = Var.new(:"_m#{depth}")
        xt = ((d * t**n - b) / (a - c * t**n)).simplify
        g = replace_root(f, base, t, n).subs(x => xt)
        g = (g * xt.diff(t)).cancel
        return nil if depends?(g, x)
        r = Integrate.attempt(g, t, depth + 1)
        return nil unless r && Integrate.complete?(r)
        r.subs(t => base**Rational(1, n)).simplify
      end

      # ---- R(exp(k x)) ---------------------------------------------------------------

      def exponential(f, x, depth)
        g = rewrite_hyperbolic(f)
        exps = g.each_node.select { |n| n.is_a?(Fn) && n.name == :exp && depends?(n.args.first, x) }.uniq
        return nil if exps.empty?
        rates = exps.map do |e|
          ab = Integrate.linear(e.args.first, x)
          return nil unless ab && exact_num?(ab.first)
          ab
        end
        denominator = rates.map { |c, _| Rational(c.value).denominator }.reduce(1) { |l, d| l.lcm(d) }
        numerator = rates.map { |c, _| (Rational(c.value) * denominator).to_i }.reduce(0) { |acc, m| acc.gcd(m) }
        rate = Rational(numerator, denominator)
        t = Var.new(:"_e#{depth}")
        map = exps.zip(rates).to_h do |e, (c, d)|
          power = t**Integer(Rational(c.value) / rate)
          [e, Scalar.zero?(d) ? power : Fn.new(:exp, [d]) * power]
        end
        h = g.subs(map).simplify
        return nil if depends?(h, x)
        r = Integrate.attempt((h / (Num.new(rate) * t)).cancel, t, depth + 1)
        return nil unless r && Integrate.complete?(r)
        real_log_exp(r.subs(t => Fn.new(:exp, [Num.new(rate) * x])), x).simplify
      end

      # log(exp(u)) is u only on the principal strip, so the general fold
      # leaves it alone (log(exp(2*pi*i)) is 0). The integration variable is
      # real, and the substitution t = exp(r*x) has just put that exp there
      # itself, so here the rule does hold: without it the antiderivative of
      # 1/(1 + exp(x)) came back as -log(1 + exp(x)) + log(exp(x)).
      def real_log_exp(expr, x)
        if expr.is_a?(Fn) && expr.name == :log && expr.args.size == 1 &&
           (inner = expr.args.first).is_a?(Fn) && inner.name == :exp && depends?(inner.args.first, x)
          return inner.args.first
        end
        expr.map_children { |c| real_log_exp(c, x) }
      end

      # sin(u)**(2k) / cos(u)**n = (1 - cos(u)**2)**k / cos(u)**n, and the same with
      # the roles swapped: a sum of powers of one function, which the table and
      # the heuristic handle in their familiar forms (1/cos(x) => log((1 + sin(x))/cos(x))).
      def reduce_even_power(f, x, depth)
        _, factors = Simplify.factorize(Trigonometry.expand_trig(f).simplify)
        return nil unless factors.size == 2 && factors.values.all? { |e| e.is_a?(Integer) }
        fns = factors.keys
        return nil unless fns.all? { |b| b.is_a?(Fn) && %i[sin cos].include?(b.name) } && fns.map(&:name).sort == %i[cos sin]
        return nil unless fns.map { |b| b.args.first } .uniq.size == 1
        sin_f, cos_f = fns.sort_by { |b| b.name == :sin ? 0 : 1 }
        m = factors[sin_f]
        n = factors[cos_f]
        g =
          if m.positive? && m.even? && n.negative?
            (1 - cos_f**2)**(m / 2) * cos_f**n
          elsif n.positive? && n.even? && m.negative?
            (1 - sin_f**2)**(n / 2) * sin_f**m
          end
        return nil unless g
        r = Integrate.attempt(g.expand, x, depth + 1)
        r && Integrate.complete?(r) ? r : nil
      end

      # atan(tan(u)) => u: the same formal antiderivative, without the jumps
      # - for the atan(tan(u)) the substitution t = tan(u/2) put there. One
      # the integrand already had (`keep`) is a sawtooth, not u:
      # integrate(atan(tan(x)), x) is not x**2/2 (third review, D7).
      def unwind(e, keep = [])
        e = e.map_children { |c| unwind(c, keep) }
        if e.is_a?(Fn) && e.name == :atan && e.args.first.is_a?(Fn) && e.args.first.name == :tan && !keep.include?(e)
          return e.args.first.args.first
        end
        e
      end

      def rewrite_hyperbolic(e)
        e = e.map_children { |c| rewrite_hyperbolic(c) }
        return e unless e.is_a?(Fn) && %i[sinh cosh tanh].include?(e.name) && e.args.size == 1
        u = e.args.first
        plus = Fn.new(:exp, [u])
        minus = Fn.new(:exp, [Simplify.negate(u)])
        case e.name
        when :sinh then (plus - minus) / 2
        when :cosh then (plus + minus) / 2
        else (plus - minus) / (plus + minus)
        end
      end

      # ---- R(sin u, cos u), the Weierstrass substitution t = tan(u/2) ------------

      def trigonometric(f, x, depth)
        return nil if f.each_node.none? { |n| n.is_a?(Fn) && %i[sin cos tan].include?(n.name) && depends?(n.args.first, x) }
        reduced = reduce_even_power(f, x, depth)
        return reduced if reduced
        g = Trigonometry.expand_trig(f).simplify
        trigs = g.each_node.select { |n| n.is_a?(Fn) && %i[sin cos].include?(n.name) && depends?(n.args.first, x) }.uniq
        return nil if trigs.empty?
        args = trigs.map { |n| n.args.first.simplify }.uniq
        return nil unless args.size == 1
        u = args.first
        ab = Integrate.linear(u, x) or return nil
        slope = ab.first
        t = Var.new(:"_h#{depth}")
        map = trigs.to_h do |n|
          [n, n.name == :sin ? 2 * t / (1 + t**2) : (1 - t**2) / (1 + t**2)]
        end
        h = g.subs(map).simplify
        return nil if depends?(h, x)
        r = Integrate.attempt((h * 2 / (slope * (1 + t**2))).cancel, t, depth + 1)
        return nil unless r && Integrate.complete?(r)
        r.subs(t => Fn.new(:tan, [u / 2])).simplify
      end
    end
  end
end
