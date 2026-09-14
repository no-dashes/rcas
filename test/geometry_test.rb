# frozen_string_literal: true

require_relative "test_helper"

class GeometryTest < Minitest::Test
  A = RCAS.point(0, 0)
  B = RCAS.point(4, 0)
  C = RCAS.point(0, 3)

  def test_the_three_four_five_triangle
    assert_equal "4", RCAS.distance(A, B).to_s
    assert_equal "3", RCAS.distance(A, C).to_s
    assert_equal "5", RCAS.distance(B, C).to_s
    assert_equal "6", RCAS.area(A, B, C).to_s
    assert_equal "12", RCAS.perimeter(A, B, C).to_s
    assert_equal "pi/2", RCAS.angle(B, A, C).to_s, "the right angle is exact"
    assert_equal "acos(4/5)", RCAS.angle(A, B, C).to_s
    assert_in_delta Math.acos(0.8), RCAS.angle(A, B, C).evalf, 1e-12
    refute RCAS.collinear?(A, B, C)
    assert RCAS.collinear?(A, B, RCAS.point(7, 0))
    assert_equal "(4/3, 1)", RCAS.centroid(A, B, C).to_s
    assert_equal "circle((2, 3/2), 5/2)", RCAS.circumcircle(A, B, C).to_s, "the circumcentre of a right triangle is the midpoint of the hypotenuse"
  end

  def test_lines
    assert_equal "y = 0", RCAS.line(A, B).to_s
    assert_equal "2*x - y = 0", RCAS.line(A, slope: 2).to_s
    assert_equal "2", RCAS.line(A, slope: 2).slope.to_s
    assert_nil RCAS.line(A, C).slope, "a vertical line has no slope"
    assert RCAS.line(A, B).contains?(RCAS.point(7, 0))
    assert RCAS.line(A, B).parallel?(RCAS.line(C, RCAS.point(4, 3)))
    assert RCAS.line(A, B).perpendicular?(RCAS.line(A, C))
    assert_equal "3", RCAS.distance(C, RCAS.line(A, B)).to_s
    assert_equal "3", RCAS.distance(RCAS.line(A, B), C).to_s, "either order"
    assert_equal "-2 + x = 0", RCAS.perpendicular_bisector(A, B).to_s
    assert_equal "(2, 0)", RCAS.midpoint(A, B).to_s
    assert_equal "-12 + 3*x + 4*y = 0", RCAS.parallel_through(RCAS.line(B, C), RCAS.point(4, 0)).to_s
    assert_equal RCAS.line(B, C), RCAS.parallel_through(RCAS.line(B, C), B), "through a point of the line it is the line itself"
    assert RCAS.perpendicular_through(RCAS.line(A, B), C).perpendicular?(RCAS.line(A, B))
  end

  def test_intersections
    assert_equal "(0, 0)", RCAS.intersect(RCAS.line(A, B), RCAS.line(A, C)).to_s
    assert_nil RCAS.intersect(RCAS.line(A, B), RCAS.line(C, RCAS.point(4, 3))), "parallel lines do not meet"
    points = RCAS.intersect(RCAS.line(A, C), RCAS.circle(A, 2))
    assert_equal ["(0, 2)", "(0, -2)"], points.map(&:to_s)
    assert_empty RCAS.intersect(RCAS.line(RCAS.point(0, 5), RCAS.point(1, 5)), RCAS.circle(A, 2)), "a line that misses"
    assert_equal 1, RCAS.intersect(RCAS.line(RCAS.point(0, 2), RCAS.point(1, 2)), RCAS.circle(A, 2)).size, "a tangent touches once"
    meeting = RCAS.intersect(RCAS.circle(A, 5), RCAS.circle(B, 5))
    assert_equal ["(2, 21**(1/2))", "(2, -21**(1/2))"], meeting.map(&:to_s)
    assert_nil RCAS.intersect(RCAS.circle(A, 1), RCAS.circle(A, 2)), "concentric circles"
  end

  def test_circles_and_symbolic_coordinates
    k = RCAS.circle(RCAS.point(1, 2), 3)
    assert_equal "(-1 + x)**2 + (-2 + y)**2 = 9", k.equation.to_s
    assert_equal "9*pi", k.area.to_s
    assert_equal "6*pi", k.circumference.to_s
    assert k.contains?(RCAS.point(4, 2))
    refute k.contains?(A)
    p = RCAS.point(:a, :b)
    assert_equal "(a**2 + b**2)**(1/2)", RCAS.distance(A, p).to_s
    assert_equal "(a/2, b/2)", RCAS.midpoint(A, p).to_s
    assert_raises(RCAS::Geometry::Error) { RCAS.line(A, A) }
    assert_raises(RCAS::Geometry::Error) { RCAS.circumcircle(A, B, RCAS.point(7, 0)) }
  end
end
