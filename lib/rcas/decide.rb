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
    # A Float is believed when it exceeds rounding at the largest
    # intermediate magnitude by this factor.
    FLOAT_MARGIN = 1e-9

    # :positive, :negative or :zero for a real constant; nil when that is
    # not decided (not constant, not real, or beyond the routes above).
    def sign(e)
      e = Expression.lift(e)
      return nil unless decidable?(e)
      return number_sign(e.value) if e.is_a?(Num)
      exact = exact_value(e)
      return :zero if exact&.zero?
      found = precise_sign(e, nonzero: !exact.nil?)
      return found unless found == :unsupported
      float_sign(e)
    end

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
        return complex_float_zero?(e)
      end
      s = sign(e)
      return s == :zero if s
      complex_float_zero?(e) # log(-1) is complex without an i in sight
    end

    # An expression in indeterminates that no normal form reduces
    # (gamma(1 - a)/gamma(-a) + a): true when it vanishes at several random
    # rational points, each decided exactly; false as soon as one point
    # shows it does not; nil when no point could be decided. A nonzero
    # rational function vanishing at four random rational points is not a
    # risk worth naming; a Float residue under 1e-9 was, and four copies of
    # that test with their own seeds and tolerances were one of the third
    # review's duplications (section 5).
    def identically_zero?(expr, points: 4, seed: 20260922)
      e = Expression.lift(expr)
      return zero?(e) if e.variables.empty?
      return true if Scalar.identically_zero?(e)
      random = Random.new(seed)
      decided = 0
      points.times do
        point = e.variables.to_h { |name| [name, Num.new(Rational(random.rand(3..97), random.rand(2..11)))] }
        value = begin
          e.subs(point).simplify
        rescue ZeroDivisionError
          next # a pole: this point says nothing
        end
        verdict = zero?(value)
        return false if verdict == false
        decided += 1 if verdict
      end
      decided.positive? ? true : nil
    rescue StandardError, NotImplementedError => rescued
      RCAS.guard!(rescued) if rescued.is_a?(StandardError)
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

    # :unsupported when Precision cannot evaluate the expression at all, or
    # only to the digits of a Float inside it.
    def precise_sign(e, nonzero: false)
      values = []
      LEVELS.each do |digits|
        value = begin
          Precision.evalf(e, digits, certify: false)
        rescue ZeroDivisionError
          return nil
        rescue StandardError, NotImplementedError => rescued
          RCAS.guard!(rescued)
          return :unsupported
        end
        return :unsupported if value.digits < digits
        values << value.value
        next if values.size < 2
        coarse, fine = values[-2], values[-1]
        return :zero if !nonzero && (fine.zero? || fine.abs <= coarse.abs * SHRINK)
        if !fine.zero? && !coarse.zero? && (fine - coarse).abs <= fine.abs * AGREE
          return fine.positive? ? :positive : :negative
        end
      end
      nil
    end

    def float_sign(e)
      v, scale = float_with_scale(e)
      return nil unless v.is_a?(Float) && v.finite?
      return nil unless v.abs > scale * Float::EPSILON / FLOAT_MARGIN
      v.positive? ? :positive : :negative
    end

    # A complex Float that stands clear of rounding is not zero; nothing
    # smaller is decided.
    def complex_float_zero?(e)
      v, scale = float_with_scale(e)
      return nil unless v.is_a?(Numeric) && v.abs.finite?
      v.abs > scale * Float::EPSILON / FLOAT_MARGIN ? false : nil
    end

    # The value as a Float or Complex, and the largest magnitude of any
    # subexpression on the way to it: a result far above the rounding of
    # that magnitude is not rounding. nil when there is no number.
    def float_with_scale(e)
      nodes = e.each_node.to_a
      return [nil, 0.0] if nodes.size > 400
      scale = 1.0
      value = nil
      nodes.each do |node|
        v = begin
          node.evalf
        rescue StandardError, Math::DomainError => rescued
          RCAS.guard!(rescued)
          nil
        end
        v = v.value if v.is_a?(Num)
        v = v.to_f if v.is_a?(Decimal)
        next unless v.is_a?(Numeric) && v.abs.to_f.finite?
        value = v if node.equal?(e)
        scale = [scale, v.abs.to_f].max
      end
      value = Complex(value.real.to_f, value.imaginary.to_f) if value.is_a?(Complex)
      value = value.to_f if value.is_a?(Numeric) && !value.is_a?(Complex)
      [value, scale]
    end
  end
end
