# frozen_string_literal: true

module RCAS
  OO = Const.new(:oo, Float::INFINITY)
  register_infinity

  # Unevaluated limit.
  class Limit < Expression
    attr_reader :expr, :var, :point

    def initialize(expr, var, point)
      @expr = expr
      @var = var
      @point = point
      freeze
    end

    def children = [expr, var, point]
    def rebuild(expr, var, point) = Limit.new(expr, var, point)
    def to_sexp = [:limit, expr.to_sexp, var.to_sexp, point.to_sexp]
  end

  class SeriesError < StandardError; end

  # Truncated Puiseux series in a local variable t: sum of coeff * t**exp for
  # rational exponents below +order+. Coefficients are Expressions and may
  # contain the marker variable LOG for log(t).
  #
  # Sources: series arithmetic (product, quotient, composition, powers) as
  # in [Knu98, §4.7]. Limits take the leading term of this expansion at the
  # point; that is the textbook strategy, not Gruntz's MRV algorithm
  # [Gru96], which is why bounded oscillation is left unevaluated. Keys:
  # MANUAL.md, Sources.
  class Series
    LOG = Var.new(:_L)

    attr_reader :terms, :order

    def initialize(terms, order)
      @order = terms.is_a?(Hash) ? order : order
      @terms = terms.select { |e, c| e < order && !Scalar.zero?(c) }.sort.to_h.freeze
      freeze
    end

    def self.constant(c, order)
      c = Expression.lift(c)
      new(Scalar.zero?(c) ? {} : { 0 => c }, order)
    end

    def self.variable(order) = new({ 1 => Num.new(1) }, order)

    def zero? = terms.empty?
    def min_exponent = terms.keys.min
    def low = min_exponent || order
    def constant_term = terms[0] || Num.new(0)
    def leading = terms.first

    def +(other) = Series.new(terms.merge(other.terms) { |_, a, b| (a + b).simplify }, [order, other.order].min)
    def -(other) = self + other.scale(Num.new(-1))
    def scale(c) = Series.new(terms.transform_values { |v| (v * c).simplify }, order)
    def shift(k) = Series.new(terms.to_h { |e, c| [norm(e + k), c] }, norm(order + k))
    def truncate(n) = Series.new(terms, [order, n].min)

    def *(other)
      new_order = [order + other.low, other.order + low].min
      out = {}
      terms.each do |e1, c1|
        other.terms.each do |e2, c2|
          e = norm(e1 + e2)
          next if e >= new_order
          out[e] = out[e] ? (out[e] + c1 * c2).simplify : (c1 * c2).simplify
        end
      end
      Series.new(out, new_order)
    end

    def **(n)
      return inverse**(-n) if n.negative?
      result = Series.constant(1, order + low * [n - 1, 0].max)
      n.times { result *= self }
      result
    end

    # 1 / self: pull out c*t**m, then a geometric series in the rest.
    def inverse
      raise SeriesError, "cannot invert a series that is zero to the known order" if zero?
      m = min_exponent
      c = terms[m]
      u = shift(-m).scale((Num.new(1) / c).simplify) - Series.constant(1, order - m)
      Series.compose(u, order - m) { |k| Num.new((-1)**k) }.scale((Num.new(1) / c).simplify).shift(-m)
    end

    # sum_{k>=0} coeff(k) * u**k, u with positive minimal exponent.
    def self.compose(u, order)
      c0 = Expression.lift(yield(0))
      return Series.constant(c0, order) if u.zero?
      mu = u.min_exponent
      raise SeriesError, "composition needs a series without constant term" unless mu.positive?
      kmax = (order / mu).ceil
      acc = Series.constant(c0, order)
      pow = Series.constant(1, order)
      (1..kmax).each do |k|
        pow = (pow * u).truncate(order)
        break if pow.zero?
        acc += pow.scale(Expression.lift(yield(k)))
      end
      acc
    end

    def to_expr(t, log_of_t)
      sum = terms.reduce(Num.new(0)) { |acc, (e, c)| acc + c * Simplify.power_node(t, e) }
      sum.subs(LOG => log_of_t).simplify
    end

    private

    def norm(e) = Simplify.normalize_number(e.is_a?(Rational) ? e : Rational(e))
  end

  # Series expansion and limits.
  #
  #   series(sin(x), x, 0, 6)      # => x - x**3/6 + x**5/120 + O(x**6)
  #   limit(sin(x)/x, x, 0)        # => 1
  #   limit((1 + 1/x)**x, x, oo)   # => e
  module Limits
    module_function

    T = Var.new(:_t)

    def series(f, x, a = 0, n = 6, big_o: true)
      f = Expression.lift(f)
      x = Expression.lift(x)
      a = Expression.lift(a)
      g, back, oh = localize(f, x, a)
      s = adaptive(g, n)
      result = back.call(s.to_expr(T, Fn.new(:log, [T])))
      result = result + Fn.new(:O, [oh.call(s.order)]) if big_o
      result.simplify
    end

    def taylor(f, x, a = 0, n = 6) = series(f, x, a, n, big_o: false)

    # dir: :both (default for finite points), :right or :left
    def limit(f, x, a, dir = nil)
      f = Expression.lift(f)
      x = Expression.lift(x)
      a = Expression.lift(a)
      g, = localize(f, x, a)
      side = infinite?(a) ? :right : (dir || :both)
      if side == :both
        right = one_sided(g, :right)
        left = one_sided(g, :left)
        return right if right == left || (right.is_a?(Num) && left.is_a?(Num) && right == left)
        return Limit.new(f, x, a)
      end
      one_sided(g, side)
    rescue SeriesError, ZeroDivisionError, NotImplementedError
      Limit.new(f, x, a)
    end

    # ---- helpers -----------------------------------------------------------

    def infinite?(a) = a == OO || a == Neg.new(OO)

    # [g(t), back-substitution, O-term builder] with the limit at t -> 0+
    def localize(f, x, a)
      if a == OO
        [f.subs(x => 1 / T), ->(e) { e.subs(T => 1 / x) }, ->(o) { Pow.new(x, Num.new(-o)) }]
      elsif a == Neg.new(OO)
        [f.subs(x => -1 / T), ->(e) { e.subs(T => -1 / x) }, ->(o) { Pow.new(x, Num.new(-o)) }]
      else
        shift = Scalar.zero?(a) ? x : x - a
        [f.subs(x => T + a), ->(e) { e.subs(T => shift) }, ->(o) { Simplify.power_node(shift, o) }]
      end
    end

    def adaptive(g, n)
      order = n
      s = nil
      6.times do
        s = expand(g, order)
        return s.truncate(n) if s.order >= n
        order += (n - s.order) + 1
      end
      s
    end

    def one_sided(g, side)
      g = g.subs(T => -T) if side == :left
      s = nil
      begin
        [4, 8, 16, 32].each do |n|
          s = adaptive(g, n)
          break unless s.zero?
        end
      rescue SeriesError
        return termwise(g) || exponential_fallback(g)
      end
      return Num.new(0) if s.zero?

      e, c = s.leading
      if c.variables.include?(Series::LOG.name)
        m = Var.new(:_M)
        poly = Solve.polynomial_coefficients(c.subs(Series::LOG => -m).expand, m) or raise SeriesError, "log coefficient"
        degree = poly.size - 1
        lc = poly.last
        return Num.new(0) if e.positive?
        return c.simplify if e.zero? && degree.zero?
        return signed_infinity(lc)
      end
      return Num.new(0) if e.positive?
      return c.simplify if e.zero?
      signed_infinity(c)
    end

    # exp(-1/t)*t and friends: look at log(g) instead, whose leading term
    # decides between 0, oo and exp(finite).
    def exponential_fallback(g)
      coeff, factors = Simplify.factorize(g)
      exponential = factors.any? { |base, exp| base == Simplify.exp_base || (base.is_a?(Fn) && base.name == :exp) || (exp.is_a?(Expression) && exp.variables.include?(T.name)) }
      raise SeriesError, "no exponential factor in #{g}" unless exponential
      negative = Simplify.negative?(coeff)
      positive = negative ? Simplify.rebuild_product(-coeff, factors) : g
      value = one_sided(log_of(positive), :right)
      raise SeriesError, "unexpected log limit #{value}" if value.is_a?(Limit)
      result =
        if value == Neg.new(OO) then Num.new(0)
        elsif value == OO then OO
        else Fn.new(:exp, [value]).simplify
        end
      negative ? Neg.new(result).simplify : result
    end

    # The limit of a sum is the sum of the limits when every term has a
    # finite one (exp(-1/t)/t + erf(1/t) at t -> 0+, say); nil otherwise.
    def termwise(g)
      constant, terms = Simplify.termize(g)
      if terms.size + (constant.zero? ? 0 : 1) < 2 # c * (a + b): distribute first
        return nil unless g.each_node.any? { |n| n.is_a?(Add) || n.is_a?(Sub) }
        constant, terms = Simplify.termize(Expand.expand(g))
        return nil if terms.size + (constant.zero? ? 0 : 1) < 2
      end
      total = Num.new(constant)
      terms.each do |factors, coeff|
        value = one_sided(Simplify.rebuild_product(coeff, factors), :right)
        return nil if value.is_a?(Limit) || infinite?(value) || value.each_node.any? { |n| n == OO }
        total += value
      end
      total.simplify
    end

    def log_of(g)
      coeff, factors = Simplify.factorize(g)
      raise SeriesError, "sign of #{g}" unless coeff.is_a?(Numeric) && coeff.real? && coeff.positive?
      factors.reduce(Fn.new(:log, [Num.new(coeff)])) do |acc, (base, exp)|
        piece = base == Simplify.exp_base ? Expression.lift(exp) : Expression.lift(exp) * Fn.new(:log, [base])
        acc + piece
      end
    end

    def signed_infinity(c)
      sign = Scalar.numeric?(c) ? c.value : (c.variables.empty? ? c.evalf : nil)
      raise SeriesError, "sign of #{c} unknown" unless sign.is_a?(Numeric) && sign.real?
      sign.negative? ? Neg.new(OO).simplify : OO
    end

    # ---- the expansion ----------------------------------------------------------

    def expand(f, order)
      case f
      when Num, Const then Series.constant(f, order)
      when Var then f == T ? Series.variable(order) : Series.constant(f, order)
      when Add then expand(f.left, order) + expand(f.right, order)
      when Sub then expand(f.left, order) - expand(f.right, order)
      when Neg then expand(f.arg, order).scale(Num.new(-1))
      when Mul then product(f, order)
      when Div then product(Mul.new(f.left, Pow.new(f.right, Num.new(-1))), order)
      when Pow then power(f, order)
      when Fn then function(f, order)
      else raise SeriesError, "no series for #{f.class}"
      end
    end

    # Factors are expanded to an order that keeps the product exact to +order+.
    def product(f, order)
      _, factors = Simplify.factorize(f)
      coeff, = Simplify.factorize(f)
      parts = factors.map { |base, exp| [base, exp] }
      known = parts.map { |base, exp| expand_power(base, exp, order) }
      lows = known.map(&:low)
      total_low = lows.sum
      series = parts.each_with_index.map do |(base, exp), i|
        needed = order - (total_low - lows[i])
        needed > order ? expand_power(base, exp, needed) : known[i]
      end
      series.reduce(Series.constant(coeff, order + [total_low, 0].min)) { |acc, s| acc * s }.truncate(order)
    end

    def expand_power(base, exp, order)
      return expand(base, order) if exp == 1
      power(Pow.new(base, Expression.lift(exp)), order)
    end

    def power(f, order)
      base, exp = f.base, f.exponent
      if exp.is_a?(Num) && exp.integer?
        n = exp.value
        s = expand(base, order)
        return s.truncate(order)**0 if n.zero?
        return (expand(base, order + [n - 1, 0].max)**n).truncate(order) if n.positive?
        return (expand(base, order + 2 * s.low.abs)**n).truncate(order) if n.negative?
      end
      if base.is_a?(Fn) && base.name == :exp
        return function(Fn.new(:exp, [base.args.first * exp]), order)
      end
      if exp.variables.include?(T.name)
        return function(Fn.new(:exp, [exp * Fn.new(:log, [base])]), order)
      end
      s = expand(base, order)
      raise SeriesError, "power of a series that is zero to the known order" if s.zero?
      m = s.min_exponent
      c = s.terms[m]
      r = exp.is_a?(Num) ? exp.value : exp
      raise SeriesError, "#{f}: symbolic exponent on a vanishing base" if !r.is_a?(Numeric) && !m.zero?
      u = s.shift(-m).scale((Num.new(1) / c).simplify) - Series.constant(1, order - m)
      binomial = ->(k) { (0...k).reduce(Num.new(1)) { |acc, j| (acc * (Expression.lift(r) - j) / (j + 1)).simplify } }
      lead = Simplify.power_node(c, r)
      Series.compose(u, order - m, &binomial).scale(lead.simplify).shift(r.is_a?(Numeric) ? m * r : 0)
    end

    def function(f, order)
      raise SeriesError, "#{f.name} takes one argument" unless f.args.size == 1
      name = f.name
      return expand(Fn.new(:sin, f.args) / Fn.new(:cos, f.args), order) if name == :tan

      s = expand(f.args.first, order)
      return Series.constant(Fn.new(name, [s.constant_term]).simplify, order) if s.zero? || (s.terms.keys - [0]).empty?

      if name == :log
        m = s.min_exponent
        c = s.terms[m]
        u = s.shift(-m).scale((Num.new(1) / c).simplify) - Series.constant(1, order - m)
        tail = Series.compose(u, order - m) { |k| k.zero? ? Num.new(0) : Num.new(Rational((-1)**(k + 1), k)) }
        head = { 0 => (Fn.new(:log, [c]) + Num.new(m) * Series::LOG).simplify }
        return Series.new(head, order) + tail.truncate(order)
      end

      if name == :atan && s.min_exponent.negative?
        c = s.terms[s.min_exponent]
        sign = Scalar.numeric?(c) ? c.value : (c.variables.empty? ? c.evalf : nil)
        raise SeriesError, "sign of #{c}" unless sign.is_a?(Numeric) && sign.real?
        half_pi = Series.constant((sign.negative? ? -PI / 2 : PI / 2).simplify, order)
        return half_pi - function(Fn.new(:atan, [Pow.new(f.args.first, Num.new(-1))]), order)
      end
      if %i[erf erfc].include?(name) && s.min_exponent.negative?
        # erf(+-oo) = +-1 up to an exponentially small tail: a constant, for limits
        c = s.terms[s.min_exponent]
        sign = Scalar.numeric?(c) ? c.value : (c.variables.empty? ? c.evalf : nil)
        raise SeriesError, "sign of #{c}" unless sign.is_a?(Numeric) && sign.real?
        value = name == :erf ? (sign.negative? ? -1 : 1) : (sign.negative? ? 2 : 0)
        return Series.constant(Num.new(value), order)
      end
      raise SeriesError, "#{f} has an essential singularity" if s.min_exponent.negative?
      c = s.constant_term
      s0 = s - Series.constant(c, order)
      w = Var.new(:_w)
      derivative = Fn.new(name, [w])
      factorial = 1
      coefficients = []
      Series.compose(s0, order) do |k|
        while coefficients.size <= k
          coefficients << (derivative.subs(w => c).simplify / factorial).simplify
          derivative = derivative.diff(w)
          factorial *= coefficients.size
        end
        coefficients[k]
      end
    end
  end
end
