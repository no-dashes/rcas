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
      e = assert_raises(NotImplementedError) { RCAS.real_domain(f, x) }
      assert_match(/real_domain/, e.message)
    end
    assert_equal "(-oo, 0) ∪ (0, oo)", RCAS.real_domain(1 / x, x).to_s
  end

end
