# frozen_string_literal: true

module RCAS
  # Zeilberger's algorithm (creative telescoping): the recurrence a definite
  # hypergeometric sum S(n) = sum_k F(n, k) obeys.
  #
  # Gosper's algorithm decides whether one term has an antidifference.
  # Zeilberger's runs it on a whole pencil of terms at once: it looks for
  # constants sigma_0, ..., sigma_r (free of k, rational in n) and a rational
  # R with
  #
  #   sum_j sigma_j*F(n + j, k) = G(k + 1) - G(k),   G(k) = R(k)*F(n, k),
  #
  # and then summing over k makes the right-hand side telescope away, so
  # sum_j sigma_j*S(n + j) = 0. What makes it work is that the whole thing
  # stays linear: dividing by F(n, k) leaves
  #
  #   sum_j sigma_j*a_j(k) = R(k + 1)*r(k) - R(k),
  #
  # with a_j(k) = F(n + j, k)/F(n, k) and r(k) = F(n, k + 1)/F(n, k) known
  # rational functions. Writing sum_j sigma_j*a_j = N(k)/D(k), the term ratio
  # of the pencil is r(k)*D(k)/D(k + 1) * N(k + 1)/N(k), whose
  # Gosper-Petkovsek normal form has the sigmas only in the c part: Gosper's
  # equation a(k)*X(k + 1) - b(k - 1)*X(k) = c_0(k)*N(k) is linear in the
  # coefficients of X and in the sigmas together, and one null space of one
  # matrix gives both. The order r is raised until a solution turns up.
  #
  # The telescoping identity is verified as a rational identity before it is
  # returned; the step from it to the recurrence for the sum needs natural
  # boundaries, that is F(n, k) = 0 outside the range summed over (binomial
  # coefficients give that by themselves).
  #
  # Sources (keys: MANUAL.md, Sources): [Zei91]; [Koe14, ch. 7];
  # [PWZ96, ch. 6].
  module Zeilberger
    MAX_ORDER = 4

    # The recurrence and the proof that goes with it.
    Certificate = Struct.new(:coefficients, :rational, :order, :term, :n, :k) do
      # sum_j coefficients[j]*s(n + j) as an expression, for an unknown
      # sequence named +name+.
      def recurrence(name)
        coefficients.each_with_index.map { |c, j| c * Fn.new(name, [(n + j).simplify]) }.reduce(:+).simplify
      end

      def to_s = "#{recurrence(:S)} = 0"
      def inspect = to_s
    end

    module_function

    # The recurrence for S(n) = sum_k F(n, k), as an Equation in the unknown
    # sequence +s+, which names the sum and its index: sumrecursion(F, k, S(n)).
    def sumrecursion(term, k, s, max_order: MAX_ORDER)
      n = index_of(s)
      k = Expression.lift(k)
      found = certificate(term, n, k, max_order: max_order)
      raise NotImplementedError, "sumrecursion: no recurrence of order #{max_order} or less for #{term}" if found.nil?
      if boundary_terms?(found, n, k)
        raise NotImplementedError, "sumrecursion: the telescoping identity holds for #{term}, but its " \
                                   "boundary terms do not vanish, so the sum itself does not obey the recurrence"
      end
      Equation.new(found.recurrence(s.name), Num.new(0))
    end

    # Creative telescoping proves the identity under the summation sign;
    # carrying it over to the sum needs the boundary terms to vanish, and for
    # a term such as binomial(n, k)/(k + 1), with its pole at k = -1, they do
    # not. So sum_{k=0}^{n} F(n, k) is put into the recurrence for the first
    # few n, and only a residue that is demonstrably non-zero counts against
    # it: a check that cannot be carried out says nothing either way.
    def boundary_terms?(found, n, k)
      term = found.term
      order = found.coefficients.size - 1
      (0..(order + 2)).any? do |i|
        values = (0..order).map { |j| value_at(term, n, k, Num.new(0), n, i + j) }
        next false if values.any?(&:nil?)
        total = values.each_with_index.reduce(Num.new(0)) do |acc, (value, j)|
          acc + found.coefficients[j].subs(n => i) * value
        end
        nonzero?(total)
      end
    end

    # Is this expression definitely not zero? Exactly where it can be
    # decided, at random values for whatever parameters are left otherwise.
    def nonzero?(value)
      simplified = value.simplify
      return false if Scalar.zero?(simplified)
      names = simplified.variables.to_a
      return !Scalar.zero?(simplified.cancel) if names.empty?
      random = Random.new(20140610)
      3.times do
        point = names.to_h { |v| [v, random.rand(3..29)] }
        number = simplified.evalf(**point)
        next unless number.is_a?(Numeric) && number.finite?
        return true if number.abs > 1e-9 * [1, number.abs].max
        return false
      end
      false
    rescue ZeroDivisionError, DomainError, ArgumentError, TypeError
      false
    end

    # The certificate that proves it: the rational R with
    # sum_j sigma_j*F(n + j, k) = G(k + 1) - G(k) and G(k) = R(k)*F(n, k).
    def sumcertificate(term, k, s, max_order: MAX_ORDER)
      n = index_of(s)
      k = Expression.lift(k)
      found = certificate(term, n, k, max_order: max_order)
      raise NotImplementedError, "sumcertificate: no recurrence of order #{max_order} or less for #{term}" if found.nil?
      found.rational
    end

    def index_of(s)
      raise ArgumentError, "name the sum and its index, e.g. S(n)" unless s.is_a?(Fn) && s.args.size == 1
      n = s.args.first
      raise ArgumentError, "the index must be a symbol, got #{n}" unless n.is_a?(Var)
      n
    end

    # => Certificate, or nil when no recurrence of order <= max_order exists.
    def certificate(term, n, k, max_order: MAX_ORDER)
      term = Expression.lift(term).simplify
      n = Expression.lift(n)
      k = Expression.lift(k)
      in_k = Summation.term_ratio(term, k)&.first or return nil
      in_n = Summation.term_ratio(term, n)&.first or return nil
      (1..max_order).each do |order|
        found = attempt(term, n, k, in_k, in_n, order)
        return found if found
      end
      nil
    end

    # The closed form of S(n) = sum_k F(n, k) between bounds that are natural
    # boundaries: the recurrence creative telescoping gives, solved with as
    # many initial values as its order and checked against direct summation.
    # nil when any of that fails, so the sum stays unevaluated instead of
    # coming out wrong.
    def closed_form(term, n, k, from, to, max_order: 2)
      found = certificate(term, n, k, max_order: max_order) or return nil
      order = found.coefficients.size - 1
      return nil if order.zero?
      init = {}
      (0...order).each do |i|
        value = value_at(term, n, k, from, to, i) or return nil
        init[i] = value
      end
      equation = Equation.new(found.recurrence(:_S), Num.new(0))
      closed = Recurrence.rsolve(equation, :_S, n, init: init).rhs
      return nil if closed.variables.any? { |v| v.to_s.start_with?("C") } # constants left unfixed
      confirmed?(closed, term, n, k, from, to, order) ? closed.simplify : nil
    rescue NotImplementedError, ArgumentError, DomainError, ZeroDivisionError
      nil
    end

    CONFIRMATIONS = 3

    # sum_k F(i, k) for one concrete i, added up term by term.
    def value_at(term, n, k, from, to, i)
      bounds = [from, to].map { |bound| bound.subs(n => i).simplify }
      return nil unless bounds.all? { |b| b.is_a?(Num) && b.value.is_a?(Integer) }
      Summation.direct_sum(term.subs(n => i), k, *bounds)
    rescue ZeroDivisionError, DomainError
      nil
    end

    # The closed form has to agree with the sum itself past the values that
    # were fitted: a recurrence derived for natural boundaries says nothing
    # about a sum whose boundary terms do not vanish.
    def confirmed?(closed, term, n, k, from, to, order)
      (order..(order + CONFIRMATIONS)).all? do |i|
        expected = value_at(term, n, k, from, to, i)
        next true if expected.nil?
        actual = closed.subs(n => i).simplify
        Scalar.zero?((expected - actual).simplify)
      end
    end

    # One order: build Gosper's equation for the pencil and solve it.
    def attempt(term, n, k, in_k, in_n, order)
      sigmas = (0..order).map { |j| Var.new(:"_z#{j}") }
      base = [k.name, n.name] | term.variables.to_a
      ring = QQ[*base]
      big = QQ[*(base + sigmas.map(&:name))]

      shifted = [Num.new(1)]
      (1...(order + 1)).each { |j| shifted << (shifted.last * in_n.subs(n => n + j - 1)).cancel }
      fractions = shifted.map { |a| Fraction.as_fraction(a, base) or return nil }
      denominator = fractions.map(&:last).reduce(ring.one) { |acc, q| acc.lcm(q) }
      numerators = fractions.map { |(p, q)| p * denominator.exact_div(q) }
      pencil = sigmas.each_with_index.reduce(big.zero) do |acc, (s, j)|
        acc + big.call(s) * numerators[j].to_ring(big)
      end
      return nil if pencil.zero?

      pair = Fraction.as_fraction(in_k, base) or return nil
      p = pair.first * denominator
      q = pair.last * Summation.shift(denominator, k, 1)
      common = p.gcd(q)
      p = p.exact_div(common)
      q = q.exact_div(common)
      a, b, c0 = Summation.normal_form(p, q, k)
      bm = Summation.shift(b, k, -1)
      c = c0.to_ring(big) * pencil
      bound = Summation.degree_bound(a.to_ring(big), bm.to_ring(big), c, k.name) or return nil

      xs = (0..bound).map { |i| Var.new(:"_y#{i}") }
      x_of_k = xs.each_with_index.reduce(Num.new(0)) { |acc, (x, i)| acc + x * k**i }
      equation = (a.to_expr * x_of_k.subs(k => k + 1) - bm.to_expr * x_of_k - c.to_expr).expand
      conditions = Solve.polynomial_coefficients(equation, k) or return nil
      values = solve(conditions, xs, sigmas) or return nil

      coefficients, factor = clear_denominators(sigmas.map { |s| values[s] }, n)
      return nil if coefficients.all? { |c2| Scalar.zero?(c2) }
      # The identity is linear in the sigmas, so the certificate is scaled
      # by whatever clearing the denominators scaled them by.
      rational = certificate_of(values, xs, factor, bm, c0, denominator, k, ring)
      found = Certificate.new(coefficients, rational, order, term, n, k)
      verify(found, in_k, shifted) ? found : nil
    rescue DomainError, NotImplementedError, ZeroDivisionError
      nil
    end

    # R(k) = factor*b(k - 1)*X(k) / (c_0(k)*D(k)), kept in the polynomial ring
    # and reduced once at the end: assembling it as an expression and
    # cancelling that costs minutes on a sum of three binomial cubes,
    # because the common denominator is built up by multiplication.
    def certificate_of(values, xs, factor, bm, c0, denominator, k, ring)
      pairs = xs.map { |x| Fraction.as_fraction(values[x], ring.vars) || [ring.call(values[x]), ring.one] }
      common = pairs.map(&:last).reduce(ring.one) { |acc, d| acc.lcm(d) }
      numerator = pairs.each_with_index.reduce(ring.zero) do |acc, ((p, q), i)|
        acc + p * common.exact_div(q) * ring.call(k**i)
      end
      num = ring.call(factor) * bm.to_ring(ring) * numerator
      den = c0.to_ring(ring) * denominator.to_ring(ring) * common
      shared = num.gcd(den)
      num = num.exact_div(shared)
      den = den.exact_div(shared)
      den.constant? ? (num.to_expr / den.to_expr).simplify : num.to_expr / den.to_expr
    end

    # A null space vector of the homogeneous system in which not every sigma
    # is zero: that is the recurrence. Vectors with all sigmas zero only say
    # that Gosper's equation itself has a solution and are of no use here.
    #
    # The coefficients are polynomials in n, so PolyMatrix does the kernel by
    # evaluation and interpolation; row reduction over the rational functions
    # themselves swells the entries badly (an order-2 system was still
    # running after a minute).
    def solve(conditions, xs, sigmas)
      unknowns = xs + sigmas
      rows = conditions.map do |condition|
        unknowns.map { |u| Solve.polynomial_coefficients(condition, u)&.[](1) || Num.new(0) }
      end
      vectors = PolyMatrix.kernel(rows) || row_reduce(conditions, unknowns)
      vectors.each do |vector|
        values = unknowns.each_with_index.to_h { |u, i| [u, vector[i]] }
        next if sigmas.all? { |s| Scalar.zero?(values[s]) }
        return values
      end
      nil
    end

    # The same kernel by plain row reduction, for coefficients PolyMatrix
    # will not take (a second parameter beside n).
    def row_reduce(conditions, unknowns)
      solution = Solve.linear_system(conditions, unknowns).first or return []
      free = unknowns - solution.keys
      free.map do |one|
        assignment = free.to_h { |v| [v, Num.new(v == one ? 1 : 0)] }
        unknowns.map { |v| (solution[v] || v).subs(assignment).cancel }
      end
    end

    # The sigmas come out of the linear algebra as rational functions of n;
    # the recurrence reads better with polynomial coefficients, so multiply
    # by the common denominator and drop the content. Returns the
    # coefficients and the factor they were multiplied by.
    def clear_denominators(coefficients, n)
      vars = coefficients.flat_map { |c| c.variables.to_a }.uniq | [n.name]
      ring = QQ[*vars]
      common = ring.one
      coefficients.each do |c|
        pair = Fraction.as_fraction(c, vars) or return [coefficients, Num.new(1)]
        common = common.lcm(pair.last)
      end
      polynomials = coefficients.map { |c| ring.call((c * common.to_expr).cancel.expand) }
      factor = common
      content = polynomials.reduce(ring.zero) { |acc, poly| acc.gcd(poly) }
      unless content.zero? || content.constant?
        polynomials = polynomials.map { |poly| poly.exact_div(content) }
        factor = factor.exact_div(content)
      end
      polynomials, scale = integral(polynomials)
      factor *= scale
      if negative?(polynomials)
        polynomials = polynomials.map { |poly| -poly }
        factor = -factor
      end
      [polynomials.map(&:to_expr), factor.to_expr]
    rescue DomainError, NotImplementedError, ZeroDivisionError
      [coefficients, Num.new(1)]
    end

    # Integer coefficients without a common divisor: over the rationals the
    # gcd above is monic and leaves 2*n + 4, n/2 alone.
    def integral(polynomials)
      numbers = polynomials.flat_map { |poly| poly.terms.values }.grep(Num).map(&:value).grep(Numeric)
      return [polynomials, polynomials.first.ring.one] unless numbers.all? { |v| v.is_a?(Integer) || v.is_a?(Rational) }
      scale = numbers.reduce(1) { |l, v| l.lcm(v.is_a?(Rational) ? v.denominator : 1) }
      divisor = numbers.map { |v| (v * scale).to_i.abs }.reduce(0) { |g, v| g.gcd(v) }
      divisor = 1 if divisor.zero?
      value = Rational(scale, divisor)
      return [polynomials, polynomials.first.ring.one] if value == 1
      [polynomials.map { |poly| poly * value }, Polynomial.constant(polynomials.first.ring, value)]
    end

    # Does the highest coefficient carry a minus sign?
    def negative?(polynomials)
      lead = polynomials.reverse.find { |poly| !poly.zero? }&.leading_coefficient
      lead.is_a?(Num) && lead.value.is_a?(Numeric) && lead.value.real? && lead.value.negative?
    end

    CHECKS = 4

    # sum_j sigma_j*a_j(k) = R(k + 1)*r(k) - R(k). The linear algebra behind
    # the certificate is exact and PolyMatrix checks its own kernel vectors,
    # so this is a check on the derivation rather than on the arithmetic:
    # both sides are rational, and they are compared at exact rational
    # points, which is far cheaper than a normal form of the difference.
    def verify(found, in_k, shifted)
      k = found.k
      left = shifted.each_with_index.reduce(Num.new(0)) { |acc, (a, j)| acc + found.coefficients[j] * a }
      difference = left - (found.rational.subs(k => k + 1) * in_k - found.rational)
      names = difference.variables.to_a
      random = Random.new(20140610) # the book's publication date, for a stable seed
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
        break if checked >= CHECKS
      end
      checked >= CHECKS
    end
  end
end
