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
  #   solve(abs(x) - 1, x)              # => [1, -1]
  #
  # Polynomials are solved exactly through factorization over QQ, the
  # quadratic formula, k-th roots for binomials and the quadratic formula
  # with symbolic coefficients; irreducible factors of degree >= 3 with
  # numeric coefficients get numeric roots. Transcendental equations are
  # reduced to polynomials in one atom (exp(x), sin(x), sqrt(x), ...) and
  # inverted. An equation with abs or sign is split into its cases and each
  # candidate substituted back. Systems: linear in the unknowns, or two
  # polynomial equations in two unknowns through resultants.
  #
  # Sources (keys: MANUAL.md, Sources): elimination by resultants [GCL92,
  # ch. 9], [CLO15, §3.6]; numeric roots by the Durand-Kerner (Weierstrass)
  # simultaneous iteration [Ker66], started at powers of 0.4 + 0.9i.
  module Solve
    MAX_DEPTH = 6
    # abs and sign split the line into cases; 2**n branches, so a small n.
    CASES = %i[abs sign].freeze
    MAX_CASES = 3

    module_function

    # all: true adds the period of the trigonometric functions, so that the
    # answer is the whole family rather than the solutions in one period.
    # The unknown's declared domain (assume(x: ZZ), or domain: here) keeps
    # out the solutions that demonstrably do not lie in it.
    def solve(target, vars = nil, all: false, domain: nil)
      if target.equal?(true) || target.equal?(false)
        raise ArgumentError, "solve: `==` compares structurally in Ruby and this one is already #{target}; " \
                             "write solve(eq(lhs, rhs), x) or solve(hold { lhs == rhs }, x)"
      end
      return Inequalities.solve(target, vars) if target.is_a?(Inequality) || (target.is_a?(Array) && target.any? { |t| t.is_a?(Inequality) })
      return system(target, vars, domain: domain) if target.is_a?(Array)
      return piecewise(target, vars) if piecewise?(target)
      f = to_zero(target).simplify
      x = variable(f, vars)
      # 0 = 0 holds for every value of x. That is an answer, and a set is
      # what says it; raising made a true statement look like a failure.
      return RealSet.reals if Scalar.zero?(f)
      ordered(restrict(dedupe(univariate(f, x, 0, all: all)), x, domain))
    end

    # Real roots ascending, then the rest in the order they were found. The
    # order a method happens to produce is not an answer about the roots.
    def ordered(roots)
      keys = roots.each_with_index.to_h do |root, i|
        value = begin
          root.evalf
        rescue StandardError
          nil
        end
        value = value.value if value.is_a?(Num)
        [root, value.is_a?(Numeric) && value.real? ? [0, value.to_f, i] : [1, 0.0, i]]
      end
      roots.sort_by { |root| keys[root] }
    end

    # Drop the solutions that contradict what the unknown was declared to
    # be - a number set, a sign, or both. What cannot be decided stays
    # (Infer.excluded?), so an answer is never lost to a guess.
    def restrict(roots, x, domain)
      wanted = domain || RCAS.assumption(x.name)
      sign = RCAS.signs[x.name]
      return roots if wanted.nil? && sign.nil?
      roots.reject do |root|
        (wanted && Infer.excluded?(root, wanted)) || (sign && wrong_sign?(root, sign))
      end
    end

    # What each declared sign allows a root to be.
    ALLOWED_SIGNS = { positive: %i[positive], nonnegative: %i[positive zero],
                      negative: %i[negative], nonpositive: %i[negative zero] }.freeze

    def wrong_sign?(root, sign)
      found = root_sign(root)
      !found.nil? && !ALLOWED_SIGNS.fetch(sign, %i[positive negative zero]).include?(found)
    end

    # The sign of a constant root, or nil when it is not decided: a root
    # with a parameter in it, or one that is not real.
    def root_sign(root)
      return nil unless root.variables.empty?
      return :zero if Scalar.zero?(root)
      value = Analysis.numeric(root)
      return nil if value.nil?
      value.positive? ? :positive : :negative
    end

    # An integer parameter for the periodic solutions, avoiding the names in use.
    def period_parameter(f, x)
      taken = f.variables | [x.name]
      name = %i[k n m j].find { |candidate| !taken.include?(candidate) }
      name ||= (1..).lazy.map { |i| :"k#{i}" }.find { |candidate| !taken.include?(candidate) }
      Var.new(name)
    end

    def to_zero(target) = target.is_a?(Equation) ? Sub.new(target.lhs, target.rhs) : Expression.lift(target)

    def piecewise?(target)
      return true if target.is_a?(Expression) && target.each_node.any? { |n| n.is_a?(Piecewise) }
      target.is_a?(Equation) && (target.lhs.each_node.any? { |n| n.is_a?(Piecewise) } || target.rhs.each_node.any? { |n| n.is_a?(Piecewise) })
    end

    # Every branch is solved on its own piece (piecewise.rb).
    def piecewise(target, vars)
      return Piecewises.solve(Piecewises.hoist(target), Num.new(0), vars) unless target.is_a?(Equation)
      pw = Piecewises.hoist(Sub.new(target.lhs, target.rhs).simplify)
      return Piecewises.solve(pw, Num.new(0), vars) if pw.is_a?(Piecewise)
      Solve.solve(pw, vars)
    end

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

    def univariate(f, x, depth, all: false)
      return [] if depth > MAX_DEPTH
      f = f.simplify
      raise ArgumentError, "every value of #{x} is a solution" if Scalar.zero?(f)
      return [] unless depends?(f, x)

      cases = case_nodes(f, x)
      return case_split(f, x, cases, depth, all: all) unless cases.empty?

      num, den = numerator_denominator(f, x)
      coeffs = polynomial_coefficients(num, x)
      roots = coeffs ? polynomial_roots(coeffs) : transcendental(num, x, depth, all: all)
      roots = roots.map(&:simplify).reject { |r| Scalar.zero?(den.subs(x => r).simplify) }
      verify(f, x, roots)
    end

    # The distinct abs(u) and sign(u) in f whose u depends on x: the places
    # where f is one expression to the left of a point and another to the right.
    def case_nodes(f, x)
      f.each_node.select { |n| n.is_a?(Fn) && CASES.include?(n.name) && n.args.size == 1 && depends?(n.args.first, x) }.uniq
    end

    # |u| is u where u >= 0 and -u where u <= 0, and sign(u) is 1, -1 and 0
    # in the same three places, so an equation with n of them is 2**n
    # equations without any, together with the points where a sign vanishes.
    # Every candidate goes back through verify, which drops the roots of a
    # branch that do not lie in it, so the answer is the case split a
    # student writes - and |x| - 1 = 0 no longer comes back empty.
    def case_split(f, x, nodes, depth, all: false)
      raise NotImplementedError, "can't solve #{f} = 0 for #{x}: too many cases" if nodes.size > MAX_CASES
      roots = [1, -1].repeated_permutation(nodes.size).flat_map { |signs| branch_roots(f, x, nodes, signs, depth, all: all) }
      roots += nodes.select { |n| n.name == :sign }.flat_map { |n| univariate(n.args.first, x, depth + 1, all: all) }
      verify(f, x, dedupe(roots.map(&:simplify)))
    end

    def branch_roots(f, x, nodes, signs, depth, all: false)
      branch = nodes.zip(signs).map { |node, sign| [node, branch_value(node, sign)] }.to_h
      univariate(f.subs(branch), x, depth + 1, all: all)
    rescue ArgumentError => e
      raise unless e.message.start_with?("every value")
      # A whole branch vanishes: |x| - x is zero on all of x >= 0, which is
      # a set, and solve answers with points. Name the branch instead.
      raise ArgumentError, "every #{x} with #{branch_conditions(nodes, signs).join(' and ')} solves #{f} = 0"
    end

    def branch_value(node, sign)
      return Num.new(sign) if node.name == :sign
      sign.positive? ? node.args.first : Neg.new(node.args.first)
    end

    def branch_conditions(nodes, signs)
      nodes.zip(signs).map do |node, sign|
        strict = node.name == :sign
        op = if sign.positive? then strict ? :> : :>=
             else strict ? :< : :<=
             end
        Inequality.new(node.args.first, op, 0)
      end
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

    def transcendental(f, x, depth, all: false)
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
        return values.flat_map { |v| invert(u, v, x, depth, all: all) }
      end

      # x**(p/q): substitute t = x**(1/q)
      q = root_denominator(f, x)
      if q > 1
        g = replace_root(f, x, q, t)
        values = univariate(g, t, depth + 1)
        return values.map { |v| (v**q).simplify }
      end

      product = product_equation(f, x, depth, all: all)
      return product if product

      radicals = radical_equation(f, x, depth)
      return radicals if radicals

      logs = logarithmic_equation(f, x, depth)
      return logs if logs

      raise NotImplementedError, "can't solve #{f} = 0 for #{x}; nsolve(#{f}, #{x}: a..b) finds a root numerically"
    end

    # A product vanishes where one of its factors does, so a product no
    # rule can take whole is still three easy equations when it is written
    # as one: (x + 1)*(x - 2)*sin(x). Every factor has to be solvable, or
    # the answer would be missing roots without saying so; a factor in the
    # denominator is not one of them (`numerator_denominator` has already
    # taken those away, and its zeros are poles rather than roots).
    def product_equation(f, x, depth, all: false)
      _, factors = Simplify.factorize(f)
      pieces = factors.filter_map do |base, exponent|
        next nil if exponent.is_a?(Numeric) && Simplify.negative?(exponent)
        # a positive power vanishes exactly where its base does, and a
        # symbolic exponent is the factor itself: exp(u) is stored as
        # EXP**u, whose base knows nothing about x
        piece = exponent.is_a?(Numeric) && exponent.positive? ? base : Simplify.power_node(base, exponent)
        depends?(piece, x) ? piece : nil
      end
      if pieces.size < 2
        # a product the normal form has already multiplied out:
        # (x - 2)*log(x)/x arrives as -2*log(x) + x*log(x)
        common, rest = Simplify.common_factor(f)
        pieces = [common, rest].compact.select { |piece| depends?(piece, x) }
        return nil if pieces.size < 2
      end
      pieces.flat_map { |piece| univariate(piece, x, depth + 1, all: all) }
    rescue NotImplementedError
      nil # one factor rcas cannot solve: the product is no easier
    end

    # sqrt(u) = v: the radical on one side, both sides to the q-th power,
    # and the answers kept only where the original equation is defined.
    # Raising to a power invents roots, and `verify` drops those.
    def radical_equation(f, x, depth)
      constant, terms = Simplify.termize(f)
      with, without = terms.partition { |factors, _| root_index(factors, x) }
      return nil unless with.size == 1
      q = root_index(with.first.first, x)
      return nil if q.nil? || q > 3
      side = Simplify.rebuild_sum(0, with.to_h)
      rest = Simplify.rebuild_sum(-constant, without.to_h.transform_values { |c| -c })
      g = (Expand.expand(Simplify.power_node(side, q)) - Expand.expand(Simplify.power_node(rest, q))).simplify
      return nil if root_denominator(g, x) > 1 || g.each_node.any? { |n| root_index_of(n, x) }
      defined_roots(f, x, univariate(g, x, depth + 1))
    rescue NotImplementedError
      nil
    end

    # log(u) + log(v) = c: one logarithm instead of two, which the atom
    # substitution can then invert.
    def logarithmic_equation(f, x, depth)
      logs = f.each_node.count { |n| n.is_a?(Fn) && n.name == :log && depends?(n, x) }
      return nil unless logs > 1
      combined = Trigonometry.logcombine(f).simplify
      return nil if combined == f
      defined_roots(f, x, univariate(combined, x, depth + 1))
    rescue NotImplementedError
      nil
    end

    # The denominator of a fractional exponent on a base that involves x.
    def root_index(factors, x)
      factors.filter_map { |base, exp| root_index_of(Simplify.power_node(base, exp), x) }.max
    end

    def root_index_of(node, x)
      return nil unless node.is_a?(Pow) && node.exponent.is_a?(Num)
      value = node.exponent.value
      return nil unless value.is_a?(Rational) && value.denominator > 1 && depends?(node.base, x)
      value.denominator
    end

    # A root of the squared equation is a root of this one only where this
    # one is defined: a logarithm needs a positive argument and an even root
    # a non-negative one. That is the check a student is told to make.
    def defined_roots(f, x, roots)
      conditions = Analysis.domain_conditions(f, x)
      return roots if conditions.empty?
      roots.select do |root|
        conditions.all? do |condition|
          value = begin
            Expression.lift(condition.lhs - condition.rhs).evalf(x.name => root.evalf)
          rescue StandardError
            nil
          end
          next true unless value.is_a?(Numeric) && value.real?
          case condition.op
          when :> then value > 1e-9
          when :>= then value > -1e-9
          when :!= then value.abs > 1e-9
          else true
          end
        end
      end
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

    # Solutions of u = v for x, where u is a single atom containing x. With
    # all: true the period of sin, cos and tan is added, with an integer
    # parameter, so that every solution is covered and not just one period.
    def invert(u, v, x, depth, all: false)
      case u
      when Fn
        arg = u.args.first
        period = all ? period_parameter(arg - v, x) : nil
        turn = ->(multiple) { period ? multiple * PI * period : Num.new(0) }
        targets =
          case u.name
          when :exp  then [Fn.new(:log, [v])]
          when :log  then [Fn.new(:exp, [v])]
          when :sin  then [Fn.new(:asin, [v]) + turn.call(2), PI - Fn.new(:asin, [v]) + turn.call(2)]
          when :cos  then [Fn.new(:acos, [v]) + turn.call(2), -Fn.new(:acos, [v]) + turn.call(2)]
          when :tan  then [Fn.new(:atan, [v]) + turn.call(1)]
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
        next true unless (r.variables - f.variables + [x.name]).empty? || r.variables.empty?
        value = begin
          f.evalf(x: r.evalf)
        rescue StandardError
          nil
        end
        !value.is_a?(Numeric) || value.abs < 1e-8
      end
    end

    # ---- systems ---------------------------------------------------------------------

    def system(targets, vars, domain: nil)
      fs = targets.map { |t| to_zero(t).simplify }
      unknowns = Array(vars).map { |v| Expression.lift(v) }
      raise ArgumentError, "solve: list the unknowns, e.g. solve([...], [x, y])" if unknowns.empty?

      solutions =
        if fs.all? { |f| linear_in?(f, unknowns) }
          linear_system(fs, unknowns)
        elsif (found = polynomial_system(fs, unknowns))
          found
        elsif fs.size == 2 && unknowns.size == 2
          polynomial_pair(fs, unknowns)
        else
          raise NotImplementedError, "only linear systems and polynomial systems with rational coefficients are supported"
        end
      restrict_system(solutions, unknowns, domain)
    end

    # A solution of a system survives when every unknown in it does.
    def restrict_system(solutions, unknowns, domain)
      wanted = unknowns.to_h { |x| [x, domain || RCAS.assumption(x.name)] }.compact
      return solutions if wanted.empty?
      solutions.reject do |solution|
        next false unless solution.is_a?(Hash)
        solution.any? { |x, value| wanted[x] && Infer.excluded?(value, wanted[x]) }
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
