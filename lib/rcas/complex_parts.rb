# frozen_string_literal: true

module RCAS
  # re, im, conj, arg.
  #
  #   re(3 + 2*I)                 # => 3
  #   im((1 + I)**2)              # => 2
  #   conj(x + I*y)               # => x - i*y   after assume(x: RR, y: RR)
  #   arg(-1), arg(1 + I)         # => pi, pi/4
  #
  # The expression is expanded and each term split by its complex
  # coefficient. A factor is taken as real only when its inferred domain says
  # so (numbers, pi, variables assumed real); anything else stays inside an
  # unevaluated re(...) or im(...), so re(x) is re(x) until x is declared real.
  module ComplexParts
    module_function

    def re(e) = parts(Expression.lift(e)).first
    def im(e) = parts(Expression.lift(e)).last

    def conj(e)
      real, imaginary = parts(Expression.lift(e))
      (real - I * imaginary).simplify
    end

    def arg(e)
      e = Expression.lift(e)
      real, imaginary = parts(e)
      if constant?(real) && constant?(imaginary)
        # arg(0) has no value (A7)
        return UNDEFINED if Decide.zero?(real) && Decide.zero?(imaginary)
        exact = exact_angle(real, imaginary)
        return exact if exact
        # an exact number keeps its angle as a node rather than turning into
        # a Float; a Float in, a Float out - from parts taken to enough
        # digits: exp(pi*sqrt(163)) - 640320**3 - 744 + i is a hair left of
        # the imaginary axis, and the Float real part said -480 (Q1)
        return Fn.new(:arg, [e]) unless e.each_node.any? { |n| n.is_a?(Num) && (n.value.is_a?(Float) || (n.value.is_a?(Complex) && n.value.real.is_a?(Float))) }
        x = precise_float(real)
        y = precise_float(imaginary)
        return Num.new(Math.atan2(y, x)) if x && y
      end
      Fn.new(:arg, [e])
    end

    def precise_float(e)
      v = Precision.evalf(e, 20).to_f
      v.finite? ? v : nil
    rescue StandardError, NotImplementedError, RCAS::Unsupported => rescued
      RCAS.guard!(rescued, refused: true)
      v = e.evalf
      v.is_a?(Numeric) && !v.is_a?(Complex) ? v.to_f : nil
    end

    # => [re, im]
    def parts(e)
      constant, table = Expand.table(e)
      real = Num.new(real_of(constant))
      imaginary = Num.new(imaginary_of(constant))
      table.each do |factors, coeff|
        term = Simplify.rebuild_product(1, factors)
        a = Num.new(real_of(coeff))
        b = Num.new(imaginary_of(coeff))
        if real_valued?(term)
          real += a * term
          imaginary += b * term
        elsif (known = known_parts(term))
          tr, ti = known
          real += a * tr - b * ti
          imaginary += b * tr + a * ti
        else
          tr = Fn.new(:re, [term])
          ti = Fn.new(:im, [term])
          real += a * tr - b * ti
          imaginary += b * tr + a * ti
        end
      end
      [real.simplify, imaginary.simplify]
    end

    # The parts of a term that is real factors times one logarithm of a
    # constant: log(u) = log|u| + i*arg(u), so im(log(-1)) is pi and
    # -log(-1) is not a real point (third review, S14). nil otherwise.
    def known_parts(term)
      coeff, factors = Simplify.factorize(term)
      real, other = factors.partition { |base, exp| real_valued?(Simplify.power_node(base, exp)) }
      return nil unless other.size == 1
      base, exp = other.first
      return nil unless exp == 1 && base.is_a?(Fn) && base.name == :log && base.args.size == 1 && constant?(base.args.first)
      u = base.args.first
      angle = arg(u)
      return nil if angle.is_a?(Fn)
      scale = Simplify.rebuild_product(coeff, real.to_h)
      [(scale * Fn.new(:log, [Fn.new(:abs, [u]).simplify])).simplify, (scale * angle).simplify]
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      nil
    end

    def real_of(v) = v.is_a?(Complex) ? v.real : v
    def imaginary_of(v) = v.is_a?(Complex) ? v.imaginary : 0

    def real_valued?(term)
      return false if term.each_node.any? { |n| n.is_a?(Num) && n.value.is_a?(Complex) }
      d = Infer.domain(term)
      !d.nil? && d <= RR
    end

    def constant?(e) = e.variables.empty? && e.each_node.none? { |n| n.is_a?(Fn) && %i[re im arg].include?(n.name) }

    # 0, pi, +-pi/2 and the atan table, by quadrant; nil when not exact.
    def exact_angle(real, imaginary)
      if Scalar.zero?(imaginary)
        return Num.new(0) if positive?(real)
        return PI if negative?(real)
        return nil
      end
      if Scalar.zero?(real)
        return positive?(imaginary) ? (PI / 2).simplify : (-PI / 2).simplify
      end
      ratio = (imaginary / real).simplify
      t = Functions.exact_value(:atan, ratio)
      # atan is odd: atan(-sqrt(3)) = -atan(sqrt(3)), which the table knows
      if t.nil? && negative?(ratio)
        u = Functions.exact_value(:atan, Simplify.negate(ratio).simplify)
        t = Simplify.negate(u).simplify if u
      end
      # no table value: atan of the ratio is still the exact angle, moved to
      # the right half-plane's other side when the real part is negative
      t ||= Fn.new(:atan, [ratio]) if positive?(real) || negative?(real)
      return nil unless t
      return t if positive?(real)
      (positive?(imaginary) ? t + PI : t - PI).simplify
    end

    # The signs are decided (Decide), not read off a Float: a real part of
    # -7.5e-13 computed from terms of size 10**17 has no Float sign (Q1).
    def positive?(e) = Decide.sign(e) == :positive
    def negative?(e) = Decide.sign(e) == :negative
  end
end
