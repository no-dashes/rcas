# frozen_string_literal: true

module RCAS
  # The q-analogues: everything in the q-world is built from the q-Pochhammer
  # symbol
  #
  #   (a; q)_n = (1 - a)(1 - a*q)...(1 - a*q**(n - 1)),
  #
  # which plays the part the rising factorial plays for ordinary
  # hypergeometric terms. On top of it sit the q-bracket [n]_q, the
  # q-factorial and the q-binomial coefficient:
  #
  #   [n]_q = (1 - q**n)/(1 - q)      -> n as q -> 1
  #   [n]_q! = [1]_q*[2]_q*...*[n]_q = (q; q)_n/(1 - q)**n
  #   qbinomial(n, k, q) = (q; q)_n/((q; q)_k*(q; q)_(n - k))
  #
  # Each is a function of its own so that output stays readable; the
  # algorithms expand them into q-Pochhammer symbols themselves, the way the
  # ordinary ones expand binomials into factorials. Integer arguments fold
  # right away, as everywhere else in rcas.
  #
  # Sources (keys: MANUAL.md, Sources): [Koe14, ch. 10]; [GR04, ch. 1].
  module QFunctions
    NAMES = %i[qpochhammer qbracket qfactorial qbinomial].freeze
    MAX_FOLD = 128

    module_function

    # (a; q)_n, the q-Pochhammer symbol.
    def qpochhammer(a, q, n)
      a = Expression.lift(a)
      q = Expression.lift(q)
      n = Expression.lift(n)
      m = integer(n)
      return Fn.new(:qpochhammer, [a, q, n]) if m.nil? || m.negative? || m > MAX_FOLD
      (0...m).reduce(Num.new(1)) { |acc, i| acc * (1 - a * q**i) }.simplify
    end

    # [n]_q = 1 + q + ... + q**(n - 1).
    def qbracket(n, q)
      n = Expression.lift(n)
      q = Expression.lift(q)
      m = integer(n)
      return Fn.new(:qbracket, [n, q]) if m.nil? || m.negative? || m > MAX_FOLD
      (0...m).reduce(Num.new(0)) { |acc, i| acc + q**i }.simplify
    end

    # [n]_q! = [1]_q*[2]_q*...*[n]_q.
    def qfactorial(n, q)
      n = Expression.lift(n)
      q = Expression.lift(q)
      m = integer(n)
      return Fn.new(:qfactorial, [n, q]) if m.nil? || m.negative? || m > MAX_FOLD
      (1..m).reduce(Num.new(1)) { |acc, i| acc * qbracket(Num.new(i), q) }.expand
    end

    # The Gaussian binomial coefficient: a polynomial in q whose value at
    # q = 1 is the ordinary one.
    def qbinomial(n, k, q)
      n = Expression.lift(n)
      k = Expression.lift(k)
      q = Expression.lift(q)
      top = integer(n)
      bottom = integer(k)
      return Fn.new(:qbinomial, [n, k, q]) if top.nil? || bottom.nil? || top.negative? || top > MAX_FOLD
      return Num.new(0) if bottom.negative? || bottom > top
      numerator = ((top - bottom + 1)..top).reduce(Num.new(1)) { |acc, i| acc * (1 - q**i) }
      denominator = (1..bottom).reduce(Num.new(1)) { |acc, i| acc * (1 - q**i) }
      (numerator / denominator).cancel.expand
    end

    # Constant folding, called by Functions.fold when Simplify meets one of
    # these nodes: an integer index gives the product, whatever q is.
    def fold(fn)
      case fn.name
      when :qpochhammer then fn.args.size == 3 ? qpochhammer(*fn.args) : nil
      when :qbracket then fn.args.size == 2 ? qbracket(*fn.args) : nil
      when :qfactorial then fn.args.size == 2 ? qfactorial(*fn.args) : nil
      when :qbinomial then fn.args.size == 3 ? qbinomial(*fn.args) : nil
      end
    end

    # ---- what the algorithms work with ------------------------------------------

    # Everything rewritten in q-Pochhammer symbols, the way to_factorials
    # rewrites binomials.
    def to_pochhammer(expr)
      expr = expr.map_children { |c| to_pochhammer(c) }
      return expr unless expr.is_a?(Fn) && NAMES.include?(expr.name)
      case expr.name
      when :qbracket
        n, q = expr.args
        (1 - q**n) / (1 - q)
      when :qfactorial
        n, q = expr.args
        Fn.new(:qpochhammer, [q, q, n]) / (1 - q)**n
      when :qbinomial
        n, k, q = expr.args
        Fn.new(:qpochhammer, [q, q, n]) /
          (Fn.new(:qpochhammer, [q, q, k]) * Fn.new(:qpochhammer, [q, q, (n - k).simplify]))
      else expr
      end
    end

    # Every q-Pochhammer symbol of one family written on the lowest index
    # that occurs, (a; q)_(m + d) = (a; q)_m*(1 - a*q**m)*...*(1 - a*q**(m + d - 1)),
    # so that a sum of such terms has a common factor and cancel can put it
    # over one denominator.
    def align(expr)
      symbols = expr.each_node.select { |e| e.is_a?(Fn) && e.name == :qpochhammer && e.args.size == 3 }.uniq
      return expr if symbols.size < 2
      replacements = {}
      symbols.group_by { |e| [e.args[0], e.args[1]] }.each_value do |family|
        family.combination(2).each do |one, other|
          d = (one.args[2] - other.args[2]).simplify
          next unless d.is_a?(Num) && d.value.is_a?(Integer) && !d.zero?
          big, small, steps = d.value.positive? ? [one, other, d.value] : [other, one, -d.value]
          a, q, m = small.args
          replacements[big] ||= (0...steps).reduce(small) { |acc, i| acc * (1 - a * q**(m + i)) }
        end
      end
      replacements.empty? ? expr : expr.subs(replacements)
    end

    # (a; q)_(m + d) / (a; q)_m = (1 - a*q**m)...(1 - a*q**(m + d - 1)):
    # cancel q-Pochhammer symbols whose indices differ by an integer, so that
    # a term ratio comes out as a rational function of q**k. Mutates
    # +factors+ (base => exponent), like Combinatorics.merge_factorials.
    def merge_pochhammers(factors)
      loop do
        symbols = factors.keys.select { |b| b.is_a?(Fn) && b.name == :qpochhammer }
        pair = nil
        symbols.combination(2).each do |one, other|
          next unless one.args[0] == other.args[0] && one.args[1] == other.args[1]
          d = (one.args[2] - other.args[2]).simplify
          next unless d.is_a?(Num) && d.value.is_a?(Integer) && !d.zero?
          pair = d.value.positive? ? [one, other, d.value] : [other, one, -d.value]
          break
        end
        return factors unless pair
        big, small, d = pair
        a, q, m = small.args
        exponent = factors.delete(big)
        Simplify.add_factor(factors, small, exponent)
        (0...d).each { |i| Simplify.add_factor(factors, (1 - a * q**(m + i)).simplify, exponent) }
      end
    end

    def integer(value)
      value.is_a?(Num) && value.value.is_a?(Integer) ? value.value : nil
    end
  end
end
