# frozen_string_literal: true

module RCAS
  # q-summation: Gosper's algorithm in the q-world.
  #
  # A term is q-hypergeometric when t(k + 1)/t(k) is a rational function of
  # q**k, the way an ordinary hypergeometric term has a rational function of
  # k. Writing x for q**k turns the shift k -> k + 1 into x -> q*x, and
  # everything Gosper does goes through with that one change: the
  # q-Gosper-Petkovsek normal form
  #
  #   t(k + 1)/t(k) = a(x)/b(x) * c(q*x)/c(x),  gcd(a(x), b(q**h*x)) = 1
  #
  # for every integer h >= 0, and then the q-analogue of Gosper's equation
  #
  #   a(x)*X(q*x) - b(x/q)*X(x) = c(x)
  #
  # for a polynomial X, from which the antidifference is
  # S(k) = b(x/q)*X(x)/c(x) * t(k). The answer is checked by differencing it.
  #
  # Sources (keys: MANUAL.md, Sources): [Koe14, ch. 11]; [Koe93] for the
  # q-analogue of the algorithm; [GR04] for the notation.
  module QSummation
    X = Var.new(:_qx) # stands for q**k while the algorithm runs

    module_function

    # The term ratio t(k + 1)/t(k) as a rational function of q**k (as X), or
    # nil when the term is not q-hypergeometric.
    #
    # A sum of terms is written as one q-hypergeometric term times a rational
    # function of q**k: the first summand is the core, the others are
    # measured against it, and the ratio of the whole is the ratio of the
    # core times R(q*x)/R(x). Terms like q**(k + 1)/(q; q)_(k + 1) -
    # q**k/(q; q)_k only telescope together, so taking them apart would lose
    # the answer.
    def ratio(f, k, q)
      f = QFunctions.align(Expression.lift(f).simplify)
      parts = summands(f)
      core = parts.first
      base = term_ratio(core, k, q) or return nil
      return base if parts.size == 1
      pieces = parts.map { |part| relative(part, core, k, q) }
      return nil if pieces.any?(&:nil?)
      total = pieces.reduce(:+).cancel
      return nil if Scalar.zero?(total)
      (base * total.subs(X => (q * X).simplify) / total).cancel
    rescue ZeroDivisionError, DomainError
      nil
    end

    # The ratio of a single q-hypergeometric term.
    def term_ratio(f, k, q)
      g = QFunctions.to_pochhammer(f)
      in_x(cancel_q(g.subs(k => k + 1) / g), k, q)
    end

    # part/core as a rational function of q**k, or nil.
    def relative(part, core, k, q)
      in_x(cancel_q(QFunctions.to_pochhammer(part) / QFunctions.to_pochhammer(core)), k, q)
    end

    # Cancel q-Pochhammer symbols whose indices differ by an integer first,
    # then the rest as usual.
    def cancel_q(quotient)
      coefficient, factors = Simplify.factorize(quotient, simplify: true)
      QFunctions.merge_pochhammers(factors)
      Simplify.rebuild_product(coefficient, factors).cancel
    end

    # q**(a*k + b) becomes q**b * X**a; nil when a k is left over.
    def in_x(expr, k, q)
      out = powers_in_x(expr, k, q)
      out.variables.include?(k.name) ? nil : out
    end

    def powers_in_x(expr, k, q) = powers_in(expr, k, q, X)

    # q**(a*v + b) becomes q**b * target**a: X stands for q**k, and
    # q-Zeilberger has a second one standing for q**n.
    def powers_in(expr, v, q, target)
      if expr.is_a?(Pow) && expr.base == q
        cs = Solve.polynomial_coefficients(expr.exponent, v)
        if cs && cs.size == 2 && cs[1].is_a?(Num) && cs[1].value.is_a?(Integer)
          return (Simplify.power_node(q, cs[0]) * target**cs[1].value).simplify
        end
      end
      expr.map_children { |c| powers_in(c, v, q, target) }
    end

    # X back to q**k.
    def in_k(expr, k, q) = expr.subs(X => q**k)

    # q**n, for a parameter n, is not a polynomial in q: stand such powers in
    # by variables of their own, so that the coefficients live in
    # QQ(q, q**n) as they should. Returns the expression and { q**n => var }.
    def abstract(expr, q)
      powers = expr.each_node.select do |node|
        node.is_a?(Pow) && node.base == q && !(node.exponent.is_a?(Num) && node.exponent.value.is_a?(Integer))
      end.uniq
      return [expr, {}] if powers.empty?
      parameters = powers.each_with_index.to_h { |power, i| [power, Var.new(:"_qp#{i}")] }
      [expr.subs(parameters), parameters]
    end

    # ---- q-Gosper ----------------------------------------------------------------

    # The q-antidifference: S(k) with S(k + 1) - S(k) = f(k), or nil.
    def qgosper(f, k, q)
      single(Expression.lift(f).simplify, k, q)
    end

    # The summands of a sum, flattened.
    def summands(f)
      case f
      when Add then summands(f.left) + summands(f.right)
      when Sub then summands(f.left) + summands(f.right).map { |t| Simplify.negate(t) }
      else [f]
      end
    end

    def single(f, k, q)
      r = ratio(f, k, q) or return nil
      r, parameters = abstract(r, q)
      pair = Fraction.as_fraction(r, [X.name, q.name] + parameters.values.map(&:name)) or return nil
      a, b, c = normal_form(pair.first, pair.last, q)
      bm = shift(b, q, -1)
      bound = degree_bound(a, bm, c, q) or return nil
      xs = (0..bound).map { |i| Var.new(:"_w#{i}") }
      poly = xs.each_with_index.reduce(Num.new(0)) { |acc, (v, i)| acc + v * X**i }
      equation = (a.to_expr * poly.subs(X => q * X) - bm.to_expr * poly - c.to_expr).expand
      conditions = Solve.polynomial_coefficients(equation, X) or return nil
      solution = linear_solve(conditions, xs) or return nil
      value = poly.subs(solution).subs(xs.to_h { |v| [v, Num.new(0)] })
      rational = (bm.to_expr * value / c.to_expr).cancel.subs(parameters.invert)
      plain = (in_k(rational, k, q) * f).cancel
      tidied = tidy(plain, k, q)
      # Cancelling expands, which is worth it when it collapses the answer
      # and not when it only spreads it out: keep the shorter form.
      antidifference = tidied.to_s.length <= plain.to_s.length ? tidied : plain
      telescopes?(antidifference, f, k, q) ? antidifference : nil
    rescue DomainError, NotImplementedError, ZeroDivisionError
      nil
    end

    # sum_{k=from}^{to} f(k) for a q-hypergeometric term: the antidifference
    # at the ends, or nil.
    def qsum(f, k, from, to, q)
      g = qgosper(f, k, q) or return nil
      ends(g, k, from, to, q) || ends(tidy(g, k, q), k, from, to, q)
    end

    # The antidifference at both ends. A removable zero in the denominator
    # (the form the answer happens to be written in) makes this nil, and the
    # caller tries again with the cancelled form.
    def ends(g, k, from, to, q)
      (g.subs(k => (to + 1).simplify) - g.subs(k => from)).cancel
    rescue ZeroDivisionError
      nil
    end

    # S(k + 1) - S(k) = f(k), checked at exact points; the linear algebra is
    # exact, so this is a check on the derivation.
    def telescopes?(s, f, k, q)
      difference = s.subs(k => k + 1) - s - f
      names = difference.variables.to_a
      random = Random.new(20140610)
      checked = 0
      40.times do
        point = names.to_h { |v| [v, Num.new(v == k.name ? random.rand(3..40) : Rational(random.rand(5..97), random.rand(2..7)))] }
        value = begin
          difference.subs(point).simplify
        rescue ZeroDivisionError
          next
        end
        return false unless Scalar.zero?(value)
        checked += 1
        break if checked >= 4
      end
      checked >= 4
    end

    # Cancel an expression that mixes q-Pochhammer symbols with powers of
    # q**k: stand both in by variables, cancel as a rational function, put
    # them back. Without it an antidifference keeps the shape of the term it
    # came from, R(q**k)*f(k), instead of collapsing.
    def tidy(expr, k, q)
      expr = QFunctions.align(QFunctions.to_pochhammer(expr.simplify))
      symbols = expr.each_node.select { |e| e.is_a?(Fn) && QFunctions::NAMES.include?(e.name) }.uniq
      names = symbols.each_with_index.to_h { |symbol, i| [symbol, Var.new(:"_qa#{i}")] }
      abstracted = powers_in_x(expr.subs(names), k, q)
      return expr if abstracted.variables.include?(k.name)
      cancelled = abstracted.cancel
      in_k(cancelled, k, q).subs(names.invert).simplify
    rescue ZeroDivisionError, DomainError
      expr
    end

    # ---- linear algebra over the rational functions -------------------------------

    # Solve a small linear system, cancelling every entry on the way.
    # Elimination.rref leaves entries such as q + q*(q - 1)/(1 - q) standing
    # and Scalar.zero? does not cancel them, so a consistent system can be
    # declared inconsistent; here the entries are rational functions of q and
    # cancelling each one keeps them small as well.
    # => { unknown => value }, free unknowns standing for themselves, or nil.
    def linear_solve(conditions, unknowns)
      width = unknowns.size
      rows = conditions.map do |condition|
        row = unknowns.map { |u| Solve.polynomial_coefficients(condition, u)&.[](1) || Num.new(0) }
        row + [Simplify.negate(condition.subs(unknowns.to_h { |u| [u, Num.new(0)] })).simplify]
      end
      pivots = []
      rank = 0
      (0...width).each do |column|
        break if rank == rows.size
        found = (rank...rows.size).find { |i| !vanishes?(rows[i][column]) }
        next unless found
        rows[rank], rows[found] = rows[found], rows[rank]
        pivot = rows[rank][column]
        rows[rank] = rows[rank].map { |v| (v / pivot).cancel }
        rows.each_with_index do |row, i|
          next if i == rank || vanishes?(row[column])
          factor = row[column]
          rows[i] = row.each_with_index.map { |v, j| (v - factor * rows[rank][j]).cancel }
        end
        pivots << column
        rank += 1
      end
      return nil if rows.any? { |row| row[0...width].all? { |v| vanishes?(v) } && !vanishes?(row[width]) }
      solution = {}
      pivots.each_with_index do |column, i|
        value = rows[i][width]
        (0...width).each do |j|
          next if j == column || vanishes?(rows[i][j])
          value = (value - rows[i][j] * unknowns[j]).cancel
        end
        solution[unknowns[column]] = value
      end
      solution
    end

    def vanishes?(value)
      return true if Scalar.zero?(value)
      value.is_a?(Expression) && Scalar.zero?(value.cancel)
    rescue ZeroDivisionError
      false
    end

    # ---- the polynomial side -----------------------------------------------------

    # p(x)/q(x) = a(x)/b(x) * c(q*x)/c(x) with gcd(a(x), b(q**h*x)) = 1 for
    # every integer h >= 0.
    def normal_form(p, b, q, var = X)
      a, c = p, p.ring.one
      dispersion(a, b, q, var).each do |h|
        g = a.gcd(shift(b, q, h, var))
        next if g.constant?
        a = a.exact_div(g)
        b = b.exact_div(shift(g, q, -h, var))
        (1..h).each { |i| c *= shift(g, q, -i, var) }
      end
      [a, b, c]
    end

    # p(q**h * x), in the variable +var+ (X while q-Gosper runs, the equation's
    # own indeterminate for q-difference equations).
    def shift(poly, q, h, var = X) = poly.ring.call(poly.to_expr.subs(var => (q**h * var).simplify).expand)

    # The h >= 0 with gcd(a(x), b(q**h*x)) != 1. A shared root means
    # q**h = beta/alpha for roots alpha of a and beta of b, so h cannot
    # exceed the degree in q of the resultant of a(x) and b(y*x); within that
    # bound the gcds are simply tried.
    def dispersion(a, b, q, var = X)
      y = Var.new(:_qy)
      ring = QQ[*(a.ring.vars | [:_qy])]
      shifted = ring.call(b.to_expr.subs(var => y * var).expand)
      resultant = ring.call(a.to_expr).resultant(shifted, var.name)
      return [] if resultant.zero?
      bound = [resultant.degree(q.name), a.degree(var.name) + b.degree(var.name)].max
      (0..bound).select { |h| !a.gcd(shift(b, q, h, var)).constant? }
    rescue DomainError, NotImplementedError
      (0..(a.degree(var.name) + b.degree(var.name))).select { |h| !a.gcd(shift(b, q, h, var)).constant? }
    end

    # The degree of X in a(x)*X(q*x) - b(x/q)*X(x) = c(x): the leading terms
    # give (lc(a)*q**d - lc(b))*x**(m + d), so either they do not cancel and
    # d = deg c - m, or q**d = lc(b)/lc(a) pins d down.
    def degree_bound(a, bm, c, q)
      da, db, dc = a.degree(X.name), bm.degree(X.name), c.degree(X.name)
      candidates = [dc - [da, db].max]
      if da == db
        power = power_of_q((bm.leading_coefficient_in(X.name).to_expr / a.leading_coefficient_in(X.name).to_expr).cancel, q)
        candidates << power if power
      end
      bound = candidates.compact.max
      bound.nil? || bound.negative? ? nil : bound
    end

    # d with expr = q**d, or nil.
    def power_of_q(expr, q)
      coefficient, factors = Simplify.factorize(expr.simplify)
      return nil unless coefficient == 1 && factors.size == 1 && factors.key?(q)
      d = factors[q]
      d.is_a?(Integer) ? d : nil
    end
  end
end
