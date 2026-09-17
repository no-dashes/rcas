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
        u = Simplify.rebuild_product(coeff <=> 0, factors)
        rest = Simplify.rebuild_product(coeff - (coeff <=> 0), factors)
        return addition_formula(expr.name, u, rest)
      end
      expr
    end

    def addition_formula(name, a, b)
      sa, ca = expand_trig(Fn.new(:sin, [a])), expand_trig(Fn.new(:cos, [a]))
      sb, cb = expand_trig(Fn.new(:sin, [b])), expand_trig(Fn.new(:cos, [b]))
      case name
      when :sin then (sa * cb + ca * sb).expand
      when :cos then (ca * cb - sa * sb).expand
      end
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
    rescue DomainError, NotImplementedError
      nil
    end

    # log(a*b**n/c) => log(a) + n*log(b) - log(c)   (arguments assumed positive)
    def expand_log(expr)
      expr = Expression.lift(expr).map_children { |c| expand_log(c) }
      return expr unless expr.is_a?(Fn) && expr.name == :log && expr.args.size == 1
      coeff, factors = Simplify.factorize(expr.args.first.simplify)
      return expr if factors.empty? || (factors.size == 1 && factors.values.first == 1 && coeff == 1)
      pieces = factors.map { |base, exp| Expression.lift(exp) * Fn.new(:log, [base]) }
      if coeff.is_a?(Rational)
        pieces << Fn.new(:log, [Num.new(coeff.numerator)]) unless coeff.numerator == 1
        pieces << -Fn.new(:log, [Num.new(coeff.denominator)])
      elsif coeff != 1
        pieces << Fn.new(:log, [Num.new(coeff)])
      end
      pieces.reduce { |acc, p| acc + p }.simplify
    end

    # a*log(u) + b*log(v) => log(u**a * v**b) for rational a, b.
    def logcombine(expr)
      expr = Expression.lift(expr).simplify
      constant, terms = Simplify.termize(expr)
      inside = {}
      rest = {}
      terms.each do |factors, coeff|
        log = factors.size == 1 && factors.values.first == 1 && factors.keys.first.is_a?(Fn) && factors.keys.first.name == :log
        if log && (coeff.is_a?(Integer) || coeff.is_a?(Rational))
          Simplify.add_factor(inside, factors.keys.first.args.first, coeff)
        else
          rest[factors] = coeff
        end
      end
      return expr if inside.size < 2 && rest.size + inside.size == terms.size && inside.values.all? { |e| e == 1 }
      combined = Simplify.rebuild_sum(constant, rest)
      combined += Fn.new(:log, [Simplify.rebuild_product(1, inside)]) unless inside.empty?
      combined.simplify
    end
  end
end
