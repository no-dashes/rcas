# frozen_string_literal: true

require_relative "test_helper"

class VectorCalculusTest < Minitest::Test
  X = RCAS::Var.new(:x)
  Y = RCAS::Var.new(:y)
  Z = RCAS::Var.new(:z)
  T = RCAS::Var.new(:t)
  U = RCAS::Var.new(:u)
  V = RCAS::Var.new(:v)
  A = RCAS::Var.new(:a)
  CIRCLE = [RCAS.cos(T), RCAS.sin(T)].freeze
  SPHERE = [RCAS.sin(V) * RCAS.cos(U), RCAS.sin(V) * RCAS.sin(U), RCAS.cos(V)].freeze

  def pi = RCAS::PI

  def test_scalar_line_integrals
    assert_equal "2*pi", RCAS.line_integral(1, CIRCLE, t: 0..2 * pi).to_s, "the length of the unit circle"
    assert_equal "2*pi", RCAS.line_integral(X**2 + Y**2, CIRCLE, t: 0..2 * pi).to_s
    assert_equal "3**(1/2)/2", RCAS.line_integral(X, [T, T, T], t: 0..1).to_s, "a wire whose density grows along it"
    helix = [RCAS.cos(T), RCAS.sin(T), T]
    assert_equal "2*2**(1/2)*pi**2", RCAS.line_integral(Z, helix, t: 0..2 * pi).to_s
    assert_equal RCAS.arclength(CIRCLE, t: 0..pi).to_s, RCAS.line_integral(1, CIRCLE, t: 0..pi).to_s, "f = 1 is the arc length"
    assert_equal "2*2**(1/2)*pi", RCAS.arclength(helix, t: 0..2 * pi).to_s, "arclength takes a space curve too"
  end

  def test_the_work_a_field_does
    assert_equal "2*pi", RCAS.line_integral([-Y, X], CIRCLE, t: 0..2 * pi).to_s
    assert_equal "2*pi**2 - 2*pi", RCAS.line_integral([Y, -X, Z], [RCAS.cos(T), RCAS.sin(T), T], t: 0..2 * pi).to_s
    # a gradient field does the same work along any path between the ends
    field = [2 * X * Y, X**2]
    straight = RCAS.line_integral(field, [T, T], t: 0..1)
    curved = RCAS.line_integral(field, [T, T**2], t: 0..1)
    assert_equal "1", straight.to_s
    assert_equal straight.to_s, curved.to_s, "a conservative field is path independent"
    assert_equal "1", RCAS.potential(field).subs(X => 1, Y => 1).simplify.to_s, "and the work is the difference of potentials"
  end

  def test_coordinates_are_x_y_z_unless_told_otherwise
    assert_equal "2*pi", RCAS.line_integral([-V, U], CIRCLE, vars: [U, V], t: 0..2 * pi).to_s
    assert_equal "2*pi*a", RCAS.line_integral([-A * Y, A * X], CIRCLE, t: 0..2 * pi).to_s, "a parameter is not a coordinate"
  end

  def test_flux_across_a_plane_curve
    assert_equal "2*pi", RCAS.flux([X, Y], CIRCLE, t: 0..2 * pi).to_s, "the outward flux of the radial field"
    assert_equal "0", RCAS.flux([-Y, X], CIRCLE, t: 0..2 * pi).to_s, "a rotation crosses the circle nowhere"
  end

  def test_the_area_a_closed_curve_encloses
    assert_equal "pi", RCAS.enclosed_area(CIRCLE, t: 0..2 * pi).to_s
    assert_equal "-pi", RCAS.enclosed_area([RCAS.cos(T), -RCAS.sin(T)], t: 0..2 * pi).to_s, "clockwise is negative"
    assert_equal "6*pi", RCAS.enclosed_area([3 * RCAS.cos(T), 2 * RCAS.sin(T)], t: 0..2 * pi).to_s, "an ellipse"
    assert_equal "3*pi/8", RCAS.enclosed_area([RCAS.cos(T)**3, RCAS.sin(T)**3], t: 0..2 * pi).to_s, "the astroid"
  end

  def test_surface_integrals
    assert_equal "3**(1/2)", RCAS.surface_integral(1, [U, V, U + V], u: 0..1, v: 0..1).to_s, "a slanted unit square"
    assert_equal "6*pi", RCAS.surface_integral(1, [RCAS.cos(U), RCAS.sin(U), V], u: 0..2 * pi, v: 0..3).to_s, "a cylinder"
    assert_equal "2**(1/2)*pi", RCAS.surface_integral(1, [V * RCAS.cos(U), V * RCAS.sin(U), V], u: 0..2 * pi, v: 0..1).to_s, "a cone"
    sphere = SPHERE.map { |c| A * c }
    assert_equal "4*pi*a**2", RCAS.surface_integral(1, sphere, v: 0..pi, u: 0..2 * pi).to_s, "the sphere of radius a"
    assert_equal "4*pi/3", RCAS.surface_integral(Z**2, SPHERE, v: 0..pi, u: 0..2 * pi).to_s
  end

  def test_the_parametrization_orients_the_surface
    assert_equal "4*pi", RCAS.flux([X, Y, Z], SPHERE, v: 0..pi, u: 0..2 * pi).to_s, "r_v x r_u points outwards"
    assert_equal "-4*pi", RCAS.flux([X, Y, Z], SPHERE, u: 0..2 * pi, v: 0..pi).to_s, "the other order turns the normal round"
  end

  def test_green
    assert_equal "2", RCAS.green([-Y, X], x: 0..1, y: 0..1).to_s
    assert_equal "1/3", RCAS.green([Y**2, X**2], y: 0..X, x: 0..1).to_s, "the inner bound may depend on the outer variable"
    assert_equal "0", RCAS.green([X, Y], x: 0..1, y: 0..1).to_s, "a gradient field circulates nowhere"
  end

  # The theorem itself: the double integral equals the circulation around the
  # four sides of the square, each run anticlockwise.
  def test_green_agrees_with_the_boundary
    field = [X * Y, X + Y]
    sides = [[T, 0], [1, T], [1 - T, 1], [0, 1 - T]]
    circulation = sides.sum { |c| RCAS.line_integral(field, c, t: 0..1) }
    assert_equal RCAS.green(field, x: 0..1, y: 0..1).to_s, circulation.simplify.to_s
  end

  def test_stokes_agrees_with_the_boundary
    disc = [U * RCAS.cos(V), U * RCAS.sin(V), 0]
    [[-Y, X, 0], [Z, X, Y], [X * Y, Y * Z, Z * X]].each do |field|
      flux = RCAS.stokes(field, disc, u: 0..1, v: 0..2 * pi)
      circulation = RCAS.line_integral(field, [RCAS.cos(T), RCAS.sin(T), 0], t: 0..2 * pi)
      assert_equal circulation.simplify.to_s, flux.to_s, "curl through the disc = circulation around its edge"
    end
    assert_equal RCAS.stokes([-Y, X, 0], disc, u: 0..1, v: 0..2 * pi).to_s,
                 RCAS.flux(RCAS.curl([-Y, X, 0], [X, Y, Z]), disc, u: 0..1, v: 0..2 * pi).to_s, "stokes is the flux of the curl"
  end

  # The flux out of the unit cube through its six faces, against the triple
  # integral of the divergence over it.
  def test_divergence_theorem_agrees_with_the_flux
    field = [X**2, Y, Z]
    faces = [[[1, U, V], false], [[0, U, V], true], [[U, 1, V], true], [[U, 0, V], false],
             [[U, V, 1], false], [[U, V, 0], true]]
    total = faces.sum do |(patch, reversed)|
      value = RCAS.flux(field, patch, u: 0..1, v: 0..1)
      reversed ? -value : value
    end
    assert_equal "3", RCAS.divergence_theorem(field, x: 0..1, y: 0..1, z: 0..1).to_s
    assert_equal "3", total.simplify.to_s
  end

  def test_conservative_fields_and_their_potentials
    assert RCAS.conservative?([2 * X * Y, X**2])
    refute RCAS.conservative?([-Y, X])
    assert RCAS.conservative?([Y * Z, X * Z, X * Y])
    refute RCAS.conservative?([Y, -X, 0])
    assert_equal "x**2*y", RCAS.potential([2 * X * Y, X**2]).to_s
    assert_equal "x*y*z", RCAS.potential([Y * Z, X * Z, X * Y]).to_s
    assert_equal "x**2/2 + y**3/3", RCAS.potential([X, Y**2]).to_s
    potential = RCAS.potential([RCAS.exp(X) * RCAS.cos(Y), -RCAS.exp(X) * RCAS.sin(Y)])
    assert_equal "cos(y)*exp(x)", potential.to_s
    assert_equal "(cos(y)*exp(x), -(exp(x)*sin(y)))", RCAS.gradient(potential, [X, Y]).simplify.to_s, "the gradient is the field again"
    error = assert_raises(ArgumentError) { RCAS.potential([-Y, X]) }
    assert_includes error.message, "not conservative"
  end

  def test_what_it_cannot_do_stays_an_integral
    formal = RCAS.line_integral(1, [T, RCAS.exp(T**2)], t: 0..1)
    assert_kind_of RCAS::Integral, formal
    assert_in_delta 2.1276164, formal.evalf, 1e-6
    surface = RCAS.surface_integral(1, [U, V, U**2 + V**2], u: 0..1, v: 0..1)
    assert_kind_of RCAS::Integral, surface
  end

  # sqrt(u**2) is u only where u is positive; where the sign changes on the
  # parameter range the answer keeps its absolute value.
  def test_the_length_element_keeps_an_honest_sign
    element = RCAS::VectorCalculus.norm([RCAS.sin(V), 0], [[V, 0, pi]])
    assert_equal "sin(v)", element.to_s
    assert_equal "abs(sin(v))", RCAS::VectorCalculus.norm([RCAS.sin(V), 0], [[V, 0, 2 * pi]]).to_s
    assert_equal "-sin(v)", RCAS::VectorCalculus.norm([RCAS.sin(V), 0], [[V, -pi, 0]]).to_s
    assert_equal "(1 + t**2)**(1/2)", RCAS::VectorCalculus.norm([1, T], [[T, 0, 1]]).to_s, "nothing to take out"
  end

  def test_arguments_that_do_not_fit
    assert_raises(ArgumentError) { RCAS.line_integral([X, Y, Z], [RCAS.cos(T), RCAS.sin(T)], t: 0..1) }
    assert_raises(ArgumentError) { RCAS.line_integral(1, [T], t: 0..1) }
    assert_raises(ArgumentError) { RCAS.green([-Y, X], x: 0..1) }
    assert_raises(ArgumentError) { RCAS.surface_integral(1, [U, V, 0], u: 0..1) }
    assert_raises(ArgumentError) { RCAS.divergence_theorem([X, Y, Z], x: 0..1, y: 0..1) }
    assert_raises(ArgumentError) { RCAS.stokes([X, Y], [U, V, 0], u: 0..1, v: 0..1) }
  end
end
