# frozen_string_literal: true

module RCAS
  # Unevaluated sum.
  class Sum < Expression
    attr_reader :term, :var, :from, :to

    def initialize(term, var, from, to)
      @term = term
      @var = var
      @from = from
      @to = to
      freeze
    end

    def bound_variable = var
    def children = [term, var, from, to]
    def rebuild(term, var, from, to) = Sum.new(term, var, from, to)
    def to_sexp = [:sum, term.to_sexp, var.to_sexp, from.to_sexp, to.to_sexp]
  end

  # Symbolic summation.
  #
  #   sum(k, k, 1, n)              # => n/2 + n**2/2
  #   sum(k**2, k, 1, n)           # => n/6 + n**2/2 + n**3/3
  #   sum(2**k, k, 0, n)           # => -1 + 2*2**n
  #   sum(1/(k*(k + 1)), k, 1, oo) # => 1
  #
  # Polynomials in k get their closed form directly; other terms go through
  # Gosper's algorithm, which finds an antidifference whenever the term is
  # hypergeometric and one exists. A definite sum in one other variable is
  # then tried with creative telescoping (zeilberger.rb): the recurrence it
  # yields is solved and the answer checked against the sum itself. Anything
  # else stays an unevaluated Sum.
  #
  # Sources (keys: MANUAL.md, Sources): power sums by Newton interpolation
  # and Bernoulli numbers, zeta(2m) [GKP94, §6.5]; Euler-Maclaurin tail for
  # zeta(s) numerically [GKP94, §9.5]; Gosper [Gos78] with the degree bound
  # for the polynomial ansatz from [PWZ96, ch. 5].
  module Summation
    module_function

    def sum(f, k, from, to)
      f = Expression.lift(f).simplify
      k = Expression.lift(k)
      from = Expression.lift(from)
      to = Expression.lift(to)
      whole_bounds!(from, to)
      return UNDEFINED if pole_in_range?(f, k, from, to)
      hypergeometric_form(summed(f, k, from, to), to)
    end

    # A sum runs over integers: sum(k, k, 1.5, 3) was 5.625, which is
    # Faulhaber at a bound that is not one (third review, S11).
    def whole_bounds!(from, to)
      [from, to].each do |b|
        next unless b.is_a?(Num) && b.value.is_a?(Numeric) && b.value.real?
        next if b.value == b.value.round
        raise ArgumentError, "sum: the bounds must be integers, got #{b}"
      end
    end

    # A term with no value inside the range leaves the sum without one:
    # sum(1/(k*(k + 1)), k, -1, 3) telescoped straight across k = -1 and
    # k = 0 to -5/4 (third review, S4, the discrete twin of the poles an
    # integral is split at). Only integer poles count, and only against
    # numeric bounds; a symbolic upper bound is left to the rest.
    def pole_in_range?(f, k, from, to)
      return false unless from.is_a?(Num) && from.value.is_a?(Integer)
      upper = Limits.infinite?(to) ? Float::INFINITY : (to.is_a?(Num) && to.value.is_a?(Integer) ? to.value : nil)
      return false if upper.nil?
      Analysis.denominators(f, k).any? do |d|
        roots = begin
          Solve.solve(d, k)
        rescue StandardError, NotImplementedError
          next false
        end
        next false unless roots.is_a?(Array)
        roots.any? { |r| r.is_a?(Num) && r.value.is_a?(Integer) && r.value >= from.value && r.value <= upper }
      end
    end

    def summed(f, k, from, to)
      # 0 + 0 + ... is 0, however many terms: f*(oo - from + 1) said undefined
      return Num.new(0) if f.is_a?(Num) && f.value.zero?
      return (f * (to - from + 1)).simplify unless f.variables.include?(k.name)

      coeffs = Solve.polynomial_coefficients(f, k)
      return polynomial_sum(coeffs, k, from, to) if coeffs && to != OO

      if to == OO && (z = zeta_sum(f, k, from))
        return z
      end

      # sum_{k=0}^{n} binomial(n, k) ... is the full series when the terms
      # vanish beyond n - which binomial(n, k)/(n - k + 1) does not: the
      # pole at k = n + 1 cancels the zero of the binomial there.
      original = upper = to
      to = OO if vanishes_past_upper?(f, k, to)

      g = gosper(f, k)
      if g
        upper = to == OO ? tail_limit(g, k) : g.subs(k => to + 1)
        return (upper - g.subs(k => from)).cancel if upper
      end
      if to == OO && (known = classical_series(f, k, from))
        return known
      end
      if (telescoped = creative_telescoping(f, k, from, upper))
        return telescoped
      end
      direct = direct_sum(f, k, from, original)
      return direct if direct
      return Fn.new(:harmonic, [original]) if from == Num.new(1) && !Limits.infinite?(original) && Scalar.one?((f * k).simplify) # sum 1/k = H_n
      Sum.new(f, k, from, original)
    end

    # f = binomial(n, k)*r(k) with a symbolic n, and r has no pole at
    # k = n + 1, n + 2, ...: then every term past n is 0 and the sum may run
    # to infinity. r has to be a product of powers in k (a rational function
    # times c**k); anything else is not examined and keeps the bound.
    def vanishes_past_upper?(f, k, to)
      return false unless to.is_a?(Expression) && !to.variables.empty? && !to.variables.include?(k.name)
      top = f.each_node.find { |e| e.is_a?(Fn) && e.name == :binomial && e.args.first == to && e.args.last == k }
      return false unless top
      rest = (f / top).simplify
      return false if rest.each_node.any? { |e| e.is_a?(Fn) && e.variables.include?(k.name) && e.name != :exp }
      _, factors = Simplify.factorize(rest)
      factors.all? do |base, exp|
        next true unless base.variables.include?(k.name)
        next true unless exp.is_a?(Numeric) && exp.negative?
        coeffs = Solve.polynomial_coefficients(base, k) or next false
        next false unless coeffs.size == 2 # a linear factor: its root can be named
        root = (-coeffs[0] / coeffs[1]).simplify
        shift = (root - to).simplify
        !(shift.is_a?(Num) && shift.value.is_a?(Integer) && shift.value.positive?) &&
          !(shift.is_a?(Num) && shift.value.is_a?(Rational) && shift.value.denominator == 1 && shift.value.positive?) &&
          shift.variables.empty?
      end
    end

    # A definite sum in one other variable, over bounds that make the terms
    # outside them vanish: Zeilberger's algorithm gives a recurrence for the
    # sum, and the recurrence is solved.
    def creative_telescoping(f, k, from, to)
      return nil unless from.is_a?(Num) && from.value.is_a?(Integer)
      outer = (f.variables - [k.name]).to_a
      return nil unless outer.size == 1
      n = Var.new(outer.first)
      return nil unless to == n || Limits.infinite?(to)
      return nil unless term_ratio(f, k) && term_ratio(f, n)
      # Order 1 only: a sum whose closed form is hypergeometric satisfies a
      # first-order recurrence, and the higher orders are expensive on terms
      # like binomial(n, k)**4 that have no closed form anyway. sumrecursion
      # goes further when asked.
      Zeilberger.closed_form(f, n, k, from, to == n ? to : n, max_order: 1)
    rescue DomainError, NotImplementedError, ZeroDivisionError
      nil
    end

    # Ratio of consecutive terms as a rational function of k (binomials and
    # factorials cancelled), or nil.
    def term_ratio(f, k)
      g = Combinatorics.to_factorials(f)
      ratio = (g.subs(k => k + 1) / g).cancel
      pair = Fraction.as_fraction(ratio, [k.name]) or return nil
      [ratio, pair]
    end

    def classical_series(f, k, from, depth = 0)
      return nil unless from.is_a?(Num) && from.value.is_a?(Integer)
      pair = term_ratio(f, k)
      return nil if pair.nil?
      known = Combinatorics.known_series(pair.first, k)
      if known
        m0, total = known
        return nil if from.value < m0
        first = f.subs(k => m0).simplify
        return nil if first.each_node.any? { |n| n.is_a?(Fn) && %i[factorial gamma].include?(n.name) && n.args.first.is_a?(Num) }
        result = (first * total).simplify
        (m0...from.value).each { |i| result -= f.subs(k => i).simplify }
        return result.simplify
      end
      # leading terms that vanish (k*binomial(n, k) at k = 0): shift the index
      return nil if depth > 2 || !Scalar.zero?(f.subs(k => from).simplify)
      shifted = f.subs(k => k + from.value + 1).simplify
      classical_series(shifted, k, Num.new(0), depth + 1)
    rescue ZeroDivisionError
      nil # the ratio matched a template but the term itself has a pole
    end

    MAX_DIRECT_TERMS = 100_000

    # No closed form but integer bounds: add the terms up exactly.
    def direct_sum(f, k, from, to)
      return nil unless [from, to].all? { |b| b.is_a?(Num) && b.value.is_a?(Integer) }
      return nil if to.value - from.value > MAX_DIRECT_TERMS
      total = Num.new(0)
      (from.value..to.value).each { |i| total = Scalar.add(total, Expression.lift(f.call(k.name => i))) }
      total.is_a?(Num) ? total : total.simplify
    end

    # ---- c / k**s from k = m to infinity: c * (zeta(s) - partial sum) -----------

    def zeta_sum(f, k, from)
      coeff, factors = Simplify.factorize(f)
      return nil unless factors.size == 1 && factors.key?(k)
      s = factors[k]
      return nil unless s.is_a?(Numeric) && s.real? && s < -1
      return nil unless from.is_a?(Num) && from.value.is_a?(Integer) && from.value >= 1
      s = -s
      return nil unless s.is_a?(Integer)
      partial = (1...from.value).sum { |n| Rational(1, n**s) }
      (Num.new(coeff) * (Fn.new(:zeta, [Num.new(s)]) - Num.new(partial))).simplify
    end

    # zeta(2m) = (-1)^(m+1) B_2m (2 pi)^(2m) / (2 (2m)!)
    def zeta_even(n)
      m = n / 2
      b = bernoulli(n)
      factorial = (1..n).reduce(1, :*)
      c = Rational((-1)**(m + 1) * 2**n, 2 * factorial) * b
      (Num.new(c) * PI**n).simplify
    end

    def bernoulli(n)
      @bernoulli ||= [Rational(1)]
      while @bernoulli.size <= n
        m = @bernoulli.size
        s = (0...m).sum { |j| binomial(m + 1, j) * @bernoulli[j] }
        @bernoulli << -s / (m + 1)
      end
      @bernoulli[n]
    end

    def binomial(n, k) = (1..k).reduce(1) { |acc, i| acc * (n - k + i) / i }

    # Euler-Maclaurin tail after 200 terms; accurate to ~1e-12 for s >= 1.5.
    def zeta_numeric(s)
      raise ArgumentError, "zeta(s) needs s > 1, got #{s}" unless s > 1
      n = 200
      head = (1...n).sum { |i| i.to_f**-s }
      head + n**(1 - s) / (s - 1) + 0.5 * n**-s + s * n**(-s - 1) / 12 - s * (s + 1) * (s + 2) * n**(-s - 3) / 720
    end

    # ---- polynomials: Faulhaber by interpolation -----------------------------

    def polynomial_sum(coeffs, k, from, to)
      total = Num.new(0)
      coeffs.each_with_index do |c, j|
        next if Scalar.zero?(c)
        s = power_sum(j)
        total += c * (s.call(n: to) - s.call(n: from - 1))
      end
      tidy(total.expand)
    end

    # A hypergeometric closed form is often a binomial coefficient in
    # disguise: the sum of binomial(n, k)**2 comes back from the gammas as
    # 2**(2*n)*gamma(1/2 + n)/(pi**(1/2)*n!), which is binomial(2*n, n).
    def hypergeometric_form(value, to)
      return value unless to.is_a?(Var)
      Combinatorics.as_binomial(value, to) || value
    end

    # A closed form reads better factored, which is the form a course
    # writes: n**2*(1 + n)**2/4 rather than n**2/4 + n**3/2 + n**4/4. A
    # number stays the number it is, and a polynomial that does not factor
    # comes back as it went in.
    def tidy(value)
      return value if value.is_a?(Num) || value.variables.empty?
      value.factor.simplify
    rescue StandardError, NotImplementedError
      value
    end

    # S_j(n) = 1**j + 2**j + ... + n**j as a polynomial in n.
    def power_sum(j)
      @power_sums ||= {}
      @power_sums[j] ||= begin
        n = Var.new(:n)
        points = (0..j + 1).map { |m| [m, (1..m).sum { |i| i**j }] }
        # Newton interpolation with exact rationals
        coefficients = points.map { |_, v| Rational(v) }
        (1..j + 1).each do |level|
          (j + 1).downto(level) { |i| coefficients[i] = (coefficients[i] - coefficients[i - 1]) / (points[i][0] - points[i - level][0]) }
        end
        poly = Num.new(0)
        (j + 1).downto(0) { |i| poly = (poly * (n - points[i][0]) + coefficients[i]) }
        poly.expand
      end
    end

    # ---- Gosper's algorithm ------------------------------------------------------

    # Antidifference g with g(k+1) - g(k) = f(k), or nil.
    def gosper(f, k)
      ratio_pair = term_ratio(f, k)
      return nil if ratio_pair.nil?
      p, q = ratio_pair.last
      ring = p.ring
      return nil unless ring.vars.include?(k.name)
      kn = k.name

      a, b, c = normal_form(p, q, k)

      bm = shift(b, k, -1)
      d = degree_bound(a, bm, c, kn) or return nil
      xs = (0..d).map { |i| Var.new(:"_x#{i}") }
      xk = xs.each_with_index.reduce(Num.new(0)) { |acc, (v, i)| acc + v * k**i }
      equation = (a.to_expr * xk.subs(k => k + 1) - bm.to_expr * xk - c.to_expr).expand
      conditions = Solve.polynomial_coefficients(equation, k) or return nil
      solution = Solve.linear_system(conditions, xs).first or return nil
      x_expr = xk.subs(solution).subs(xs.to_h { |v| [v, Num.new(0)] }) # free unknowns: any value works
      g = (bm.to_expr * x_expr * f / c.to_expr).cancel
      check = (g.subs(k => k + 1) - g - f).cancel
      Scalar.zero?(check) || numerically_zero?(check, k) ? g : nil
    rescue DomainError, NotImplementedError, ZeroDivisionError
      nil
    end

    # Gosper-Petkovsek normal form of a term ratio: polynomials a, b, c with
    # p(k)/q(k) = a(k)/b(k) * c(k + 1)/c(k) and gcd(a(k), b(k + h)) = 1 for
    # every integer h >= 0. Zeilberger's algorithm uses it too.
    def normal_form(p, q, k)
      a, b, c = p, q, p.ring.one
      dispersion(a, b, k.name).each do |h|
        g = a.gcd(shift(b, k, h))
        next if g.constant?
        a = a.exact_div(g)
        b = b.exact_div(shift(g, k, -h))
        (1..h).each { |i| c *= shift(g, k, -i) }
      end
      [a, b, c]
    end

    def shift(poly, k, h) = poly.ring.call(poly.to_expr.subs(k => k + h))

    # Non-negative integers h with gcd(a(k), b(k+h)) non-trivial.
    def dispersion(a, b, kn)
      h = Var.new(:_h)
      ringh = QQ[*a.ring.vars, :_h]
      bh = ringh.call(b.to_expr.subs(Var.new(kn) => Var.new(kn) + h))
      res = ringh.call(a.to_expr).resultant(bh, kn)
      return [] if res.zero?
      coeffs = (0..res.degree(:_h)).map { |i| res.coefficient_in(:_h, i).to_expr }
      roots = begin
        Solve.polynomial_roots(coeffs)
      rescue NotImplementedError
        []
      end
      roots.select { |r| r.is_a?(Num) && r.value.is_a?(Integer) && r.value >= 0 }.map(&:value).uniq.sort
    end

    def degree_bound(a, bm, c, kn)
      da, db, dc = a.degree(kn), bm.degree(kn), c.degree(kn)
      lca = a.leading_coefficient_in(kn)
      lcb = bm.leading_coefficient_in(kn)
      candidates = []
      if da != db || lca != lcb
        candidates << dc - [da, db].max
      else
        n = da
        candidates << dc - n + 1
        diff = bm.coefficient_in(kn, n - 1) - a.coefficient_in(kn, n - 1)
        if n >= 1 && diff.constant? && lca.constant?
          ratio = Scalar.div(diff.constant_term, lca.constant_term)
          candidates << ratio.value if ratio.is_a?(Num) && ratio.value.is_a?(Integer)
        end
      end
      d = candidates.max
      d.negative? ? nil : d
    end

    # Random-point check for identities the canonical form does not prove.
    def numerically_zero?(expr, _k)
      rng = Random.new(7)
      3.times do
        values = expr.variables.to_h { |v| [v, rng.rand(2.0..5.0)] }
        value = expr.evalf(**values)
        return false unless value.is_a?(Numeric) && value.abs < 1e-9 * [1, expr.variables.size].max
      end
      true
    rescue StandardError
      false
    end

    # lim_{k -> oo} g(k) for the antidifference: geometric factors with
    # |ratio| < 1 vanish, anything else goes to Limits.limit.
    # The geometric factors of a term are taken together: 2**k/3**k is
    # (2/3)**k and converges, while each factor alone said "2**k diverges"
    # (third review, S3).
    def tail_limit(g, k)
      constant, table = Expand.table(g)
      kept = {}
      table.each do |factors, coeff|
        drop = false
        ratio = 1r
        numeric_ratio = true
        factors.each do |base, exp|
          if base.is_a?(Fn) && %i[factorial gamma].include?(base.name) && base.variables.include?(k.name) && exp.is_a?(Integer)
            raise ArgumentError, "the sum diverges" if exp.positive?
            drop = true
            next
          end
          next unless exp.is_a?(Expression) && exp.variables.include?(k.name) && !base.variables.include?(k.name)
          slope = exp.diff(k)
          next unless slope.is_a?(Num) && (slope.value.is_a?(Integer) || slope.value.is_a?(Rational))
          magnitude =
            if base.is_a?(Num) && base.value.is_a?(Numeric) then base.value.abs
            elsif base == Simplify.exp_base then Math::E
            end
          if magnitude.nil?
            numeric_ratio = false # symbolic ratio: convergence (|ratio| < 1) is assumed
            next
          end
          ratio *= magnitude.is_a?(Float) ? magnitude**slope.value : Rational(magnitude)**slope.value
        end
        if !drop && numeric_ratio && ratio != 1
          raise ArgumentError, "the sum diverges" if ratio > 1
          drop = true
        elsif !numeric_ratio
          drop = true
        end
        kept[factors] = coeff unless drop
      end
      rest = Simplify.rebuild_sum(constant, kept)
      value = Limits.limit(rest, k, OO)
      value.is_a?(Limit) ? nil : value
    end
  end
end
