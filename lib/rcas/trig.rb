# frozen_string_literal: true

module RCAS
  # Trigonometric and logarithmic rewriting: expand_trig, trigsimp,
  # expand_log, logcombine.
  module Trigonometry
    module_function

    # sin(a + b), cos(a + b) and integer multiples written out.
    def expand_trig(expr)
      expr = Expression.lift(expr).map_children { |c| expand_trig(c) }
      return expr unless expr.is_a?(Fn) && %i[sin cos tan].include?(expr.name) && expr.args.size == 1
      return (expand_trig(Fn.new(:sin, expr.args)) / expand_trig(Fn.new(:cos, expr.args))).simplify if expr.name == :tan

      arg = expr.args.first.simplify
      constant, terms = Simplify.termize(arg)
      addends = terms.map { |factors, coeff| Simplify.rebuild_product(coeff, factors) }
      addends << Num.new(constant) unless constant.zero?
      if addends.size >= 2
        a = addends.first
        b = addends.drop(1).reduce { |acc, t| acc + t }
        return addition_formula(expr.name, a, b)
      end
      coeff, factors = Simplify.factorize(arg)
      if coeff.is_a?(Integer) && coeff.abs >= 2 && !factors.empty?
        return multiple_angle(expr.name, coeff, Simplify.rebuild_product(1, factors))
      end
      expr
    end

    # sin(n*u) and cos(n*u) by de Moivre, (cos u + i sin u)**n [AS64, 4.3.
    # 29-30]: one binomial sum. Peeling one u at a time and expanding sin
    # and cos of the rest separately doubled the work per multiple, and
    # sin(16*x) took nine seconds (third review, section 5).
    def multiple_angle(name, n, u)
      s = expand_trig(Fn.new(:sin, [u]))
      c = expand_trig(Fn.new(:cos, [u]))
      m = n.abs
      terms = (0..m).filter_map do |k|
        next nil if name == :sin ? k.even? : k.odd?
        sign = (-1)**(k / 2)
        Num.new(sign * (0...k).reduce(1) { |acc, i| acc * (m - i) } / (1..k).reduce(1, :*)) * c**(m - k) * s**k
      end
      total = terms.reduce(:+).expand
      name == :sin && n.negative? ? Simplify.negate(total).expand : total
    end

    def addition_formula(name, a, b)
      sa, ca = expand_trig(Fn.new(:sin, [a])), expand_trig(Fn.new(:cos, [a]))
      sb, cb = expand_trig(Fn.new(:sin, [b])), expand_trig(Fn.new(:cos, [b]))
      case name
      when :sin then (sa * cb + ca * sb).expand
      when :cos then (ca * cb - sa * sb).expand
      end
    end

    # sin and cos repeat every 2*pi, tan and cot every pi, so an added term
    # that is an integer multiple of the period drops out of the argument:
    # sin(pi/6 + 2*pi*k) is sin(pi/6) for an integer k. The multiple has to
    # be *known* to be one, which is what assume(k: ZZ) says - for an
    # undeclared k nothing happens, because k = 1/2 would be another matter.
    PERIODS = { sin: 2, cos: 2, tan: 1 }.freeze

    def reduce_period(name, arg)
      period = PERIODS[name]
      return nil if period.nil?
      constant, terms = Simplify.termize(Expression.lift(arg))
      kept = terms.reject { |factors, coeff| whole_period?(factors, coeff, period) }
      return nil if kept.size == terms.size
      Simplify.rebuild_sum(constant, kept)
    end

    # Is coeff * factors an integer multiple of period*pi?
    def whole_period?(factors, coeff, period)
      return false unless factors[PI] == 1
      return false unless coeff.is_a?(Integer) && (coeff % period).zero?
      rest = factors.reject { |base, _| base == PI }
      return true if rest.empty?
      domain = Infer.domain(Simplify.rebuild_product(1, rest))
      !domain.nil? && domain <= ZZ
    end

    # The function whose even powers are replaced when +keep+ is kept, and
    # what its square becomes: sin**2 + cos**2 = 1, cosh**2 - sinh**2 = 1.
    SQUARES = {
      sin: [:cos, ->(p) { Num.new(1) - p**2 }],
      cos: [:sin, ->(p) { Num.new(1) - p**2 }],
      sinh: [:cosh, ->(p) { Num.new(1) + p**2 }],
      cosh: [:sinh, ->(p) { p**2 - Num.new(1) }]
    }.freeze

    # Shortest form among several rewritings using sin**2 + cos**2 = 1 and
    # cosh**2 - sinh**2 = 1.
    def trigsimp(expr)
      base = tan_to_sin_cos(Expression.lift(expr)).simplify
      candidates = [Expression.lift(expr).simplify, base, polynomial_cancel(base)]
      [false, true].each do |expanded|
        f = expanded ? expand_trig(base) : base
        SQUARES.each_key do |keep|
          candidates << polynomial_cancel(reduce_squares(f, keep))
        end
      end
      candidates.compact.map(&:simplify).min_by { |c| [c.each_node.count, c.to_s.size] }
    end

    def tan_to_sin_cos(expr)
      expr = expr.map_children { |c| tan_to_sin_cos(c) }
      expr.is_a?(Fn) && expr.name == :tan ? Fn.new(:sin, expr.args) / Fn.new(:cos, expr.args) : expr
    end

    # Replace even powers of the function that is not kept: cos**2 => 1 - sin**2.
    def reduce_squares(expr, keep)
      num, den = numerator_denominator(expr)
      (reduce_table(num, keep) / reduce_table(den, keep)).simplify
    end

    def numerator_denominator(expr)
      _, table = Expand.table(expr)
      den_factors = {}
      table.each_key do |factors|
        factors.each do |base, exp|
          next unless exp.is_a?(Integer) && exp.negative?
          den_factors[base] = [den_factors[base] || 0, -exp].max
        end
      end
      den = Simplify.rebuild_product(1, den_factors)
      [(expr * den).expand, den]
    end

    def reduce_table(expr, keep)
      victim, square = SQUARES[keep]
      constant, table = Expand.table(expr)
      result = Num.new(constant)
      table.each do |factors, coeff|
        reducible = factors.select { |base, exp| base.is_a?(Fn) && base.name == victim && exp.is_a?(Integer) && exp >= 2 }
        term = Simplify.rebuild_product(coeff, factors.reject { |b, _| reducible.key?(b) })
        reducible.each do |base, exp|
          partner = Fn.new(keep, [base.args.first])
          term = (term * square.call(partner)**(exp / 2) * base**(exp % 2)).expand
        end
        result += term
      end
      result.expand
    end

    # Cancel common factors treating each function application as a variable.
    def polynomial_cancel(expr)
      atoms = expr.each_node.select { |n| n.is_a?(Fn) }.uniq
      return expr.cancel if atoms.empty?
      names = atoms.each_with_index.to_h { |a, i| [a, Var.new(:"_f#{i}")] }
      substituted = expr.subs(names)
      return nil if substituted.each_node.any? { |n| n.is_a?(Fn) }
      substituted.cancel.subs(names.invert)
    rescue DomainError, NotImplementedError, RCAS::Unsupported
      nil
    end

    # log(a*b**n/c) => log(a) + n*log(b) - log(c), for the factors it holds
    # for: log(p*u) = log(p) + log(u) and log(p**n) = n*log(p) when p > 0,
    # which is proved (Decide for a constant, the assumptions for a symbol).
    # The fifth review's decision: the rules no longer assume an undeclared
    # argument positive - log(x**2) is 0 at x = -1 and 2*log(x) is 2*i*pi.
    # A factor whose sign is declared negative is taken by its absolute value
    # when it is all there is, with the i*pi an odd number of them leaves
    # (third review, C4, A5). `force: true` is the textbook manipulation,
    # every argument taken as positive (SymPy's name for MuPAD's
    # IgnoreAnalyticConstraints).
    def expand_log(expr, force: false)
      expr = Expression.lift(expr).map_children { |c| expand_log(c, force: force) }
      return expr unless expr.is_a?(Fn) && expr.name == :log && expr.args.size == 1
      coeff, factors = Simplify.factorize(expr.args.first.simplify)
      return expr if factors.empty? || (factors.size == 1 && factors.values.first == 1 && coeff == 1)
      pieces = []
      kept = {}
      negatives = {}
      factors.each do |base, exp|
        sign = base.variables.empty? ? Decide.sign(base) : RCAS.sign_of(base)
        if sign == :negative && exp.is_a?(Integer)
          negatives[base] = exp
        elsif force || sign == :positive
          pieces << Expression.lift(exp) * Fn.new(:log, [base])
        else
          kept[base] = exp
        end
      end
      unless kept.empty?
        # what is not proved positive stays inside one logarithm, with the
        # negative factors and a negative coefficient
        negatives.each { |base, exp| kept[base] = exp }
        if coeff.is_a?(Numeric) && coeff.real? && coeff.positive?
          pieces.concat(coefficient_logs(coeff))
          coeff = 1
        end
        pieces << Fn.new(:log, [Simplify.rebuild_product(coeff, kept)])
        return pieces.reduce { |acc, p| acc + p }.simplify
      end
      flips = negatives.values.sum
      negatives.each { |base, exp| pieces << Num.new(exp) * Fn.new(:log, [Neg.new(base).simplify]) }
      pieces << I * PI if flips.odd? && !(coeff.is_a?(Numeric) && coeff.real? && coeff.negative?)
      if flips.odd? && coeff.is_a?(Numeric) && coeff.real? && coeff.negative?
        coeff = -coeff # two negatives: the product is positive after all
      end
      if coeff.is_a?(Numeric) && coeff.real? && coeff.negative?
        return expr if pieces.empty?
        pieces << Fn.new(:log, [Num.new(coeff)])
      else
        pieces.concat(coefficient_logs(coeff))
      end
      pieces.reduce { |acc, p| acc + p }.simplify
    end

    def coefficient_logs(coeff)
      return [] if coeff == 1
      return [Fn.new(:log, [Num.new(coeff)])] unless coeff.is_a?(Rational)
      logs = []
      logs << Fn.new(:log, [Num.new(coeff.numerator)]) unless coeff.numerator == 1
      logs << -Fn.new(:log, [Num.new(coeff.denominator)])
      logs
    end

    # a*log(u) + b*log(v) => log(u**a * v**b) for rational a, b - for the
    # arguments it holds for: positive ones, proved (2*log(-1) is 2*i*pi and
    # log((-1)**2) is 0, and 3*log(i) is not log(-i): third review, A4).
    # One argument whose sign is not known may still join the positive
    # ones with coefficient 1, since log(p*u) = log(p) + log(u) for p > 0.
    # Undeclared arguments are no longer assumed positive (the fifth
    # review's decision); `force: true` combines every logarithm.
    def logcombine(expr, force: false)
      expr = Expression.lift(expr).simplify
      constant, terms = Simplify.termize(expr)
      inside = {}
      rest = {}
      loose = nil
      terms.each do |factors, coeff|
        log = factors.size == 1 && factors.values.first == 1 && factors.keys.first.is_a?(Fn) && factors.keys.first.name == :log &&
              (coeff.is_a?(Integer) || coeff.is_a?(Rational))
        argument = log && factors.keys.first.args.first
        if log && (force || combinable?(argument))
          Simplify.add_factor(inside, argument, coeff)
        elsif log && coeff == 1 && loose.nil? && !argument.each_node.any? { |n| n.is_a?(Num) && n.value.is_a?(Complex) }
          loose = factors
        else
          rest[factors] = coeff
        end
      end
      if loose
        if inside.empty?
          rest[loose] = 1
        else
          Simplify.add_factor(inside, loose.keys.first.args.first, 1)
        end
      end
      return expr if inside.size < 2 && rest.size + inside.size == terms.size && inside.values.all? { |e| e == 1 }
      combined = Simplify.rebuild_sum(constant, rest)
      combined += Fn.new(:log, [Simplify.rebuild_product(1, inside)]) unless inside.empty?
      combined.simplify
    end

    def combinable?(u)
      return Decide.sign(u) == :positive if u.variables.empty?
      RCAS.sign_of(u) == :positive
    end
  end
end
