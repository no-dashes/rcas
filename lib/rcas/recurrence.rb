# frozen_string_literal: true

module RCAS
  # Linear recurrences.
  #
  #   rsolve(eq(u(n + 2), u(n + 1) + u(n)), u, n)                       # general solution
  #   rsolve(eq(u(n + 2), u(n + 1) + u(n)), u, n, init: {0 => 0, 1 => 1})  # Fibonacci
  #   rsolve(eq(u(n + 1), 2*u(n) + 1), u, n, init: {0 => 0})            # => -1 + 2**n
  #   rsolve(eq(u(n + 1), n*u(n)), u, n)                                # => C1*(n - 1)!
  #
  # In bin/rcas an undefined name applied to arguments, u(n + 1), is the
  # unknown sequence. With constant coefficients the homogeneous solution
  # comes from the characteristic roots (multiplicities give n, n**2, ...
  # factors) and a forcing term that is a sum of polynomials times b**n goes
  # through undetermined coefficients; with coefficients that depend on n,
  # Petkovsek's algorithm gives the hypergeometric solutions, and rsolve
  # writes down the general solution only when there are as many of them as
  # the order of the recurrence (`hyper` lists them either way). Initial
  # values fix the constants through a linear system.
  #
  # Sources (keys: MANUAL.md, Sources): [GKP94, §7.3]; the constant-coefficient
  # method is the discrete twin of ode.rb's; [Pet92] and [Koe14, ch. 9] for
  # the rest (petkovsek.rb).
  module Recurrence
    module_function

    def rsolve(equation, u, n, init: {})
      name, n, coeffs, forcing = normalize(equation, u, n)
      constants = []
      general =
        if coeffs.any? { |c| c.variables.include?(n.name) }
          hypergeometric_solution(coeffs, forcing, n, constants)
        else
          constant_coefficient_solution(coeffs, forcing, n, constants)
        end
      unless init.empty?
        early = init.keys.map { |i| Expression.lift(i) }.select { |i| i.is_a?(Num) && i.value < @start.to_i }
        unless early.empty?
          # the closed form holds from the first index past the singularities
          # of the coefficients; before it, it says nothing (u(0) = 1 for
          # u(n + 1) = (n - 3)*u(n) made the constant 1/(-4)!: S6)
          raise NotImplementedError, "rsolve: the closed form holds from #{n} = #{@start} on, so it cannot take the initial value at #{early.map(&:to_s).join(', ')}"
        end
        general = initial_values(general, init, n, constants)
      end
      Equation.new(Fn.new(name, [n]), general)
    ensure
      @start = nil
    end

    # Petkovsek's `Hyper`: the hypergeometric solutions of a homogeneous
    # recurrence, as terms, without the constants rsolve puts in front.
    def hyper(equation, u, n)
      _, n, coeffs, forcing = normalize(equation, u, n)
      raise NotImplementedError, "hyper: #{equation} is not homogeneous" unless Scalar.zero?(forcing)
      Petkovsek.solutions(coeffs, n)
    end

    # [name, index, [p_0, ..., p_r], forcing] of the equation read as
    # sum_j p_j(n)*u(n + j) = forcing(n).
    def normalize(equation, u, n)
      n = Expression.lift(n)
      raise ArgumentError, "rsolve: the index must be a symbol, got #{n}" unless n.is_a?(Var)
      name = sequence_name(u)
      f = Solve.to_zero(equation).simplify
      shifts = shift_table(f, name, n)
      raise ArgumentError, "#{equation} contains no #{name}(#{n} + k)" if shifts.empty?
      low = shifts.values.min
      unless low.zero? # u(n - 1) = ... : renumber so the lowest shift is 0
        f = f.subs(n => n - low).simplify
        shifts = shift_table(f, name, n)
      end
      order = shifts.values.max
      raise ArgumentError, "#{equation} is not a recurrence: only #{name}(#{n}) occurs" if order.zero?

      ds = (0..order).map { |k| Var.new(:"_s#{k}") }
      g = f.subs(shifts.to_h { |t, k| [t, ds[k]] })
      raise NotImplementedError, "only linear recurrences are supported" unless Solve.linear_in?(g, ds)
      coeffs = ds.map { |d| Solve.polynomial_coefficients(g, d)[1] || Num.new(0) }
      forcing = Simplify.negate(g.subs(ds.to_h { |d| [d, Num.new(0)] })).simplify
      coeffs, forcing = clear_denominators(coeffs, forcing, n)
      [name, n, coeffs, forcing]
    end

    # u(n + 1) = (2*n + 3)*u(n)/(n + 2) is the same recurrence as
    # (n + 2)*u(n + 1) - (2*n + 3)*u(n) = 0, and Petkovsek needs the second
    # form: multiply through by the common denominator.
    def clear_denominators(coeffs, forcing, n)
      parts = coeffs + [forcing]
      return [coeffs, forcing] if parts.all? { |c| Solve.polynomial_coefficients(c, n) }
      vars = parts.flat_map { |c| c.variables.to_a }.uniq | [n.name]
      ring = QQ[*vars]
      common = ring.one
      parts.each do |c|
        pair = Fraction.as_fraction(c, vars) or return [coeffs, forcing]
        common = common.lcm(pair.last)
      end
      return [coeffs, forcing] if common.constant?
      factor = common.to_expr
      [coeffs.map { |c| (c * factor).cancel.expand }, (forcing * factor).cancel.expand]
    rescue DomainError, NotImplementedError, ZeroDivisionError
      [coeffs, forcing]
    end

    # Constant coefficients: characteristic roots and undetermined
    # coefficients, the discrete twin of dsolve's.
    def constant_coefficient_solution(coeffs, forcing, n, constants)
      roots = Solve.polynomial_roots(coeffs).map(&:simplify)
      homogeneous = homogeneous_solution(roots, n, constants)
      particular = Scalar.zero?(forcing) ? Num.new(0) : (undetermined_coefficients(coeffs, forcing, roots, n) || raise(NotImplementedError, "no method for the forcing term #{forcing}"))
      (homogeneous + particular).simplify
    end

    # Coefficients that depend on n: Petkovsek's algorithm. As many
    # independent hypergeometric solutions as the order of the recurrence
    # span its solution space; with fewer, the missing ones are not
    # hypergeometric and the general solution cannot be written down, so we
    # say so rather than pass off a part of it as the whole.
    def hypergeometric_solution(coeffs, forcing, n, constants)
      unless Scalar.zero?(forcing)
        raise NotImplementedError, "rsolve: polynomial coefficients with the forcing term #{forcing} are not supported"
      end
      order = coeffs.size - 1
      ratios = Petkovsek.ratios(coeffs, n)
      found = ratios.map { |ratio| Petkovsek.term(ratio, n) }
      @start = ratios.map { |ratio| Petkovsek.start_index(ratio, n) }.max
      raise NotImplementedError, "rsolve: no hypergeometric solutions (see hyper)" if found.empty?
      if found.size < order
        raise NotImplementedError, "rsolve: only #{found.size} of #{order} solutions are hypergeometric: " \
                                   "#{found.map(&:to_s).join(', ')} (see hyper)"
      end
      # as many solutions as the order is not yet a basis: they have to be
      # independent, which their Casoratian says (third review, S5)
      unless independent?(found, n, order, @start.to_i)
        raise NotImplementedError, "rsolve: the hypergeometric solutions #{found.map(&:to_s).join(', ')} do not span the solutions (see hyper)"
      end
      found.map do |t|
        constants << Var.new(:"C#{constants.size + 1}")
        constants.last * t
      end.reduce(:+).simplify
    end

    # det[t_j(m + i)] != 0 at some integer m past the start: then the terms
    # are independent. Exact at every point, so a zero there is a zero.
    def independent?(terms, n, order, start)
      (start..start + 4).any? do |m|
        rows = (0...order).map do |i|
          terms.map { |t| t.subs(n => Num.new(m + i)).simplify }
        end
        next false unless rows.flatten.all? { |v| v.is_a?(Num) }
        Scalar.zero?(Elimination.det(rows)) == false
      end
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      true # nothing to evaluate: the count stands, as before
    end

    def sequence_name(u)
      case u
      when Symbol then u
      when Var then u.name
      when Fn then u.name
      else raise ArgumentError, "rsolve: name the sequence, e.g. rsolve(equation, u, n)"
      end
    end

    # { u(n + k) node => k }
    def shift_table(f, name, n)
      f.each_node.select { |e| e.is_a?(Fn) && e.name == name }.uniq.to_h do |t|
        raise ArgumentError, "#{t}: one argument expected" unless t.args.size == 1
        cs = Solve.polynomial_coefficients(t.args.first, n)
        unless cs && cs.size == 2 && Scalar.one?(cs[1]) && cs[0].is_a?(Num) && cs[0].value.is_a?(Integer)
          raise NotImplementedError, "#{t}: the argument must be #{n} plus an integer"
        end
        [t, cs[0].value]
      end
    end

    def homogeneous_solution(roots, n, constants)
      tally = []
      roots.each do |r|
        entry = tally.find { |root, _| root == r }
        entry ? entry[1] += 1 : tally << [r, 1]
      end
      tally.sort_by { |r, _| [r.variables.empty? && !r.evalf.is_a?(Complex) ? r.evalf.to_f : Float::INFINITY, r.to_s] }
      parts = tally.map do |r, m|
        next nil if Scalar.zero?(r) # a zero root contributes nothing for n >= order
        poly = (0...m).map do |j|
          constants << Var.new(:"C#{constants.size + 1}")
          j.zero? ? constants.last : constants.last * n**j
        end.reduce(:+)
        poly * r**n
      end.compact
      parts.empty? ? Num.new(0) : parts.reduce(:+)
    end

    # Forcing terms polynomial(n) * b**n; the ansatz for base b is
    # n**m * (A_0 + ... + A_d n**d) * b**n, m the multiplicity of b as a root.
    def undetermined_coefficients(coeffs, forcing, roots, n)
      classes = forcing_classes(forcing, n) or return nil
      unknowns = []
      ansatz = classes.map do |b, degree|
        m = roots.count { |r| Scalar.zero?((r - b).simplify) }
        poly = (0..degree).map do |j|
          unknowns << Var.new(:"_A#{unknowns.size}")
          unknowns.last * n**(j + m)
        end.reduce(:+)
        Scalar.one?(b) ? poly : poly * b**n
      end.reduce(:+)
      applied = coeffs.each_with_index.map { |a, k| a * ansatz.subs(n => n + k) }.reduce(:+)
      residual = (applied - forcing).expand
      equations = collect_by_function(residual, unknowns, n)
      solution = Solve.linear_system(equations, unknowns).first or return nil
      unknowns.each { |a| solution[a] ||= Num.new(0) }
      ansatz.subs(solution).simplify
    end

    # { base => degree }: base**(c n) with the offset folded into the coefficient.
    def forcing_classes(forcing, n)
      constant, terms = Simplify.termize(forcing, simplify: true)
      classes = {}
      add = lambda do |b, degree|
        key = classes.keys.find { |b2| Scalar.zero?((b - b2).simplify) } || b
        classes[key] = [classes[key] || 0, degree].max
      end
      add.call(Num.new(1), 0) unless constant.zero?
      terms.each_key do |factors|
        base_total = Num.new(1)
        degree = 0
        factors.each do |base, e|
          exponent = Expression.lift(e)
          if base == n
            return nil unless e.is_a?(Integer) && e >= 0
            degree += e
          elsif base.variables.include?(n.name)
            return nil
          elsif exponent.variables.include?(n.name)
            cs = Solve.polynomial_coefficients(exponent, n)
            return nil unless cs && cs.size == 2
            base_total *= Simplify.power_node(base, cs[1])
          end
        end
        add.call(base_total.simplify, degree)
      end
      classes
    end

    # Group the terms of a residual, linear in the unknowns, by the function
    # of n they multiply; b**(n + 1) is split into b * b**n.
    def collect_by_function(residual, unknowns, n)
      constant, table = Expand.table(residual)
      groups = { Num.new(1) => [Num.new(constant)] }
      table.each do |factors, coeff|
        coefficient = Num.new(coeff)
        function = {}
        factors.each do |base, e|
          exponent = Expression.lift(e)
          if unknowns.include?(base)
            coefficient *= base
          elsif exponent.variables.include?(n.name)
            cs = Solve.polynomial_coefficients(exponent, n)
            if cs && cs.size == 2
              coefficient *= Simplify.power_node(base, cs[0]) unless Scalar.zero?(cs[0])
              function[base] = (cs[1] * n).expand
            else
              function[base] = e
            end
          elsif base.variables.include?(n.name)
            function[base] = e
          else
            coefficient *= Simplify.power_node(base, e)
          end
        end
        key = Simplify.rebuild_product(1, function).simplify
        (groups[key] ||= []) << coefficient
      end
      groups.values.map { |parts| parts.reduce(:+) }
    end

    def initial_values(general, init, n, constants)
      equations = init.map { |i, value| (general.subs(n => i) - Expression.lift(value)).simplify }
      solution = Solve.linear_system(equations, constants).first
      raise ArgumentError, "rsolve: the initial values #{init} are inconsistent" if solution.nil?
      general.subs(solution).simplify
    end
  end
end
