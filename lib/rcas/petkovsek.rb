# frozen_string_literal: true

module RCAS
  # Petkovsek's algorithm: the hypergeometric solutions of a linear
  # recurrence with polynomial coefficients,
  #
  #   p_0(n)*u(n) + p_1(n)*u(n + 1) + ... + p_r(n)*u(n + r) = 0.
  #
  # A hypergeometric term is one whose ratio u(n + 1)/u(n) is rational, and
  # Petkovsek's theorem says every such ratio solving the recurrence can be
  # written
  #
  #   u(n + 1)/u(n) = z * a(n)/b(n) * c(n + 1)/c(n)
  #
  # with a, b monic, gcd(a(n), b(n + h)) = 1 for every integer h >= 0,
  # a(n) | p_0(n), b(n) | p_r(n + r - 1), z a constant and c a polynomial.
  # That turns an infinite search into a finite one: run through the monic
  # divisors a and b, read the possible z off the leading coefficients (the
  # top-degree terms have to cancel), and look for c with PolyRecurrence.
  # Every candidate is verified on the ratio before it is returned.
  #
  # Sources (keys: MANUAL.md, Sources): [Pet92]; [Koe14, ch. 9];
  # [PWZ96, ch. 8].
  module Petkovsek
    MAX_DIVISORS = 64

    module_function

    # The ratios u(n + 1)/u(n) of the hypergeometric solutions, as rational
    # functions of n.
    def ratios(coeffs, n)
      coeffs = coeffs.map { |c| Expression.lift(c).expand }
      r = coeffs.size - 1
      return [] if r < 1 || Scalar.zero?(coeffs.first) || Scalar.zero?(coeffs.last)
      ring = ring_for(coeffs, n) or return []
      last = ring.call(coeffs.last.subs(n => n + r - 1).expand)
      found = []
      divisors(ring.call(coeffs.first)).each do |a|
        divisors(last).each do |b|
          next unless Summation.dispersion(a, b, n.name).empty?
          candidates(coeffs, a, b, n, r).each do |ratio|
            found << ratio unless found.any? { |f| Scalar.zero?((f - ratio).cancel) }
          end
        end
      end
      found
    rescue DomainError, NotImplementedError, ZeroDivisionError
      []
    end

    # The solutions themselves: the ratios turned back into terms, in closed
    # form wherever the product has one (factorials, powers, rationals).
    def solutions(coeffs, n) = ratios(coeffs, n).map { |ratio| term(ratio, n) }

    # The term with the given ratio, as a product from the first index at
    # which the ratio is defined and non-zero.
    def term(ratio, n)
      i = Var.new(:_i)
      Products.product(ratio.subs(n => i), i, Num.new(start_index(ratio, n)), (n - 1).simplify)
    end

    # ---- the search --------------------------------------------------------------

    # The (a, b) pair fixes A_j = a(n)...a(n + j - 1) and B_j = b(n + j)...
    # b(n + r - 1); what is left is z and the polynomial c in
    # sum_j p_j(n) z**j A_j(n) B_j(n) c(n + j) = 0.
    def candidates(coeffs, a, b, n, r)
      base = (0..r).map do |j|
        aj = (0...j).reduce(Num.new(1)) { |acc, i| acc * shift(a, n, i) }
        bj = (j...r).reduce(Num.new(1)) { |acc, i| acc * shift(b, n, i) }
        (coeffs[j] * aj * bj).expand
      end
      zs(base, n, r).flat_map do |z|
        qs = base.each_with_index.map { |q, j| (q * z**j).expand }
        PolyRecurrence.basis(qs, n).filter_map do |c|
          ratio = (z * a.to_expr * c.subs(n => n + 1) / (b.to_expr * c)).cancel
          ratio if satisfies?(coeffs, ratio, n, r)
        end
      end
    end

    # The constants z for which the top-degree terms of the transformed
    # equation can cancel: the roots of sum_{j in J} lc(q_j)*z**j, where J
    # collects the j of maximal degree.
    def zs(base, n, r)
      degrees = base.map { |q| Solve.polynomial_coefficients(q, n)&.size }
      return [] if degrees.any?(&:nil?)
      top = degrees.each_index.select { |j| degrees[j] == degrees.max }
      return [] if top.size < 2 # one term alone cannot cancel
      coefficients = Array.new(r + 1) { Num.new(0) }
      top.each { |j| coefficients[j] = Solve.polynomial_coefficients(base[j], n).last }
      Solve.polynomial_roots(coefficients).map(&:simplify)
           .reject { |z| Scalar.zero?(z) || z.is_a?(RootOf) }
           .uniq { |z| z.to_s }
    rescue NotImplementedError, DomainError
      []
    end

    # Does a term with this ratio satisfy the recurrence? Checked as a
    # rational identity: sum_j p_j(n) * ratio(n)*...*ratio(n + j - 1) = 0.
    def satisfies?(coeffs, ratio, n, r)
      total = Num.new(0)
      product = Num.new(1)
      (0..r).each do |j|
        total += coeffs[j] * product
        product = (product * ratio.subs(n => n + j)).cancel if j < r
      end
      Scalar.zero?(total.cancel)
    rescue ZeroDivisionError
      false
    end

    # ---- polynomials -------------------------------------------------------------

    def ring_for(coeffs, n)
      vars = coeffs.flat_map { |c| c.variables.to_a }.uniq
      vars = [n.name] | vars
      QQ[*vars]
    end

    def shift(poly, n, h) = poly.to_expr.subs(n => n + h)

    # Every monic divisor of +poly+, the constant 1 included.
    def divisors(poly)
      return [poly.ring.one] if poly.constant?
      factorization = poly.factor
      list = [poly.ring.one]
      factorization.factors.each do |factor, multiplicity|
        list = list.flat_map { |d| (0..multiplicity).map { |i| d * factor**i } }
        return [poly.ring.one] if list.size > MAX_DIVISORS
      end
      list.map(&:monic).uniq { |d| d.to_expr.to_s }
    rescue NotImplementedError, DomainError
      [poly.ring.one]
    end

    # The first index from which the product of the ratio is finite and
    # non-zero: past every non-negative integer root of numerator and
    # denominator.
    def start_index(ratio, n)
      pair = Fraction.as_fraction(ratio, [n.name]) or return 0
      roots = pair.flat_map do |poly|
        coefficients = (0..poly.degree(n.name)).map { |i| poly.coefficient_in(n.name, i).to_expr }
        next [] unless coefficients.all? { |c| c.variables.empty? }
        Solve.polynomial_roots(coefficients)
      end
      integers = roots.filter_map { |r| r.simplify }
                      .select { |r| r.is_a?(Num) && r.value.is_a?(Integer) && !r.value.negative? }
                      .map(&:value)
      integers.empty? ? 0 : integers.max + 1
    rescue NotImplementedError, DomainError, ZeroDivisionError
      0
    end
  end
end
