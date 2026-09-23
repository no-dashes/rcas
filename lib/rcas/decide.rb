# frozen_string_literal: true

module RCAS
  # Questions about a constant expression - is it zero, what is its sign -
  # answered by a proof or not at all.
  #
  #   Decide.sign(exp(-100))                 # => :positive
  #   Decide.zero?(I*exp(-40))               # => false
  #   Decide.zero?(sqrt(2)**2 - 2)           # => true
  #   Decide.sign(exp(pi*sqrt(163)) - 640320**3 - 744)   # => :negative
  #
  # The routes, in order: a number is read off; a constant in one or two
  # radicals is decided exactly (Algebraic.exact); anything else is
  # evaluated at two precisions (Precision.evalf, 30 and 60 digits, then 60
  # and 120), which tells a true zero - cancellation, shrinking as the
  # digits rise - from a small number that stays where it is; and last a
  # Float, trusted only when it stands well clear of the rounding its own
  # largest intermediate value could have produced. A complex constant is
  # split into its real and imaginary parts (ComplexParts) and each is
  # decided on its own.
  #
  # nil means undecided, and a caller has to treat it as such: "no sign
  # found" is not "positive", and "not shown to be zero" is not "non-zero".
  # This is the one place where a numeric test may settle an exact
  # question; the third review (22 Sept 2026) found a dozen private copies
  # with absolute tolerances, each wrong somewhere.
  module Decide
    module_function

    LEVELS = [30, 60, 120].freeze
    # A zero shrinks by the ratio of the precisions (1e-30 per step); a
    # value that shrinks by less than this is not cancellation.
    SHRINK = BigDecimal("1e-20")
    # Two precisions agree on a value when they differ by less than this
    # relative amount.
    AGREE = BigDecimal("1e-10")

    # :positive, :negative or :zero for a real constant; nil when that is
    # not decided (not constant, not real, or beyond the routes above).
    def sign(e)
      e = Expression.lift(e)
      return nil unless decidable?(e)
      return number_sign(e.value) if e.is_a?(Num)
      exact = exact_value(e)
      return :zero if exact&.zero?
      found, value, bound = precise(e)
      return found if SIGNS.include?(found)
      if found == :unsupported
        found = float_sign(e)
        return found if found
      end
      # every evaluation was consistent with 0, and no evaluation can
      # prove that: a root separation bound or a normal form can
      return :zero if value && algebraic_zero?(e, value, bound)
      :zero if exact.nil? && symbolic_zero?(e)
    end

    SIGNS = %i[positive negative].freeze

    # true, false, or nil when undecided. Complex constants are welcome.
    def zero?(e)
      e = Expression.lift(e)
      return nil unless decidable?(e)
      return e.value.zero? if e.is_a?(Num) && e.value.is_a?(Numeric)
      exact = exact_value(e)
      return exact.zero? if exact
      if complex?(e)
        re, im = begin
          ComplexParts.parts(e)
        rescue StandardError => rescued
          RCAS.guard!(rescued)
          [nil, nil]
        end
        if re && !parts_symbolic?(re) && !parts_symbolic?(im)
          signs = [sign(re), sign(im)]
          return false if signs.any? { |s| s && s != :zero }
          return true if signs.all?(:zero)
          return nil
        end
        return complex_zero?(e)
      end
      s = sign(e)
      return s == :zero if s
      return false if annihilator_at_zero(e) == :nonzero
      complex_zero?(e) # log(-1) is complex without an i in sight
    end

    def complex_zero?(e)
      verdict = complex_float_zero?(e)
      return verdict unless verdict.nil?
      symbolic_zero?(e) ? true : nil
    end

    # An expression in indeterminates that no normal form reduces
    # (gamma(1 - a)/gamma(-a) + a): true when it vanishes at every one of
    # several random rational points, each decided exactly; false as soon
    # as one point shows it does not; nil otherwise. A point that is a pole
    # or cannot be decided is no evidence for zero, and a fresh one is
    # drawn in its place. The denominators are primes above 100: with
    # denominators 2..11, sin(30*pi*x) vanished at all four points, and one
    # decided zero among poles was enough for a true (the sixth review's
    # preflight). A nonzero rational function vanishing at four random
    # rational points is not a risk worth naming; a Float residue under
    # 1e-9 was, and four copies of that test with their own seeds and
    # tolerances were one of the third review's duplications (section 5).
    SAMPLE_DENOMINATORS = [101, 103, 107, 109, 113, 127, 131, 137, 139, 149].freeze

    def identically_zero?(expr, points: 4, seed: 20260922)
      e = Expression.lift(expr)
      return zero?(e) if e.variables.empty?
      return false if Scalar.nonzero_somewhere?(e)
      return true if Scalar.identically_zero?(e) || factorial_zero?(e)
      random = Random.new(seed)
      decided = 0
      (3 * points).times do
        point = e.variables.to_h { |name| [name, Num.new(Rational(random.rand(3..997), SAMPLE_DENOMINATORS.sample(random: random)))] }
        value = begin
          e.subs(point).simplify
        rescue ZeroDivisionError
          next # a pole: this point says nothing
        end
        verdict = zero?(value)
        return false if verdict == false
        decided += 1 if verdict
        return true if decided == points
      end
      nil
    rescue StandardError, NotImplementedError, RCAS::Unsupported => rescued
      RCAS.guard!(rescued, refused: true) if rescued.is_a?(StandardError)
      nil
    end

    def positive?(e) = sign(e) == :positive
    def negative?(e) = sign(e) == :negative
    def nonzero?(e) = zero?(e) == false

    # ---- routes -------------------------------------------------------------

    def decidable?(e)
      e.is_a?(Expression) && e.variables.empty? &&
        e.each_node.none? { |n| n.is_a?(Integral) || n.is_a?(Derivative) || n.is_a?(Limit) || n == UNDEFINED }
    end

    def number_sign(v)
      return nil unless v.is_a?(Numeric) && v.real?
      return nil if v.respond_to?(:nan?) && v.nan?
      return :zero if v.zero?
      v.positive? ? :positive : :negative
    end

    def exact_value(e)
      Algebraic.exact(e)
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      nil
    end

    def complex?(e)
      e.each_node.any? { |n| n.is_a?(Num) && n.value.is_a?(Complex) }
    end

    def parts_symbolic?(part) = part.each_node.any? { |n| n.is_a?(Fn) && %i[re im].include?(n.name) }

    # :positive or :negative when two precisions agree on a value well above
    # the rounding error of the largest magnitude in the walk (a value that
    # is smaller could be what is left of an exact 0 whose terms each
    # rounded); nil when every level is consistent with 0 - which is not a
    # proof of 0 (exp(10**-100) - 1 is exactly 0 at 30 and 60 digits); and
    # :unsupported when Precision cannot evaluate the expression at all, or
    # only to the digits of a Float inside it.
    def precise_sign(e) = precise(e).first

    # [verdict, value, bound] - the last value and its error bound come
    # along for algebraic_zero?
    def precise(e)
      previous = nil
      LEVELS.each do |digits|
        value, scale, keep = begin
          Precision.evalf_with_scale(e, digits)
        rescue ZeroDivisionError
          return nil
        rescue StandardError, NotImplementedError, RCAS::Unsupported => rescued
          RCAS.guard!(rescued, refused: true)
          return :unsupported
        end
        return :unsupported if keep < digits
        bound = scale.mult(BigDecimal("1e-#{digits}"), 5)
        if previous
          coarse, coarse_bound = previous
          consistent = (value - coarse).abs <= coarse_bound + bound
          return [value.positive? ? :positive : :negative] if consistent && value.abs > bound
        end
        previous = [value, bound]
      end
      [nil, *previous]
    end

    # An algebraic constant - rationals, radicals, i, RootOf - is a root of
    # the polynomial Algebraic.annihilator builds. If 0 is not a root the
    # constant is not 0; if it is, the other roots are at least
    # |q0|/(|q0| + max|qi|) away from it (Cauchy's bound for q = p/x**m),
    # and a value evaluated below that distance is 0. That proves
    # sqrt(2)*sqrt(3) - sqrt(6) = 0, which has three radicals and is beyond
    # Algebraic.exact.
    def algebraic_zero?(e, value, bound)
      q = annihilator_at_zero(e)
      return false if q.nil? || q == :nonzero
      separation = Rational(q.first) / (q.first + q.drop(1).max.to_r)
      value.abs + bound < BigDecimal(separation.numerator).div(separation.denominator, 20) / 2
    end

    # The coefficients of p/x**m (absolute values, constant term first) when
    # 0 is a root of the annihilating polynomial p of an algebraic constant,
    # :nonzero when it is not - a proof that the constant is not 0 - and
    # nil when the constant is not algebraic in that sense or too large.
    def annihilator_at_zero(e)
      return nil unless e.each_node.all? { |n| ALGEBRAIC_NODES.any? { |c| n.is_a?(c) } } && e.each_node.count <= 40
      x = Var.new(:_decide)
      coefficients = Coefficients.coeffs(Algebraic.annihilator(e, x), x)
      return nil unless coefficients.all? { |c| c.is_a?(Num) && (c.value.is_a?(Integer) || c.value.is_a?(Rational)) }
      m = coefficients.index { |c| !c.value.zero? }
      return nil if m.nil?
      return :nonzero if m.zero?
      coefficients.drop(m).map { |c| c.value.abs }
    rescue StandardError, NotImplementedError, RCAS::Unsupported => rescued
      RCAS.guard!(rescued, refused: true) if rescued.is_a?(StandardError)
      nil
    end

    ALGEBRAIC_NODES = [Num, Add, Sub, Mul, Div, Neg, Pow, RootOf].freeze

    # A constant that the normal forms reduce to 0: expand, cancel, the
    # Pythagorean identity. Asked only after every evaluation came out
    # consistent with 0, so the cost is paid where a proof is wanted.
    def symbolic_zero?(e)
      return false if Thread.current[:rcas_decide_symbolic] # the normal forms asked us
      begin
        Thread.current[:rcas_decide_symbolic] = true
        simplified = e.simplify
        return true if simplified.is_a?(Num) && simplified.value == 0
        return true if factorial_zero?(e)
        !simplified.is_a?(Num) && Scalar.identically_zero?(simplified)
      ensure
        Thread.current[:rcas_decide_symbolic] = nil
      end
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    # gamma(u) is (u - 1)!, and simplify cancels factorials whose arguments
    # differ by an integer: gamma(-42/5)/gamma(-47/5) + 47/5 is 0 that way
    # and undecided every other way. A sum of factorials is divided by one
    # of them first, which makes every term such a ratio: (1 + k)! - k! -
    # k*k! over k! expands to 0. (It had been "shown" zero by the sampled
    # points that happened to be integers, which was also what called
    # sin(30*pi*x) zero.) A factorial has no zeros, so the quotient
    # vanishes exactly where the sum does.
    def factorial_zero?(e)
      return false unless e.each_node.any? { |n| n.is_a?(Fn) && %i[gamma factorial].include?(n.name) }
      rewritten = as_factorials(e)
      return true if zero_number?(rewritten.simplify)
      rewritten.each_node.select { |n| n.is_a?(Fn) && n.name == :factorial }.uniq.first(3).any? do |f|
        zero_number?(Expand.expand(rewritten / f).simplify)
      end
    end

    def zero_number?(v) = v.is_a?(Num) && v.value.is_a?(Numeric) && v.value.zero?

    def as_factorials(e)
      e = e.map_children { |c| as_factorials(c) }
      e.is_a?(Fn) && e.name == :gamma && e.args.size == 1 ? Fn.new(:factorial, [(e.args.first - 1).simplify]) : e
    end

    def float_sign(e)
      v, error = float_with_error(e)
      return nil unless v.is_a?(Float) && v.abs > ERROR_MARGIN * error
      v.positive? ? :positive : :negative
    end

    # A complex Float that stands clear of rounding is not zero; nothing
    # smaller is decided.
    def complex_float_zero?(e) = float_nonzero?(e) ? false : nil

    # The value as a Float or Complex and a bound on its rounding error, in
    # one walk: an exact number is off by half an ulp, a sum by the errors
    # of its terms, a product relatively, a function by its derivative
    # times the error of its argument (a first-order running error bound).
    # A value well above its bound is not rounding. nil when there is no
    # number. (The largest intermediate magnitude stood in for the bound
    # before, which counted the 92160 of sqrt(2)/92160 as a magnitude that
    # might have cancelled; and it evaluated every node separately.)
    def float_with_error(e)
      float_bound(e)
    rescue ZeroDivisionError, Math::DomainError, FloatDomainError
      nil
    end

    # A Float that stands clear of its rounding error is not 0: the quick
    # half of every zero test, asked before the exact routes, which can cost
    # a factorization over a number field.
    def float_nonzero?(e)
      value, error = float_with_error(e)
      !value.nil? && value.abs > ERROR_MARGIN * error
    end

    # How far above its error bound a value has to be (the bound is first
    # order, and the functions' derivatives are taken at the value).
    ERROR_MARGIN = 64
    EPS = Float::EPSILON

    def float_bound(e)
      value, error =
        case e
        when Num
          x = e.value
          case x
          when Integer, Rational then [x.to_f, x.to_f.abs * EPS]
          when Float then [x, x.abs * EPS]
          when Complex then [Complex(x.real.to_f, x.imaginary.to_f), x.abs.to_f * EPS]
          end
        when Const then e.name == :pi ? [Math::PI, Math::PI * EPS] : nil
        when Neg
          a, ea = float_bound(e.arg)
          a && [-a, ea]
        when Add, Sub, Mul, Div
          a, ea = float_bound(e.left)
          return nil if a.nil?
          b, eb = float_bound(e.right)
          return nil if b.nil?
          case e
          when Add then (v = a + b) && [v, ea + eb + v.abs * EPS]
          when Sub then (v = a - b) && [v, ea + eb + v.abs * EPS]
          when Mul then (v = a * b) && [v, a.abs * eb + b.abs * ea + ea * eb + v.abs * EPS]
          else
            return nil if b.abs <= eb
            v = a / b
            [v, (ea + v.abs * eb) / (b.abs - eb) + v.abs * EPS]
          end
        when Pow then power_bound(e)
        when Fn
          return nil unless e.args.size == 1
          a, ea = float_bound(e.args.first)
          a && function_bound(e.name, a, ea)
        end
      return nil unless value.is_a?(Numeric) && value.abs.finite? && error.finite?
      [value, error]
    end

    def power_bound(e)
      a, ea = float_bound(e.base)
      return nil if a.nil?
      n = e.exponent
      if n.is_a?(Num) && n.value.is_a?(Integer)
        k = n.value
        return nil if k.negative? && a.abs <= ea
        v = a**k
        return [v, v.abs * EPS] if ea.zero?
        # |d(a**k)| = |k|*|a|**(k - 1)*|da|, over the whole interval a +- ea
        reach = k.negative? ? a.abs - ea : a.abs + ea
        return [v, k.abs * reach**(k - 1) * ea + v.abs * EPS * (k.abs.bit_length + 1)]
      end
      b, eb = float_bound(n)
      return nil if b.nil? || a.abs <= ea
      v = complex_power(a, b)
      logs = Math.log(a.abs).abs + Math::PI
      [v, v.abs * (b.abs * ea / (a.abs - ea) + logs * eb + 4 * EPS)]
    end

    def complex_power(a, b)
      return a**b if a.is_a?(Float) && a.positive? && b.is_a?(Float)
      CMath_lite.exp(Complex(b) * CMath_lite.log(Complex(a)))
    end

    # [f(a), error] from the error of a: |f'| over a +- ea bounds the step.
    def function_bound(name, a, ea)
      v = function_value(name, a)
      return nil if v.nil?
      imaginary = a.is_a?(Complex) ? a.imaginary.abs : 0.0
      slope =
        case name
        when :re, :im, :conj, :abs then 1.0
        when :arg then a.abs > ea ? 1.0 / (a.abs - ea) : nil
        when :sign then a.abs > ea ? 0.0 : nil
        when :sin, :cos then Math.cosh(imaginary + ea)
        when :erf, :erfc then imaginary.zero? ? 1.2 : nil
        when :atan
          # 1/(1 + z**2), bounded away from the poles at +-i
          room = (1 + a * a).abs - 2 * a.abs * ea - ea * ea
          room.positive? ? 1.0 / room : nil
        when :exp then Math.exp(a.real + ea)
        when :sinh, :cosh then Math.cosh(a.real.abs + ea) + 1
        when :log then a.abs > ea ? 1.0 / (a.abs - ea) : nil
        when :tan
          c = Math.cos(a.real).abs
          c > ea ? 1.0 / (c - ea)**2 : nil
        when :asin, :acos
          # 1/sqrt(1 - z**2), bounded away from +-1 (asin(2) is fine)
          room = (1 - a * a).abs - 2 * a.abs * ea - ea * ea
          room.positive? ? 1.0 / Math.sqrt(room) : nil
        else
          # re, im, gamma, ... by evalf: a slope we do not know is only
          # harmless when the argument carries no error beyond an ulp, and
          # far from where the function is singular or jumps
          ea <= a.abs * 4 * EPS ? unknown_slope(name, a, ea, v) : nil
        end
      return nil if slope.nil?
      [v, slope * ea + v.abs * 8 * EPS]
    end

    # The points where a function evaluated by evalf is not smooth: the
    # poles of gamma at 0, -1, -2, ... and the rest. An ulp of error in the
    # argument is a large relative error in the distance to a pole, and
    # gamma(-1 + 10**-15) has a slope near 10**30, where 1e3*(|v| + 1) said
    # 10**18 - an exact zero came out as -8e11 and "not zero" (the sixth
    # review's preflight). Near such a point the bound grows like the
    # slope of a simple pole, 1/d**2 over the distance d; within the error
    # of the argument there is no bound at all.
    SINGULAR = {
      gamma: :nonpositive, digamma: :nonpositive, psi: :nonpositive,
      factorial: :negative, harmonic: :negative,
      zeta: [1.0], li: [1.0, 0.0], Ei: [0.0], Ci: [0.0],
      floor: :integers, ceil: :integers, round: :half_integers
    }.freeze
    JUMPING = %i[floor ceil round].freeze

    def unknown_slope(name, a, ea, v)
      d = singular_distance(SINGULAR[name], a)
      return 1e3 * (v.abs + 1) if d.nil?
      return nil if d <= 2 * ea
      return 0.0 if JUMPING.include?(name)
      1e3 * (v.abs + 1) * (1 + 1 / d) + 1 / (d * d)
    end

    def singular_distance(points, a)
      return nil if points.nil?
      re = a.real.to_f
      nearest =
        case points
        when Array then points.min_by { |p| (a - p).abs }
        when :nonpositive then [re.round, 0].min
        when :negative then [re.round, -1].min
        when :integers then re.round
        when :half_integers then re.floor + 0.5
        end
      (a - nearest).abs
    end

    def function_value(name, a)
      if a.is_a?(Float)
        case name
        when :exp then return Math.exp(a)
        when :sin, :cos, :atan, :sinh, :cosh, :tan, :erf, :erfc then return Math.public_send(name, a)
        when :log then return a.positive? ? Math.log(a) : CMath_lite.log(Complex(a))
        when :abs then return a.abs
        when :sign then return (a <=> 0).to_f
        when :asin, :acos then return Math.public_send(name, a) if a.abs <= 1
        end
      end
      return a.abs if name == :abs
      return a.real.to_f if name == :re
      return a.imaginary.to_f if name == :im
      return a.conj if name == :conj
      return Math.atan2(a.imaginary.to_f, a.real.to_f) if name == :arg
      return CMath_lite.public_send(name, Complex(a)) if CMath_lite::NAMES.include?(name)
      # re, im, gamma, ...: evalf takes the function of the number
      v = Fn.new(name, [Num.new(a)]).evalf
      v = v.value if v.is_a?(Num)
      v.is_a?(Numeric) ? (v.is_a?(Complex) ? Complex(v.real.to_f, v.imaginary.to_f) : v.to_f) : nil
    end
  end
end
