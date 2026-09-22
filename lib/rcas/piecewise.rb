# frozen_string_literal: true

module RCAS
  # A function given case by case:
  #
  #   piecewise(x < 0 => -x, :else => x**2)
  #
  # The conditions are Inequalities, Equations, Intervals, RealSets or the
  # default `:else`, and the first condition that holds decides (the rule
  # Maple and Mathematica use). Construction never rewrites: the branches
  # are kept as written, and a branch is picked only once the indeterminate
  # has a value.
  class Piecewise < Expression
    OTHERWISE = :else

    attr_reader :branches # [[condition, value], ...] in the order given

    def initialize(branches)
      raise ArgumentError, "piecewise needs at least one branch" if branches.empty?
      @branches = branches.map { |cond, value| [cond, Expression.lift(value)] }.freeze
      freeze
    end

    def conditions = branches.map(&:first)
    def values = branches.map(&:last)

    # Only the values are children: a condition is not an Expression, so
    # every generic rewrite carries it along untouched (see replace_with).
    def children = values
    def rebuild(*values) = Piecewise.new(conditions.zip(values))
    def to_sexp = [:piecewise, *branches.map { |cond, value| [cond.to_s, value.to_sexp] }]

    def ==(other) = other.is_a?(Piecewise) && other.branches == branches
    alias eql? ==
    def hash = [Piecewise, branches].hash

    def variables
      (conditions.flat_map { |c| Piecewises.condition_variables(c) } | values.flat_map(&:variables)).uniq.sort
    end

    def replace_with(table)
      return table[self] if table.key?(self)
      Piecewise.new(branches.map { |cond, value| [Piecewises.substitute(cond, table), value.replace_with(table)] })
    end

    # The indeterminate the conditions speak about.
    def var(given = nil) = Piecewises.var(self, given)

    # The value at a point; DomainError when no branch covers it.
    def at(value) = Piecewises.at(self, value)

    # [[RealSet, value], ...] with the first-match rule applied, so that the
    # sets are disjoint and branches that nothing is left of are dropped.
    def sets(x = nil) = Piecewises.located(self, Piecewises.var(self, x)).map { |_, set, value| [set, value] }

    # The finite points where the definition changes.
    def breakpoints(x = nil) = Piecewises.breakpoints(self, x)

    # The jumps, and the corners where the one-sided derivatives differ.
    def discontinuities(x = nil) = Piecewises.discontinuities(self, x)
    def kinks(x = nil) = Piecewises.kinks(self, x)
    def continuous?(x = nil) = discontinuities(x).empty?
    def differentiable?(x = nil) = continuous?(x) && kinks(x).empty?
  end

  # Building, deciding and calculus for Piecewise nodes.
  #
  # Each condition becomes a RealSet (inequalities.rb) whenever an operation
  # needs to know *where* a branch lives: integration cuts the range at the
  # breakpoints and glues the antiderivatives together there, limits pick
  # the branch they approach through, and solve keeps only the roots that
  # lie in their own piece.
  module Piecewises
    module_function

    # piecewise(x < 0 => -x, :else => x**2), a plain Hash, or an array of
    # [condition, value] pairs.
    def build(*positional, **keywords)
      pairs = []
      positional.each do |arg|
        case arg
        when Hash then pairs.concat(arg.to_a)
        when Array then pairs.concat(arg.map { |pair| Array(pair) })
        else raise ArgumentError, "piecewise: expected condition => value pairs, got #{arg.class}"
        end
      end
      pairs.concat(keywords.to_a)
      raise ArgumentError, "piecewise: expected condition => value pairs" if pairs.empty?
      Piecewise.new(pairs.map { |cond, value| [check_condition(cond), value] })
    end

    def check_condition(cond)
      case cond
      when Inequality, Equation, Interval, RealSet then cond
      when :else, :otherwise, true then Piecewise::OTHERWISE
      else raise ArgumentError, "piecewise: #{cond.inspect} is not a condition"
      end
    end

    # The otherwise-branch is the Symbol :else, and after the README's
    # `include RCAS::Functions` a Symbol responds to simplify and subs as
    # well - so the conditions are told apart by what they are, not by what
    # they respond to (the Math.respond_to? trap once more: third review, S9).
    def statement?(cond) = !cond.is_a?(Symbol) && (cond.is_a?(Expression) || cond.is_a?(Inequality) || cond.is_a?(Equation) || cond.is_a?(Membership) || cond.is_a?(Interval) || cond.is_a?(RealSet))

    def condition_variables(cond) = statement?(cond) && cond.respond_to?(:variables) ? cond.variables : []

    # The condition of a branch, typeset (latex.rb asks for this).
    def condition_latex(cond, pw)
      case cond
      when Piecewise::OTHERWISE then "\\text{otherwise}"
      when Interval, RealSet then "#{LaTeX.print(var(pw))} \\in #{cond.to_latex}"
      else LaTeX.of(cond)
      end
    rescue StandardError
      "\\text{#{cond}}"
    end

    def substitute(cond, table) = statement?(cond) && cond.respond_to?(:subs) ? cond.subs(table) : cond
    def simplify_condition(cond) = statement?(cond) && cond.respond_to?(:simplify) ? cond.simplify : cond

    # ---- deciding ----------------------------------------------------------

    # Pick the branch the conditions decide on, or simplify what is left.
    # The branches are walked in order and only the ones that can still
    # happen are touched: the value of a branch that cannot (1/x under
    # x < 0 at x = 0) is never even simplified.
    def simplify(pw)
      kept = []
      pw.branches.each do |cond, value|
        cond = simplify_condition(cond)
        holds = decide(cond)
        return safely(value) if holds && kept.empty?
        next if holds == false
        kept << [cond, value]
      end
      raise DomainError, "piecewise: no branch holds (#{pw.conditions.join('; ')})" if kept.empty?
      Piecewise.new(kept.map { |cond, value| [cond, safely(value)] })
    end

    def safely(value)
      value.simplify
    rescue ZeroDivisionError
      value
    end

    # true, false, or nil when the condition cannot be decided as it stands.
    # Exact on the boundary (Scalar.zero? decides equality), numeric for the
    # sign away from it.
    def decide(cond)
      return true if cond == Piecewise::OTHERWISE
      case cond
      when Interval, RealSet then nil
      when Equation
        cond.variables.empty? ? Scalar.zero?(cond.lhs - cond.rhs) : nil
      when Inequality
        return nil unless cond.variables.empty?
        f = (cond.lhs - cond.rhs).simplify
        return %i[<= >=].include?(cond.op) if Scalar.zero?(f)
        value = f.evalf
        value.is_a?(Numeric) && value.real? ? value.public_send(cond.op, 0) : nil
      end
    end

    # The value of the first branch that holds. An undecidable condition
    # stops the search: the node comes back unchanged rather than guessing.
    def select(pw)
      pw.branches.each do |cond, value|
        holds = decide(cond)
        return pw if holds.nil?
        return value if holds
      end
      raise DomainError, "piecewise: no branch holds (#{pw.conditions.join('; ')})"
    end

    def at(pw, point)
      x = var(pw)
      value = Expression.lift(point)
      pw.branches.each do |cond, branch|
        holds = cond.is_a?(Interval) || cond.is_a?(RealSet) ? cond.include?(numeric(value)) : decide(substitute(cond, { x => value }))
        raise DomainError, "piecewise: #{cond} does not decide at #{x} = #{point}" if holds.nil?
        return branch.subs(x => value).simplify if holds
      end
      raise DomainError, "piecewise: no branch covers #{x} = #{point}"
    end

    def numeric(value)
      v = value.is_a?(Numeric) ? value : Expression.lift(value).evalf
      raise DomainError, "piecewise: #{value} is not a real point" unless v.is_a?(Numeric) && v.real?
      v
    end

    # ---- where the branches live -------------------------------------------

    def var(pw, given = nil)
      return Expression.lift(given) if given
      names = pw.conditions.flat_map { |c| condition_variables(c) }.uniq
      names = pw.values.flat_map(&:variables).uniq if names.empty?
      raise ArgumentError, "piecewise: which indeterminate? (#{names.join(', ')})" unless names.size == 1
      Var.new(names.first)
    end

    # The RealSet a single condition describes.
    def set_of(cond, x)
      case cond
      when Piecewise::OTHERWISE then RealSet.reals
      when Interval then RealSet.new([cond])
      when RealSet then cond
      when Equation then RealSet.new(Solve.solve(cond, x.name, principal: true).map { |r| Interval.point(Expression.lift(r)) })
      when Inequality then Inequalities.solve(cond, x)
      end
    end

    # [[condition, RealSet, value], ...]: the branches with the first-match
    # rule applied, so the sets are disjoint. Branches that are left with
    # nothing disappear.
    def located(pw, x)
      taken = RealSet.empty
      pw.branches.filter_map do |cond, value|
        set = set_of(cond, x)
        raise NotImplementedError, "piecewise: can't locate #{cond}" if set.nil?
        set -= taken
        taken |= set
        set.empty? ? nil : [cond, set, value]
      end
    end

    def breakpoints(pw, given = nil)
      x = var(pw, given)
      points = located(pw, x).flat_map { |_, set, _| set.intervals.flat_map { |i| [i.low, i.high] } }
      points.reject { |p| Limits.infinite?(p) }.uniq.sort_by { |p| p.evalf }
    end

    # ---- hoisting -----------------------------------------------------------

    # An expression with a piecewise inside it is a piecewise: 2*f(x) with
    # f = piecewise(c => v) is piecewise(c => 2*v), because the branches
    # are disjoint. Integration and limits hoist before they start, so
    # that sq(x)*sin(k*x) is integrated branch by branch and not with the
    # piecewise as an opaque atom.
    def hoist(expr)
      node = expr.is_a?(Piecewise) ? nil : expr.each_node.find { |n| n.is_a?(Piecewise) }
      return expr unless node
      hoisted = Piecewise.new(node.branches.map { |cond, value| [cond, hoist(expr.subs(node => value))] })
      flatten(hoisted)
    end

    # A branch whose value is itself a piecewise: intersect the conditions.
    def flatten(pw)
      return pw unless pw.values.any? { |value| value.is_a?(Piecewise) }
      x = var(pw)
      branches = located(pw, x).flat_map do |_, set, value|
        value.is_a?(Piecewise) ? located(value, x).map { |_, inner, v| [set & inner, v] } : [[set, value]]
      end
      Piecewise.new(branches.reject { |set, _| set.empty? })
    rescue ArgumentError, NotImplementedError
      pw
    end

    # ---- calculus ----------------------------------------------------------

    # An antiderivative of each branch, shifted so that the pieces fit
    # together where they meet. The constant is not cosmetic: without it
    # every branch is still an antiderivative of its own piece, but the
    # function jumps at the breakpoint and definite integrals across it come
    # out wrong.
    def integrate(pw, x)
      x = Expression.lift(x)
      pieces = located(pw, x).map { |cond, set, value| [cond, set, Integrate.integrate(value, x)] }
      Piecewise.new(glue(pieces, x).map { |cond, _, antiderivative| [cond, antiderivative] })
    end

    # Walk the pieces from left to right, adding to each the constant that
    # continues the one before it at their common endpoint.
    def glue(pieces, x)
      order = pieces.each_with_index.sort_by { |(_, set, _), _| set.intervals.first.low_value }
      glued = []
      order.each do |(cond, set, antiderivative), index|
        previous = glued.last
        constant = Num.new(0)
        if previous && (point = meeting_point(previous.first[1], set))
          constant = jump(previous.first[2], antiderivative, point, x)
        end
        glued << [[cond, set, (antiderivative + constant).simplify], index]
      end
      glued.sort_by(&:last).map(&:first)
    end

    # The point where two neighbouring sets meet, if they do.
    def meeting_point(left, right)
      high = left.intervals.last.high
      low = right.intervals.first.low
      return nil if Limits.infinite?(high) || Limits.infinite?(low)
      Scalar.zero?(high - low) ? high : nil
    end

    # F_left(point) - F_right(point), or zero when that is not a number.
    def jump(before, after, point, x)
      value = (before - after).subs(x => point).simplify
      return Num.new(0) if value.each_node.any? { |n| (n.is_a?(Num) && n.value.is_a?(Float) && !n.value.finite?) || n.is_a?(Integral) }
      value
    rescue StandardError
      Num.new(0)
    end

    # Definite integral: the range is cut at the breakpoints and every piece
    # integrated with its own branch.
    def definite(pw, x, from, to)
      x = Expression.lift(x)
      from = Expression.lift(from)
      to = Expression.lift(to)
      return Neg.new(definite(pw, x, to, from)).simplify if from.evalf > to.evalf
      range = RealSet.new([Interval.new(from, to)])
      total = located(pw, x).sum(Num.new(0)) do |_, set, value|
        (set & range).intervals.sum(Num.new(0)) do |piece|
          Scalar.zero?(piece.high - piece.low) ? Num.new(0) : Integrate.definite(value, x, piece.low, piece.high)
        end
      end
      total.simplify
    end

    # ---- limits -------------------------------------------------------------

    # The limit picks the branch the point is approached through.
    def limit(pw, x, point, dir = nil)
      x = Expression.lift(x)
      point = Expression.lift(point)
      sides = dir ? [dir] : %i[left right]
      values = sides.map { |side| one_sided(pw, x, point, side) }
      return values.first if values.size == 1 && !values.first.nil?
      return values.first if values.size == 2 && !values.first.nil? && agree?(*values)
      Limit.new(pw, x, point)
    end

    def one_sided(pw, x, point, side)
      branch = approaching(pw, x, point, side) or return nil
      value = Limits.limit(branch, x, point, side)
      value.is_a?(Limit) ? nil : value
    end

    # The branch that owns the points just to the left/right of the point.
    def approaching(pw, x, point, side)
      value = interval_value(point)
      found = located(pw, x).find do |_, set, _|
        set.intervals.any? do |i|
          side == :left ? (i.low_value < value && value <= i.high_value) : (i.low_value <= value && value < i.high_value)
        end
      end
      found&.last
    end

    def interval_value(point) = Limits.infinite?(point) ? (point == OO ? Float::INFINITY : -Float::INFINITY) : point.evalf

    # ---- continuity ---------------------------------------------------------

    # The breakpoints where the two sides disagree, or where the function's
    # value is not the common limit: the jumps.
    def discontinuities(pw, given = nil)
      x = var(pw, given)
      breakpoints(pw, x).reject do |point|
        left = one_sided(pw, x, point, :left)
        right = one_sided(pw, x, point, :right)
        next false if left.nil? || right.nil?
        value = begin
          at(pw, point)
        rescue DomainError
          nil
        end
        agree?(left, right) && (value.nil? || agree?(left, value))
      end
    end

    # The breakpoints where the function is continuous but the one-sided
    # derivatives differ: the corners.
    def kinks(pw, given = nil)
      x = var(pw, given)
      jumps = discontinuities(pw, x)
      derivative = Piecewise.new(pw.branches.map { |cond, value| [cond, Differentiate.diff(value, x).simplify] })
      breakpoints(pw, x).reject do |point|
        next true if jumps.include?(point)
        agree?(one_sided(derivative, x, point, :left), one_sided(derivative, x, point, :right))
      end
    end

    def agree?(a, b)
      return false if a.nil? || b.nil?
      return true if a == b
      return false if a.is_a?(Limit) || b.is_a?(Limit)
      Scalar.zero?(Expression.lift(a) - Expression.lift(b))
    rescue StandardError
      false
    end

    # ---- solving -------------------------------------------------------------

    # Solve branch by branch and keep the roots that lie in their own piece.
    # A branch that is equal to the right-hand side everywhere contributes
    # its whole set, and then the answer is a RealSet rather than a list.
    # Every branch solved on its piece, completely: a periodic branch keeps
    # all its periods inside the piece (sin(x) = 0 on x > 0 is
    # {pi + pi*k | k in NN}, not pi alone), and a branch that is the
    # right-hand side everywhere contributes its whole piece - solve answers
    # that with a set now, and the old rescue waited for an error that no
    # longer comes (third review, S8).
    def solve(pw, rhs, given = nil)
      x = var(pw, given)
      rhs = Expression.lift(rhs)
      roots = []
      families = []
      everywhere = []
      located(pw, x).each do |_, set, value|
        found = begin
          Solve.solve(Equation.new(value, rhs), x.name)
        rescue ArgumentError => e
          raise unless e.message.include?("every value")
          everywhere << set
          next
        end
        unless found.is_a?(Array)
          everywhere << (found.is_a?(RealSet) ? set & found : set)
          next
        end
        found.each do |r|
          if r.is_a?(ImageSet)
            within(set, r).each { |m| m.is_a?(ImageSet) ? families << m : roots << m }
          elsif inside?(set, r)
            roots << r
          end
        end
      end
      roots = roots.uniq.sort_by { |r| Expression.lift(r).evalf }
      return roots + families if everywhere.empty?
      raise NotImplementedError, "piecewise: a whole piece and infinitely many points do not make one set" unless families.empty?
      everywhere.reduce(RealSet.new(roots.map { |r| Interval.point(Expression.lift(r)) })) { |a, b| a | b }
    end

    def inside?(set, root)
      value = Expression.lift(root).evalf
      value.is_a?(Numeric) && value.real? && set.include?(value)
    end

    MAX_POINTS = 1000

    # The members of the family a + b*k that lie in the set: the points of a
    # bounded piece, and a family over NN running away from the end of an
    # unbounded one.
    def within(set, family)
      return [] if family.nonreal?
      return [family] unless family.parameters.size == 1 && family.domain == ZZ
      k = family.parameters.first
      a = family.at(0)
      b = (family.at(1) - a).simplify
      av = Analysis.numeric(a)
      bv = Analysis.numeric(b)
      raise NotImplementedError, "piecewise: can't place #{family} in #{set}" if av.nil? || bv.nil? || bv.zero?
      set.intervals.flat_map do |interval|
        lo, hi = interval.low_value, interval.high_value
        first = lo.infinite? ? nil : ((lo - av) / bv)
        last = hi.infinite? ? nil : ((hi - av) / bv)
        first, last = last, first if bv.negative?
        low_k = first && (first.ceil - 1)
        high_k = last && (last.floor + 1)
        if low_k && high_k
          raise NotImplementedError, "piecewise: too many solutions in #{interval}" if high_k - low_k > MAX_POINTS
          (low_k..high_k).map { |i| family.at(i) }.select { |m| interval.include?(m) }
        elsif low_k
          start = (low_k..low_k + 3).find { |i| interval.include?(family.at(i)) }
          start ? [ImageSet.new((a + b * (Num.new(start) + k)).simplify, [k], NN)] : []
        elsif high_k
          start = (high_k - 3..high_k).to_a.reverse.find { |i| interval.include?(family.at(i)) }
          start ? [ImageSet.new((a + b * (Num.new(start) - k)).simplify, [k], NN)] : []
        else
          [family]
        end
      end
    end
  end
end
