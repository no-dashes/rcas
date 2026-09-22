# frozen_string_literal: true

module RCAS
  # A real interval with optional open ends; -oo and oo are allowed.
  class Interval
    attr_reader :low, :high, :left_open, :right_open

    def initialize(low, high, left_open: false, right_open: false)
      @low = Expression.lift(low)
      @high = Expression.lift(high)
      @left_open = left_open || Limits.infinite?(@low)
      @right_open = right_open || Limits.infinite?(@high)
      freeze
    end

    def self.open(low, high) = new(low, high, left_open: true, right_open: true)
    def self.closed(low, high) = new(low, high)
    def self.point(v) = new(v, v)
    def self.reals = new(Neg.new(OO).simplify, OO)

    def point? = low == high
    def low_value = Limits.infinite?(low) ? (low == OO ? Float::INFINITY : -Float::INFINITY) : low.evalf
    def high_value = Limits.infinite?(high) ? (high == OO ? Float::INFINITY : -Float::INFINITY) : high.evalf

    # Exact where the ends are close to v: 1 + 10**-15/2 lies in
    # (1, 1 + 10**-15), which Floats cannot see (Inequalities.compare).
    def include?(v)
      v = Expression.lift(v)
      value = v.evalf
      return false unless value.is_a?(Numeric) && value.real?
      below = Inequalities.compare(low, v)
      above = Inequalities.compare(v, high)
      return false if below.nil? || above.nil?
      (left_open ? below.negative? : below <= 0) && (right_open ? above.negative? : above <= 0)
    end

    def empty?
      order = Inequalities.compare(low, high) || (low_value <=> high_value)
      order.positive? || (order.zero? && (left_open || right_open))
    end

    def ==(other) = other.is_a?(Interval) && other.low == low && other.high == high && other.left_open == left_open && other.right_open == right_open
    alias eql? ==
    def hash = [Interval, low, high, left_open, right_open].hash

    def to_s
      return "{#{low}}" if point?
      "#{left_open ? '(' : '['}#{low}, #{high}#{right_open ? ')' : ']'}"
    end
    alias inspect to_s

    def to_latex(wrap: nil)
      return "\\{#{LaTeX.print(low)}\\}" if point?
      "\\left#{left_open ? '(' : '['}#{LaTeX.print(low)}, #{LaTeX.print(high)}\\right#{right_open ? ')' : ']'}"
    end
  end

  # A finite union of disjoint intervals, the result of solving an inequality.
  class RealSet
    include Enumerable
    attr_reader :intervals

    def initialize(intervals)
      @intervals = RealSet.normalize(intervals).freeze
      freeze
    end

    def self.empty = new([])
    def self.reals = new([Interval.reals])

    # Intervals with symbolic endpoints, already in order: no normalisation.
    def self.raw(intervals)
      set = allocate
      set.instance_variable_set(:@intervals, intervals.freeze)
      set.freeze
    end

    # Sort, drop empty pieces, merge touching ones. The ends are compared
    # exactly (Inequalities.compare), so two roots 10**-15 apart bound an
    # interval instead of merging into a point.
    def self.normalize(list)
      order = ->(a, b) { Inequalities.compare(a, b) || (a.evalf.to_f <=> b.evalf.to_f) }
      sorted = list.reject(&:empty?).sort do |a, b|
        c = order.call(a.low, b.low)
        c.zero? ? (a.left_open ? 1 : 0) <=> (b.left_open ? 1 : 0) : c
      end
      merged = []
      sorted.each do |i|
        last = merged.last
        touch = last && order.call(i.low, last.high)
        if last && (touch.negative? || (touch.zero? && !(i.left_open && last.right_open)))
          reach = order.call(i.high, last.high)
          if reach.positive? || (reach.zero? && !i.right_open)
            merged[-1] = Interval.new(last.low, i.high, left_open: last.left_open, right_open: i.right_open)
          end
        else
          merged << i
        end
      end
      merged
    end

    def each(&block) = intervals.each(&block)
    def empty? = intervals.empty?
    def include?(v) = intervals.any? { |i| i.include?(v) }
    def |(other) = RealSet.new(intervals + other.intervals)

    def &(other)
      pieces = intervals.product(other.intervals).map { |a, b| RealSet.intersect(a, b) }.compact
      RealSet.new(pieces)
    end

    def self.intersect(a, b)
      lo, lo_open = [[a.low, a.left_open, a.low_value], [b.low, b.left_open, b.low_value]].max_by { |_, open, v| [v, open ? 1 : 0] }.values_at(0, 1)
      hi, hi_open = [[a.high, a.right_open, a.high_value], [b.high, b.right_open, b.high_value]].min_by { |_, open, v| [v, open ? 0 : 1] }.values_at(0, 1)
      i = Interval.new(lo, hi, left_open: lo_open, right_open: hi_open)
      i.empty? ? nil : i
    end

    # The gaps between the intervals: everything the set leaves out.
    def complement
      pieces = []
      low, open = Neg.new(OO).simplify, false
      intervals.each do |i|
        pieces << Interval.new(low, i.low, left_open: open, right_open: !i.left_open)
        low, open = i.high, !i.right_open
      end
      pieces << Interval.new(low, OO, left_open: open)
      RealSet.new(pieces.reject { |i| i.point? && Limits.infinite?(i.low) })
    end

    def -(other) = self & other.complement

    def ==(other) = other.is_a?(RealSet) && other.intervals == intervals
    alias eql? ==
    def hash = [RealSet, intervals].hash

    def to_s
      return "{}" if empty?
      intervals.map(&:to_s).join(" ∪ ")
    end
    alias inspect to_s

    def to_latex(wrap: nil)
      return "\\emptyset" if empty?
      intervals.map(&:to_latex).join(" \\cup ")
    end
  end

  # lhs < rhs, lhs <= rhs, lhs > rhs, lhs >= rhs
  class Inequality
    OPS = { :< => "<", :<= => "<=", :> => ">", :>= => ">=", :!= => "!=" }.freeze
    FLIP = { :< => :>, :<= => :>=, :> => :<, :>= => :<=, :!= => :!= }.freeze

    attr_reader :lhs, :op, :rhs

    def initialize(lhs, op, rhs)
      raise ArgumentError, "unknown relation #{op}" unless OPS.key?(op)
      @lhs = Expression.lift(lhs)
      @op = op
      @rhs = Expression.lift(rhs)
      freeze
    end

    # As f OP 0 with OP in {<, <=}.
    def normalized
      f = (lhs - rhs).simplify
      %i[< <= !=].include?(op) ? [f, op] : [(-f).simplify, FLIP[op]]
    end

    def strict? = %i[< > !=].include?(op)
    def swap = Inequality.new(rhs, FLIP[op], lhs)
    def subs(*args) = Inequality.new(lhs.subs(*args), op, rhs.subs(*args))
    def simplify = Inequality.new(lhs.simplify, op, rhs.simplify)
    # hold { a < b }.doit: both sides evaluated, the statement kept (C9)
    def evaluate = Inequality.new(lhs.evaluate, op, rhs.evaluate)
    alias doit evaluate
    alias unhold evaluate
    def variables = (lhs.variables | rhs.variables).sort
    def solve(var = nil) = Inequalities.solve(self, var)

    def holds?(**bindings)
      value = Expression.lift((lhs - rhs).call(**bindings)).evalf
      raise ArgumentError, "#{self} is not numeric with #{bindings}" unless value.is_a?(Numeric) && value.real?
      value.public_send(op, 0)
    end

    def ==(other) = other.is_a?(Inequality) && other.lhs == lhs && other.op == op && other.rhs == rhs
    alias eql? ==
    def hash = [Inequality, lhs, op, rhs].hash

    def to_s = "#{lhs} #{OPS[op]} #{rhs}"
    alias inspect to_s

    def to_latex(wrap: nil)
      symbol = { :< => "<", :<= => "\\le", :> => ">", :>= => "\\ge", :!= => "\\ne" }[op]
      "#{LaTeX.print(lhs)} #{symbol} #{LaTeX.print(rhs)}"
    end
  end

  # A solution that depends on a parameter: one value per region of the
  # parameter line.
  #
  #   solve(x**2 - a >= 0, x)
  #   => a <= 0: (-oo, oo)
  #      a > 0:  (-oo, -a**(1/2)] ∪ [a**(1/2), oo)
  class Cases
    attr_reader :var, :branches # [[RealSet over var, value], ...]

    def initialize(var, branches)
      @var = var
      @branches = branches.freeze
      freeze
    end

    def size = branches.size
    def each(&block) = branches.each(&block)
    include Enumerable

    # The value for a concrete parameter, with the parameter substituted
    # into the ends: at(1) of a > 0: (a, oo) is (1, oo).
    def at(value)
      branch = branches.find { |cond, _| cond.include?(value) }
      raise ArgumentError, "#{var} = #{value} is not covered" unless branch
      set = branch.last
      return set unless set.is_a?(RealSet)
      point = Expression.lift(value)
      RealSet.new(set.intervals.map do |i|
        Interval.new(i.low.subs(var => point).simplify, i.high.subs(var => point).simplify, left_open: i.left_open, right_open: i.right_open)
      end)
    end

    def condition(set)
      parts = set.intervals.map do |i|
        lo, hi = i.low, i.high
        if i.point? then "#{var} = #{lo}"
        elsif Limits.infinite?(lo) && Limits.infinite?(hi) then "any #{var}"
        elsif Limits.infinite?(lo) then "#{var} #{i.right_open ? '<' : '<='} #{hi}"
        elsif Limits.infinite?(hi) then "#{var} #{i.left_open ? '>' : '>='} #{lo}"
        else "#{lo} #{i.left_open ? '<' : '<='} #{var} #{i.right_open ? '<' : '<='} #{hi}"
        end
      end
      parts.join(" or ")
    end

    def to_s
      texts = branches.map { |cond, _| "#{condition(cond)}:" }
      width = texts.map(&:size).max
      branches.each_with_index.map { |(_, value), i| "#{texts[i].ljust(width)} #{value}" }.join("\n")
    end
    alias inspect to_s

    def to_latex(wrap: nil)
      rows = branches.map do |cond, value|
        text = condition(cond).gsub("<=", "\\le").gsub(">=", "\\ge").gsub(" or ", "\\text{ or }")
        "#{value.to_latex} & \\text{if } #{text}"
      end
      "\\begin{cases} #{rows.join(' \\\\ ')} \\end{cases}"
    end
  end

  # Solving inequalities in one real variable by sign charts.
  #
  #   solve(x**2 < 4, x)                 # => (-2, 2)
  #   solve(abs(x - 1) <= 2, x)          # => [-1, 3]
  #   solve((x - 1)/(x + 1) >= 0, x)     # => (-oo, -1) ∪ [1, oo)
  #   solve([x > 1, x < 3], x)           # => (1, 3)
  module Inequalities
    module_function

    def solve(target, var = nil)
      list = target.is_a?(Array) ? target : [target]
      raise ArgumentError, "solve: expected inequalities" unless list.all? { |t| t.is_a?(Inequality) }
      x = var ? Expression.lift(var) : Solve.variable(list.map(&:lhs).reduce(:+) + list.map(&:rhs).reduce(:+), nil)
      list.map { |ineq| single(ineq, x) }.reduce { |a, b| a & b }
    end

    # The inequality is solved in its simplified form, and then the poles
    # of the inequality *as written* are taken out: x/x > 0 is 1 > 0 after
    # simplify, and still says nothing at x = 0.
    def single(ineq, x)
      raw = Expression.lift(ineq.lhs - ineq.rhs)
      f, op = ineq.normalized
      params = f.variables - [x.name]
      if params.size == 1
        return Parametric.new(f, op, x, Var.new(params.first)).solve
      elsif params.size > 1
        raise NotImplementedError, "inequalities with several parameters (#{params.join(', ')}) are not supported"
      end
      f = Num.new(0) if f.variables.include?(x.name) && Solve.rational_identity?(f, x)
      without_poles(solved(f, op, x), raw, x)
    end

    def solved(f, op, x)
      return not_equal(f, x) if op == :!=
      return (Scalar.zero?(f) ? (op == :<= ? RealSet.reals : RealSet.empty) : constant_case(f, op)) unless f.variables.include?(x.name)
      absolutes = f.each_node.select { |n| n.is_a?(Fn) && n.name == :abs && n.args.first.variables.include?(x.name) }.uniq
      return sign_chart(f, op, x) if absolutes.empty?
      piecewise(f, op, x, absolutes)
    end

    # The set less the real zeros of the denominators of raw.
    def without_poles(set, raw, x)
      return set unless set.is_a?(RealSet) && !set.empty?
      points = Analysis.denominators(raw, x).flat_map do |d|
        zeros = Solve.solve(d, x)
        raise NotImplementedError, "the poles of #{raw} (the zeros of #{d}) are not a finite set of points" unless zeros.is_a?(Array) && zeros.none? { |z| z.is_a?(ImageSet) }
        zeros.select { |z| real?(z) }.map { |z| real_part(z) }
      end
      return set if points.empty?
      set - RealSet.new(points.map { |p| Interval.point(p) })
    end

    # f != 0: everything except the zeros of f (and the points where f is undefined).
    def not_equal(f, x)
      return (Scalar.zero?(f) ? RealSet.empty : RealSet.reals) unless f.variables.include?(x.name)
      num, den = Solve.numerator_denominator(f, x)
      unless Solve.polynomial_coefficients(num, x) && Solve.polynomial_coefficients(den, x)
        raise NotImplementedError, "only polynomial and rational inequalities are supported: #{f}"
      end
      RealSet.new(regions(real_roots(num, x) + real_roots(den, x)))
    end

    def constant_case(f, op)
      sign = sign_of(f)
      raise NotImplementedError, "cannot decide the sign of #{f}" if sign.nil?
      holds = case op
              when :< then sign == :negative
              when :<= then sign != :positive
              end
      holds ? RealSet.reals : RealSet.empty
    end

    # Split the real line at the zeros of the abs arguments; on each piece
    # abs(u) is u or -u.
    def piecewise(f, op, x, absolutes)
      points = distinct(absolutes.flat_map { |a| real_roots(a.args.first, x) })
      pieces = regions(points).map do |region|
        t = sample(region)
        replaced = absolutes.reduce(f) do |acc, a|
          u = a.args.first
          sign = sign_of(u.subs(x => t)) or raise NotImplementedError, "cannot decide the sign of #{u} at #{t}"
          acc.subs(a => (sign == :negative ? -u : u))
        end
        RealSet.new([region]) & single(Inequality.new(replaced, op, 0), x)
      end
      # the split points themselves - where f has a value there at all
      points.each do |p|
        value = begin
          f.subs(x => p).simplify
        rescue ZeroDivisionError
          next
        end
        next unless Integrate.defined_value?(value)
        sign = sign_of(value)
        next if sign.nil?
        pieces << RealSet.new([Interval.point(p)]) if op == :< ? sign == :negative : sign != :positive
      end
      pieces.reduce(RealSet.empty) { |acc, s| acc | s }
    end

    def sign_chart(f, op, x)
      num, den = Solve.numerator_denominator(f, x)
      unless Solve.polynomial_coefficients(num, x) && Solve.polynomial_coefficients(den, x)
        raise NotImplementedError, "only polynomial and rational inequalities are supported: #{f}"
      end
      zeros = real_roots(num, x)
      poles = real_roots(den, x)
      points = distinct(zeros + poles)
      pieces = []
      regions(points).each do |region|
        t = sample(region)
        sign = sign_of(f.subs(x => t)) or raise NotImplementedError, "cannot decide the sign of #{f} at #{t}"
        pieces << region if sign == :negative || (sign == :zero && op == :<=)
      end
      unless op == :<
        zeros.each { |z| pieces << Interval.point(z) unless poles.any? { |p| compare(p, z)&.zero? } }
      end
      RealSet.new(pieces)
    end

    # Real roots as exact expressions, ordered. A root is real when that is
    # decided - (x - 1)**2 + 10**-26 has the roots 1 +- 10**-13*i, which a
    # tolerance of 1e-12 on the imaginary part took for the real 1.
    def real_roots(f, x)
      return [] unless f.variables.include?(x.name)
      roots = Solve.univariate(f, x, 0)
      sort(distinct(roots.select { |r| real?(r) }.map { |r| real_part(r) }))
    rescue ArgumentError
      raise NotImplementedError, "cannot find the real roots of #{f}"
    rescue NotImplementedError => e
      raise NotImplementedError, "cannot find the real roots of #{f}: #{e.message}"
    end

    # true when r is shown to be real, false when shown not to be; a root
    # that cannot be told is refused rather than guessed.
    def real?(r)
      r = Expression.lift(r)
      return true if (d = Infer.domain(r)) && d <= RR
      return r.value.is_a?(Numeric) && r.value.real? if r.is_a?(Num)
      imaginary = ComplexParts.im(r)
      decided = Decide.zero?(imaginary)
      # a parameter with a declared sign: i*a is not real for a > 0
      decided = false if decided.nil? && %i[positive negative].include?(RCAS.sign_of(imaginary))
      raise NotImplementedError, "cannot decide whether #{r} is real" if decided.nil?
      decided
    end

    def real_part(r)
      r = Expression.lift(r)
      return r if (d = Infer.domain(r)) && d <= RR
      return Num.new(r.value.real) if r.is_a?(Num) && r.value.is_a?(Complex)
      ComplexParts.re(r)
    end

    # Open intervals between consecutive points, from -oo to oo.
    def regions(points)
      sorted = sort(distinct(points))
      bounds = [Neg.new(OO).simplify] + sorted + [OO]
      bounds.each_cons(2).map { |a, b| Interval.open(a, b) }
    end

    # A point strictly inside an open region, exact: a short rational where
    # the Floats can see the gap, the midpoint otherwise.
    def sample(region)
      lo, hi = region.low, region.high
      return Num.new(0) if Limits.infinite?(lo) && Limits.infinite?(hi)
      return (hi - 1).simplify if Limits.infinite?(lo)
      return (lo + 1).simplify if Limits.infinite?(hi)
      a, b = region.low_value.to_f, region.high_value.to_f
      if a.finite? && b.finite? && b - a > 1e-9 * [1.0, a.abs, b.abs].max
        r = Num.new(((a + b) / 2).rationalize(Rational((b - a) / 4)))
        return r if compare(lo, r) == -1 && compare(r, hi) == -1
      end
      ((lo + hi) / 2).simplify
    end

    # The old Float test point, for callers that want a number.
    def test_point(region) = sample(region).evalf.to_f

    def sign_of(value)
      value = Expression.lift(value).simplify
      rank = infinity_rank(value)
      return rank.positive? ? :positive : :negative unless rank.zero?
      Decide.sign(value)
    end

    # -1, 0 or 1 for two real constants (the infinities included), or nil
    # when it cannot be told. The Floats answer when they are well apart;
    # close values are decided exactly.
    def compare(a, b)
      a = Expression.lift(a)
      b = Expression.lift(b)
      ra = infinity_rank(a)
      rb = infinity_rank(b)
      return ra <=> rb if ra != 0 || rb != 0
      fa = real_float(a)
      fb = real_float(b)
      if fa && fb && (fa - fb).abs > 1e-9 * [1.0, fa.abs, fb.abs].max
        return fa <=> fb
      end
      return 0 if a == b
      sign = sign_of(a - b)
      return { positive: 1, negative: -1, zero: 0 }[sign] if sign
      fa && fb ? fa <=> fb : nil
    end

    def infinity_rank(e)
      return 1 if e == OO
      return -1 if Limits.infinite?(e)
      0
    end

    def real_float(e)
      v = e.evalf
      v = v.value if v.is_a?(Num)
      v.is_a?(Numeric) && v.real? && v.to_f.finite? ? v.to_f : nil
    rescue StandardError, Math::DomainError
      nil
    end

    def distinct(points)
      points.each_with_object([]) { |p, out| out << p unless out.any? { |q| compare(p, q)&.zero? } }
    end

    def sort(points)
      points.sort { |p, q| compare(p, q) || (p.evalf.to_f <=> q.evalf.to_f) }
    end
  end

  # One-parameter inequalities: split the parameter line at the values where
  # the structure of the solution changes, solve exactly in each piece, and
  # write the endpoints through the symbolic roots.
  class Parametric
    def initialize(f, op, x, a)
      @f = f
      @op = op
      @x = x
      @a = a
    end

    def solve
      num, den = Solve.numerator_denominator(@f, @x)
      unless Solve.polynomial_coefficients(num, @x) && Solve.polynomial_coefficients(den, @x)
        raise NotImplementedError, "only polynomial and rational inequalities are supported: #{@f}"
      end
      roots = symbolic_roots(num) + symbolic_roots(den)
      points = critical_values(roots, num, den)
      pieces = []
      Inequalities.regions(points).each do |region|
        sample = sample_point(region)
        set = Inequalities.single(Inequality.new(@f.subs(@a => sample), @op, 0), @x)
        pieces << [region, symbolize(set, roots, sample)]
      end
      points.each do |c|
        # x/a > 1 at a = 0 is no inequality at all: it holds for no x
        at_point = begin
          Inequalities.single(Inequality.new(@f.subs(@a => c), @op, 0), @x)
        rescue ZeroDivisionError
          RealSet.empty
        end
        pieces << [Interval.point(c), at_point]
      end
      pieces.sort_by! { |region, _| [region.low_value, region.point? ? 0 : 1] }
      merged = merge(pieces)
      return merged.first.last if merged.size == 1
      Cases.new(@a, merged)
    end

    private

    def symbolic_roots(poly)
      return [] unless poly.variables.include?(@x.name)
      Solve.univariate(poly, @x, 0)
    rescue NotImplementedError, ArgumentError
      raise NotImplementedError, "cannot solve #{poly} = 0 for #{@x} with the parameter #{@a}"
    end

    # Parameter values where roots become real, coincide, or the degree drops.
    def critical_values(roots, num, den)
      values = []
      roots.each do |r|
        r.each_node do |n|
          next unless n.is_a?(Pow) && n.exponent.is_a?(Num) && n.exponent.value.is_a?(Rational) && n.base.variables.include?(@a.name)
          values.concat(parameter_roots(n.base))
        end
      end
      roots.combination(2) { |r1, r2| values.concat(parameter_roots((r1 - r2).simplify)) }
      [num, den].each do |poly|
        coeffs = Solve.polynomial_coefficients(poly, @x)
        next unless coeffs
        values.concat(parameter_roots(coeffs.last)) if coeffs.last.variables.include?(@a.name)
        # a coefficient that has no value there: x/a at a = 0
        coeffs.each { |c| Analysis.denominators(c, @a).each { |d| values.concat(parameter_roots(d)) } }
      end
      values.uniq { |v| v.evalf.round(10) }.sort_by(&:evalf)
    end

    def parameter_roots(expr)
      return [] unless expr.variables.include?(@a.name)
      Inequalities.real_roots(expr, @a)
    rescue NotImplementedError
      []
    end

    # A rational number strictly inside the region (exact arithmetic downstream).
    def sample_point(region)
      lo, hi = region.low_value, region.high_value
      value =
        if lo == -Float::INFINITY && hi == Float::INFINITY then 0.0
        elsif lo == -Float::INFINITY then hi - 1.0
        elsif hi == Float::INFINITY then lo + 1.0
        else (lo + hi) / 2.0
        end
      r = value.rationalize(Rational(1, 10**6))
      r = value.to_r unless (lo < r && r < hi)
      Num.new(r)
    end

    # Replace numeric endpoints by the symbolic roots that produced them.
    def symbolize(set, roots, sample)
      intervals = set.intervals.map do |i|
        Interval.new(symbolic_endpoint(i.low, roots, sample), symbolic_endpoint(i.high, roots, sample),
                     left_open: i.left_open, right_open: i.right_open)
      end
      RealSet.raw(intervals)
    end

    def symbolic_endpoint(value, roots, sample)
      return value if Limits.infinite?(value)
      target = value.evalf
      match = roots.find do |r|
        v = r.evalf(@a.name => sample.value)
        v.is_a?(Numeric) && v.real? && (v - target).abs <= 1e-9 * [1.0, target.abs].max
      end
      match || raise(NotImplementedError, "cannot express the endpoint #{value} through the roots")
    end

    # Adjacent pieces with the same solution share one condition.
    def merge(pieces)
      merged = []
      pieces.each do |region, set|
        if merged.any? && merged.last.last == set
          merged[-1] = [merged.last.first | RealSet.new([region]), set]
        else
          merged << [RealSet.new([region]), set]
        end
      end
      merged
    end
  end
end
