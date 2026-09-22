# Review: linear algebra, ODEs, Laplace, vector calculus, plane geometry.
require_relative 'test_helper'
require 'rcas'

class ReviewLinearAlgebraTest < Minitest::Test
  def setup
    @x, @y, @z, @t, @s, @a, @b, @k = %i[x y z t s a b k].map { |n| RCAS::Var.new(n) }
  end
  def teardown = RCAS.forget
  def n(v) = RCAS::Num.new(v)
  def zero?(e) = RCAS::Scalar.zero?(RCAS.simplify(e))

  # Numeric value of e with the given bindings.
  def value(e, bindings) = RCAS::Expression.lift(e).subs(bindings.to_h { |k, v| [RCAS::Var.new(k), n(v)] }).evalf

  def test_the_line_through_two_points_contains_them
    # (2,2),(3,3) lie on x - y = 0; (0,1),(1,1) on y - 1 = 0.
    [[[2, 2], [3, 3]], [[0, 1], [1, 1]], [[1, 2], [3, 5]]].each do |p, q|
      l = RCAS.line(RCAS.point(*p), RCAS.point(*q))
      assert l.contains?(RCAS.point(*p)), "#{l} misses #{p}"
      assert l.contains?(RCAS.point(*q)), "#{l} misses #{q}"
    end
    # The horizontal line y = 1 touches the unit circle at (0, 1), not (0, -1).
    touch = RCAS.intersect(RCAS.line(RCAS.point(0, 1), RCAS.point(1, 1)), RCAS.circle(RCAS.point(0, 0), 1))
    assert_equal [RCAS.point(0, 1)], touch
  end

  def test_the_line_with_given_slope_contains_its_point
    # Through (1,1) with slope 2: y - 1 = 2(x - 1), i.e. 2x - y - 1 = 0.
    l = RCAS.line(RCAS.point(1, 1), slope: 2)
    assert l.contains?(RCAS.point(1, 1)), "#{l} misses (1, 1)"
    assert l.contains?(RCAS.point(2, 3)), "#{l} misses (2, 3)"
  end

  def test_the_distance_between_parallel_lines
    # x - y = 0 and x - y - 1 = 0 are 1/sqrt(2) apart.
    l = RCAS.line(RCAS.point(0, 0), RCAS.point(1, 1))
    m = RCAS.line(RCAS.point(1, 0), RCAS.point(2, 1))
    assert zero?(RCAS.distance(l, m) - RCAS.sqrt(2) / 2)
  end

  def test_a_tiny_complex_determinant_is_not_zero
    # det diag(i*exp(-100), 1) = i*exp(-100), about 3.7e-44*i, not 0.
    m = RCAS.matrix([[RCAS::I * RCAS.exp(-100), 0], [0, 1]])
    refute RCAS::Scalar.zero?(RCAS::I * RCAS.exp(-100))
    assert_equal 2, m.rank
  end
end
