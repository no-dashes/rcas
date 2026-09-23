# frozen_string_literal: true

module RCAS
  # Linear q-difference equations,
  #
  #   p_0(x)*f(x) + p_1(x)*f(q*x) + ... + p_r(x)*f(q**r*x) = 0,
  #
  # and their q-hypergeometric solutions: Petkovsek's algorithm with the
  # shift x -> q*x in place of n -> n + 1. A q-hypergeometric term is one
  # whose ratio f(q*x)/f(x) is rational in x, and the same theorem holds with
  # the same shape,
  #
  #   f(q*x)/f(x) = z * a(x)/b(x) * c(q*x)/c(x),
  #
  # with a(x) a divisor of p_0(x), b(x) a divisor of p_r(q**(r - 1)*x),
  # gcd(a(x), b(q**h*x)) = 1 for every integer h >= 0, z free of x and c a
  # polynomial. The polynomial c is found with a degree bound of its own: the
  # top-degree terms give sum_j lc(Q_j)*(q**d)**j = 0, so q**d has to be a
  # root of that polynomial in one variable and d is read off it.
  #
  # Solutions are reported at x = q**n, where a q-hypergeometric term is a
  # product of q-Pochhammer symbols and powers - the form in which such
  # answers are written and the form q-summation can use. Every candidate is
  # verified on the ratio before it is returned.
  #
  # Sources (keys: MANUAL.md, Sources): [Koe14, ch. 12]; [APP98] for the
  # q-analogue of Petkovsek's algorithm; [GR04] for the notation.
  module QDifference
    MAX_DIVISORS = 64

    module_function

    # qsolve(eq(f(q*x), (1 - a*x)*f(x)), f, x, q) => f(q**n) = C1*(a; q)_n
    def qsolve(equation, f, x, q, n: :n)
      name, x, q, coeffs, forcing = normalize(equation, f, x, q)
      raise RCAS::Unsupported, "qsolve: #{forcing} makes the equation inhomogeneous" unless Scalar.zero?(forcing)
      index = Var.new(n)
      order = coeffs.size - 1
      found = solutions(coeffs, x, q, index)
      raise RCAS::Unsupported, "qsolve: no q-hypergeometric solutions (see qhyper)" if found.empty?
      if found.size < order
        raise RCAS::Unsupported, "qsolve: only #{found.size} of #{order} solutions are q-hypergeometric: " \
                                   "#{found.map(&:to_s).join(', ')} (see qhyper)"
      end
      general = found.each_with_index.map { |t, i| Var.new(:"C#{i + 1}") * t }.reduce(:+).simplify
      Equation.new(Fn.new(name, [(q**index).simplify]), general)
    end

    # The ratios f(q*x)/f(x) of the q-hypergeometric solutions: the honest
    # description, free of any choice of index.
    def qhyper(equation, f, x, q)
      _, x, q, coeffs, forcing = normalize(equation, f, x, q)
      raise RCAS::Unsupported, "qhyper: #{equation} is not homogeneous" unless Scalar.zero?(forcing)
      ratios(coeffs, x, q)
    end

    # The solutions as terms in n, where x = q**n.
    def solutions(coeffs, x, q, n)
      ratios(coeffs, x, q).filter_map { |ratio| term(ratio, x, q, n) }
    end

    # ---- reading the equation ----------------------------------------------------

    # [name, x, q, [p_0, ..., p_r], forcing]
    def normalize(equation, f, x, q)
      x = Expression.lift(x)
      q = Expression.lift(q)
      raise ArgumentError, "qsolve: the indeterminate must be a symbol, got #{x}" unless x.is_a?(Var)
      name = Recurrence.sequence_name(f)
      g = Solve.to_zero(equation).simplify
      shifts = shift_table(g, name, x, q)
      raise ArgumentError, "#{equation} contains no #{name}(q**j*#{x})" if shifts.empty?
      low = shifts.values.min
      unless low.zero?
        g = g.subs(x => (q**(-low) * x).simplify).simplify
        shifts = shift_table(g, name, x, q)
      end
      order = shifts.values.max
      raise ArgumentError, "#{equation} is not a q-difference equation: only #{name}(#{x}) occurs" if order.zero?
      ds = (0..order).map { |j| Var.new(:"_f#{j}") }
      h = g.subs(shifts.to_h { |t, j| [t, ds[j]] })
      raise RCAS::Unsupported, "only linear q-difference equations are supported" unless Solve.linear_in?(h, ds)
      coeffs = ds.map { |d| Solve.polynomial_coefficients(h, d)&.[](1) || Num.new(0) }
      forcing = Simplify.negate(h.subs(ds.to_h { |d| [d, Num.new(0)] })).simplify
      coeffs, forcing = Recurrence.clear_denominators(coeffs, forcing, x)
      [name, x, q, coeffs.map { |c| c.expand }, forcing]
    end

    # { f(q**j*x) node => j }
    def shift_table(g, name, x, q)
      g.each_node.select { |e| e.is_a?(Fn) && e.name == name }.uniq.to_h do |t|
        raise ArgumentError, "#{t}: one argument expected" unless t.args.size == 1
        j = power_of_q((t.args.first / x).cancel, q)
        raise RCAS::Unsupported, "#{t}: the argument must be #{x} times a power of #{q}" if j.nil?
        [t, j]
      end
    end

    # ---- q-Petkovsek -------------------------------------------------------------

    def ratios(coeffs, x, q)
      r = coeffs.size - 1
      return [] if r < 1 || Scalar.zero?(coeffs.first) || Scalar.zero?(coeffs.last)
      ring = QQ[*([x.name, q.name] | coeffs.flat_map { |c| c.variables.to_a })]
      first = ring.call(coeffs.first)
      last = ring.call(coeffs.last.subs(x => (q**(r - 1) * x).simplify).expand)
      found = []
      divisors(first, x).each do |a|
        divisors(last, x).each do |b|
          next unless QSummation.dispersion(a, b, q, x).empty?
          candidates(coeffs, a, b, x, q, r).each do |ratio|
            found << ratio unless found.any? { |other| Scalar.zero?((other - ratio).cancel) }
          end
        end
      end
      found
    rescue DomainError, NotImplementedError, RCAS::Unsupported, ZeroDivisionError
      []
    end

    # For one (a, b): the possible z, and for each the polynomials c.
    def candidates(coeffs, a, b, x, q, r)
      base = (0..r).map do |j|
        aj = (0...j).reduce(Num.new(1)) { |acc, i| acc * a.to_expr.subs(x => (q**i * x).simplify) }
        bj = (j...r).reduce(Num.new(1)) { |acc, i| acc * b.to_expr.subs(x => (q**i * x).simplify) }
        (coeffs[j] * aj * bj).expand
      end
      zs(base, x, r).flat_map do |z|
        qs = base.each_with_index.map { |poly, j| (poly * z**j).expand }
        polynomial_solutions(qs, x, q).filter_map do |c|
          ratio = (z * a.to_expr * c.subs(x => (q * x).simplify) / (b.to_expr * c)).cancel
          ratio if satisfies?(coeffs, ratio, x, q, r)
        end
      end
    end

    # The z for which the top-degree terms can cancel.
    def zs(base, x, r)
      degrees = base.map { |poly| Solve.polynomial_coefficients(poly, x)&.size }
      return [] if degrees.any?(&:nil?)
      top = degrees.each_index.select { |j| degrees[j] == degrees.max }
      return [] if top.size < 2
      coefficients = Array.new(r + 1) { Num.new(0) }
      top.each { |j| coefficients[j] = Solve.polynomial_coefficients(base[j], x).last }
      Solve.polynomial_roots(coefficients).map(&:simplify)
           .reject { |z| Scalar.zero?(z) || z.is_a?(RootOf) }
           .uniq { |z| z.to_s }
    rescue NotImplementedError, RCAS::Unsupported, DomainError
      []
    end

    # sum_j p_j(x)*ratio(x)*ratio(q*x)*...*ratio(q**(j - 1)*x) = 0?
    def satisfies?(coeffs, ratio, x, q, r)
      total = Num.new(0)
      product = Num.new(1)
      (0..r).each do |j|
        total += coeffs[j] * product
        product = (product * ratio.subs(x => (q**j * x).simplify)).cancel if j < r
      end
      Scalar.zero?(total.cancel)
    rescue ZeroDivisionError
      false
    end

    # ---- polynomial solutions of a q-difference equation --------------------------

    # Polynomial solutions c of sum_j Q_j(x)*c(q**j*x) = 0, a basis.
    def polynomial_solutions(coeffs, x, q)
      bound = degree_bound(coeffs, x, q)
      return [] if bound.nil? || bound.negative?
      ws = (0..bound).map { |i| Var.new(:"_qc#{i}") }
      c = ws.each_with_index.reduce(Num.new(0)) { |acc, (w, i)| acc + w * x**i }
      residual = coeffs.each_with_index.reduce(Num.new(0)) do |acc, (poly, j)|
        acc + poly * c.subs(x => (q**j * x).simplify)
      end
      conditions = Solve.polynomial_coefficients(residual.expand, x) or return []
      solution = QSummation.linear_solve(conditions, ws) or return []
      general = c.subs(solution)
      free = ws - solution.keys
      free.filter_map do |one|
        value = general.subs(free.to_h { |w| [w, Num.new(w == one ? 1 : 0)] }).simplify
        Scalar.zero?(value) ? nil : value
      end
    end

    # A solution of degree d makes the top-degree terms
    # sum_j lc(Q_j)*(q**d)**j*x**(D + d) cancel, so q**d is a root of that
    # polynomial in one variable; d is read off the roots that are powers
    # of q.
    def degree_bound(coeffs, x, q)
      degrees = coeffs.map { |poly| Solve.polynomial_coefficients(poly, x)&.size }
      return nil if degrees.any?(&:nil?)
      top = degrees.each_index.select { |j| degrees[j] == degrees.max }
      return nil if top.empty?
      return nil if top.size < 2 # a single top term cannot vanish
      coefficients = Array.new(coeffs.size) { Num.new(0) }
      top.each { |j| coefficients[j] = Solve.polynomial_coefficients(coeffs[j], x).last }
      Solve.polynomial_roots(coefficients).map(&:simplify)
           .filter_map { |z| power_of_q(z, q) }
           .reject(&:negative?).max
    rescue NotImplementedError, RCAS::Unsupported, DomainError
      nil
    end

    # ---- from a ratio to a term ---------------------------------------------------

    # The term u(n) = f(q**n) with f(q*x)/f(x) = ratio: every factor
    # (1 - a*x) of the ratio contributes a q-Pochhammer symbol (a; q)_n, a
    # factor x contributes q**(n*(n - 1)/2), and what is left of the constant
    # contributes z**n. nil when a factor is not linear in x.
    def term(ratio, x, q, n)
      pair = Fraction.as_fraction(ratio, [x.name, q.name] | ratio.variables.to_a) or return nil
      numerator, denominator = pair
      parts = [[numerator, 1], [denominator, -1]]
      constant = Num.new(1)
      total = Num.new(1)
      parts.each do |poly, sign|
        pieces = linear_pieces(poly, x, q) or return nil
        pieces.each do |kind, value|
          case kind
          when :constant then constant = sign.positive? ? constant * value : constant / value
          when :power then total *= Simplify.power_node(q, ((n * (n - 1) / 2) * sign * value).simplify)
          when :pochhammer
            factor = pochhammer(value, q, n)
            total = sign.positive? ? total * factor : total / factor
          end
        end
      end
      (Simplify.power_node(constant.simplify, n) * total).simplify
    rescue DomainError, ZeroDivisionError, NotImplementedError, RCAS::Unsupported
      nil
    end

    # (a; q)_n, except that (q**(-m); q)_n vanishes from n = m + 1 on: start
    # the product past the zero instead, as Petkovsek's (n - 1)! does for
    # u(n + 1) = n*u(n).
    def pochhammer(a, q, n)
      m = power_of_q(a, q)
      return Fn.new(:qpochhammer, [a, q, n]) if m.nil? || m.positive?
      Fn.new(:qpochhammer, [q, q, (n + m - 1).simplify])
    end

    # A polynomial in x as constants, powers of x and factors 1 - a*x.
    def linear_pieces(poly, x, q)
      pieces = []
      factorization = poly.factor
      pieces << [:constant, factorization.unit] unless Scalar.one?(factorization.unit)
      factorization.factors.each do |factor, multiplicity|
        degree = factor.degree(x.name)
        case degree
        when 0 then pieces << [:constant, Simplify.power_node(factor.to_expr, multiplicity)]
        when 1
          low = factor.coefficient_in(x.name, 0).to_expr
          high = factor.coefficient_in(x.name, 1).to_expr
          if Scalar.zero?(low) # a bare x
            pieces << [:power, multiplicity]
            pieces << [:constant, Simplify.power_node(high, multiplicity)]
          else
            multiplicity.times { pieces << [:pochhammer, Simplify.negate(high / low).cancel] }
            pieces << [:constant, Simplify.power_node(low, multiplicity)]
          end
        else return nil
        end
      end
      pieces
    rescue NotImplementedError, RCAS::Unsupported, DomainError
      nil
    end

    # ---- shared helpers ----------------------------------------------------------

    # Every divisor of +poly+ that involves x, and 1.
    def divisors(poly, x)
      return [poly.ring.one] if poly.degree(x.name).zero?
      list = [poly.ring.one]
      poly.factor.factors.each do |factor, multiplicity|
        next if factor.degree(x.name).zero? # a unit of QQ(q)[x]
        list = list.flat_map { |d| (0..multiplicity).map { |i| d * factor**i } }
        return [poly.ring.one] if list.size > MAX_DIVISORS
      end
      list.uniq { |d| d.to_expr.to_s }
    rescue NotImplementedError, RCAS::Unsupported, DomainError
      [poly.ring.one]
    end

    # d with value = q**d, or nil.
    def power_of_q(value, q)
      value = Expression.lift(value).simplify
      return 0 if Scalar.one?(value)
      coefficient, factors = Simplify.factorize(value)
      return nil unless coefficient == 1 && factors.size == 1 && factors.key?(q)
      d = factors[q]
      d.is_a?(Integer) ? d : nil
    end
  end
end
