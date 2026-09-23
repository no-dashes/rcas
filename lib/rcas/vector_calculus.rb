# frozen_string_literal: true

module RCAS
  # Integrals along a curve and over a surface, and the three theorems that
  # turn one of them into another.
  #
  #   line_integral(x*y, [cos(t), sin(t)], t: 0..pi/2)     # scalar: f ds
  #   line_integral([-y, x], [cos(t), sin(t)], t: 0..2*pi) # vector: F . dr
  #   surface_integral(1, [u, v, u + v], u: 0..1, v: 0..1) # f dS
  #   flux([x, y, z], sphere, u: 0..2*pi, v: 0..pi)        # F . n dS
  #   green([-y, x], x: 0..1, y: 0..1)                     # the double integral
  #   stokes([-y, x, 0], disc, u: 0..1, v: 0..2*pi)
  #   divergence_theorem([x, y, z], x: 0..1, y: 0..1, z: 0..1)
  #
  # Everything here is a parametrization followed by an ordinary integral:
  # a curve is [x(t), y(t)] or [x(t), y(t), z(t)], a surface is
  # [x(u, v), y(u, v), z(u, v)], and the field is written in x, y, z (name
  # other coordinates with vars:). The integrals are the ones integrate
  # already does, so an integrand it cannot do stays an integral(...) node.
  #
  # Sources (keys: MANUAL.md, Sources): the elements ds = |r'| dt and
  # dS = |r_u x r_v| du dv and the three theorems are the textbook ones
  # [MT12, ch. 7-8]; the general statement behind all three is Stokes's
  # theorem for differential forms [Spi65, ch. 4-5].
  module VectorCalculus
    module_function

    # The coordinates a field is written in, when nobody says: x, y, z if
    # that is all it uses, otherwise its own variables if there are exactly
    # as many as the parametrization has components.
    COORDINATES = %i[x y z].freeze

    def coordinates(integrand, vars, dim)
      return Array(vars).map { |v| Expression.lift(v) } if vars && !Array(vars).empty?
      default = COORDINATES.first(dim).map { |n| Var.new(n) }
      names = list(integrand).flat_map { |f| Expression.lift(f).variables }.uniq
      # a field that mentions x, y or z is read in x, y, z, and its other
      # names are parameters: (a*y, -x, 0) with a as a coordinate did no
      # work around the circle (third review, L8)
      return default if (names - COORDINATES).empty? || names.size != dim || names.any? { |n| COORDINATES.include?(n) }
      names.sort.map { |n| Var.new(n) }
    end

    def vector?(obj) = obj.is_a?(Array) || obj.is_a?(Vector)

    # A field, a curve or a surface as a plain Array; a scalar field is one
    # component of its own, which is what tells the two kinds apart.
    def list(obj)
      return obj.to_a if obj.is_a?(Vector)
      obj.is_a?(Array) ? obj : [obj]
    end

    # The components of a curve, a surface or a field, as Expressions.
    def components(obj, name, sizes)
      parts = list(obj)
      unless vector?(obj) && sizes.include?(parts.size)
        raise ArgumentError, "#{name}: expected #{sizes.map(&:to_s).join(' or ')} components, got #{obj.inspect}"
      end
      parts.map { |c| Expression.lift(c) }
    end

    # f(r(t)): the field along the parametrization.
    def along(expr, coords, parametrization)
      Expression.lift(expr).subs(coords.zip(parametrization).to_h)
    end

    def dot(a, b) = a.zip(b).map { |u, v| u * v }.reduce(:+).simplify

    def cross(a, b)
      [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]].map(&:simplify)
    end

    # ---- the length element ---------------------------------------------------

    # |v|, with the perfect squares taken out of the root: sqrt(16*sin(v)**2)
    # is 4*sin(v) on 0..pi. The sign of such a factor is decided on the
    # parameter range (ranges is [[var, from, to], ...]) and abs(...) is the
    # answer when it changes there, so nothing is assumed silently.
    def norm(parts, ranges = [])
      radicand = parts.map { |c| Expression.lift(c)**2 }.reduce(:+).simplify
      radicand = shorter(radicand, Trigonometry.trigsimp(radicand.expand)) if trigonometric?(radicand)
      coeff, factors = Simplify.factorize(radicand)
      outside = Num.new(1)
      inside = {}
      factors.each do |base, exponent|
        half = exponent.is_a?(Integer) && exponent.even? ? exponent / 2 : nil
        if half.nil?
          inside[base] = exponent
        else
          outside *= (half.even? ? base : root_factor(base, ranges))**half
        end
      end
      (outside * Analysis.root(Simplify.rebuild_product(coeff, inside))).simplify
    end

    TRIGONOMETRIC = (Trigonometry::SQUARES.keys + %i[tan tanh]).freeze

    def trigonometric?(expr) = expr.each_node.any? { |n| n.is_a?(Fn) && TRIGONOMETRIC.include?(n.name) }

    def shorter(a, b) = [a, b].min_by { |e| [e.each_node.count, e.to_s.size] }

    # sqrt(u**2) is u, -u or abs(u), by the sign of u on the parameter
    # ranges - a sign that is proved, never sampled.
    def root_factor(base, ranges)
      case proven_sign(base, ranges) || real_sign(base, ranges)
      when :positive, :nonnegative then base
      when :negative, :nonpositive then Neg.new(base).simplify
      else Fn.new(:abs, [base])
      end
    end

    # The sign that needs no range: 4*u**2 + 4*v**2 is not negative for the
    # real parameters of any range (the abs kept it formal: fourth review),
    # and on a box the enclosure of the base may be one-signed.
    def real_sign(base, ranges)
      names = ranges.map { |var, _, _| Expression.lift(var).name }
      sign = RCAS.assume(**names.to_h { |n| [n, RR] }) { RCAS.sign_of(base) }
      return sign if sign
      ranges.empty? ? nil : Analysis.sign_on_box(base, ranges)
    end

    # In one variable the zeros decide (Analysis.sign_on_interval). On a box
    # of several ranges the sign is proved factor by factor: a product whose
    # every factor moves with one range at most has the sign of the product
    # of theirs. Anything else keeps its abs - sampling five points of the
    # box said x + y - 1/10 was positive on the unit square, and it is not
    # in the corner (third review, T2).
    def proven_sign(base, ranges)
      base = Expression.lift(base)
      one = single_range(base, ranges)
      return Analysis.sign_on_interval(base, one[0], one[1], one[2]) if one
      boxed = ranges.empty? ? nil : Analysis.sign_on_box(base, ranges)
      return boxed if %i[positive negative].include?(boxed)
      coeff, factors = Simplify.factorize(base)
      return nil unless coeff.is_a?(Numeric) && coeff.real? && !coeff.zero?
      negative = coeff.negative?
      factors.each do |factor, exponent|
        sign = proven_sign_of_factor(factor, ranges)
        return nil if sign.nil?
        next if exponent.is_a?(Integer) && exponent.even?
        return nil unless exponent.is_a?(Integer) || sign == :positive
        negative = !negative if sign == :negative
      end
      negative ? :negative : :positive
    end

    def proven_sign_of_factor(factor, ranges)
      return Analysis.constant_sign(factor) if factor.variables.empty?
      one = single_range(factor, ranges)
      one ? Analysis.sign_on_interval(factor, one[0], one[1], one[2]) : nil
    end

    # The one range the expression actually moves with, when there is one.
    def single_range(base, ranges)
      wanted = ranges.select { |var, _, _| Expression.lift(base).variables.include?(Expression.lift(var).name) }
      wanted.size == 1 && Expression.lift(base).variables.size == 1 ? wanted.first : nil
    end

    # ---- line integrals -------------------------------------------------------

    # A scalar field integrated against ds = |r'(t)| dt, a vector field
    # against dr = r'(t) dt (the work it does along the curve).
    def line_integral(integrand, curve, var, from, to, vars: nil)
      r = components(curve, "line_integral", [2, 3])
      t = Expression.lift(var)
      dr = r.map { |c| c.diff(t) }
      coords = coordinates(integrand, vars, r.size)
      integrand =
        if vector?(integrand)
          f = components(integrand, "line_integral", [r.size])
          dot(f.map { |c| along(c, coords, r) }, dr)
        else
          (along(integrand, coords, r) * norm(dr, [[t, from, to]])).simplify
        end
      Integrate.definite(integrand, t, from, to)
    end

    # The flux of a plane field across a curve: the integral of F . n ds with
    # n = (y', -x')/|r'|, which points to the right of the direction of
    # travel (outwards for a curve run anticlockwise).
    def curve_flux(field, curve, var, from, to, vars: nil)
      r = components(curve, "flux", [2])
      f = components(field, "flux", [2])
      t = Expression.lift(var)
      coords = coordinates(field, vars, 2)
      p, q = f.map { |c| along(c, coords, r) }
      Integrate.definite((p * r[1].diff(t) - q * r[0].diff(t)).simplify, t, from, to)
    end

    # The area a closed plane curve encloses, by Green's theorem:
    # 1/2 * integral(x*y' - y*x'), positive when the curve runs anticlockwise.
    def enclosed_area(curve, var, from, to)
      r = components(curve, "enclosed_area", [2])
      t = Expression.lift(var)
      Integrate.definite(((r[0] * r[1].diff(t) - r[1] * r[0].diff(t)) / 2).simplify, t, from, to)
    end

    # ---- surface integrals ----------------------------------------------------

    # A scalar field against dS = |r_u x r_v| du dv, a vector field against
    # the vector element (r_u x r_v) du dv, whose direction is the normal
    # the parametrization orients. `ranges` is [[u, from, to], [v, from, to]]
    # and they are integrated in that order, the first one innermost.
    def surface_integral(integrand, surface, ranges, vars: nil)
      r = components(surface, "surface_integral", [3])
      normal = surface_normal(r, ranges)
      coords = coordinates(integrand, vars, 3)
      integrand =
        if vector?(integrand)
          f = components(integrand, "surface_integral", [3])
          dot(f.map { |c| along(c, coords, r) }, normal)
        else
          (along(integrand, coords, r) * norm(normal, ranges)).simplify
        end
      integrate_over(integrand, ranges)
    end

    # r_u x r_v: the vector surface element, normal to the surface and as
    # long as the area the parameters sweep out.
    def surface_normal(r, ranges)
      u, v = ranges.first(2).map { |range| Expression.lift(range.first) }
      cross(r.map { |c| c.diff(u) }, r.map { |c| c.diff(v) })
    end

    # The ranges innermost first: an inner range may depend on the outer
    # variables, never an outer range on an inner one - y: 0..x with x
    # innermost is no region, and the answer kept an integration variable
    # (third review, L14).
    def integrate_over(integrand, ranges)
      check_nesting!(ranges)
      ranges.reduce(Expression.lift(integrand)) do |acc, (var, from, to)|
        Integrate.definite(acc, Expression.lift(var), from, to)
      end
    end

    def check_nesting!(ranges)
      names = ranges.map { |var, _, _| Expression.lift(var).name }
      ranges.each_with_index do |(var, from, to), i|
        inner = names.first(i)
        used = [from, to].flat_map { |b| Expression.lift(b).variables } & inner
        next if used.empty?
        raise ArgumentError, "the range of #{var} depends on #{used.join(', ')}, which is integrated first; " \
                             "list the ranges innermost first, each depending only on the ones after it"
      end
    end

    # A field with a singularity inside the region is outside the
    # theorems: the vortex (-y, x)/(x**2 + y**2) has zero curl everywhere it
    # is defined and circulates 2*pi around the origin (third review, L13).
    # Refused unless every denominator of the field is shown not to vanish
    # on the region - a sign under real coordinates, or no zero in the one
    # range it moves with.
    def regular_on!(field, xs, ranges, name)
      list(field).each do |component|
        Analysis.denominators(Expression.lift(component), xs.first).concat(
          xs.drop(1).flat_map { |x| Analysis.denominators(Expression.lift(component), x) }
        ).uniq.each do |d|
          next if nonvanishing?(d, xs, ranges)
          raise RCAS::Unsupported, "#{name}: the field is singular where #{d} = 0, which may meet the region; the theorem needs a field without singularities there"
        end
      end
    end

    def nonvanishing?(d, xs, ranges)
      sign = RCAS.assume(**xs.to_h { |x| [x.name, RR] }) { RCAS.sign_of(d) }
      return true if %i[positive negative].include?(sign)
      # x**2 + y**2 >= 2 on [1, 2]x[1, 2]: the enclosure proves it (the
      # vortex on that square was refused: fourth review)
      !ranges.empty? && (%i[positive negative].include?(proven_sign(d, ranges)) || %i[positive negative].include?(Analysis.sign_on_box(d, ranges)))
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    # ---- the three theorems ---------------------------------------------------

    # Green: the circulation of [P, Q] around the boundary of a plane region
    # is the double integral of Q_x - P_y over the region. The region is the
    # two ranges, innermost first, so the inner bounds may depend on the
    # outer variable.
    def green(field, ranges, vars: nil)
      f = components(field, "green", [2])
      xs = region_coordinates(ranges, vars, 2, "green")
      check_nesting!(ranges)
      regular_on!(f, xs, ranges, "green")
      integrate_over((f[1].diff(xs[0]) - f[0].diff(xs[1])).simplify, ranges)
    end

    # Stokes: the circulation of a field around the edge of a surface is the
    # flux of its curl through the surface.
    def stokes(field, surface, ranges, vars: nil)
      f = components(field, "stokes", [3])
      xs = coordinates(field, vars, 3)
      surface_integral(Analysis.curl(f, xs).to_a, surface, ranges, vars: xs)
    end

    # Gauss: the flux of a field out of the boundary of a solid is the
    # triple integral of its divergence over the solid, the three ranges
    # again innermost first.
    def divergence_theorem(field, ranges, vars: nil)
      f = components(field, "divergence_theorem", [3])
      xs = region_coordinates(ranges, vars, 3, "divergence_theorem")
      check_nesting!(ranges)
      regular_on!(f, xs, ranges, "divergence_theorem")
      integrate_over(Analysis.divergence(f, xs), ranges)
    end

    # For a region the coordinates are the ones the ranges name, in
    # alphabetical order, so that [P, Q] belongs to x, y and not to the order
    # of integration.
    def region_coordinates(ranges, vars, dim, name)
      return Array(vars).map { |v| Expression.lift(v) } if vars && !Array(vars).empty?
      names = ranges.map { |var, _, _| Expression.lift(var).name }
      raise ArgumentError, "#{name}: give #{dim} ranges" unless names.size == dim
      names.sort.map { |n| Var.new(n) }
    end

    # ---- conservative fields --------------------------------------------------

    # A field is conservative when it is the gradient of a potential; on a
    # region without holes that is exactly the symmetry of the derivatives
    # (curl = 0 in three variables, Q_x = P_y in two).
    #
    # "Without holes" is the part that is easy to forget: a field with a
    # singularity has a hole in its domain, and its symmetric derivatives
    # prove nothing there, so such a field is refused rather than
    # certified.
    def conservative?(field, vars = nil)
      f = components(field, "conservative?", [2, 3])
      xs = coordinates(field, vars, f.size)
      return symmetric?(f, xs) if regular?(f, xs)
      # a field with a singularity is conservative on its domain when it has
      # a potential there: grad(1/r) is, the vortex is not
      return true if symmetric?(f, xs) && global_potential(f, xs)
      regular_on!(f, xs, [], "conservative?")
    end

    def symmetric?(f, xs)
      (0...f.size).to_a.combination(2).all? { |i, j| Scalar.zero?((f[i].diff(xs[j]) - f[j].diff(xs[i])).simplify) }
    end

    def regular?(f, xs)
      regular_on!(f, xs, [], "conservative?")
      true
    rescue NotImplementedError, RCAS::Unsupported
      false
    end

    # The potential f with gradient f = field, up to a constant: integrate
    # the first component, then correct it with what the next components
    # still miss. Raises when the field has no potential. A potential found
    # is its own proof, whatever the topology of the domain - checked by
    # differentiating, and by asking that it be singular only where the
    # field is: (2x, 2y)/(x**2 + y**2) has log(x**2 + y**2) (refused as
    # singular before: fourth review), while the vortex's -atan(x/y) breaks
    # on the line y = 0, where the field is smooth.
    def potential(field, vars = nil)
      f = components(field, "potential", [2, 3])
      xs = coordinates(field, vars, f.size)
      raise ArgumentError, "potential: (#{f.join(', ')}) is not conservative" unless symmetric?(f, xs)
      return construct_potential(f, xs) if regular?(f, xs)
      global_potential(f, xs) or regular_on!(f, xs, [], "potential")
    end

    def construct_potential(f, xs)
      f.each_with_index.reduce(Num.new(0)) do |found, (component, i)|
        missing = (component - found.diff(xs[i])).simplify
        antiderivative = Integrate.integrate(missing, xs[i])
        raise ArgumentError, "potential: cannot integrate #{missing} with respect to #{xs[i]}" if antiderivative.is_a?(Integral)
        (found + antiderivative).simplify
      end
    end

    # A potential of a singular field that is defined wherever the field
    # is, with the field as its gradient; nil otherwise.
    def global_potential(f, xs)
      phi = construct_potential(f, xs)
      gradient = xs.each_with_index.all? { |x, i| Scalar.zero?((phi.diff(x) - f[i]).simplify) }
      gradient && singular_within?(phi, f, xs) ? phi : nil
    rescue ArgumentError
      nil
    end

    # Every place the potential may break - a denominator, the argument of
    # a log, a radicand - is a zero of the field's denominators: each of its
    # irreducible factors is one of theirs.
    def singular_within?(phi, f, xs)
      field_factors = f.flat_map { |c| xs.flat_map { |x| Analysis.denominators(Expression.lift(c), x) } }
                       .flat_map { |d| irreducible_factors(d, xs) }.uniq
      breaks = xs.flat_map { |x| Analysis.denominators(phi, x) } +
               phi.each_node.select { |n| n.is_a?(Fn) && n.name == :log }.map { |n| n.args.first } +
               phi.each_node.select { |n| n.is_a?(Pow) && n.exponent.is_a?(Num) && !n.exponent.value.is_a?(Integer) }.map(&:base) +
               phi.each_node.select { |n| n.is_a?(Fn) && !%i[log exp sin cos].include?(n.name) }.flat_map(&:args)
      breaks.uniq.all? do |b|
        next true if b.variables.empty?
        irreducible_factors(b, xs).all? { |factor| field_factors.any? { |g| Scalar.zero?((factor - g).simplify) || Scalar.zero?((factor + g).simplify) } }
      end
    end

    def irreducible_factors(d, xs)
      d = Expression.lift(d)
      d = d.base while d.is_a?(Pow) && d.exponent.is_a?(Num) && d.exponent.value.positive? # (x**2 + y**2)**(3/2)
      numerator = Fraction.as_fraction(d, xs.map(&:name))
      return [Expression.lift(d)] if numerator.nil? || !numerator.last.constant?
      Factor.factor(numerator.first).factors.map { |g, _| g.to_expr }.reject { |g| g.variables.empty? }
    rescue StandardError, NotImplementedError, RCAS::Unsupported => rescued
      RCAS.guard!(rescued, refused: true) if rescued.is_a?(StandardError)
      [Expression.lift(d)]
    end
  end
end
