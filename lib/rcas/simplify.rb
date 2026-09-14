# frozen_string_literal: true

require "prime"

module RCAS
  # Algebraic simplification.
  #
  # Sums are flattened into (constant, {factors => coefficient}) and products
  # into (coefficient, {base => exponent}); numbers fold exactly using
  # Integer/Rational arithmetic. The result is rebuilt into a tree with a
  # canonical ordering so structurally equal inputs print identically.
  module Simplify
    module_function

    # Sentinel base for exponential factors: exp(u) is stored as EXP**u so
    # that exp(x)*exp(y) merges into exp(x + y) and exp(x)**2 into exp(2*x).
    def exp_base = (@exp_base ||= Fn.new(:exp, [Num.new(1)]))

    def simplify(expr)
      case expr
      when Num, Var      then expr
      when Add, Sub, Neg then rebuild_sum(*termize(expr, simplify: true))
      when Mul, Div, Pow then rebuild_product(*factorize(expr, simplify: true))
      when Fn            then Functions.fold(expr.map_children { |c| simplify(c) })
      else expr
      end
    end

    # Rational with denominator 1 becomes Integer, a Complex with zero
    # imaginary part becomes real; everything else is kept.
    def normalize_number(value)
      case value
      when Rational then value.denominator == 1 ? value.numerator : value
      when Complex
        re = normalize_number(value.real)
        im = normalize_number(value.imaginary)
        im.is_a?(Integer) && im.zero? ? re : Complex(re, im)
      else value
      end
    end

    # Sign test that tolerates Complex (never "negative").
    def negative?(value)
      value.is_a?(Numeric) && value.real? && value.negative?
    end

    def imaginary_unit?(base) = base.is_a?(Num) && base.value.is_a?(Complex)

    # For choosing + or - in a sum: -i*x is written with a minus.
    def sign_negative?(value)
      return value.imaginary.negative? if value.is_a?(Complex) && value.real.zero? && value.imaginary.real?
      negative?(value)
    end

    # ---- sums -------------------------------------------------------------

    # => [constant, { factors_hash => coefficient }]
    # Iterative so that long left-leaning sums don't exhaust the stack.
    # With simplify: true the non-sum leaves are simplified on the way (a
    # single pass over the whole sum, instead of once per nesting level).
    def termize(expr, sign = 1, constant = 0, terms = {}, simplify: false)
      stack = [[expr, sign, !simplify]]
      until stack.empty?
        e, s, done = stack.pop
        case e
        when Add then stack.push([e.right, s, done], [e.left, s, done])
        when Sub then stack.push([e.right, -s, done], [e.left, s, done])
        when Neg then stack.push([e.arg, -s, done])
        when Num then constant += s * e.value
        else
          unless done
            e = simplify(e)
            if e.is_a?(Add) || e.is_a?(Sub) || e.is_a?(Neg) || e.is_a?(Num)
              stack.push([e, s, true])
              next
            end
          end
          coeff, factors = factorize(e)
          if factors.empty?
            constant += s * coeff
          else
            terms[factors] = (terms[factors] || 0) + s * coeff
          end
        end
      end
      [constant, terms]
    end

    def rebuild_sum(constant, terms)
      parts = terms.reject { |_, c| c.zero? }.map do |factors, coeff|
        [rebuild_product(sign_negative?(coeff) ? -coeff : coeff, factors), sign_negative?(coeff), sort_key(rebuild_product(1, factors))]
      end
      parts.sort_by! { |_, _, key| key }
      unless constant.zero?
        entry = [Num.new(sign_negative?(constant) ? -constant : constant), sign_negative?(constant)]
        index = parts.index { |_, _, key| key.first >= 0 } || parts.size
        parts.insert(index, entry)
      end
      return Num.new(0) if parts.empty?
      sum_tree(parts.map { |e, neg| [e, neg] })
    end

    # Longest left-leaning chain we build; longer sums become balanced trees
    # of such chains so that tree depth stays logarithmic.
    CHAIN = 32

    # parts: [[expr, negative?], ...]
    def sum_tree(parts)
      if parts.size <= CHAIN
        (first, negative), *rest = parts
        acc = negative ? negate(first) : first
        return rest.reduce(acc) { |sum, (e, neg)| neg ? Sub.new(sum, e) : Add.new(sum, e) }
      end
      left, right = parts.each_slice((parts.size + 1) / 2).to_a
      if right.first[1]
        Sub.new(sum_tree(left), sum_tree(right.map { |e, neg| [e, !neg] }))
      else
        Add.new(sum_tree(left), sum_tree(right))
      end
    end

    # ---- products ---------------------------------------------------------

    # => [coefficient, { base => exponent }]
    # Exponents are Ruby numbers when numeric, otherwise Expressions.
    # Iterative over Mul/Div chains for the same reason as termize.
    def factorize(expr, power = 1, coeff = 1, factors = {}, simplify: false)
      stack = [[expr, power, !simplify]]
      until stack.empty?
        e, pw, done = stack.pop
        case e
        when Num
          coeff *= pow_number(e.value, pw)
        when Neg
          coeff *= pow_number(-1, pw)
          stack.push([e.arg, pw, done])
        when Mul
          stack.push([e.right, pw, done], [e.left, pw, done])
        when Div
          raise ZeroDivisionError, "division by zero" if e.right.is_a?(Num) && e.right.zero?
          stack.push([e.right, -pw, done], [e.left, pw, done])
        when Pow
          e = Pow.new(simplify(e.base), simplify(e.exponent)) unless done
          exp = exponent_value(e.exponent)
          if e.base.is_a?(Num) && e.base.value == 1
            next # 1**anything
          elsif e.base.is_a?(Num) && exp.is_a?(Expression) && (e.base.value.is_a?(Integer) || e.base.value.is_a?(Rational))
            # 2**(k + 1) => 2 * 2**k so that both spellings share one canonical form
            constant, rest = termize(exp)
            if constant.is_a?(Integer) && !constant.zero?
              coeff *= pow_number(e.base.value, constant * pw) if pw.is_a?(Integer)
              exp = exponent_value(rebuild_sum(0, rest))
            end
            add_factor(factors, e.base, multiply_exponents(exp, pw))
          elsif e.base.is_a?(Fn) && e.base.name == :exp && e.base.args.size == 1
            # e**x, exp(u)**v  =>  exp(u*v)
            add_factor(factors, exp_base, multiply_exponents(multiply_exponents(exponent_value(e.base.args.first), exp), pw))
          elsif exp.is_a?(Integer)
            stack.push([e.base, pw * exp, true])
          elsif exp.is_a?(Numeric) && e.base.is_a?(Num) && (root = exact_power(e.base.value, exp))
            coeff *= pow_number(root, pw)
          elsif e.base.is_a?(Num) && exp.is_a?(Numeric) && (exp.is_a?(Float) || e.base.value.is_a?(Float))
            coeff *= pow_number(e.base.value**exp, pw)
          elsif e.base.is_a?(Num) && e.base.value.is_a?(Integer) && e.base.value.negative? && exp.is_a?(Rational) && exp.denominator == 2
            # sqrt(-n) = i*sqrt(n)
            coeff *= Complex(0, 1)**(exp.numerator * pw) if pw.is_a?(Integer)
            return factorize(expr, power, coeff, factors) unless pw.is_a?(Integer) # give up merging; rare
            stack.push([Pow.new(Num.new(-e.base.value), Num.new(exp)), pw, true])
          elsif e.base.is_a?(Num) && exp.is_a?(Rational) && (parts = extract_root(e.base.value, exp.denominator))
            root, rest = parts
            coeff *= pow_number(root, exp.numerator * pw)
            add_factor(factors, Num.new(rest), multiply_exponents(exp, pw)) unless rest == 1
          elsif exp.is_a?(Rational) && (e.base.is_a?(Mul) || e.base.is_a?(Div)) && (split = positive_coefficient_split(e.base))
            # (4*a)**(1/2) => 4**(1/2) * a**(1/2): a positive number may always leave the root
            c, rest = split
            stack.push([Pow.new(Num.new(c), e.exponent), pw, true], [Pow.new(rest, e.exponent), pw, true])
          elsif exp.is_a?(Rational) && (e.base.is_a?(Add) || e.base.is_a?(Sub)) && (split = sum_content_split(e.base, exp.denominator))
            # (4 - 4*y**2)**(1/2) => 2*(1 - y**2)**(1/2)
            c, rest = split
            stack.push([Pow.new(Num.new(c), e.exponent), pw, true], [Pow.new(rest, e.exponent), pw, true])
          else
            add_factor(factors, e.base, multiply_exponents(exp, pw))
          end
        when Fn
          if e.name == :exp && e.args.size == 1
            add_factor(factors, exp_base, multiply_exponents(exponent_value(e.args.first), pw))
          else
            unless done
              e = simplify(e)
              if e.is_a?(Num) || e.is_a?(Neg) || e.is_a?(Mul) || e.is_a?(Div) || e.is_a?(Pow) || (e.is_a?(Fn) && e.name == :exp)
                stack.push([e, pw, true])
                next
              end
            end
            add_factor(factors, e, pw)
          end
        else
          unless done
            e = simplify(e)
            if e.is_a?(Num) || e.is_a?(Neg) || e.is_a?(Mul) || e.is_a?(Div) || e.is_a?(Pow)
              stack.push([e, pw, true])
              next
            end
          end
          add_factor(factors, e, pw)
        end
      end
      Combinatorics.merge_factorials(factors) if factors.count { |b, _| b.is_a?(Fn) && b.name == :factorial } > 1
      [coeff, factors]
    end

    def rebuild_product(coeff, factors)
      coeff = normalize_number(coeff)
      return Num.new(0) if coeff.zero?
      return Num.new(coeff) if factors.all? { |_, exp| exp.is_a?(Numeric) && exp.zero? }
      if coeff.is_a?(Complex) && coeff.real.zero?
        factors = factors.merge(Num.new(Complex(0, 1)) => 1)
        coeff = coeff.imaginary
      end

      # 2**(-1/2) => 2**(1/2)/2, 2**(3/2) => 2*2**(1/2): a positive integer base keeps a
      # fractional exponent in (0, 1); the integer part moves into the coefficient.
      factors = factors.to_h do |base, exp|
        next [base, exp] unless base.is_a?(Num) && base.value.is_a?(Integer) && base.value.positive? && exp.is_a?(Rational) && exp.floor != 0
        m = exp.floor
        coeff = normalize_number(coeff * Rational(base.value)**m)
        [base, exp - m]
      end
      numerator, denominator = [], []
      factors.sort_by { |base, _| factor_key(base) }.each do |base, exp|
        next if exp.is_a?(Numeric) && exp.zero?
        if exp.is_a?(Numeric) && negative?(exp)
          node = power_node(base, -exp)
          node.is_a?(Num) && !imaginary_unit?(base) ? coeff = normalize_number(coeff.quo(node.value)) : denominator << node
        else
          node = power_node(base, exp)
          node.is_a?(Num) && !imaginary_unit?(base) ? coeff = normalize_number(coeff * node.value) : numerator << node
        end
      end
      return Num.new(0) if coeff.zero?

      if numerator.size == 1 && denominator.empty? && coeff != 1 &&
         (numerator.first.is_a?(Add) || numerator.first.is_a?(Sub))
        constant, terms = termize(numerator.first)
        if (constant.zero? ? 0 : 1) + terms.size >= 2
          return rebuild_sum(constant * coeff, terms.transform_values { |c| c * coeff })
        end
      end

      if coeff.is_a?(Rational)
        denominator.unshift(Num.new(coeff.denominator))
        coeff = coeff.numerator
      end

      negative = negative?(coeff)
      coeff = negative ? -coeff : coeff
      numerator.unshift(Num.new(coeff)) unless coeff == 1 && !numerator.empty?

      result = product_node(numerator)
      result = Div.new(result, product_node(denominator)) unless denominator.empty?
      negative ? negate(result) : result
    end

    # ---- helpers ----------------------------------------------------------

    def add_factor(factors, base, exp)
      factors[base] = add_exponents(factors[base] || 0, exp)
    end

    def exponent_value(exp) = exp.is_a?(Num) ? exp.value : exp

    def add_exponents(a, b)
      return normalize_number(a + b) if a.is_a?(Numeric) && b.is_a?(Numeric)
      exponent_value(simplify(Expression.lift(a) + Expression.lift(b)))
    end

    def multiply_exponents(a, b)
      return normalize_number(a * b) if a.is_a?(Numeric) && b.is_a?(Numeric)
      exponent_value(simplify(Expression.lift(a) * Expression.lift(b)))
    end

    # Exact integer power, going through Rational for negative exponents.
    def pow_number(value, power)
      return value if power == 1
      return normalize_number(value**power) if value.is_a?(Complex)
      if power.is_a?(Integer) && power.negative?
        raise ZeroDivisionError, "division by zero" if value.zero?
        return normalize_number(Rational(value)**power) if value.is_a?(Integer) || value.is_a?(Rational)
      end
      normalize_number(value**power)
    end

    # 4 ** (1/2) => 2, 8 ** (2/3) => 4, 2 ** (1/2) => nil (stays symbolic).
    def exact_power(value, exp)
      return nil unless exp.is_a?(Rational) && value.is_a?(Integer) && value >= 0
      root = Integer.sqrt(value) if exp.denominator == 2
      root ||= (value**(1.0 / exp.denominator)).round
      return nil unless root**exp.denominator == value
      pow_number(root, exp.numerator)
    end

    def power_node(base, exp)
      return Functions.fold(Fn.new(:exp, [Expression.lift(exp)])) if base == exp_base
      return base if exp == 1
      Pow.new(base, Expression.lift(exp))
    end

    # 32 = 4**2 * 2  =>  [4, 2] for q = 2; nil when nothing can be extracted.
    def extract_root(value, q)
      if value.is_a?(Rational)
        num = extract_root(value.numerator, q) || [1, value.numerator]
        den = extract_root(value.denominator, q) || [1, value.denominator]
        return nil if num.first == 1 && den.first == 1
        return [Rational(num.first, den.first), normalize_number(Rational(num.last, den.last))]
      end
      return nil unless value.is_a?(Integer) && value > 1 && value.bit_length <= 64
      root = 1
      rest = 1
      Prime.prime_division(value).each do |prime, e|
        root *= prime**(e / q)
        rest *= prime**(e % q)
      end
      root == 1 ? nil : [root, rest]
    end

    # [c, rest] for a product c*rest with a positive rational c != 1, else nil.
    def positive_coefficient_split(expr)
      c, factors = factorize(expr)
      return nil unless (c.is_a?(Integer) || c.is_a?(Rational)) && !c.zero? && c.abs != 1 && !factors.empty?
      [c.abs, rebuild_product(c.negative? ? -1 : 1, factors)] # sqrt(-4*a) = 2*sqrt(-a)
    end

    # [content, sum / content] when the rational content of a sum with
    # rational coefficients has a q-th root to extract, else nil.
    def sum_content_split(expr, q)
      constant, terms = termize(expr)
      values = terms.values + (constant.zero? ? [] : [constant])
      return nil unless values.all? { |v| v.is_a?(Integer) || v.is_a?(Rational) }
      content = values.map(&:abs).reduce { |g, v| Polynomial.rational_gcd(g, v) }
      return nil if content == 1 || extract_root(content, q).nil?
      rest = rebuild_sum(normalize_number(Rational(constant) / content), terms.transform_values { |c| normalize_number(Rational(c) / content) })
      [content, rest]
    end

    # A sum whose terms are all negative, like -1 - 2*x.
    def negative_sum?(expr)
      return false unless expr.is_a?(Add) || expr.is_a?(Sub)
      constant, terms = termize(expr)
      !negative?(-constant) && terms.values.all? { |c| negative?(c) } && !(constant.zero? && terms.empty?)
    end

    def product_node(list)
      return Num.new(1) if list.empty?
      return list.reduce { |acc, f| Mul.new(acc, f) } if list.size <= CHAIN
      left, right = list.each_slice((list.size + 1) / 2).to_a
      Mul.new(product_node(left), product_node(right))
    end

    # Negate a product by flipping the sign of its leading numeric factor when
    # there is one, so "-2*x" rather than "-(2*x)".
    def negate(expr)
      case expr
      when Num then Num.new(-expr.value)
      when Div then Div.new(negate(expr.left), expr.right)
      when Mul
        leading = negate(expr.left)
        leading.is_a?(Neg) ? Neg.new(expr) : Mul.new(leading, expr.right)
      else Neg.new(expr)
      end
    end

    # Ordering of terms in a sum: ascending total degree ("1 + 2*x + x**2"),
    # then graded lexicographic on variables ("x**3 + 3*x**2*y + ..."), then
    # by text as a tie-break.
    def sort_key(expr)
      [degree(expr), exponent_vector(expr), expr.to_s]
    end

    def exponent_vector(expr)
      _, factors = factorize(expr)
      factors.map { |base, exp| [base.to_s, exp.is_a?(Numeric) && exp.real? ? -exp : 0] }.sort
    rescue ZeroDivisionError
      []
    end

    # Ordering of factors in a product: variables first, then functions, then
    # parenthesized sums.
    def factor_key(base)
      rank =
        case base
        when Num   then base.value.is_a?(Complex) ? -1 : 0
        when Const then 1
        when Var   then 2
        when Fn    then 3
        else 4
        end
      [rank, base.to_s]
    end

    def degree(expr)
      case expr
      when Num, Const then 0
      when Var then 1
      when Neg then degree(expr.arg)
      when Mul then degree(expr.left) + degree(expr.right)
      when Div then degree(expr.left) - degree(expr.right)
      when Pow then expr.exponent.is_a?(Num) && expr.exponent.value.is_a?(Integer) ? degree(expr.base) * expr.exponent.value : 1
      when Add, Sub then [degree(expr.left), degree(expr.right)].max
      when Fn then expr.name == :O ? 10**9 : 1
      else 1
      end
    end
  end
end
