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
        exact = exact_angle(real, imaginary)
        return exact if exact
        x = real.evalf
        y = imaginary.evalf
        return Num.new(Math.atan2(y, x)) if x.is_a?(Numeric) && y.is_a?(Numeric) && !x.is_a?(Complex) && !y.is_a?(Complex)
      end
      Fn.new(:arg, [e])
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
    rescue StandardError
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
      t = Functions.exact_value(:atan, (imaginary / real).simplify) or return nil
      return t if positive?(real)
      (positive?(imaginary) ? t + PI : t - PI).simplify
    end

    def positive?(e)
      v = e.evalf
      v.is_a?(Numeric) && !v.is_a?(Complex) && v.positive?
    end

    def negative?(e)
      v = e.evalf
      v.is_a?(Numeric) && !v.is_a?(Complex) && v.negative?
    end
  end
end
