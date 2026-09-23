# frozen_string_literal: true

module RCAS
  # Linear optimization: a linear objective, maximized or minimized over the
  # points that satisfy linear inequalities and equations, exactly.
  #
  #   maximize(3*x + 2*y, [x + y <= 4, x + 3*y <= 6], nonnegative: true)
  #   # => maximum 12 at x = 4, y = 0
  #   minimize(x + y, [x + 2*y >= 3, 3*x + y >= 4], nonnegative: true)
  #   maximize(5*x + 4*y, [6*x + 4*y <= 24, x + 2*y <= 6], nonnegative: true, integer: true)
  #
  # The simplex method in two phases: the first finds a vertex of the
  # feasible region by minimizing the sum of artificial variables (a
  # positive minimum means there is no feasible point at all), the second
  # walks from vertex to vertex along edges that improve the objective until
  # none does, or until an edge runs off to infinity. Every pivot is chosen
  # by Bland's rule - the entering and the leaving variable are the ones of
  # smallest index among the candidates - which is what guarantees the walk
  # ends: with the textbook largest-coefficient rule a degenerate problem can
  # cycle for ever. The arithmetic is exact, so "optimal", "infeasible" and
  # "unbounded" are decisions, not tolerances.
  #
  # Variables are free unless the constraints bound them. A variable with a
  # lower bound x >= c is written c + x' with x' >= 0; one without is the
  # difference of two non-negative ones. `nonnegative: true` adds x >= 0 for
  # every variable, the textbook convention (Maple's NONNEGATIVE).
  #
  # `integer:` (true, or a list of variables) asks for whole-number values
  # and is answered by branch and bound: the linear program without the
  # integrality is solved, and a variable that comes out fractional splits
  # the problem into x <= floor and x >= ceil, each solved in turn; a branch
  # whose relaxation is no better than the best whole-number point found so
  # far is cut off.
  #
  # Sources (keys: MANUAL.md, Sources): the simplex method [Dan63]; the two
  # phases, Bland's rule and cycling, and duality as in [Chv83, ch. 2-5];
  # Bland's rule itself [Bla77]; branch and bound [LD60]; [Sch86] for the
  # theory of both.
  module LinearProgram
    # Branch and bound gives up after this many linear programs: "no
    # whole-number optimum" and "unlucky" look the same from in here, and a
    # CAS that spins for ever is worse than one that says so.
    MAX_NODES = 2000

    module_function

    def maximize(objective, constraints, vars = nil, nonnegative: false, integer: nil)
      optimize(:max, objective, constraints, vars, nonnegative: nonnegative, integer: integer)
    end

    def minimize(objective, constraints, vars = nil, nonnegative: false, integer: nil)
      optimize(:min, objective, constraints, vars, nonnegative: nonnegative, integer: integer)
    end

    def optimize(sense, objective, constraints, vars, nonnegative:, integer:)
      objective = Expression.lift(objective)
      constraints = Array(constraints).flatten
      vars = variables(objective, constraints, vars)
      floats = ([objective] + constraints.flat_map { |c| [c.lhs, c.rhs] }).any? { |e| float?(e) }
      rows = constraints.map { |c| row(c, vars) }
      rows += vars.map { |v| [unit(vars, v), :>=, 0r] } if nonnegative
      cost, constant = linear(objective, vars, "the objective")
      cost = cost.map(&:-@) if sense == :min
      problem = Problem.new(vars, rows, cost)
      whole = integer_variables(integer, vars)
      found = whole.empty? ? problem.solve : branch_and_bound(problem, whole)
      result(sense, found, objective, constant, vars, floats, integer: !whole.empty?)
    end

    # ---- reading the problem ------------------------------------------------------

    def variables(objective, constraints, given)
      constraints.each do |c|
        next if c.is_a?(Equation) || (c.is_a?(Inequality) && !c.strict?)
        if c.is_a?(Inequality)
          raise ArgumentError, "#{c}: a strict inequality has no optimum on its boundary, where a linear optimum lies; write it with <= or >=" unless c.op == :!=
          raise ArgumentError, "#{c}: != cuts the feasible region in two, which is no longer a linear program"
        end
        raise ArgumentError, "a constraint must be an inequality (x + y <= 4) or an equation (eq(x + y, 3)), got #{c.inspect}"
      end
      names = given ? Array(given).map { |v| Expression.lift(v) } : nil
      names ||= (objective.variables | constraints.flat_map { |c| c.lhs.variables | c.rhs.variables }).sort.map { |n| Var.new(n) }
      raise ArgumentError, "the variables must be symbols, got #{names.inspect}" unless names.all?(Var)
      names
    end

    def integer_variables(integer, vars)
      return [] if integer.nil? || integer == false
      return (0...vars.size).to_a if integer == true
      Array(integer).map do |v|
        i = vars.index(Expression.lift(v))
        raise ArgumentError, "integer: #{v} is not one of the variables #{vars.join(', ')}" if i.nil?
        i
      end
    end

    # [coefficients, :<= | :>= | :==, right-hand side]
    def row(constraint, vars)
      coeffs, constant = linear(constraint.lhs - constraint.rhs, vars, constraint.to_s)
      op = constraint.is_a?(Equation) ? :== : { :<= => :<=, :>= => :>= }.fetch(constraint.op)
      [coeffs, op, -constant]
    end

    def unit(vars, v) = vars.map { |w| w == v ? 1r : 0r }

    # The coefficient of each variable and the constant term of a linear
    # expression, as Rationals.
    def linear(expr, vars, what)
      constant, table = Expand.table(Expression.lift(expr))
      coeffs = Array.new(vars.size, 0r)
      table.each do |factors, coeff|
        var = factors.size == 1 && factors.first[1] == 1 ? vars.index(factors.first[0]) : nil
        unless var
          term = Simplify.rebuild_product(coeff, factors)
          raise ArgumentError, "#{what} is not linear in #{vars.join(', ')}: #{term}" if term.variables.intersect?(vars.map(&:name))
          raise ArgumentError, "#{what} has a parameter, #{term.variables.join(', ')}; the coefficients must be numbers"
        end
        coeffs[var] += number(coeff, what)
      end
      [coeffs, number(constant, what)]
    end

    # A Float is taken as the decimal it was written as (0.1 as 1/10), and
    # the answer is then reported in Floats again.
    def number(value, what)
      value = value.value if value.is_a?(Num)
      return value.to_r if value.is_a?(Integer) || value.is_a?(Rational)
      return Rational(value.to_s) if value.is_a?(Float) && value.finite?
      raise ArgumentError, "#{what}: the coefficients must be rational numbers, got #{value}"
    end

    def float?(e) = Expression.lift(e).each_node.any? { |n| n.is_a?(Num) && n.value.is_a?(Float) }

    # ---- the problem in standard form ---------------------------------------------

    # max cost*x subject to rows, x free unless a row bounds it from below.
    # Solved by `solve`, which answers [:optimal, x, unique] | [:infeasible]
    # | [:unbounded].
    class Problem
      attr_reader :vars, :rows, :cost

      def initialize(vars, rows, cost)
        @vars = vars
        @rows = rows
        @cost = cost
      end

      def with(extra_rows) = Problem.new(vars, rows + extra_rows, cost)

      def solve
        shift, split = substitution
        tableau, basis, columns = standard_form(shift, split)
        artificial = columns[:artificial]
        # phase 1: a feasible vertex, or the proof that there is none
        phase_one = Array.new(columns[:count], 0r)
        artificial.each { |j| phase_one[j] = -1r }
        LinearProgram.simplex(tableau, basis, phase_one, (0...columns[:count]).to_a)
        return [:infeasible] unless basis.each_with_index.all? { |j, i| !artificial.include?(j) || tableau[i][-1].zero? }
        LinearProgram.drive_out(tableau, basis, artificial)
        # phase 2: the objective, over the columns that are not artificial
        allowed = (0...columns[:count]).reject { |j| artificial.include?(j) }
        objective = Array.new(columns[:count], 0r)
        columns[:structure].each { |j, var, sign| objective[j] += sign * cost[var] }
        status, = LinearProgram.simplex(tableau, basis, objective, allowed)
        return [:unbounded] if status == :unbounded
        values = Array.new(columns[:count], 0r)
        basis.each_with_index { |j, i| values[j] = tableau[i][-1] }
        x = point(values, columns, shift)
        [:optimal, x, LinearProgram.unique(tableau, basis, objective, allowed, columns)]
      end

      # x_i = shift_i + x'_i where the rows give a lower bound, and
      # x_i = p_i - m_i where they give none (split).
      def substitution
        shift = Array.new(vars.size)
        rows.each do |coeffs, op, rhs|
          nonzero = coeffs.each_index.reject { |j| coeffs[j].zero? }
          next unless nonzero.size == 1
          j = nonzero.first
          a = coeffs[j]
          next unless (op == :>= && a.positive?) || (op == :<= && a.negative?) || op == :==
          bound = rhs / a
          shift[j] = shift[j] ? [shift[j], bound].max : bound
        end
        [shift, shift.each_index.select { |j| shift[j].nil? }]
      end

      # The tableau [A | b] with b >= 0, a slack for every <=, a surplus
      # and an artificial for every >=, an artificial for every equation;
      # the starting basis is the slacks and the artificials.
      def standard_form(shift, split)
        structure = [] # [column, variable, sign]
        vars.each_index do |i|
          structure << [structure.size, i, 1r]
          structure << [structure.size, i, -1r] if split.include?(i)
        end
        n = structure.size
        m = rows.size
        slack_count = rows.count { |_, op, _| op != :== }
        # at most one artificial per row; which rows need one is known only
        # once b is made non-negative, so the unused columns are cut at the end
        count = n + slack_count + m
        tableau = []
        basis = []
        artificial = []
        slack = n
        extra = n + slack_count
        rows.each do |coeffs, op, rhs|
          line = Array.new(count + 1, 0r)
          structure.each { |j, var, sign| line[j] = sign * coeffs[var] }
          b = rhs - coeffs.each_index.sum { |var| shift[var] ? coeffs[var] * shift[var] : 0r }
          if b.negative?
            line.map!(&:-@)
            b = -b
            op = { :<= => :>=, :>= => :<=, :== => :== }[op]
          end
          line[-1] = b
          if op == :<=
            line[slack] = 1r
            basis << slack
            slack += 1
          else
            if op == :>=
              line[slack] = -1r
              slack += 1
            end
            line[extra] = 1r
            basis << extra
            artificial << extra
            extra += 1
          end
          tableau << line
        end
        count = extra
        tableau.map! { |line| line.first(count) + [line[-1]] }
        [tableau, basis, { structure: structure, artificial: artificial, count: count, split: split }]
      end

      def point(values, columns, shift)
        x = shift.map { |s| s || 0r }
        columns[:structure].each { |j, var, sign| x[var] += sign * values[j] }
        x
      end
    end

    # Pivot until no allowed column improves the objective (maximized),
    # choosing by Bland's rule. [:optimal] or [:unbounded, column].
    def simplex(tableau, basis, cost, allowed)
      loop do
        reduced = reduced_costs(tableau, basis, cost)
        entering = allowed.find { |j| !basis.include?(j) && reduced[j].positive? }
        return [:optimal] unless entering
        leaving = ratio_row(tableau, basis, entering)
        return [:unbounded, entering] unless leaving
        pivot(tableau, basis, leaving, entering)
      end
    end

    # c_j - c_B . column j: how much the objective gains per unit of x_j
    def reduced_costs(tableau, basis, cost)
      (0...cost.size).map do |j|
        cost[j] - basis.each_with_index.sum { |b, i| cost[b] * tableau[i][j] }
      end
    end

    # The row that limits the entering column first; a tie goes to the
    # basic variable of smallest index (Bland). nil when nothing limits it.
    def ratio_row(tableau, basis, entering)
      candidates = tableau.each_index.select { |i| tableau[i][entering].positive? }
      return nil if candidates.empty?
      candidates.min_by { |i| [tableau[i][-1] / tableau[i][entering], basis[i]] }
    end

    def pivot(tableau, basis, row, column)
      p = tableau[row][column]
      tableau[row] = tableau[row].map { |v| v / p }
      tableau.each_index do |i|
        next if i == row || tableau[i][column].zero?
        f = tableau[i][column]
        tableau[i] = tableau[i].zip(tableau[row]).map { |a, b| a - f * b }
      end
      basis[row] = column
    end

    # After phase 1 an artificial can still be basic, at level 0. It is
    # pivoted out on any other column of its row; a row with no other entry
    # says an equation was implied by the others, and it goes.
    def drive_out(tableau, basis, artificial)
      tableau.each_index.to_a.reverse_each do |i|
        next unless artificial.include?(basis[i])
        j = (0...tableau[i].size - 1).find { |c| !artificial.include?(c) && !tableau[i][c].zero? }
        if j
          pivot(tableau, basis, i, j)
        else
          tableau.delete_at(i)
          basis.delete_at(i)
        end
      end
    end

    # Whether the optimal point is the only one. A non-basic column with
    # reduced cost 0 is an edge along which the objective stays put; the
    # point is unique when every such edge leaves x unchanged (a split
    # variable's partner does), and not when one moves x a positive
    # distance. An edge that moves x but cannot be followed at all (a
    # degenerate vertex) decides nothing: nil.
    def unique(tableau, basis, cost, allowed, columns)
      reduced = reduced_costs(tableau, basis, cost)
      verdict = true
      allowed.each do |j|
        next if basis.include?(j) || !reduced[j].zero?
        direction = Hash.new(0r)
        columns[:structure].each do |col, var, sign|
          change = col == j ? 1r : -(basis.index(col) ? tableau[basis.index(col)][j] : 0r)
          direction[var] += sign * change
        end
        next if direction.values.all?(&:zero?)
        row = ratio_row(tableau, basis, j)
        return false if row.nil? || tableau[row][-1].positive?
        verdict = nil
      end
      verdict
    end

    # ---- whole numbers --------------------------------------------------------------

    def branch_and_bound(problem, whole)
      best = nil
      stack = [[]]
      nodes = 0
      until stack.empty?
        extra = stack.pop
        nodes += 1
        raise RCAS::Unsupported, "integer: no answer after #{MAX_NODES} linear programs; the branch and bound gives up" if nodes > MAX_NODES
        status, x, = problem.with(extra).solve
        next if status == :infeasible
        if status == :unbounded
          raise RCAS::Unsupported, "integer: the problem without integrality is unbounded, and rcas does not decide whether a whole-number point runs off with it"
        end
        value = problem.cost.each_index.sum { |i| problem.cost[i] * x[i] }
        next if best && value <= best[1]
        i = whole.find { |k| x[k].denominator != 1 }
        if i.nil?
          best = [x, value]
          next
        end
        coeffs = LinearProgram.unit(problem.vars, problem.vars[i])
        stack << (extra + [[coeffs, :>=, x[i].ceil.to_r]])
        stack << (extra + [[coeffs, :<=, x[i].floor.to_r]])
      end
      best ? [:optimal, best[0], nil] : [:infeasible]
    end

    # ---- the answer -----------------------------------------------------------------

    def result(sense, found, objective, constant, vars, floats, integer:)
      status, x, unique = found
      return Result.new(sense, status, nil, nil, objective, nil) if status == :infeasible
      return Result.new(sense, status, sense == :max ? OO : Neg.new(OO).simplify, nil, objective, nil) if status == :unbounded
      value = objective.subs(vars.zip(x).to_h { |v, e| [v, Num.new(e)] }).simplify
      value = Num.new(Simplify.normalize_number(number(value, "the objective") )) if value.is_a?(Num)
      point = Assignment[vars.zip(x).to_h { |v, e| [v, Num.new(floats ? e.to_f : Simplify.normalize_number(e))] }]
      value = Num.new(value.value.to_f) if floats && value.is_a?(Num)
      Result.new(sense, :optimal, value, point, objective, integer ? nil : unique)
    end

    # What maximize and minimize answer: the status, the optimal value and
    # the point where it is taken. `value, point = maximize(...)` works,
    # because the result spreads like an array.
    class Result
      attr_reader :sense, :status, :value, :point, :objective, :unique

      def initialize(sense, status, value, point, objective, unique)
        @sense = sense
        @status = status
        @value = value
        @point = point
        @objective = objective
        @unique = unique
        freeze
      end

      def optimal? = status == :optimal
      def infeasible? = status == :infeasible
      def unbounded? = status == :unbounded
      def unique? = unique
      def to_a = [value, point]
      def to_ary = to_a
      def ==(other) = other.is_a?(Result) && [sense, status, value, point] == [other.sense, other.status, other.value, other.point]

      def to_s
        word = sense == :max ? "maximum" : "minimum"
        case status
        when :infeasible then "infeasible: no point satisfies the constraints"
        when :unbounded then "unbounded: #{objective} has no #{word} on the feasible region"
        else
          at = point.empty? ? "" : " at #{point.map { |v, e| "#{v} = #{e}" }.join(', ')}"
          "#{word} #{value}#{at}#{unique == false ? ' (one of infinitely many optimal points)' : ''}"
        end
      end

      def inspect = to_s

      def to_latex(wrap: nil)
        word = sense == :max ? "\\max" : "\\min"
        case status
        when :infeasible then "\\text{infeasible}"
        when :unbounded then "#{word} = #{sense == :max ? '' : '-'}\\infty"
        else
          at = point.map { |v, e| "#{LaTeX.of(v)} = #{LaTeX.of(e)}" }.join(",\\ ")
          "#{word} = #{LaTeX.of(value)}#{at.empty? ? '' : "\\ \\text{at}\\ #{at}"}"
        end
      end
    end
  end
end
