# frozen_string_literal: true

module RCAS
  # Polynomial solutions of a linear recurrence with polynomial coefficients,
  #
  #   q_0(n)*c(n) + q_1(n)*c(n + 1) + ... + q_r(n)*c(n + r) = 0,
  #
  # the subroutine Petkovsek's algorithm rests on. The whole difficulty is
  # bounding the degree of c, and the bound is Abramov's: write the operator
  # in the difference basis, L = sum_i w_i(n)*Delta**i with Delta = N - 1 and
  # w_i = sum_j binomial(j, i)*q_j. Delta**i lowers the degree by exactly i,
  # so with
  #
  #   m    = max_i (deg w_i - i)
  #   P(d) = sum of lc(w_i)*d*(d - 1)*...*(d - i + 1) over the i that reach m
  #
  # a candidate c of degree d gives deg L(c) = d + m whenever P(d) != 0.
  # A solution of L(c) = 0 therefore needs P(d) = 0, and an inhomogeneous
  # right-hand side needs d + m = deg(rhs); the bound is the largest of those.
  #
  # Sources (keys: MANUAL.md, Sources): [Koe14, ch. 9], [PWZ96, ch. 8].
  module PolyRecurrence
    module_function

    # A basis of the polynomial solutions of the homogeneous equation, as
    # expressions in +n+; [] when the only one is zero.
    def basis(coeffs, n)
      solutions(coeffs, n).last
    end

    # [particular, basis] for L(c) = rhs (rhs nil or 0: [0, basis]), or
    # [nil, []] when there is no polynomial solution.
    def solutions(coeffs, n, rhs = nil)
      homogeneous = rhs.nil? || Scalar.zero?(rhs)
      d = degree_bound(coeffs, n, rhs)
      return [nil, []] if d.nil? || d.negative?
      xs = (0..d).map { |i| Var.new(:"_p#{i}") }
      c = xs.each_with_index.reduce(Num.new(0)) { |acc, (x, i)| acc + x * n**i }
      residual = apply(coeffs, c, n)
      residual -= rhs unless homogeneous
      conditions = Solve.polynomial_coefficients(residual.expand, n) or return [nil, []]
      solution = Solve.linear_system(conditions, xs).first or return [nil, []]
      general = c.subs(solution)
      free = xs - solution.keys
      particular = homogeneous ? Num.new(0) : pick(general, free, nil) || Num.new(0)
      # With a right-hand side each choice of the free constants carries the
      # particular solution with it; the difference is the homogeneous part.
      [particular, free.filter_map { |f| difference(pick(general, free, f), particular) }]
    end

    # L(c) with c substituted: sum_j q_j(n)*c(n + j).
    def apply(coeffs, c, n)
      coeffs.each_with_index.reduce(Num.new(0)) { |acc, (q, j)| acc + q * c.subs(n => n + j) }.simplify
    end

    # The largest degree a polynomial solution can have, or nil for none.
    def degree_bound(coeffs, n, rhs = nil)
      tops = leading_terms(coeffs, n) or return nil
      return nil if tops.empty?
      m = tops.map { |(i, degree, _)| degree - i }.max
      d = Var.new(:_d)
      indicial = tops.select { |(i, degree, _)| degree - i == m }
                     .reduce(Num.new(0)) { |acc, (i, _, lc)| acc + lc * falling(d, i) }
      bounds = integer_roots(indicial, d)
      unless rhs.nil? || Scalar.zero?(rhs)
        cs = Solve.polynomial_coefficients(rhs.expand, n) or return nil
        bounds += [cs.size - 1 - m]
      end
      bounds.max
    end

    # [index, degree, leading coefficient] of every non-zero w_i.
    def leading_terms(coeffs, n)
      delta_coefficients(coeffs).each_with_index.filter_map do |w, i|
        cs = Solve.polynomial_coefficients(w.expand, n) or return nil
        next nil if cs.all? { |c| Scalar.zero?(c) }
        [i, cs.size - 1, cs.last]
      end
    end

    # w_i = sum_j binomial(j, i)*q_j: the operator in the difference basis.
    def delta_coefficients(coeffs)
      r = coeffs.size - 1
      (0..r).map do |i|
        (i..r).reduce(Num.new(0)) { |acc, j| acc + Num.new(choose(j, i)) * coeffs[j] }.simplify
      end
    end

    def choose(n, k) = (0...k).reduce(1) { |acc, i| acc * (n - i) / (i + 1) }

    # d*(d - 1)*...*(d - i + 1)
    def falling(d, i) = (0...i).reduce(Num.new(1)) { |acc, s| acc * (d - s) }

    def integer_roots(poly, d)
      coeffs = Solve.polynomial_coefficients(poly.expand, d) or return []
      return [] if coeffs.size < 2 # a non-zero constant has no roots
      Solve.polynomial_roots(coeffs)
           .filter_map { |r| r.simplify }
           .select { |r| r.is_a?(Num) && r.value.is_a?(Integer) && !r.value.negative? }
           .map(&:value).uniq
    rescue NotImplementedError, RCAS::Unsupported, DomainError
      []
    end

    # One member of the solution space: +free+ all zero but +one+, which is 1.
    def pick(general, free, one)
      value = general.subs(free.to_h { |v| [v, Num.new(v == one ? 1 : 0)] }).simplify
      Scalar.zero?(value) ? nil : value
    end

    def difference(solution, particular)
      return nil if solution.nil?
      value = (solution - particular).simplify
      Scalar.zero?(value) ? nil : value
    end
  end
end
