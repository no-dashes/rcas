# frozen_string_literal: true

module RCAS
  # q-Zeilberger: creative telescoping in the q-world.
  #
  # For a term F(n, k) that is q-hypergeometric in both indices it finds
  # coefficients sigma_j, rational in q**n, and a rational R with
  #
  #   sum_j sigma_j*F(n + j, k) = G(k + 1) - G(k),   G(k) = R(q**k)*F(n, k),
  #
  # so that sum_j sigma_j*S(n + j) = 0 for S(n) = sum_k F(n, k) over natural
  # boundaries. It is Zeilberger's algorithm with q-Gosper inside: with
  # x = q**k and y = q**n, the shift in k is x -> q*x and the shift in n is
  # y -> q*y, and the pencil's Gosper equation
  #
  #   a(x)*X(q*x) - b(x/q)*X(x) = c_0(x)*N(x)
  #
  # is again linear in the coefficients of X and the sigmas together.
  #
  # Sources (keys: MANUAL.md, Sources): [Koe14, ch. 12]; [Zei91] for the
  # method; [GR04] for the notation.
  module QZeilberger
    MAX_ORDER = 2 # the q-world's coefficients are bigger; ask for more with max_order:
    X = QSummation::X   # q**k
    Y = Var.new(:_qy1)  # q**n

    Certificate = Struct.new(:coefficients, :rational, :order, :term, :n, :k, :q) do
      def recurrence(name)
        coefficients.each_with_index.map { |c, j| c * Fn.new(name, [(n + j).simplify]) }.reduce(:+).simplify
      end

      def to_s = "#{recurrence(:S)} = 0"
      def inspect = to_s
    end

    module_function

    # The recurrence for S(n) = sum_k F(n, k), as an Equation in +s+ = S(n).
    def qsumrecursion(term, k, q, s, max_order: MAX_ORDER)
      n = Zeilberger.index_of(s)
      k = Expression.lift(k)
      found = certificate(term, n, k, q, max_order: max_order)
      raise NotImplementedError, "qsumrecursion: no recurrence of order #{max_order} or less for #{term}" if found.nil?
      if boundary_terms?(found, n, k)
        raise NotImplementedError, "qsumrecursion: the telescoping identity holds for #{term}, but its " \
                                   "boundary terms do not vanish, so the sum itself does not obey the recurrence"
      end
      Equation.new(found.recurrence(s.name), Num.new(0))
    end

    # The certificate: R with sum_j sigma_j*F(n + j, k) = Delta_k(R*F).
    def qsumcertificate(term, k, q, s, max_order: MAX_ORDER)
      n = Zeilberger.index_of(s)
      k = Expression.lift(k)
      found = certificate(term, n, k, q, max_order: max_order)
      raise NotImplementedError, "qsumcertificate: no recurrence of order #{max_order} or less for #{term}" if found.nil?
      found.rational
    end

    # => Certificate or nil.
    def certificate(term, n, k, q, max_order: MAX_ORDER)
      term = Expression.lift(term).simplify
      n = Expression.lift(n)
      k = Expression.lift(k)
      q = Expression.lift(q)
      in_k = ratio_in(term, k, q, n, X) or return nil
      in_n = ratio_in(term, n, q, k, Y) or return nil
      (1..max_order).each do |order|
        found = attempt(term, n, k, q, in_k, in_n, order)
        return found if found
      end
      nil
    end

    # The ratio in +v+ as a rational function of X and Y: the powers of the
    # other index have to become the other variable too.
    def ratio_in(term, v, q, other, target)
      value = QSummation.ratio(term, v, q) or return nil
      value = value.subs(X => target) unless target == X
      QSummation.powers_in(value, other, q, target == X ? Y : X)
    end

    def attempt(term, n, k, q, in_k, in_n, order)
      sigmas = (0..order).map { |j| Var.new(:"_qz#{j}") }
      base = [X.name, Y.name, q.name] | term.variables.to_a.reject { |v| [n.name, k.name].include?(v) }
      ring = QQ[*base]
      big = QQ[*(base + sigmas.map(&:name))]

      shifted = [Num.new(1)]
      (1..order).each { |j| shifted << (shifted.last * in_n.subs(Y => (q**(j - 1) * Y).simplify)).cancel }
      fractions = shifted.map { |a| Fraction.as_fraction(a, base) or return nil }
      denominator = fractions.map(&:last).reduce(ring.one) { |acc, d| acc.lcm(d) }
      numerators = fractions.map { |(p, d)| p * denominator.exact_div(d) }
      pencil = sigmas.each_with_index.reduce(big.zero) do |acc, (s, j)|
        acc + big.call(s) * numerators[j].to_ring(big)
      end
      return nil if pencil.zero?

      pair = Fraction.as_fraction(in_k, base) or return nil
      p = pair.first * denominator
      d = pair.last * QSummation.shift(denominator, q, 1)
      common = p.gcd(d)
      p = p.exact_div(common)
      d = d.exact_div(common)
      a, b, c0 = QSummation.normal_form(p, d, q)
      bm = QSummation.shift(b, q, -1)
      c = c0.to_ring(big) * pencil
      bound = QSummation.degree_bound(a.to_ring(big), bm.to_ring(big), c, q) or return nil

      xs = (0..bound).map { |i| Var.new(:"_qw#{i}") }
      poly = xs.each_with_index.reduce(Num.new(0)) { |acc, (v, i)| acc + v * X**i }
      equation = (a.to_expr * poly.subs(X => (q * X).simplify) - bm.to_expr * poly - c.to_expr).expand
      conditions = Solve.polynomial_coefficients(equation, X) or return nil
      values = solve(conditions, xs, sigmas) or return nil

      coefficients, factor = clear_denominators(sigmas.map { |s| values[s] }, q)
      return nil if coefficients.all? { |value| Scalar.zero?(value) }
      rational = (factor * bm.to_expr * poly.subs(values) / (c0.to_expr * denominator.to_expr)).cancel
      found = Certificate.new(coefficients.map { |value| value.subs(Y => q**n).simplify },
                              rational.subs(Y => q**n, X => q**k).simplify, order, term, n, k, q)
      verify(coefficients, rational, in_k, shifted, q) ? found : nil
    rescue DomainError, NotImplementedError, ZeroDivisionError
      nil
    end

    # As in the ordinary case: the recurrence carries over to the sum only
    # when the boundary terms vanish, so sum_{k=0}^{n} F(n, k) is put into it
    # for the first few n and a residue that is demonstrably non-zero counts
    # against it.
    def boundary_terms?(found, n, k)
      order = found.coefficients.size - 1
      (0..(order + 2)).any? do |i|
        values = (0..order).map { |j| Zeilberger.value_at(found.term, n, k, Num.new(0), n, i + j) }
        next false if values.any?(&:nil?)
        total = values.each_with_index.reduce(Num.new(0)) do |acc, (value, j)|
          acc + found.coefficients[j].subs(n => i) * value
        end
        Zeilberger.nonzero?(total)
      end
    end

    # A null space vector in which not every sigma vanishes.
    def solve(conditions, xs, sigmas)
      unknowns = xs + sigmas
      solution = QSummation.linear_solve(conditions, unknowns) or return nil
      free = unknowns - solution.keys
      free.each do |one|
        assignment = free.to_h { |v| [v, Num.new(v == one ? 1 : 0)] }
        values = unknowns.to_h { |v| [v, (solution[v] || v).subs(assignment).cancel] }
        next if sigmas.all? { |s| QSummation.vanishes?(values[s]) }
        return values
      end
      nil
    end

    # Coefficients rational in q**n cleared to polynomials, with the factor
    # they were multiplied by (the certificate is scaled the same way).
    def clear_denominators(coefficients, q)
      vars = [Y.name, q.name] | coefficients.flat_map { |c| c.variables.to_a }
      ring = QQ[*vars]
      common = ring.one
      coefficients.each do |c|
        pair = Fraction.as_fraction(c, vars) or return [coefficients, Num.new(1)]
        common = common.lcm(pair.last)
      end
      polynomials = coefficients.map { |c| ring.call((c * common.to_expr).cancel.expand) }
      content = polynomials.reduce(ring.zero) { |acc, poly| acc.gcd(poly) }
      factor = common
      unless content.zero? || content.constant?
        polynomials = polynomials.map { |poly| poly.exact_div(content) }
        factor = factor.exact_div(content)
      end
      [polynomials.map(&:to_expr), factor.to_expr]
    rescue DomainError, NotImplementedError, ZeroDivisionError
      [coefficients, Num.new(1)]
    end

    # sum_j sigma_j*a_j(x) = R(q*x)*r(x) - R(x), at exact points.
    def verify(coefficients, rational, in_k, shifted, q)
      left = shifted.each_with_index.reduce(Num.new(0)) { |acc, (a, j)| acc + coefficients[j] * a }
      difference = left - (rational.subs(X => (q * X).simplify) * in_k - rational)
      names = difference.variables.to_a
      random = Random.new(20140610)
      checked = 0
      40.times do
        point = names.to_h { |v| [v, Num.new(Rational(random.rand(5..97), random.rand(2..7)))] }
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
  end
end
