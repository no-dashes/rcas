# frozen_string_literal: true

module RCAS
  # D(y, x, n): the n-th derivative of an unknown function y of x, used to
  # write differential equations.
  class Derivative < Expression
    attr_reader :expr, :var, :order

    def initialize(expr, var, order = 1)
      @expr = Expression.lift(expr)
      @var = Expression.lift(var)
      @order = order
      freeze
    end

    def children = [expr, var]
    def rebuild(expr, var) = Derivative.new(expr, var, order)
    def ==(other) = other.is_a?(Derivative) && other.order == order && other.children == children
    alias eql? ==
    def hash = [Derivative, order, expr, var].hash
    def to_sexp = [:D, expr.to_sexp, var.to_sexp, order]
  end

  # Ordinary differential equations:
  #
  #   dsolve(eq(D(y, x), 2*x*y), y, x)              # separable
  #   dsolve(eq(D(y, x) + 2*y, exp(x)), y, x)       # first-order linear
  #   dsolve(D(y, x, 2) - 3*D(y, x) + 2*y, y, x)    # constant coefficients
  #   dsolve(eq(D(y, x, 2) + y, x*exp(x)), y, x)    # non-homogeneous, any order
  #
  # Returns Equation(s) y = ... with constants C1, C2 (or an implicit
  # equation when the separable case cannot be solved for y).
  #
  # Source: the textbook methods of [BD12]: separation of variables and
  # the integrating factor (ch. 2), characteristic roots, undetermined
  # coefficients and variation of parameters (ch. 3-4) (keys: MANUAL.md,
  # Sources).
  module ODE
    module_function

    def dsolve(equation, y, x)
      return system(equation, y, x) if equation.is_a?(Array)
      yv = Expression.lift(y)
      xv = Expression.lift(x)
      f = Solve.to_zero(equation).simplify
      order = f.each_node.select { |n| n.is_a?(Derivative) && n.expr == yv }.map(&:order).max
      raise ArgumentError, "#{equation} contains no derivative of #{yv}" if order.nil?
      case order
      when 1 then first_order(f, yv, xv)
      else constant_coefficients(f, yv, xv, order)
      end
    end

    # ---- systems, linear with constant coefficients ----------------------------
    #
    #   dsolve([eq(D(x, t), y), eq(D(y, t), -x)], [x, y], t)
    #
    # Written as u' = A u + c, the solution is a combination of exp(lambda*t)
    # times the eigenvectors of A, with a conjugate pair giving the real pair
    # exp(a*t)*(p*cos(b*t) - q*sin(b*t)) and its partner. A constant c adds the
    # steady state -A^-1 c. A defective matrix (too few eigenvectors) is
    # reported rather than guessed.
    def system(equations, unknowns, t)
      t = Expression.lift(t)
      us = Array(unknowns).map { |u| Expression.lift(u) }
      raise ArgumentError, "dsolve: #{equations.size} equations for #{us.size} unknowns" unless equations.size == us.size
      derivatives = us.map { |u| Derivative.new(u, t) }
      slots = us.each_index.map { |i| Var.new(:"_d#{i}") }        # linear_system wants variables
      pattern = derivatives.zip(slots).to_h
      flattened = equations.map { |e| Solve.to_zero(e).simplify.subs(pattern) }
      solved = Solve.linear_system(flattened, slots).first
      raise NotImplementedError, "dsolve: the system is not linear in the derivatives" if solved.nil? || solved.size != us.size

      rows = []
      forcing = []
      slots.each do |d|
        rhs = Expression.lift(solved[d]).expand
        coefficients = us.map do |u|
          c = Solve.polynomial_coefficients(rhs, u) or raise NotImplementedError, "dsolve: #{rhs} is not linear in #{u}"
          # x' = x**2 has the coefficients [0, 0, 1]: reading c[1] alone
          # solved it as x' = 0 (third review, L5)
          raise NotImplementedError, "dsolve: #{rhs} is not linear in #{u}; only linear systems are solved" if c.size > 2
          value = c[1] || Num.new(0)
          raise NotImplementedError, "dsolve: the coefficient #{value} is not constant" if Solve.depends?(value, t) || us.any? { |v| Solve.depends?(value, v) }
          value
        end
        rows << coefficients
        forcing << rhs.subs(us.to_h { |u| [u, Num.new(0)] }).simplify
      end

      matrix = MatrixSpace.new(RR, us.size, us.size).unchecked(rows)
      solutions = homogeneous_system(matrix, t)
      raise NotImplementedError, "dsolve: no solution basis found for this system" if solutions.size < us.size

      general = us.each_index.map do |i|
        solutions.each_with_index.map { |vector, k| Var.new(:"C#{k + 1}") * vector[i] }.reduce(:+)
      end
      unless forcing.all? { |c| Scalar.zero?(c) }
        steady = steady_state(matrix, forcing, t)
        general = general.each_with_index.map { |g, i| g + steady[i] }
      end
      us.each_with_index.map { |u, i| Equation.new(u, general[i].simplify) }
    end

    # One real solution vector per degree of freedom, as arrays of expressions.
    def homogeneous_system(matrix, t)
      out = []
      seen = []
      matrix.eigenvectors.each do |value, _multiplicity, vectors|
        next if seen.any? { |v| Scalar.zero?((v - value).simplify) }
        real, imaginary = ComplexParts.parts(Expression.lift(value))
        vectors.each do |vector|
          entries = vector.entries.map { |e| Expression.lift(e) }
          if Scalar.zero?(imaginary)
            out << entries.map { |e| (e * Fn.new(:exp, [value * t])).simplify }
            out.concat(jordan_chain(matrix, value, entries, _multiplicity - vectors.size, t))
          else
            seen << Simplify.simplify(real - I * imaginary) # skip the conjugate
            parts = entries.map { |e| ComplexParts.parts(e) }
            wave = Fn.new(:exp, [real * t])
            cosine = Fn.new(:cos, [imaginary * t])
            sine = Fn.new(:sin, [imaginary * t])
            out << parts.map { |p, q| (wave * (p * cosine - q * sine)).simplify }
            out << parts.map { |p, q| (wave * (p * sine + q * cosine)).simplify }
          end
        end
      end
      out
    end

    # A repeated eigenvalue with too few eigenvectors: (A - lambda)w_k = w_(k-1)
    # with w_0 = v gives the chain, and the k-th solution is
    # exp(lambda*t)*sum_j t**(k - j)/(k - j)! * w_j - every vector below it,
    # not only the one before (the third one lost v; third review, L4).
    def jordan_chain(matrix, value, vector, missing, t)
      out = []
      chain = [vector]
      while out.size < missing
        w = solve_singular(matrix, value, chain.last) or break
        chain << w
        k = chain.size - 1
        combination = w.each_index.map do |i|
          chain.each_with_index.map { |c, j| c[i] * t**(k - j) / RCAS.factorial(k - j) }.reduce(:+).simplify
        end
        out << combination.map { |e| (e * Fn.new(:exp, [value * t])).simplify }
      end
      out
    end

    # A particular solution of (A - lambda I) w = v, free variables set to zero.
    def solve_singular(matrix, value, vector)
      n = matrix.rows
      ws = (0...n).map { |i| Var.new(:"_w#{i}") }
      equations = (0...n).map do |i|
        row = (0...n).map { |j| (matrix[i, j] - (i == j ? value : Num.new(0))) * ws[j] }.reduce(:+)
        (row - vector[i]).simplify
      end
      solution = Solve.linear_system(equations, ws).first
      return nil if solution.nil?
      zeros = ws.to_h { |w| [w, Num.new(0)] }
      ws.map { |w| Expression.lift(solution[w] || Num.new(0)).subs(zeros).simplify }
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      nil
    end

    # The constant solution of u' = A u + c.
    def steady_state(matrix, forcing, t)
      raise NotImplementedError, "dsolve: a forcing term depending on #{t} is not supported for systems" if forcing.any? { |c| Solve.depends?(c, t) }
      raise NotImplementedError, "dsolve: the matrix is singular, so there is no constant solution" if Scalar.zero?(matrix.det)
      matrix.solve(forcing.map { |c| Simplify.negate(c).simplify }).entries
    end

    # ---- first order ---------------------------------------------------------

    def first_order(f, y, x)
      dy = Var.new(:_dy)
      coeffs = Solve.polynomial_coefficients(f.subs(Derivative.new(y, x) => dy), dy)
      raise NotImplementedError, "the equation must be linear in D(#{y}, #{x})" unless coeffs && coeffs.size == 2
      rhs = (-coeffs[0] / coeffs[1]).simplify # y' = rhs(x, y)
      separable(rhs, y, x) || linear(rhs, y, x) ||
        raise(NotImplementedError, "#{y}' = #{rhs} is neither separable nor linear")
    end

    # y' = g(x) * h(y)
    def separable(rhs, y, x)
      coeff, factors = Simplify.factorize(rhs)
      gx = {}
      hy = {}
      factors.each do |base, exp|
        in_y = Solve.depends?(base, y) || (exp.is_a?(Expression) && Solve.depends?(exp, y))
        in_x = Solve.depends?(base, x) || (exp.is_a?(Expression) && Solve.depends?(exp, x))
        return nil if in_x && in_y
        (in_y ? hy : gx)[base] = exp
      end
      g = Simplify.rebuild_product(coeff, gx)
      h = Simplify.rebuild_product(1, hy)
      left = Integrate.integrate(1 / h, y)
      right = Integrate.integrate(g, x)
      return nil unless Integrate.complete?(left) && Integrate.complete?(right)

      c1 = Var.new(:C1)
      implicit = (left - right - c1).simplify
      begin
        Solve.univariate(implicit, y, 1).map { |s| Equation.new(y, s.simplify) }
      rescue NotImplementedError, ArgumentError
        [Equation.new(left.simplify, (right + c1).simplify)]
      end
    end

    # y' = q(x) - p(x) * y
    def linear(rhs, y, x)
      coeffs = Solve.polynomial_coefficients(rhs, y)
      return nil unless coeffs && coeffs.size == 2
      q = coeffs[0]
      p = (-coeffs[1]).simplify
      mu = Fn.new(:exp, [Integrate.integrate(p, x)]).simplify
      integral = Integrate.integrate((q * mu).simplify, x)
      c1 = Var.new(:C1)
      [Equation.new(y, ((integral + c1) / mu).simplify)]
    end

    # ---- linear, constant coefficients, any order ----------------------------
    #
    #   a_n y^(n) + ... + a_1 y' + a_0 y = g(x)
    #
    # Homogeneous part from the roots of the characteristic polynomial (real
    # roots and conjugate pairs, with multiplicity); particular solution by
    # undetermined coefficients when g is a sum of terms
    # polynomial * exp(a x) * (cos(b x) | sin(b x)), otherwise by variation
    # of parameters for second-order equations.
    def constant_coefficients(f, y, x, n)
      ds = (0..n).map { |k| Var.new(:"_d#{k}") }
      pattern = { y => ds[0] }
      (1..n).each { |k| pattern[Derivative.new(y, x, k)] = ds[k] }
      g = f.subs(pattern)
      raise NotImplementedError, "only linear equations with constant coefficients are supported" unless Solve.linear_in?(g, ds)

      coeffs = ds.map { |d| Solve.polynomial_coefficients(g, d)[1] || Num.new(0) }
      raise ArgumentError, "no derivative of order #{n} in the equation" if Scalar.zero?(coeffs[n])
      coeffs.each do |k|
        raise NotImplementedError, "coefficient #{k} is not constant" if Solve.depends?(k, x) || Solve.depends?(k, y)
      end
      forcing = Simplify.negate(g.subs(ds.to_h { |d| [d, Num.new(0)] })).simplify

      groups = root_groups(Solve.polynomial_roots(coeffs))
      homogeneous = homogeneous_solution(groups, x)
      particular =
        if Scalar.zero?(forcing)
          Num.new(0)
        else
          undetermined_coefficients(coeffs, forcing, x) ||
            (n == 2 && variation_of_parameters(coeffs, forcing, groups, x)) ||
            raise(NotImplementedError, "no method for the forcing term #{forcing}")
        end
      [Equation.new(y, (homogeneous + particular).simplify)]
    end

    # Roots with multiplicity => [[re, im, multiplicity], ...]; im is nil when
    # the root cannot be split into real and imaginary part (symbolic
    # coefficients, RootOf); conjugate pairs are merged (im > 0) and the
    # groups ordered by their real part.
    def root_groups(roots)
      tally = []
      roots.map(&:simplify).each do |r|
        entry = tally.find { |root, _| root == r }
        entry ? entry[1] += 1 : tally << [r, 1]
      end
      groups = tally.map do |r, m|
        re, im = real_imaginary(r)
        re.nil? || Scalar.zero?(im) ? [r, nil, m] : [re, im, m]
      end
      merged = []
      until groups.empty?
        re, im, m = groups.shift
        if im
          j = groups.index { |re2, im2, m2| im2 && m2 == m && Scalar.zero?(re - re2) && Scalar.zero?(im + im2) }
          if j.nil?
            # no conjugate (complex coefficients): exp(r*x) on its own, not
            # a cos/sin pair, which would give the equation two constants
            # too many (third review, L6)
            merged << [(re + I * im).simplify, nil, m]
            next
          end
          groups.delete_at(j)
          im = Simplify.negate(im).simplify if evalf_or_nil(im).to_f.negative?
        end
        merged << [re, im, m]
      end
      # Numbering order: the zero root (C1 + C2*x) first, then by real part, symbolic roots last.
      merged.sort_by do |re, im, _|
        value = evalf_or_nil(re)
        [value ? 0 : 1, Scalar.zero?(re) ? -Float::INFINITY : value.to_f, im ? 1 : 0, im ? evalf_or_nil(im).to_f : 0.0, re.to_s]
      end
    end

    def evalf_or_nil(e)
      v = e.evalf
      v.is_a?(Numeric) && !v.is_a?(Complex) ? v : nil
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      nil
    end

    # -1 + 2*i => [-1, 2]; nil if some non-numeric factor may be complex.
    def real_imaginary(r)
      constant, table = Expand.table(r)
      re = {}
      im = {}
      table.each do |factors, coeff|
        return nil if factors.any? { |base, e| Simplify.imaginary_unit?(base) || (e.is_a?(Expression) && !e.variables.empty?) }
        re[factors] = coeff.is_a?(Complex) ? coeff.real : coeff
        im[factors] = coeff.is_a?(Complex) ? coeff.imaginary : 0
      end
      c_re = constant.is_a?(Complex) ? constant.real : constant
      c_im = constant.is_a?(Complex) ? constant.imaginary : 0
      [Simplify.rebuild_sum(c_re, re).simplify, Simplify.rebuild_sum(c_im, im).simplify]
    end

    # Sum over the root groups of C_i * x**j * exp(re x) [* cos/sin(im x)],
    # arranged the textbook way: exp(x)*(C1 + C2*x), exp(-x)*(C1*cos(2*x) + C2*sin(2*x)).
    def homogeneous_solution(groups, x)
      counter = 0
      constant = -> { counter += 1; Var.new(:"C#{counter}") }
      polynomial = ->(m) { (0...m).map { |j| j.zero? ? constant.call : constant.call * x**j }.reduce(:+) }
      groups.map do |re, im, m|
        exponential = Scalar.zero?(re) ? nil : Fn.new(:exp, [re * x])
        body = im ? polynomial.call(m) * Fn.new(:cos, [im * x]) + polynomial.call(m) * Fn.new(:sin, [im * x]) : polynomial.call(m)
        exponential ? body * exponential : body
      end.reduce(:+)
    end

    # The fundamental system as a flat list of functions.
    def fundamental_system(groups, x)
      groups.flat_map do |re, im, m|
        exponential = Scalar.zero?(re) ? Num.new(1) : Fn.new(:exp, [re * x])
        (0...m).flat_map do |j|
          base = x**j * exponential
          im ? [base * Fn.new(:cos, [im * x]), base * Fn.new(:sin, [im * x])] : [base]
        end
      end
    end

    def apply_operator(coeffs, u, x)
      coeffs.each_with_index.map { |a, k| a * u.diff(x, k) }.reduce(:+)
    end

    # Undetermined coefficients [BD12, §3.5, §4.3]: the forcing term is sorted
    # into classes (a, b) with a term x**k * exp(a x) * cos/sin(b x); the ansatz
    # for a class is x**m * (A_0 + ... + A_d x**d) * exp(a x) * (cos, sin)
    # where m is the multiplicity of a + i b as a characteristic root.
    def undetermined_coefficients(coeffs, forcing, x)
      classes = forcing_classes(forcing, x) or return nil
      r = Var.new(:_r)
      characteristic = coeffs.each_with_index.map { |a, k| a * r**k }.reduce(:+)
      unknowns = []
      new_unknown = -> { unknowns << Var.new(:"_A#{unknowns.size}"); unknowns.last }
      ansatz = classes.map do |(a, b), degree|
        m = root_multiplicity(characteristic, r, Scalar.zero?(b) ? a : a + I * b)
        polynomial = -> { (0..degree).map { |k| new_unknown.call * x**(k + m) }.reduce(:+) }
        exponential = Scalar.zero?(a) ? Num.new(1) : Fn.new(:exp, [a * x])
        if Scalar.zero?(b)
          polynomial.call * exponential
        else
          (polynomial.call * Fn.new(:cos, [b * x]) + polynomial.call * Fn.new(:sin, [b * x])) * exponential
        end
      end.reduce(:+)
      residual = (apply_operator(coeffs, ansatz, x) - forcing).expand
      equations = collect_by_function(residual, unknowns, x)
      solution = Solve.linear_system(equations, unknowns).first or return nil
      unknowns.each { |u| solution[u] ||= Num.new(0) }
      ansatz.subs(solution).simplify
    end

    # { [a, b] => degree } for a forcing term in the class of the method; nil otherwise.
    def forcing_classes(forcing, x)
      constant, terms = Simplify.termize(forcing, simplify: true)
      classes = {}
      add = lambda do |a, b, degree|
        key = classes.keys.find { |a2, b2| Scalar.zero?(a - a2) && (Scalar.zero?(b - b2) || Scalar.zero?(b + b2)) }
        key ||= [a, b]
        classes[key] = [classes[key] || 0, degree].max
      end
      add.call(Num.new(0), Num.new(0), 0) unless constant.zero?
      terms.each_key do |factors|
        a = Num.new(0)
        b = Num.new(0)
        degree = 0
        factors.each do |base, e|
          if base == x
            return nil unless e.is_a?(Integer) && e >= 0
            degree += e
          elsif base == Simplify.exp_base
            _, slope = linear_coefficients(Expression.lift(e), x)
            return nil unless slope
            a = (a + slope).simplify
          elsif base.is_a?(Fn) && %i[cos sin].include?(base.name) && e == 1 && Solve.depends?(base, x)
            offset, slope = linear_coefficients(base.args.first, x)
            return nil unless slope && Scalar.zero?(offset) && Scalar.zero?(b)
            b = slope
          elsif Solve.depends?(base, x) || (e.is_a?(Expression) && Solve.depends?(e, x))
            return nil
          end
        end
        add.call(a, b, degree)
      end
      classes
    end

    # u = c0 + c1 x => [c0, c1]; [nil, nil] unless u is linear in x.
    def linear_coefficients(u, x)
      cs = Solve.polynomial_coefficients(u, x)
      return [nil, nil] if cs.nil? || cs.size > 2
      [cs[0], cs[1] || Num.new(0)]
    end

    def root_multiplicity(characteristic, r, s)
      m = 0
      p = characteristic
      while Scalar.zero?(p.subs(r => s).expand)
        m += 1
        p = p.diff(r)
      end
      m
    end

    # Group the terms of a residual linear in the unknowns by the function
    # they multiply (x**k exp(a x) cos(b x), ...). exp(c0 + c1 x) is split so
    # that exp(1 + x) and exp(x) land in the same group.
    def collect_by_function(residual, unknowns, x)
      constant, table = Expand.table(residual)
      groups = { Num.new(1) => [Num.new(constant)] }
      table.each do |factors, coeff|
        coefficient = Num.new(coeff)
        function = {}
        factors.each do |base, e|
          if unknowns.include?(base)
            coefficient *= base
          elsif base == Simplify.exp_base
            offset, slope = linear_coefficients(Expression.lift(e), x)
            coefficient *= Fn.new(:exp, [offset]) if offset && !Scalar.zero?(offset)
            function[base] = slope ? (slope * x).expand : e
          elsif Solve.depends?(base, x) || (e.is_a?(Expression) && Solve.depends?(e, x))
            function[base] = e
          else
            coefficient *= Simplify.power_node(base, e) # a parameter
          end
        end
        key = Simplify.rebuild_product(1, function).simplify
        (groups[key] ||= []) << coefficient
      end
      groups.values.map { |parts| parts.reduce(:+) }
    end

    # Variation of parameters [BD12, §3.6] for a y'' + b y' + c y = g:
    #   y_p = -y1 * int(y2 g / (a W)) + y2 * int(y1 g / (a W)),  W = y1 y2' - y1' y2
    def variation_of_parameters(coeffs, forcing, groups, x)
      y1, y2 = fundamental_system(groups, x)
      wronskian = Trigonometry.trigsimp((y1 * y2.diff(x) - y1.diff(x) * y2).expand)
      scaled = (forcing / (coeffs[2] * wronskian)).simplify
      (-y1 * Integrate.integrate((y2 * scaled).simplify, x) + y2 * Integrate.integrate((y1 * scaled).simplify, x)).simplify
    end
  end
end
