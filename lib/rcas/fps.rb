# frozen_string_literal: true

module RCAS
  # The formal power series of a function: the general coefficient in closed
  # form, not the first few terms.
  #
  #   fps(exp(x), x)     # => sum(x**k/k!, k, 0, oo)
  #   fps(sin(x), x)     # => sum((-1)**k*x**(1 + 2*k)/(1 + 2*k)!, k, 0, oo)
  #   fps((1 + x)**a, x) # => sum(x**k*binomial(a, k), k, 0, oo)
  #
  # Koepf's FPS algorithm [Koe92], [Koe14, ch. 10], in four steps:
  #
  #   1. a homogeneous linear differential equation with polynomial
  #      coefficients, sum_j p_j(x)*f^(j)(x) = 0, found with undetermined
  #      coefficients (+differential_equation+),
  #   2. the recurrence its Taylor coefficients obey, read off from
  #      x**i*f^(j) term by term (+recurrence+),
  #   3. that recurrence solved. rcas goes exactly as far as Koepf's
  #      algorithm: the two-term case q(k)*a(k) + r(k)*a(k + m) = 0, which is
  #      what an m-fold symmetric hypergeometric coefficient satisfies, so the
  #      ratio a(k + m)/a(k) can be read off and multiplied up,
  #   4. the series assembled: one sum per residue class modulo m, its
  #      coefficient the product of the ratios (Products.product turns that
  #      into factorials), and the terms before the first index of a class
  #      taken from the Taylor polynomial.
  #
  # Step 1 is where the search happens. The derivatives are split into
  # {monomial in the transcendental atoms => rational function of x} and the
  # ansatz has to cancel every monomial separately, which is sufficient for
  # the equation to hold, never spurious: a relation between the atoms
  # themselves (sin**2 + cos**2 = 1) is not used, so at worst a longer
  # equation than necessary is found.
  #
  # Sources (keys: MANUAL.md, Sources): [Koe92] for the algorithm, [Koe14,
  # ch. 10] for the presentation with hypergeometric terms; the coefficient
  # recurrence of a holonomic equation is textbook, [Sta99, ch. 6].
  module FPS
    MAX_ORDER = 4    # order of the differential equation looked for
    MAX_DEGREE = 4   # degree of its polynomial coefficients
    LOOKAHEAD = 2    # coefficients checked past the first one of each class
    MAX_START = 24   # highest index taken from the Taylor polynomial

    module_function

    # The formal power series of f around x = a, or nil when there is none of
    # hypergeometric type within the bounds.
    def expansion(f, x, a = 0, max_order: MAX_ORDER, max_degree: MAX_DEGREE)
      f = Expression.lift(f)
      x = Expression.lift(x)
      a = Expression.lift(a)
      raise ArgumentError, "fps: the variable must be a symbol, got #{x}" unless x.is_a?(Var)
      raise ArgumentError, "fps: expansion point #{a} depends on #{x}" if depends?(a, x)
      local = Scalar.zero?(a) ? f : f.subs(x => x + a)
      result = at_zero(local, x, max_order, max_degree)
      return nil if result.nil?
      Scalar.zero?(a) ? result : result.subs(x => x - a)
    end

    # f = sum_k a(k)*x**k around 0.
    def at_zero(f, x, max_order, max_degree)
      f = f.simplify
      return f if polynomial?(f, x) # a polynomial is its own power series
      k = Var.new(index_for(f, x))
      search(f, x, max_order, max_degree) do |ps|
        shifts = recurrence(ps, x, k)
        shifts && assemble(shifts, f, x, k)
      end
    end

    # ---- 1. the differential equation --------------------------------------

    # The coefficients [p_0, ..., p_J] of a differential equation
    # sum_j p_j(x)*f^(j)(x) = 0 of smallest order, or nil. The order and the
    # degree of the p_j both grow until one is found.
    def differential_equation(f, x, max_order: MAX_ORDER, max_degree: MAX_DEGREE)
      f = Expression.lift(f)
      x = Expression.lift(x)
      search(f.simplify, x, max_order, max_degree) { |ps| ps }
    end

    # Every candidate equation, smallest order and degree first, until the
    # block returns something.
    def search(f, x, max_order, max_degree)
      derivatives = [f]
      rows = [parts(f, x)]
      return nil if rows.first.empty? # f = 0
      (1..max_order).each do |order|
        begin
          derivatives << derivatives.last.diff(x).simplify
        rescue ArgumentError, NotImplementedError
          return nil
        end
        rows << parts(derivatives.last, x)
        (0..max_degree).each do |degree|
          candidates = equations(rows, x, order, degree)
          candidates.each do |ps|
            result = yield(ps)
            return result if result
          end
          # x**i times an equation of this order is an equation again, and its
          # recurrence is the same one shifted: a higher degree adds nothing
          # once this order has an equation.
          break unless candidates.empty?
        end
      end
      nil
    end

    # The equations of this order and degree, as a basis of the solutions of
    # the linear system for the coefficients of the p_j.
    def equations(rows, x, order, degree)
      unknowns = (0..order).map { |j| (0..degree).map { |i| Var.new(:"_p#{j}_#{i}") } }
      equations = conditions(rows.first(order + 1), unknowns, x, degree) or return []
      return [] if equations.empty?
      width = degree + 1
      kernel(equations, unknowns.flatten).filter_map do |vector|
        ps = unknowns.each_index.map do |j|
          vector[j * width, width].each_with_index.reduce(Num.new(0)) do |acc, (c, i)|
            acc + c * Simplify.power_node(x, i)
          end.simplify
        end
        ps unless Scalar.zero?(ps.last)
      end
    end

    # The null space of a homogeneous linear system, as vectors of
    # coefficients. With a parameter among them the entries are polynomials in
    # it, and PolyMatrix does that by evaluation and interpolation, where an
    # elimination over the rational functions would swell (the same reason
    # Zeilberger uses it); a cancelling elimination is the fallback.
    def kernel(equations, unknowns)
      entries = equations.map do |equation|
        unknowns.map { |u| Solve.polynomial_coefficients(equation, u)&.at(1) || Num.new(0) }
      end
      vectors = PolyMatrix.kernel(entries)
      return vectors if vectors
      solution = QSummation.linear_solve(equations, unknowns) or return []
      free = unknowns - solution.keys
      free.map do |u|
        point = free.to_h { |v| [v, Num.new(v == u ? 1 : 0)] }
        unknowns.map { |v| (solution[v] || v).subs(point).simplify }
      end
    end

    # sum_j p_j(x)*f^(j)(x) = 0 has to hold monomial by monomial; each
    # monomial gives a rational function of x whose numerator must vanish,
    # and that numerator is linear in the coefficients of the p_j.
    def conditions(rows, unknowns, x, degree)
      keys = rows.flat_map(&:keys).uniq
      keys.flat_map do |key|
        pairs = rows.each_with_index.filter_map { |row, j| row[key] && [j, row[key]] }
        numerators = cleared(pairs, x) or return nil
        expression = numerators.reduce(Num.new(0)) do |acc, (j, numerator)|
          acc + polynomial(unknowns[j], x, degree) * numerator
        end
        Solve.polynomial_coefficients(expression.expand, x) or return nil
      end
    end

    def polynomial(coefficients, x, degree)
      (0..degree).reduce(Num.new(0)) { |acc, i| acc + coefficients[i] * Simplify.power_node(x, i) }
    end

    # The coefficients of one monomial over their common denominator. Every
    # term of a derivative is a product of powers, so its denominator can be
    # read off; only the few that occur go into the polynomial ring, for one
    # lcm and one division each. (Fraction.as_fraction on the assembled
    # coefficient builds the common denominator by multiplying instead, and
    # the third derivative of a rational function already has fifty terms.)
    def cleared(pairs, x)
      pieces = pairs.map { |j, terms| [j, terms.map { |factors, coeff| fraction_of(factors, coeff) }] }
      denominators = pieces.flat_map { |_, terms| terms.map(&:last) }.uniq
      ring = QQ[*denominators.reduce([x.name]) { |acc, d| acc | d.variables }]
      polynomials = denominators.to_h { |d| [d, ring.call(d)] }
      total = polynomials.values.reduce { |acc, d| acc.exact_div(acc.gcd(d)) * d }
      quotients = polynomials.transform_values { |d| total.exact_div(d).to_expr }
      pieces.map do |j, terms|
        [j, terms.reduce(Num.new(0)) { |acc, (numerator, denominator)| acc + numerator * quotients[denominator] }]
      end
    rescue DomainError, NotImplementedError, ZeroDivisionError
      structural(pairs)
    end

    # [numerator, denominator] of one term of a term table.
    def fraction_of(factors, coeff)
      numerator = Num.new(coeff)
      denominator = Num.new(1)
      factors.each do |base, e|
        if e.is_a?(Integer) && e.negative?
          denominator *= Simplify.power_node(base, -e)
        else
          numerator *= Simplify.power_node(base, e)
        end
      end
      [numerator, denominator.simplify]
    end

    # Without a polynomial ring (a constant such as pi in a denominator):
    # multiply by the powers that occur, which clears them too, if less tidily.
    def structural(pairs)
      powers = {}
      pairs.each do |_, terms|
        terms.each do |factors, _|
          factors.each { |base, e| powers[base] = [powers[base] || 0, -e].max if e.is_a?(Integer) && e.negative? }
        end
      end
      denominator = powers.reduce(Num.new(1)) { |acc, (base, e)| acc * Simplify.power_node(base, e) }
      pairs.map { |j, terms| [j, (coefficient_of(terms) * denominator).simplify] }
    end

    def coefficient_of(terms)
      terms.reduce(Num.new(0)) do |acc, (factors, coeff)|
        acc + factors.reduce(Num.new(coeff)) { |value, (base, e)| value * Simplify.power_node(base, e) }
      end
    end

    # An expression split by its transcendental part:
    # { {atom => exponent} => [[rational factors, numeric coefficient], ...] }.
    # exp(x)/(1 - x)**2 - x*exp(2*x) has the two keys {e => x} and {e => 2*x}.
    def parts(expr, x)
      constant, table = Expand.table(cancelled(expr))
      out = Hash.new { |h, key| h[key] = [] }
      out[{}] << [{}, constant] unless constant.zero?
      table.each do |factors, coeff|
        rational = {}
        atoms = {}
        factors.each { |base, exponent| split(base, exponent, x, rational, atoms) }
        out[atoms] << [rational, coeff]
      end
      out
    end

    # base**exponent into the rational part, the atom part, or both: a power
    # of a polynomial splits, (1 - x**2)**(-3/2) into (1 - x**2)**(-2) and
    # (1 - x**2)**(1/2), so that a derivative and its successor share an atom.
    def split(base, exponent, x, rational, atoms)
      if !depends?(base, x) && !depends?(exponent, x)
        rational[base] = exponent
      elsif rational?(base)
        whole, rest = integer_part(exponent)
        rational[base] = whole unless whole.zero?
        atoms[base] = rest if rest
      else
        atoms[base] = exponent
      end
    end

    # [integer part, remainder or nil] of an exponent.
    def integer_part(exponent)
      exponent = exponent.value if exponent.is_a?(Num)
      case exponent
      when Integer then [exponent, nil]
      when Rational then [exponent.floor, exponent - exponent.floor]
      when Expression
        constant, = Expand.table(exponent)
        whole = constant.is_a?(Integer) || constant.is_a?(Rational) ? constant.floor : 0
        [whole, whole.zero? ? exponent : (exponent - Num.new(whole)).simplify]
      else [0, exponent]
      end
    end

    # A rational function of its variables: no function call, no root.
    def rational?(expr)
      expr.each_node.all? do |node|
        case node
        when Var, Num, Add, Sub, Mul, Div, Neg then true
        when Pow then node.exponent.is_a?(Num) && node.exponent.value.is_a?(Integer)
        else false
        end
      end
    end

    def depends?(expr, x) = expr.is_a?(Expression) && expr.variables.include?(x.name)

    def polynomial?(f, x) = !Solve.polynomial_coefficients(f.expand, x).nil?

    def cancelled(expr)
      value = expr.cancel
      value.is_a?(Expression) ? value : expr
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      expr
    end

    # ---- 2. the recurrence for the coefficients -----------------------------

    # sum_j p_j(x)*f^(j)(x) = 0 with f = sum_k a(k)*x**k gives, for the
    # coefficient of x**k, sum_s q_s(k)*a(k + s) = 0 (valid for k >= 0, with
    # a(k) = 0 for negative k): x**i*f^(j) contributes a(k + j - i) with the
    # falling factorial (k - i + j)...(k - i + 1).
    # => { shift => polynomial in k }, or nil.
    def recurrence(ps, x, k)
      shifts = {}
      ps.each_with_index do |p, j|
        coefficients = Solve.polynomial_coefficients(p.expand, x) or return nil
        coefficients.each_with_index do |c, i|
          next if Scalar.zero?(c)
          falling = (1..j).reduce(Num.new(1)) { |acc, t| acc * (k - Num.new(i) + Num.new(t)) }
          shifts[j - i] = (shifts[j - i] || Num.new(0)) + c * falling
        end
      end
      shifts.transform_values { |q| q.expand.simplify }.reject { |_, q| Scalar.zero?(q) }
    end

    # ---- 3. and 4. the series ----------------------------------------------

    # Two terms q(k)*a(k) + r(k)*a(k + m) = 0 make the coefficients m-fold
    # symmetric hypergeometric: one geometric-like ratio per residue class
    # modulo m. Anything else is left to the caller (nil).
    def assemble(shifts, f, x, k)
      return nil unless shifts.size == 2
      low, high = shifts.keys.minmax
      m = high - low
      q = shifts[low].subs(k => k - Num.new(low)).expand
      r = shifts[high].subs(k => k - Num.new(low)).expand
      ratio = (Simplify.negate(q) / r).cancel
      valid = [low, 0].max # the shifted recurrence holds from here on

      ratios = (0...m).to_h { |residue| [residue, ratio.subs(k => Num.new(m) * k + Num.new(residue)).cancel] }
      # the roots of r before cancelling: (k - 1)*(a(k) - a(k - 1)) = 0
      # says nothing about a(1), and the cancelled ratio 1 forgot that, so
      # x/(1 - x) came out as 0 (third review, D5)
      leads = (0...m).to_h { |residue| [residue, r.subs(k => Num.new(m) * k + Num.new(residue)).expand] }
      starts = ratios.to_h { |residue, step| [residue, start_index(step, k, valid, m, residue, leads[residue])] }
      known = starts.map { |residue, start| m * (start + LOOKAHEAD) + residue }.max
      return nil if known > MAX_START
      taylor = begin
        Limits.taylor(f, x, 0, known + 1)
      rescue SeriesError, ZeroDivisionError, NotImplementedError
        return nil
      end

      classes = ratios.map { |residue, step| piece(step, taylor, starts[residue], residue, m, x, k) }
      return nil if classes.any? { |piece| piece == false }
      total = classes.compact.map(&:first).reduce(leading_terms(taylor, starts, m, x)) { |acc, s| acc + s }
      total.simplify
    end

    # [the sum for one residue class, its general term], nil when the class
    # vanishes (a(k0) = 0 makes every later coefficient of the class zero too,
    # the ratio having no pole past the first index), and false when no form
    # of the coefficient checks out.
    #
    # Tidying can put the coefficient out of reach of its own first index:
    # (2*k - 2)! is the (1/2 + k) gamma of sqrt(1 + x) written with
    # factorials, and it has a pole at k = 0 where the gamma had none. The
    # plain form of the product is then the one to keep.
    def piece(step, taylor, start, residue, m, x, k)
      first = Coefficients.coeff(taylor, x, m * start + residue)
      return nil if Scalar.zero?(first)
      i = Var.new(:_j)
      product = Products.product(step.subs(k => i), i, Num.new(start), (k - Num.new(1)).simplify)
      plain = (first * product).simplify
      term = candidates(plain, k, m).find { |candidate| agrees?(candidate, taylor, start, residue, m, x, k) }
      return false unless term
      power = Simplify.power_node(x, (Num.new(m) * k + Num.new(residue)).simplify)
      [Sum.new((term * power).simplify, k, Num.new(start), OO), term]
    end

    # The forms of the coefficient to offer, best first: factorials if the
    # gammas all came out in the wash, then binomial coefficients (which is
    # where (1 + x)**a and sqrt(1 + x) belong), then the product as it came.
    def candidates(plain, k, m)
      forms = []
      factorials = tidy(plain, k, m)
      forms << factorials unless gamma?(factorials)
      forms << tidy(plain, k, m, binomials: true)
      forms << plain
      forms.uniq { |form| form.to_s }
    end

    def gamma?(expr) = expr.each_node.any? { |node| node.is_a?(Fn) && node.name == :gamma }

    # The coefficients below the first index of their class, from the Taylor
    # polynomial: log(1 + x) starts its sum at k = 1, exp(x) - 1 - x at k = 2.
    def leading_terms(taylor, starts, m, x)
      (0...starts.map { |residue, start| m * start + residue }.max).reduce(Num.new(0)) do |acc, degree|
        residue = degree % m
        next acc unless degree < m * starts[residue] + residue
        acc + Coefficients.coeff(taylor, x, degree) * Simplify.power_node(x, degree)
      end
    end

    # The linear algebra behind the closed form is exact, so this is a check
    # on the derivation, not on the arithmetic: the first coefficients of the
    # class against the Taylor polynomial.
    def agrees?(term, taylor, start, residue, m, x, k)
      (start..start + LOOKAHEAD).all? do |t|
        value = term.subs(k => Num.new(t)).simplify
        difference = (opened(value) - Coefficients.coeff(taylor, x, m * t + residue)).expand
        Scalar.zero?(difference) || Scalar.zero?(difference.cancel) || Decide.identically_zero?(difference) == true
      end
    rescue ZeroDivisionError, NotImplementedError, DomainError
      false
    end

    # binomial(a, 2) is a*(a - 1)/2 for the comparison. The shape is the point
    # of the answer, so nothing else opens it up.
    def opened(expr)
      expr = expr.map_children { |child| opened(child) }
      return expr unless expr.is_a?(Fn) && expr.name == :binomial
      Combinatorics.expand_binomial(*expr.args) || expr
    end

    # The first index of the class: past the point where the recurrence takes
    # hold, and past every non-negative integer root of the denominator of the
    # ratio, where it says nothing about the next coefficient. A denominator
    # with a parameter in it has no roots to speak of, and the generic answer
    # is the one given (the sampled check still has to pass).
    def start_index(step, k, valid, m, residue, lead = nil)
      start = [((valid - residue) / m.to_r).ceil, 0].max
      pair = Fraction.as_fraction(step, [k.name])
      roots = pair ? (integer_roots(pair.last, k) || []) : []
      if lead && (poly = lead_polynomial(lead, k))
        roots += integer_roots(poly, k) || []
      end
      roots.empty? ? start : [start, roots.max + 1].max
    end

    def lead_polynomial(expr, k)
      return nil unless expr.variables.include?(k.name)
      Polynomial.from_expr(QQ[k.name, *(expr.variables - [k.name])], expr)
    rescue DomainError, NotImplementedError, ArgumentError
      nil
    end

    # The non-negative integer roots of a polynomial, or nil when its
    # coefficients are not numbers (a parameter could make anything a root).
    def integer_roots(poly, k)
      coefficients = (0..poly.degree(k.name)).map { |i| poly.coefficient_in(k.name, i).to_expr }
      return nil unless coefficients.all? { |c| c.variables.empty? }
      Solve.polynomial_roots(coefficients).map(&:simplify)
           .select { |root| root.is_a?(Num) && root.value.is_a?(Integer) && !root.value.negative? }
           .map(&:value)
    rescue NotImplementedError, DomainError, ZeroDivisionError
      nil
    end

    # ---- the shape of the coefficient --------------------------------------

    # Products.product gives one gamma per linear factor of the ratio, so the
    # coefficient of an m-fold symmetric series comes back as gammas at m
    # consecutive m-ths: gamma(1 + k)*gamma(3/2 + k) where (2*k + 1)! is
    # meant. Gauss's multiplication formula
    #
    #   gamma(z)*gamma(z + 1/m)*...*gamma(z + (m - 1)/m)
    #     = (2*pi)**((m - 1)/2)*m**(1/2 - m*z)*gamma(m*z)   [AS64, 6.1.20]
    #
    # puts them back together, and the numeric powers of k that are left over
    # (and those the ratio brought with it) are collected into one base.
    def tidy(term, k, m, binomials: false)
      coeff, factors = Simplify.factorize(term)
      factors = factors.reject { |_, e| e.is_a?(Numeric) && e.zero? }
      extra = merge_gammas(factors, k, m, binomials)
      extra *= clear_contents(factors)
      shorter(collect_powers((Simplify.rebuild_product(coeff, factors) * extra).simplify, k))
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      term
    end

    # Cancelling turns 1/(2*(1/2 + k)) into 1/(1 + 2*k) and is worth it when
    # it collapses the coefficient, not when it only spreads it out.
    def shorter(term)
      cancelled = term.cancel
      cancelled.to_s.length < term.to_s.length ? cancelled : term
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      term
    end

    # factorial(u) is gamma(u + 1): the formula needs one currency.
    def as_gammas(factors)
      out = {}
      factors.each do |base, e|
        if base.is_a?(Fn) && base.name == :factorial
          Simplify.add_factor(out, Fn.new(:gamma, [(base.args.first + Num.new(1)).simplify]), e)
        else
          Simplify.add_factor(out, base, e)
        end
      end
      out
    end

    # Mutates +factors+, returns the constant the formula brings with it.
    def merge_gammas(factors, k, m, binomials)
      factors.replace(as_gammas(factors))
      extra = Num.new(1)
      m.times do
        break unless m > 1
        group = gamma_group(factors, m) or break
        z, exponent = group
        (0...m).each { |j| Simplify.add_factor(factors, gamma_at(z, j, m), -exponent) }
        Simplify.add_factor(factors, Fn.new(:gamma, [(Num.new(m) * z).simplify]), exponent)
        extra *= Simplify.power_node(multiplication_constant(z, m), exponent)
      end
      merge_shifts(factors)
      extra *= to_binomials(factors, k) if binomials
      extra *= expand_halves(factors, k)
      merge_shifts(factors)
      factors.reject! { |_, e| e.is_a?(Numeric) && e.zero? }
      to_factorials(factors, k)
      extra
    end

    # The constant in Gauss's formula for the group starting at z.
    def multiplication_constant(z, m)
      (Simplify.power_node(Num.new(2) * PI, Rational(m - 1, 2)) *
       Simplify.power_node(Num.new(m), (Num.new(Rational(1, 2)) - Num.new(m) * z).simplify)).simplify
    end

    # A gamma left at a fractional shift, whose partners in the formula are at
    # integer ones: solved for it, the formula turns gamma(1/2 + k) into
    # (2*k)!*pi**(1/2)/(4**k*k!), which is the form a table has. The number of
    # partners is the denominator of the shift, not the modulus of the series.
    def expand_halves(factors, k)
      extra = Num.new(1)
      factors.keys.each do |base|
        next unless base.is_a?(Fn) && base.name == :gamma
        exponent = factors[base]
        next unless exponent.is_a?(Integer) && !exponent.zero?
        z = base.args.first
        d = shift_denominator(z, k)
        next unless d
        partners = (1...d).map { |j| (z + Num.new(Rational(j, d))).simplify }
        next unless partners.all? { |argument| integral?((argument - Num.new(1)).simplify, k) }
        Simplify.add_factor(factors, base, -exponent)
        Simplify.add_factor(factors, Fn.new(:gamma, [(Num.new(d) * z).simplify]), exponent)
        partners.each { |argument| Simplify.add_factor(factors, Fn.new(:gamma, [argument]), -exponent) }
        extra *= Simplify.power_node(multiplication_constant(z, d), exponent)
      end
      extra
    end

    # The denominator of the constant part of a gamma argument that is
    # otherwise integral in k: 2 for 1/2 + k, nil for k - a or 1 + k.
    def shift_denominator(z, k)
      constant, table = Expand.table(z)
      return nil unless constant.is_a?(Rational) && constant.denominator > 1
      return nil unless integral?((z - Num.new(constant)).simplify, k) && !table.empty?
      constant.denominator
    end

    # gamma(b + k)/(gamma(b)*k!) is binomial(b + k - 1, k), which upper
    # negation [GKP94, (5.14)] writes as (-1)**k*binomial(-b, k): with b = -a
    # that is the binomial series of (1 + x)**a, where this shape comes from.
    def to_binomials(factors, k)
      extra = Num.new(1)
      one = Fn.new(:gamma, [(k + Num.new(1)).simplify]) # k! in the currency of as_gammas
      return extra unless factors[one] == -1
      factors.keys.each do |base|
        next unless base.is_a?(Fn) && base.name == :gamma && factors[base] == 1
        b = (base.args.first - k).simplify
        next if depends?(b, k)
        Simplify.add_factor(factors, base, -1)
        Simplify.add_factor(factors, one, 1)
        Simplify.add_factor(factors, Fn.new(:binomial, [Simplify.negate(b).simplify, k]), 1)
        extra *= RCAS.gamma(b) * Simplify.power_node(Num.new(-1), k)
        break
      end
      extra
    end

    # gamma(z + n)/gamma(z) = z*(z + 1)*...*(z + n - 1) for an integer n > 0:
    # what Combinatorics.merge_factorials does for factorials, and what makes
    # gamma(1/2 + k)/gamma(3/2 + k) the 1/(1 + 2*k) it is.
    def merge_shifts(factors, limit = 8)
      loop do
        pair = shifted_pair(factors, limit) or return factors
        big, small, distance = pair
        exponent = factors.delete(big)
        Simplify.add_factor(factors, small, exponent)
        (0...distance).each { |i| Simplify.add_factor(factors, (small.args.first + Num.new(i)).simplify, exponent) }
      end
    end

    def shifted_pair(factors, limit)
      gammas = factors.select { |base, e| base.is_a?(Fn) && base.name == :gamma && e.is_a?(Integer) && !e.zero? }.keys
      gammas.combination(2).each do |a, b|
        distance = (a.args.first - b.args.first).simplify
        next unless distance.is_a?(Num) && distance.value.is_a?(Integer) && !distance.value.zero? && distance.value.abs <= limit
        return distance.value.positive? ? [a, b, distance.value] : [b, a, -distance.value]
      end
      nil
    end

    # (1/2 + k) is (1 + 2*k)/2: a linear factor with a rational constant hides
    # the 1 + 2*k that belongs in the answer.
    def clear_contents(factors)
      extra = Num.new(1)
      factors.keys.each do |base|
        exponent = factors[base]
        next unless (base.is_a?(Add) || base.is_a?(Sub)) && exponent.is_a?(Integer) && !exponent.zero?
        constant, table = Expand.table(base)
        values = [constant] + table.values
        next unless values.all? { |v| v.is_a?(Integer) || v.is_a?(Rational) }
        scale = values.map { |v| Rational(v).denominator }.reduce(1, :lcm)
        next if scale == 1
        factors.delete(base)
        Simplify.add_factor(factors, (base * Num.new(scale)).expand.simplify, exponent)
        extra *= Simplify.power_node(Num.new(Rational(1, scale)), exponent)
      end
      extra
    end

    def gamma_at(z, j, m) = Fn.new(:gamma, [(z + Num.new(Rational(j, m))).simplify])

    # The first m gammas at consecutive m-ths, as [z, exponent], or nil.
    def gamma_group(factors, m)
      factors.each do |base, exponent|
        next unless base.is_a?(Fn) && base.name == :gamma && exponent.is_a?(Integer) && !exponent.zero?
        z = base.args.first
        next unless (1...m).all? { |j| factors[gamma_at(z, j, m)] == exponent }
        return [z, exponent]
      end
      nil
    end

    # gamma(2 + 2*k) is (1 + 2*k)!, which is what a reader expects to see.
    def to_factorials(factors, k)
      factors.keys.each do |base|
        next unless base.is_a?(Fn) && base.name == :gamma
        argument = (base.args.first - Num.new(1)).simplify
        next unless integral?(argument, k)
        exponent = factors.delete(base)
        Simplify.add_factor(factors, Fn.new(:factorial, [argument]), exponent)
      end
      factors
    end

    # An expression that takes integer values at integer points.
    def integral?(expr, k)
      constant, table = Expand.table(expr)
      return false unless constant.is_a?(Integer)
      table.all? do |factors, coeff|
        coeff.is_a?(Integer) && factors.all? { |base, e| base == k && e.is_a?(Integer) && e.positive? }
      end
    end

    # (-1/4)**k*2**k*2**(3/2 + k) is one power of k.
    def collect_powers(expr, k)
      coeff, factors = Simplify.factorize(expr)
      base = 1r
      rest = {}
      factors.each do |b, e|
        slope = numeric?(b) ? slope_in(e, k) : nil
        if slope && !slope.zero? && !b.value.zero?
          base *= Rational(b.value)**slope
          Simplify.add_factor(rest, b, Simplify.exponent_value((Expression.lift(e) - Num.new(slope) * k).simplify))
        else
          Simplify.add_factor(rest, b, e)
        end
      end
      Simplify.add_factor(rest, Num.new(Simplify.normalize_number(base)), k) unless base == 1
      Simplify.rebuild_product(coeff, rest.reject { |_, e| e.is_a?(Numeric) && e.zero? }).simplify
    end

    def numeric?(b) = b.is_a?(Num) && (b.value.is_a?(Integer) || b.value.is_a?(Rational))

    # The coefficient of k in an exponent, when it is an integer.
    def slope_in(exponent, k)
      return nil unless exponent.is_a?(Expression)
      coefficients = Solve.polynomial_coefficients(exponent.expand, k)
      return nil unless coefficients && coefficients.size == 2
      slope = coefficients.last
      slope.is_a?(Num) && slope.value.is_a?(Integer) ? slope.value : nil
    end

    # ---- helpers -----------------------------------------------------------

    # A summation index that is not in use.
    def index_for(f, x)
      taken = f.variables + [x.name]
      return :k unless taken.include?(:k)
      (1..).each { |i| return :"k#{i}" unless taken.include?(:"k#{i}") }
    end
  end
end
