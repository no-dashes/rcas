# frozen_string_literal: true

require_relative "test_helper"

class AnalysisTest < Minitest::Test
  X = RCAS::Var.new(:x)
  Y = RCAS::Var.new(:y)

  def test_curve_sketching
    assert_equal [[-1, 2, :maximum], [1, -2, :minimum]], RCAS.extrema(X**3 - 3 * X, :x).map { |p, v, k| [p.to_s.to_i, v.to_s.to_i, k] }
    assert_equal ["0"], RCAS.inflections(X**3 - 3 * X, :x).map(&:to_s)
    assert_equal ["0"], RCAS.critical_points(X**2, :x).map(&:to_s)
    assert_equal [["-pi/2", :minimum], ["pi/2", :maximum]], RCAS.extrema(RCAS.sin(X), :x).map { |p, _, k| [p.to_s, k] }
    assert_empty RCAS.extrema(RCAS.exp(X), :x), "a function without critical points"
    assert_equal ["0"], RCAS.extrema(X**4, :x).map { |p, _, _| p.to_s }
    assert_equal :minimum, RCAS.extrema(X**4, :x).first.last, "the sign of the first derivative decides when the second vanishes"
    assert_equal ["0"], RCAS.extrema(X**3, :x).map { |p, _, k| k == :saddle ? p.to_s : "?" }
  end

  def test_tangents_and_asymptotes
    assert_equal "-1 + 2*x", RCAS.tangent(X**2, :x, 1).to_s
    assert_equal "3/2 - x/2", RCAS.normal(X**2, :x, 1).to_s
    assert_raises(ArgumentError) { RCAS.normal(X**2, :x, 0) }
    a = RCAS.asymptotes((X**2 + 1) / X, :x)
    assert_equal ["0"], a[:vertical].map(&:to_s)
    assert_empty a[:horizontal]
    assert_equal ["x"], a[:oblique].map(&:to_s)
    b = RCAS.asymptotes((2 * X + 1) / (X - 1), :x)
    assert_equal ["1"], b[:vertical].map(&:to_s)
    assert_equal ["2"], b[:horizontal].map(&:to_s)
    assert_empty RCAS.asymptotes(X**2, :x)[:vertical]
  end

  def test_where_a_function_is_defined
    assert_equal "[1, oo)", RCAS.real_domain(RCAS.sqrt(X - 1), :x).to_s
    assert_equal "(0, oo)", RCAS.real_domain(RCAS.log(X), :x).to_s
    assert_equal "(-oo, 2) ∪ (2, oo)", RCAS.real_domain(1 / (X - 2), :x).to_s
    assert_equal RCAS::RealSet.reals, RCAS.real_domain(X**2 + 1, :x)
  end

  # asin and acos are bounded both ways, and the domain said nothing about
  # them: real_domain(asin(x), x) was the whole line. Past the interval
  # they do have a value, off the real line, which is why the condition
  # has to be named rather than left to the evaluation to notice.
  def test_the_inverse_functions_are_bounded_both_ways
    assert_equal "[-1, 1]", RCAS.real_domain(RCAS.asin(X), :x).to_s
    assert_equal "[-1, 1]", RCAS.real_domain(RCAS.acos(X), :x).to_s
    assert_equal "[-1/2, 1/2]", RCAS.real_domain(RCAS.asin(2 * X), :x).to_s
    assert_equal "[2, 4]", RCAS.real_domain(RCAS.acos(X - 3), :x).to_s
    assert_equal "[-1, 0) ∪ (0, 1]", RCAS.real_domain(RCAS.asin(X) / X, :x).to_s
    assert_equal RCAS::RealSet.reals, RCAS.real_domain(RCAS.atan(X), :x), "atan is not one of them"
    assert_equal "[-1, 1]", RCAS.discuss(RCAS.asin(X), :x).domain.to_s
    ops = RCAS::Analysis.domain_conditions(RCAS.asin(X), RCAS::Var.new(:x)).map(&:op)
    assert_equal %i[>= <=], ops
  end

  def test_several_variables
    assert_equal "(2*x*y, x**2)", RCAS.gradient(X**2 * Y, [:x, :y]).to_s
    assert_equal [["2*y", "2*x"], ["2*x", "0"]], RCAS.hessian(X**2 * Y, [:x, :y]).entries.map { |r| r.map(&:to_s) }
    assert_equal [["y", "x"], ["1", "1"]], RCAS.jacobian([X * Y, X + Y], [:x, :y]).entries.map { |r| r.map(&:to_s) }
    assert_equal "2*x + 2*y", RCAS.divergence([X**2, Y**2], [:x, :y]).to_s
    assert_equal "4", RCAS.laplacian(X**2 + Y**2, [:x, :y]).to_s
    assert_equal "(0, 0, -2)", RCAS.curl([Y, -X, 0], %i[x y z]).to_s
    assert_equal "-4*x**2", RCAS.hessian(X**2 * Y, [:x, :y]).det.to_s, "the second derivative test in two variables"
    assert_raises(ArgumentError) { RCAS.curl([Y, -X], %i[x y]) }
  end

  def test_lagrange_multipliers
    points = RCAS.lagrange(X + Y, [X**2 + Y**2 - 1], [:x, :y])
    assert_equal 2, points.size
    values = points.map { |p| (p[RCAS::Var.new(:x)] + p[RCAS::Var.new(:y)]).simplify.evalf }
    assert_in_delta Math.sqrt(2), values.max, 1e-12
    assert_in_delta(-Math.sqrt(2), values.min, 1e-12)
    # the box with the largest area for a given perimeter is the square
    corner = RCAS.lagrange(X * Y, [2 * X + 2 * Y - 4], [:x, :y])
    assert_equal ["1"], corner.map { |p| p[RCAS::Var.new(:x)].to_s }
  end

  def test_iterated_integrals
    assert_equal 1, RCAS.integrate(X * Y, x: 0..1, y: 0..2)
    assert_equal Rational(1, 4), RCAS.integrate(X * Y, x: 0..1, y: 0..1)
    assert_equal 2, RCAS.integrate(1, x: 0..1, y: 0..2)
  end
  def test_arclength
    assert_equal "pi", RCAS.arclength([RCAS.cos(:t), RCAS.sin(:t)], t: 0..RCAS::PI).to_s, "half a unit circle"
    assert_in_delta 1.4789428575445973, RCAS.arclength(:x**2, x: 0..1).evalf, 1e-9
    assert_equal 5, RCAS.arclength(3 * :x / 4, x: 0..4), "a 3-4-5 triangle"
    assert_equal "3**(1/2)", RCAS.arclength([:t, :t, :t], t: 0..1).to_s, "a space curve"
    assert_raises(ArgumentError) { RCAS.arclength([:t, :t, :t, :t], t: 0..1) }
  end

  def test_solids_of_revolution
    assert_equal "pi/2", RCAS.revolution_volume(RCAS.sqrt(:x), x: 0..1).to_s
    assert_equal "pi/3", RCAS.revolution_volume(:x, x: 0..1).to_s, "a cone"
    assert_equal "pi/2", RCAS.revolution_volume(:x**2, x: 0..1, axis: :y).to_s, "cylindrical shells"
    assert_in_delta 4 * Math::PI / 3, RCAS.revolution_volume(RCAS.sqrt(1 - :x**2), x: -1..1).evalf, 1e-12, "the unit ball"
    assert_in_delta 4 * Math::PI, RCAS.revolution_surface(RCAS.sqrt(1 - :x**2), x: -1..1).evalf, 1e-9, "its surface"
  end
  # A curve discussion is about a real function: the roots of 3*x**2 + 1
  # are not critical points of the graph of x**3 + x.
  def test_only_real_points_are_reported
    x = RCAS::Var.new(:x)
    assert_empty RCAS.critical_points(x**3 + x, x)
    assert_empty RCAS.extrema(x**3 + x, x)
    assert_equal ["0"], RCAS.inflections(RCAS.tan(x), x).map(&:to_s)
    assert_equal ["-1", "1"], RCAS.critical_points(x**3 - 3 * x, x).map(&:to_s), "and nothing real is lost"
    assert_equal ["0"], RCAS.inflections(x**3 - 3 * x, x).map(&:to_s)
  end

  # A condition rcas cannot solve is not an empty one: dropping it would
  # claim the function is defined where nobody looked.
  def test_a_domain_condition_that_cannot_be_solved_says_so
    x = RCAS::Var.new(:x)
    [RCAS.log(RCAS.sin(x)), RCAS.tan(x)].each do |f|
      e = assert_raises(NotImplementedError, RCAS::Unsupported) { RCAS.real_domain(f, x) }
      assert_match(/real_domain/, e.message)
    end
    assert_equal "(-oo, 0) ∪ (0, oo)", RCAS.real_domain(1 / x, x).to_s
  end

  # An inflection is a *change* of sign of f''. Where the third derivative
  # vanishes too, the sign chart of f'' has to decide, and accepting its
  # "no change" answer turned the test round: x**4 was reported as having
  # an inflection at 0 and x**5 as having none (22 Sept 2026, a review).
  def test_an_inflection_needs_a_change_of_curvature
    x = RCAS::Var.new(:x)
    assert_empty RCAS.inflections(x**4, x), "f'' = 12*x**2 is positive on both sides"
    assert_equal ["0"], RCAS.inflections(x**5, x).map(&:to_s), "f'' = 20*x**3 changes sign"
    assert_empty RCAS.inflections(x**6, x)
    assert_equal ["0"], RCAS.inflections(x**7, x).map(&:to_s)
    assert_empty RCAS.inflections(x**2, x)
    assert_equal ["0"], RCAS.inflections(x**3, x).map(&:to_s), "a non-zero third derivative settles it at once"
  end

  # The points a curve discussion reports, read against the shapes they
  # belong to.
  def test_inflections_of_the_usual_curves
    x = RCAS::Var.new(:x)
    { x**4 => [], x**5 => ["0"], RCAS.sin(x) => ["0", "pi"],
      x**4 - x**2 => ["-6**(1/2)/6", "6**(1/2)/6"],
      RCAS.exp(-x**2) => ["-2**(1/2)/2", "2**(1/2)/2"],
      x**3 - 3 * x => ["0"] }.each do |f, points|
      assert_equal points, RCAS.inflections(f, x).map(&:to_s), "inflections of #{f}"
    end
  end

  # A radius is a distance to the axis, so it is never negative: the
  # cylinder of radius and length one has surface 2*pi whichever sign the
  # function carries, and -2*pi was the answer for f = -1 (22 Sept 2026,
  # from a review).
  def test_a_radius_of_revolution_is_a_distance
    x = RCAS::Var.new(:x)
    assert_equal "2*pi", RCAS.revolution_surface(-1, x: 0..1).to_s
    assert_equal "2*pi", RCAS.revolution_surface(1, x: 0..1).to_s
    assert_equal "pi", RCAS.revolution_volume(1, x: -1..0, axis: :y).to_s
    assert_equal "pi", RCAS.revolution_volume(1, x: 0..1, axis: :y).to_s
    assert_equal "pi", RCAS.revolution_volume(-1, x: 0..1, axis: :y).to_s
    assert_equal "pi", RCAS.revolution_volume(-1, x: 0..1).to_s, "about the x-axis f**2 was already a square"
    # a function and its negative sweep the same surface
    assert_equal RCAS.revolution_surface(x, x: 0..1).to_s, RCAS.revolution_surface(-x, x: 0..1).to_s
  end

  # Shells about the y-axis stand on one side of it; over a range that
  # crosses the axis the two halves sweep the same shells, and abs(x) would
  # count them twice. Splitting the range is the reader's call.
  def test_shells_refuse_a_range_across_the_axis
    e = assert_raises(ArgumentError) { RCAS.revolution_volume(1, x: -1..1, axis: :y) }
    assert_match(/crosses the axis/, e.message)
    assert_raises(ArgumentError) { RCAS.revolution_surface(1, x: -1..1, axis: :y) }
    assert_equal "pi", RCAS.revolution_volume(1, x: -1..0, axis: :y).to_s, "the halves on their own are fine"
    assert_equal "pi", RCAS.revolution_volume(1, x: 0..1, axis: :y).to_s
  end

  # The known volumes and areas are unchanged.
  def test_the_classical_solids_are_unchanged
    x = RCAS::Var.new(:x)
    assert_equal "pi/5", RCAS.revolution_volume(x**2, x: 0..1).to_s
    assert_equal "pi/2", RCAS.revolution_volume(x**2, x: 0..1, axis: :y).to_s
    assert_equal "4*pi/3", RCAS.revolution_volume(RCAS.sqrt(1 - x**2), x: -1..1).to_s, "the unit ball"
    assert_in_delta 4 * Math::PI, RCAS.revolution_surface(RCAS.sqrt(1 - x**2), x: -1..1).evalf, 1e-9
    # 2*pi*int_0^1 x**2*sqrt(1 + 4*x**2) dx, by Simpson to nine digits
    assert_in_delta 3.809729705, RCAS.revolution_surface(x**2, x: 0..1).evalf, 1e-8
  end

  # A condition on a *constant* argument is a condition too: log(-1) + x is
  # real nowhere, and skipping it because the argument does not move with x
  # claimed the whole line (22 Sept 2026, from a review).
  def test_a_constant_domain_condition_is_not_skipped
    x = RCAS::Var.new(:x)
    assert_equal RCAS::RealSet.empty, RCAS.real_domain(RCAS.log(-1) + x, x)
    assert_equal RCAS::RealSet.empty, RCAS.real_domain(x * RCAS.log(-2), x)
    assert_equal RCAS::RealSet.reals, RCAS.real_domain(RCAS.log(2) + x, x), "a condition that holds costs nothing"
    assert_equal "(0, oo)", RCAS.real_domain(RCAS.log(x) + RCAS.log(3), x).to_s
    assert_equal "[0, oo)", RCAS.real_domain(RCAS.sqrt(x) + RCAS.sqrt(2), x).to_s
    assert_equal "(-oo, 0) ∪ (0, oo)", RCAS.real_domain(1 / x + RCAS.log(3), x).to_s
  end

  # R1. The sign of the radius must be *proved*, not sampled: five samples
  # at 1/6..5/6 all found x - 1/10 positive on 0..1 and dropped the abs,
  # which understated the surface by 2.4% (22 Sept 2026, the second review).
  # A line is enough to show it; no high frequency is needed.
  def test_a_radius_keeps_its_absolute_value_where_the_sign_is_not_proved
    x = RCAS::Var.new(:x)
    f = x - Rational(1, 10)
    # 2*pi*sqrt(2)*int_0^1 |x - 1/10| dx = 2*pi*sqrt(2)*(1/200 + 81/200)
    assert_equal "41*2**(1/2)*pi/50", RCAS.revolution_surface(f, x: 0..1).to_s
    # 2*pi*int_0^1 x*|x - 1/10| dx = 2*pi*(1/6000 + 1701/6000)
    assert_equal "851*pi/1500", RCAS.revolution_volume(f, x: 0..1, axis: :y).to_s
    assert_in_delta 41 * Math.sqrt(2) * Math::PI / 50, RCAS.revolution_surface(f, x: 0..1).evalf, 1e-12
    assert_in_delta 851 * Math::PI / 1500, RCAS.revolution_volume(f, x: 0..1, axis: :y).evalf, 1e-12
  end

  # The decision itself, in both directions: a zero strictly inside the
  # range means there is no single sign, a zero at an end does not, and a
  # zero rcas cannot name leaves the question open.
  def test_the_sign_on_an_interval_is_decided_by_the_zeros
    x = RCAS::Var.new(:x)
    sign = ->(u, from, to) { RCAS::Analysis.sign_on_interval(u, x, RCAS::Num.new(from), RCAS::Num.new(to)) }
    assert_nil sign.call(x - Rational(1, 10), 0, 1), "a zero strictly inside"
    assert_nil sign.call(x, -1, 1)
    assert_equal :positive, sign.call(x, 0, 1), "a zero at the end is no obstacle"
    assert_equal :negative, sign.call(x, -1, 0)
    assert_equal :positive, sign.call(x - Rational(1, 10), Rational(1, 2), 1)
    assert_equal :negative, sign.call(x - Rational(1, 10), -1, 0)
    assert_equal :positive, sign.call(RCAS.sqrt(1 - x**2), -1, 1), "zeros at both ends"
    assert_equal :negative, sign.call(RCAS::Num.new(-1), 0, 1), "a constant"
    assert_equal :positive, sign.call(x**2 + 1, -1, 1), "no real zero at all"
    assert_nil sign.call(RCAS::Var.new(:a) * x, 0, 1), "a parameter in it"
  end

  # The same decision under the length element, which removes a square root
  # the same way. With more than one parameter the box is still sampled,
  # which the manual lists as a limit.
  def test_the_length_element_proves_its_sign_too
    v = RCAS::Var.new(:v)
    norm = ->(f, from, to) { RCAS::VectorCalculus.norm(f, [[v, from, to]]).to_s }
    assert_equal "abs(-1/10 + v)", norm.call([v - Rational(1, 10), 0], RCAS::Num.new(0), RCAS::Num.new(1))
    assert_equal "-1/10 + v", norm.call([v - Rational(1, 10), 0], RCAS::Num.new(Rational(1, 2)), RCAS::Num.new(1))
    assert_equal "sin(v)", norm.call([RCAS.sin(v), 0], RCAS::Num.new(0), RCAS::PI)
    assert_equal "abs(sin(v))", norm.call([RCAS.sin(v), 0], RCAS::Num.new(0), 2 * RCAS::PI)
  end

  # R5. A zero of f'' is an inflection exactly when f'' vanishes there to an
  # odd order. The old test asked whether f''' was numerically above 10**-12
  # and otherwise sampled at a fixed 10**-4: with a second zero at 10**-5
  # both readings were wrong (22 Sept 2026, the second review).
  def test_inflections_with_a_second_zero_next_door
    x = RCAS::Var.new(:x)
    a = Rational(1, 100_000)
    # f'' = x**2*(x - a): even order at 0, odd at a
    assert_equal ["1/100000"], RCAS.inflections(x**5 / 20 - a * x**4 / 12, x).map(&:to_s)
    # f'' = x**3*(x - a): odd at both
    assert_equal ["0", "1/100000"], RCAS.inflections(x**6 / 30 - a * x**5 / 20, x).map(&:to_s)
    # f'''(a) = a**3 = 10**-15 is exactly non-zero, and below the old threshold
    refute RCAS::Scalar.zero?((x**6 / 30 - a * x**5 / 20).diff(x, 3).subs(x => RCAS::Num.new(a)).simplify)
  end

  # The order itself, which is what the test now reads.
  def test_the_order_to_which_a_derivative_vanishes
    x = RCAS::Var.new(:x)
    order = ->(g, at) { RCAS::Analysis.vanishing_order(RCAS::Expression.lift(g), x, RCAS::Num.new(at)) }
    assert_equal 2, order.call(x**2, 0)
    assert_equal 3, order.call(x**3, 0)
    assert_equal 1, order.call(x - 1, 1)
    assert_equal 2, order.call(x**2 * (x - Rational(1, 100_000)), 0)
    assert_equal 3, order.call(x**3 * (x - Rational(1, 100_000)), 0)
    assert_equal 1, order.call(x**3 * (x - Rational(1, 100_000)), Rational(1, 100_000))
    assert_equal 1, order.call(RCAS.sin(x), 0)
  end

  # An undecided candidate is not a proven absence: the answer says so
  # instead of dropping it, and `discuss` turns that into "not determined"
  # rather than into "no inflections" (22 Sept 2026, the second review
  # asked for the three cases to be told apart).
  def test_an_undecided_curvature_is_refused_not_denied
    x = RCAS::Var.new(:x)
    c = RCAS::Var.new(:c)
    e = assert_raises(NotImplementedError, RCAS::Unsupported) { RCAS::Analysis.inflection_at?(RCAS::Num.new(0), x, c, []) }
    assert_match(/not decided/, e.message)
    assert_nil RCAS::Analysis.vanishing_order(RCAS::Num.new(0), x, c)
    assert_nil RCAS::Analysis.sign_change(RCAS::Num.new(0), x, c)
    # the decided cases still answer, and discuss reports them as before
    assert_empty RCAS.discuss(x**4, x).inflections
    assert_equal [[0, 0]], RCAS.discuss(x**5, x).inflections.map { |p, v| [p.to_s.to_i, v.to_s.to_i] }
  end

  # R6. A condition about a parameter is decided when the assumptions
  # settle it, and refused when they do not: with assume(a < 0) the
  # logarithm has no real value anywhere, and the answer was the whole line
  # (22 Sept 2026, the second review, correcting the first round's answer).
  def test_a_parameter_condition_is_decided_or_refused
    x = RCAS::Var.new(:x)
    a = RCAS::Var.new(:a)
    RCAS.assume(a < 0) do
      assert_equal RCAS::RealSet.empty, RCAS.real_domain(RCAS.log(a) + x, x)
      assert_equal RCAS::RealSet.empty, RCAS.real_domain(RCAS.log(a) + RCAS.log(x), x)
    end
    RCAS.assume(a > 0) do
      assert_equal RCAS::RealSet.reals, RCAS.real_domain(RCAS.log(a) + x, x)
      assert_equal "(0, oo)", RCAS.real_domain(RCAS.log(a) + RCAS.log(x), x).to_s
    end
    e = assert_raises(NotImplementedError, RCAS::Unsupported) { RCAS.real_domain(RCAS.log(a) + x, x) }
    assert_match(/depends on a/, e.message)
    assert_raises(NotImplementedError, RCAS::Unsupported) { RCAS.real_domain(RCAS.sqrt(a) + x, x) }
  end

  # An expression carrying i is real only where its imaginary part vanishes.
  def test_where_a_complex_expression_is_real
    x = RCAS::Var.new(:x)
    assert_equal "{0}", RCAS.real_domain(RCAS::I * x, x).to_s
    assert_equal "{0}", RCAS.real_domain(RCAS.sqrt(-1) * x, x).to_s
    assert_equal "{-1/2}", RCAS.real_domain(2 * RCAS::I * x + RCAS::I, x).to_s
    assert_equal "{0}", RCAS.real_domain(RCAS::I * x**2, x).to_s
    assert_equal RCAS::RealSet.empty, RCAS.real_domain(x + RCAS::I, x), "a constant imaginary part"
    assert_equal RCAS::RealSet.reals, RCAS.real_domain(RCAS::I * RCAS::I * x, x), "i**2 is real"
    assert_equal RCAS::RealSet.reals, RCAS.real_domain(x**2 + 1, x), "and nothing without an i pays for this"
  end
end
