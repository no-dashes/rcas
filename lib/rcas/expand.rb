# frozen_string_literal: true

module RCAS
  # Multiplies out products and integer powers of sums.
  #
  #   ((:x + 1) * (1 - :x)).expand   # => 1 - x**2
  #   ((:x + :y)**2).expand          # => x**2 + 2*x*y + y**2
  #
  # Works on "tables": a sum is [constant, { factors => coefficient }] where
  # factors is a { base => exponent } hash (the same shape Simplify uses).
  # Like terms are merged after every multiplication, so a product of many
  # sums never grows beyond the number of distinct monomials in the result.
  module Expand
    module_function

    def expand(expr)
      rebuild(table(expr))
    end

    # => [constant, { factors => coefficient }]
    # Sums and products are flattened with an explicit stack, so arbitrarily
    # long chains (a + b + c + ...) don't recurse once per term.
    def table(expr)
      constant = 0
      terms = {}
      stack = [[expr, 1]]
      until stack.empty?
        e, sign = stack.pop
        case e
        when Add then stack.push([e.right, sign], [e.left, sign])
        when Sub then stack.push([e.right, -sign], [e.left, sign])
        when Neg then stack.push([e.arg, -sign])
        when Num then constant += sign * e.value
        else
          c, t = term_table(e)
          constant += sign * c
          t.each { |f, coeff| add_term(terms, f, sign * coeff) }
        end
      end
      [constant, terms]
    end

    # Table of a non-additive node.
    def term_table(expr)
      case expr
      when Var then [0, { { expr => 1 } => 1 }]
      when Mul, Div then product_table(expr)
      when Pow then power(expr)
      when Fn  then single(Fn.new(expr.name, expr.args.map { |a| expand(a) }))
      else [0, { { expr => 1 } => 1 }] # constants, integrals, derivatives: atoms
      end
    end

    def product_table(expr)
      factors = []
      stack = [[expr, 1]]
      until stack.empty?
        e, power = stack.pop
        case e
        when Mul then stack.push([e.right, power], [e.left, power])
        when Div then stack.push([e.right, -power], [e.left, power])
        else factors << [e, power]
        end
      end
      factors.reduce([1, {}]) do |acc, (e, power)|
        t = table(e)
        multiply(acc, power == 1 ? t : invert(t))
      end
    end

    def rebuild((constant, terms)) = Simplify.rebuild_sum(constant, terms)

    # ---- table arithmetic -------------------------------------------------

    def add((ca, ta), (cb, tb), sign)
      terms = ta.dup
      tb.each { |f, c| add_term(terms, f, sign * c) }
      [ca + sign * cb, terms]
    end

    def scale((constant, terms), k)
      return [0, {}] if k.zero?
      [constant * k, terms.transform_values { |c| c * k }]
    end

    def multiply((ca, ta), (cb, tb))
      constant = ca * cb
      terms = {}
      ta.each { |f, c| add_term(terms, f, c * cb) } unless cb.zero?
      tb.each { |f, c| add_term(terms, f, c * ca) } unless ca.zero?
      ta.each do |fa, xa|
        tb.each do |fb, xb|
          f, c = fold_numeric(multiply_factors(fa, fb), xa * xb)
          if f.empty?
            constant += c
          else
            add_term(terms, f, c)
          end
        end
      end
      [constant, terms]
    end

    # A numeric base with an integer exponent (2**(1/2) * 2**(1/2) => 2**1)
    # belongs in the coefficient.
    def fold_numeric(factors, coeff)
      numeric = factors.select { |b, e| b.is_a?(Num) && !b.value.is_a?(Complex) && e.is_a?(Integer) }
      return [factors, coeff] if numeric.empty?
      numeric.each { |b, e| coeff *= Simplify.pow_number(b.value, e) }
      [factors.reject { |b, _| numeric.key?(b) }, Simplify.normalize_number(coeff)]
    end

    def invert(den)
      constant, terms = den
      if terms.empty?
        raise ZeroDivisionError, "division by zero" if constant.zero?
        [Simplify.normalize_number(Rational(1) / constant), {}]
      elsif terms.size == 1 && constant.zero?
        factors, coeff = terms.first
        inverse = factors.to_h { |base, exp| [base, Simplify.multiply_exponents(exp, -1)] }
        [0, { inverse => Simplify.normalize_number(Rational(1) / coeff) }]
      else
        [0, { { rebuild(den) => -1 } => 1 }]
      end
    end

    def power(expr)
      exp = expr.exponent
      base = table(expr.base)
      n = exp.value if exp.is_a?(Num) && exp.integer?
      return [1, {}] if n == 0
      return base if n == 1
      if n && n > 1 && term_count(base) > 1
        result = [1, {}]
        while n.positive?
          result = multiply(result, base) if n.odd?
          base = multiply(base, base) if n > 1
          n >>= 1
        end
        result
      else
        single(Pow.new(rebuild(base), expand(exp)))
      end
    end

    # A non-sum expression as a table, letting Simplify fold and factorize it.
    def single(expr) = Simplify.termize(Simplify.simplify(expr))

    def term_count((constant, terms)) = terms.size + (constant.zero? ? 0 : 1)

    def add_term(terms, factors, coeff)
      c = (terms[factors] || 0) + coeff
      c.zero? ? terms.delete(factors) : terms[factors] = c
    end

    def multiply_factors(fa, fb)
      merged = fa.dup
      fb.each do |base, exp|
        e = Simplify.add_exponents(merged[base] || 0, exp)
        e.is_a?(Numeric) && e.zero? ? merged.delete(base) : merged[base] = e
      end
      merged
    end
  end
end
