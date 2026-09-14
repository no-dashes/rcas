# frozen_string_literal: true

module RCAS
  # lhs = rhs. Build with eq(a, b) or a.eq(b); solve with solve(equation, x).
  class Equation
    attr_reader :lhs, :rhs

    def initialize(lhs, rhs)
      @lhs = Expression.lift(lhs)
      @rhs = Expression.lift(rhs)
      freeze
    end

    def to_expr = Sub.new(lhs, rhs)
    def simplify = Equation.new(lhs.simplify, rhs.simplify)
    def expand = Equation.new(lhs.expand, rhs.expand)
    def subs(*args) = Equation.new(lhs.subs(*args), rhs.subs(*args))
    def swap = Equation.new(rhs, lhs)
    def variables = (lhs.variables | rhs.variables).sort
    def solve(var = nil) = Solve.solve(self, var)

    # Does the equation hold for these values?
    def holds?(**bindings)
      value = Expression.lift((lhs - rhs).call(**bindings)).simplify
      value.is_a?(Num) && (value.value.is_a?(Float) ? value.value.abs < 1e-9 : value.zero?)
    end

    %i[+ - * /].each do |op|
      define_method(op) do |other|
        other.is_a?(Equation) ? Equation.new(lhs.public_send(op, other.lhs), rhs.public_send(op, other.rhs)) : Equation.new(lhs.public_send(op, other), rhs.public_send(op, other))
      end
    end
    def -@ = Equation.new(-lhs, -rhs)

    def ==(other) = other.is_a?(Equation) && other.lhs == lhs && other.rhs == rhs
    alias eql? ==
    def hash = [Equation, lhs, rhs].hash

    def to_s = "#{lhs} = #{rhs}"
    alias inspect to_s

    def to_latex(wrap: nil) = "#{LaTeX.print(lhs)} = #{LaTeX.print(rhs)}"
  end

  # Equation solving.
  #
  #   solve(x**2 - 3*x + 2, x)          # => [1, 2]
  #   solve(eq(x**2, -1), x)            # => [-i, i]
  #   solve(exp(2*x) - 3*exp(x) + 2, x) # => [0, log(2)]
  #   solve([eq(x + y, 3), eq(x - y, 1)], [x, y])   # => [{x => 2, y => 1}]
  #
  # Polynomials are solved exactly through factorization over QQ, the
  # quadratic formula, k-th roots for binomials and the quadratic formula
  # with symbolic coefficients; irreducible factors of degree >= 3 with
  # numeric coefficients get numeric roots. Transcendental equations are
  # reduced to polynomials in one atom (exp(x), sin(x), sqrt(x), ...) and
  # inverted. Systems: linear in the unknowns, or two polynomial equations
  # in two unknowns through resultants.
  #
  # Sources (keys: MANUAL.md, Sources): elimination by resultants [GCL92,
  # ch. 9], [CLO15, §3.6]; numeric roots by the Durand-Kerner (Weierstrass)
  # simultaneous iteration [Ker66], started at powers of 0.4 + 0.9i.
  module Solve
    MAX_DEPTH = 6

    module_function

    def solve(target, vars = nil)
      return Inequalities.solve(target, vars) if target.is_a?(Inequality) || (target.is_a?(Array) && target.any? { |t| t.is_a?(Inequality) })
      return system(target, vars) if target.is_a?(Array)
      f = to_zero(target).simplify
      x = variable(f, vars)
      dedupe(univariate(f, x, 0))
    end

    def to_zero(target) = target.is_a?(Equation) ? Sub.new(target.lhs, target.rhs) : Expression.lift(target)

    def variable(f, vars)
      return Expression.lift(vars) if vars
      free = f.variables
      raise ArgumentError, "solve: which variable? #{f} has #{free.size} variables" unless free.size == 1
      Var.new(free.first)
    end

    def depends?(e, x) = e.variables.include?(x.name)

    def dedupe(list)
      out = []
      list.each { |s| out << s unless out.any? { |o| o == s } }
      out
    end

    # ---- one equation, one unknown ----------------------------------------------

    def univariate(f, x, depth)
      return [] if depth > MAX_DEPTH
      f = f.simplify
      raise ArgumentError, "every value of #{x} is a solution" if Scalar.zero?(f)
      return [] unless depends?(f, x)

      num, den = numerator_denominator(f, x)
      coeffs = polynomial_coefficients(num, x)
      roots = coeffs ? polynomial_roots(coeffs) : transcendental(num, x, depth)
      roots = roots.map(&:simplify).reject { |r| Scalar.zero?(den.subs(x => r).simplify) }
      verify(f, x, roots)
    end

    # f = num / den with den the product of the x-dependent denominators.
    def numerator_denominator(f, x)
      _, table = Expand.table(f)
      den_factors = {}
      table.each_key do |factors|
        factors.each do |base, exp|
          next unless exp.is_a?(Integer) && exp.negative? && depends?(base, x)
          den_factors[base] = [den_factors[base] || 0, -exp].max
        end
      end
      return [f, Num.new(1)] if den_factors.empty?
      constant, table = Expand.table(f)
      cleared = {}
      cleared[den_factors.dup] = constant unless constant.zero?
      table.each do |factors, coeff|
        merged = factors.dup
        den_factors.each do |base, k|
          e = Simplify.add_exponents(merged[base] || 0, k)
          e.is_a?(Numeric) && e.zero? ? merged.delete(base) : merged[base] = e
        end
        cleared[merged] = (cleared[merged] || 0) + coeff
      end
      [Simplify.rebuild_sum(0, cleared).expand, Simplify.rebuild_product(1, den_factors)]
    end

    # Coefficients of f as a polynomial in x (index = degree), or nil.
    def polynomial_coefficients(f, x)
      constant, table = Expand.table(f)
      coeffs = Hash.new { Num.new(0) }
      coeffs[0] = Num.new(constant)
      table.each do |factors, coeff|
        degree = 0
        c = Num.new(coeff)
        factors.each do |base, exp|
          if base == x
            return nil unless exp.is_a?(Integer) && exp >= 0
            degree += exp
          elsif depends?(base, x) || (exp.is_a?(Expression) && depends?(exp, x))
            return nil
          else
            c *= Simplify.power_node(base, exp)
          end
        end
        coeffs[degree] = coeffs[degree] + c
      end
      list = (0..coeffs.keys.max).map { |k| coeffs[k].simplify }
      list.pop while list.size > 1 && Scalar.zero?(list.last)
      list
    end

    # Roots (with multiplicity) of the polynomial with these coefficients.
    def polynomial_roots(coeffs)
      coeffs = coeffs.dup
      coeffs.pop while coeffs.size > 1 && Scalar.zero?(coeffs.last)
      n = coeffs.size - 1
      return [] if n < 1
      return exact_roots(coeffs) if coeffs.all? { |c| c.is_a?(Num) && (c.value.is_a?(Integer) || c.value.is_a?(Rational)) }

      factored = symbolic_roots_by_factoring(coeffs)
      return factored if factored

      case n
      when 1 then [(-coeffs[0] / coeffs[1]).cancel]
      when 2 then quadratic(coeffs[2], coeffs[1], coeffs[0])
      else raise NotImplementedError, "can't solve a degree #{n} polynomial with symbolic coefficients exactly"
      end
    end

    # (x - a)*(x - 1) = 0 has the roots a and 1: factor over QQ[x, params]
    # first and read linear factors off; quadratic factors use the formula.
    def symbolic_roots_by_factoring(coeffs)
      x = Var.new(:_x)
      expr = coeffs.each_with_index.reduce(Num.new(0)) { |acc, (c, k)| acc + c * x**k }
      vars = expr.variables
      return nil unless vars.include?(:_x)
      poly = Polynomial.from_expr(QQ[*vars], expr)
      factors = poly.factor.factors.map(&:first).reject { |g| g.degree(:_x).zero? }
      return nil if factors.size <= 1 && factors.first&.degree(:_x).to_i >= 2
      factors.flat_map do |g|
        cs = (0..g.degree(:_x)).map { |k| g.coefficient_in(:_x, k).to_expr }
        case cs.size - 1
        when 1 then [(-cs[0] / cs[1]).cancel]
        when 2 then quadratic(cs[2], cs[1], cs[0])
        else raise NotImplementedError, "can't solve a degree #{cs.size - 1} factor with symbolic coefficients exactly"
        end
      end
    rescue DomainError
      nil
    end

    def quadratic(a, b, c)
      disc = (b**2 - 4 * a * c).expand
      return [(-b / (2 * a)).simplify] * 2 if Scalar.zero?(disc)
      root = square_root(disc)
      [((-b - root) / (2 * a)).simplify, ((-b + root) / (2 * a)).simplify]
    end

    # sqrt(d) with perfect squares taken out: sqrt((a - 1)**2) => a - 1 (a sign is
    # immaterial for +- roots), sqrt(4*a) => 2*sqrt(a).
    def square_root(d)
      return RCAS.sqrt(d) if d.variables.empty?
      fact = d.to_poly.factor
      unit = fact.unit.value
      return RCAS.sqrt(d) unless fact.factors.all? { |_, m| m.even? } && unit.positive?
      root = fact.factors.reduce(RCAS.sqrt(Num.new(unit))) { |acc, (g, m)| acc * g.to_expr**(m / 2) }
      root.simplify
    rescue DomainError, NotImplementedError
      RCAS.sqrt(d)
    end

    def exact_roots(coeffs)
      ring = QQ[:_x]
      poly = Polynomial.new(ring, coeffs.each_with_index.to_h { |c, k| [[k], c] })
      poly.factor.factors.flat_map do |g, m|
        roots =
          if g.degree == 1
            [Num.new(Simplify.normalize_number(Rational(-g.coeff(0).value, g.coeff(1).value)))]
          elsif g.degree == 2
            quadratic(g.coeff(2), g.coeff(1), g.coeff(0))
          elsif g.terms.size == 2 && g.coeff(0) != 0
            binomial_roots(g)
          elsif g.degree == 4 && g.terms.keys.all? { |e| e[0].even? }
            biquadratic_roots(g)
          else
            (0...g.degree).map { |i| RootOf.new(g.primitive_part, i) }
          end
        roots * m
      end
    end

    # a x^4 + b x^2 + c = 0: x = +-sqrt(r) for the two roots r of a r^2 + b r + c
    def biquadratic_roots(g)
      quadratic(g.coeff(4), g.coeff(2), g.coeff(0)).flat_map do |r|
        root = RCAS.sqrt(r)
        [Simplify.negate(root).simplify, root]
      end
    end

    # a x^k + b = 0  =>  |b/a|^(1/k) times the k-th roots of +-1
    def binomial_roots(g)
      k = g.degree
      c = Rational(-g.coeff(0).value, g.coeff(k).value)
      radius = Pow.new(Num.new(c.abs), Num.new(Rational(1, k)))
      (0...k).map do |j|
        angle = c.positive? ? Rational(2 * j, k) : Rational(2 * j + 1, k)
        (radius * Fn.new(:exp, [I * PI * angle])).simplify
      end
    end

    # Durand-Kerner iteration for an irreducible numeric polynomial.
    def numeric_roots(g)
      n = g.degree
      lc = g.coeff(n).value.to_f
      a = (0..n).map { |k| g.coeff(k).value.to_f / lc }
      roots = (0...n).map { |k| Complex(0.4, 0.9)**k }
      value = ->(z) { a.each_with_index.reduce(0) { |acc, (c, k)| acc + c * z**k } }
      500.times do
        moved = 0.0
        roots = roots.each_with_index.map do |z, i|
          denom = roots.each_with_index.reduce(1) { |acc, (w, j)| i == j ? acc : acc * (z - w) }
          nz = z - value.call(z) / denom
          moved += (nz - z).abs
          nz
        end
        break if moved < 1e-14
      end
      roots.map do |z|
        z = z.real if z.imaginary.abs < 1e-9
        Num.new(z.is_a?(Complex) ? Complex(z.real.round(12), z.imaginary.round(12)) : z.round(12))
      end.sort_by { |r| r.value.is_a?(Complex) ? [r.value.real, r.value.imaginary] : [r.value, 0] }
    end

    # ---- transcendental equations -------------------------------------------------

    def transcendental(f, x, depth)
      atoms = f.each_node.select { |n| depends?(n, x) && transcendental_atom?(n) }.uniq
      atoms = atoms.sort_by { |n| -n.each_node.count }
      t = Var.new(:"_s#{depth}")

      atoms.each do |u|
        g = replace_atom(f, u, x, t)
        next if g.nil? || depends?(g, x)
        values = begin
          univariate(g, t, depth + 1)
        rescue NotImplementedError, ArgumentError
          next
        end
        return values.flat_map { |v| invert(u, v, x, depth) }
      end

      # x**(p/q): substitute t = x**(1/q)
      q = root_denominator(f, x)
      if q > 1
        g = replace_root(f, x, q, t)
        values = univariate(g, t, depth + 1)
        return values.map { |v| (v**q).simplify }
      end

      raise NotImplementedError, "can't solve #{f} = 0 for #{x}"
    end

    def transcendental_atom?(n)
      (n.is_a?(Fn)) || (n.is_a?(Pow) && !n.base.is_a?(Var) && !(n.exponent.is_a?(Num) && n.exponent.integer?)) ||
        (n.is_a?(Pow) && !n.exponent.is_a?(Num))
    end

    # Replace the atom u by t. exp(k*v) becomes t**k for every rational k.
    def replace_atom(f, u, x, t)
      if u.is_a?(Fn) && u.name == :exp
        v = u.args.first
        constant, table = Expand.table(f)
        rebuilt = {}
        table.each do |factors, coeff|
          new_factors = {}
          factors.each do |base, exp|
            if base == Simplify.exp_base && exp.is_a?(Expression) && depends?(exp, x)
              ratio = (exp / v).simplify
              return nil unless ratio.is_a?(Num)
              new_factors[t] = (new_factors[t] || 0) + ratio.value
            else
              new_factors[base] = exp
            end
          end
          rebuilt[new_factors] = (rebuilt[new_factors] || 0) + coeff
        end
        Simplify.rebuild_sum(constant, rebuilt)
      else
        f.subs(u => t)
      end
    end

    def root_denominator(f, x)
      _, table = Expand.table(f)
      table.each_key.flat_map { |factors| factors.select { |b, e| b == x && e.is_a?(Rational) }.map { |_, e| e.denominator } }.reduce(1, :lcm)
    end

    def replace_root(f, x, q, t)
      constant, table = Expand.table(f)
      rebuilt = {}
      table.each do |factors, coeff|
        new_factors = factors.to_h do |base, exp|
          base == x ? [t, Simplify.normalize_number(Rational(exp) * q)] : [base, exp]
        end
        rebuilt[new_factors] = (rebuilt[new_factors] || 0) + coeff
      end
      Simplify.rebuild_sum(constant, rebuilt)
    end

    # Solutions of u = v for x, where u is a single atom containing x.
    def invert(u, v, x, depth)
      case u
      when Fn
        arg = u.args.first
        targets =
          case u.name
          when :exp  then [Fn.new(:log, [v])]
          when :log  then [Fn.new(:exp, [v])]
          when :sin  then [Fn.new(:asin, [v]), PI - Fn.new(:asin, [v])]
          when :cos  then [Fn.new(:acos, [v]), -Fn.new(:acos, [v])]
          when :tan  then [Fn.new(:atan, [v])]
          when :atan then [Fn.new(:tan, [v])]
          when :asin then [Fn.new(:sin, [v])]
          when :acos then [Fn.new(:cos, [v])]
          when :sinh then [Fn.new(:log, [v + RCAS.sqrt(v**2 + 1)])]
          when :cosh then [Fn.new(:log, [v + RCAS.sqrt(v**2 - 1)]), -Fn.new(:log, [v + RCAS.sqrt(v**2 - 1)])]
          else return []
          end
        targets.flat_map { |w| univariate((arg - w).simplify, x, depth + 1) }
      when Pow
        if depends?(u.base, x) && !depends?(u.exponent, x)
          univariate((u.base - v**(1 / u.exponent)).simplify, x, depth + 1)
        elsif !depends?(u.base, x)
          univariate((u.exponent - Fn.new(:log, [v]) / Fn.new(:log, [u.base])).simplify, x, depth + 1)
        else
          []
        end
      else
        []
      end
    end

    # Drop candidates that numerically fail the equation (spurious branches).
    def verify(f, x, roots)
      roots.select do |r|
        value = begin
          f.evalf(x: r.evalf)
        rescue StandardError
          nil
        end
        !value.is_a?(Numeric) || value.abs < 1e-8
      end
    end

    # ---- systems ---------------------------------------------------------------------

    def system(targets, vars)
      fs = targets.map { |t| to_zero(t).simplify }
      unknowns = Array(vars).map { |v| Expression.lift(v) }
      raise ArgumentError, "solve: list the unknowns, e.g. solve([...], [x, y])" if unknowns.empty?

      if fs.all? { |f| linear_in?(f, unknowns) }
        linear_system(fs, unknowns)
      elsif (solutions = polynomial_system(fs, unknowns))
        solutions
      elsif fs.size == 2 && unknowns.size == 2
        polynomial_pair(fs, unknowns)
      else
        raise NotImplementedError, "only linear systems and polynomial systems with rational coefficients are supported"
      end
    end

    # Polynomial systems over QQ by a lex Gröbner basis [CLO15, ch. 2 §8, ch. 3 §1]:
    # the basis is triangular, so the last unknown has a univariate polynomial;
    # its roots are substituted into the rest. nil when a coefficient is not
    # rational (parameters), so that the resultant route can try.
    def polynomial_system(fs, unknowns)
      ring = QQ[*unknowns.map(&:name)]
      polys = fs.map do |f|
        ring.call(f)
      rescue DomainError
        return nil
      end
      basis = Groebner.basis(polys, :lex)
      return [] if basis.size == 1 && basis.first.constant?
      unless Groebner.zero_dimensional?(basis, :lex)
        raise NotImplementedError, "the system has infinitely many solutions; its Gröbner basis is #{basis.map(&:to_s).join(', ')}"
      end
      triangular(basis.map(&:to_expr), unknowns, {}).map { |sol| unknowns.to_h { |u| [u, sol[u]] } }
    end

    def triangular(basis, unknowns, known)
      return [known] if unknowns.empty?
      x = unknowns.last
      rest = unknowns[0...-1].map(&:name)
      substituted = basis.map { |g| g.subs(known).simplify }.reject { |g| Scalar.zero?(g) }
      univariate = substituted.select { |g| (g.variables & rest).empty? }
      return [] if univariate.any? { |g| g.variables.empty? } # a non-zero constant: no solution on this branch
      raise NotImplementedError, "no univariate polynomial in #{x} after substituting #{known}" if univariate.empty?
      pivot = univariate.min_by { |g| polynomial_coefficients(g, x)&.size || Float::INFINITY }
      coeffs = polynomial_coefficients(pivot, x) or raise NotImplementedError, "#{pivot} is not a polynomial in #{x}"
      roots = dedupe(polynomial_roots(coeffs).map(&:simplify))
      roots = roots.select { |r| univariate.all? { |g| Scalar.zero?(g.subs(x => r).simplify) } }
      roots.flat_map { |r| triangular(basis, unknowns[0...-1], known.merge(x => r)) }
    end

    def linear_in?(f, unknowns)
      names = unknowns.map(&:name)
      _, table = Expand.table(f)
      table.each_key.all? do |factors|
        degree = 0
        factors.each do |base, exp|
          if base.is_a?(Var) && names.include?(base.name)
            return false unless exp.is_a?(Integer) && exp >= 0
            degree += exp
          elsif (base.variables & names).any? || (exp.is_a?(Expression) && (exp.variables & names).any?)
            return false
          end
        end
        degree <= 1
      end
    end

    def linear_system(fs, unknowns)
      n = unknowns.size
      rows = fs.map do |f|
        constant, table = Expand.table(f)
        row = Array.new(n) { Num.new(0) }
        rhs = Num.new(-constant)
        table.each do |factors, coeff|
          c = Num.new(coeff)
          index = nil
          factors.each do |base, exp|
            if base.is_a?(Var) && (i = unknowns.index(base))
              index = i
            else
              c *= Simplify.power_node(base, exp)
            end
          end
          index ? row[index] = Scalar.add(row[index], c.simplify) : rhs = Scalar.sub(rhs, c.simplify)
        end
        row + [rhs]
      end
      reduced, pivots = Elimination.rref(rows)
      return [] if pivots.include?(n)
      solution = {}
      pivots.each_with_index do |p, i|
        value = reduced[i][n]
        (0...n).each do |j|
          next if j == p || Scalar.zero?(reduced[i][j])
          value = Scalar.sub(value, Scalar.mul(reduced[i][j], unknowns[j]))
        end
        solution[unknowns[p]] = value.cancel
      end
      [solution]
    end

    def polynomial_pair(fs, unknowns)
      x, y = unknowns
      ring = QQ[x.name, y.name]
      f, g = fs.map do |e|
        ring.call(e)
      rescue DomainError
        raise NotImplementedError, "polynomial systems need rational coefficients: #{e}"
      end
      res = f.resultant(g, x.name)
      raise NotImplementedError, "the equations share a common factor" if res.zero?
      ys = polynomial_roots((0..res.degree(y.name)).map { |k| ring_constant(res.coefficient_in(y.name, k)) })
      dedupe(ys).flat_map do |y0|
        xs = univariate(fs[0].subs(y => y0), x, 1)
        xs.select { |x0| Equation.new(fs[1], 0).holds?(x.name => x0, y.name => y0) }.map { |x0| { x => x0, y => y0 } }
      end
    end

    def ring_constant(poly) = poly.constant_term
  end
end
