# Verification round of the third review: linear algebra, vector calculus.
# Each test pins a defect found in 8c10e71, derived independently; the
# regressions were right at da72570.
require_relative 'test_helper'
require 'rcas'
require 'timeout'

class Review2LinearAlgebraTest < Minitest::Test
  def setup
    @x, @y, @z, @u, @v = %i[x y z u v].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  def value(e, **at)
    v = RCAS::Expression.lift(e).subs(at).evalf
    v = v.value if v.is_a?(RCAS::Num)
    v
  end

  # Regression. The vortex (-y, x)/(x**2 + y**2) is smooth on [1, 2]x[1, 2]:
  # its curl is 0 there, so Green gives 0 (da72570 said 0). x**2 + y**2 >= 2
  # on the square, yet the new regularity check refuses, because the sign of
  # a factor that moves with two ranges is never decided.
  def test_green_on_a_region_that_avoids_the_singularity
    r2 = @x**2 + @y**2
    assert_equal n(0), RCAS.green([-@y / r2, @x / r2], x: 1..2, y: 1..2)
  end

  # Regression. (2x, 2y)/(x**2 + y**2) is the gradient of log(x**2 + y**2)
  # on its whole domain, so it has that potential whatever the hole at 0
  # does to the curl test (da72570 answered log(x**2 + y**2)). A potential
  # found is a proof by differentiation; the refusal belongs only to
  # conservative?'s curl test.
  def test_a_gradient_with_a_singular_point_has_its_potential
    r2 = @x**2 + @y**2
    field = [2 * @x / r2, 2 * @y / r2]
    phi = RCAS.potential(field)
    [[1, 2], [-3, 1/2r]].each do |px, py|
      assert_in_delta value(field[0], x: px, y: py), value(RCAS.diff(phi, @x), x: px, y: py), 1e-12
      assert_in_delta value(field[1], x: px, y: py), value(RCAS.diff(phi, @y), x: px, y: py), 1e-12
    end
  end

  # Regression. (u**2 - v**2, 2uv, 0) has |r_u x r_v| = 4u**2 + 4v**2, which
  # is non-negative for the real parameters of the ranges, so the area of
  # the image of the unit square is 4*(1/3 + 1/3) = 8/3 (da72570: 8/3). The
  # abs stays now and the integral with it.
  def test_a_sum_of_squares_needs_no_absolute_value
    area = RCAS.surface_integral(1, [@u**2 - @v**2, 2 * @u * @v, 0], u: 0..1, v: 0..1)
    assert_equal n(Rational(8, 3)), area
  end

  # Regression. x is declared real, so log(x**2) is real wherever it is
  # defined - just as log(x) (inferred CC) and 1/x (inferred RR) are, and
  # both of those build a matrix. log_domain answers nil for a symbolic
  # argument that may be 0 (domains.rb:510), so the matrix raises "declare
  # its variables" for a declared variable. det = log(x**2) - 2*log(x),
  # which is -2*pi*i at x = -1, so the matrix is not singular.
  def test_a_matrix_of_logarithms_of_squares_can_be_built
    RCAS.assume(x: RCAS::RR) do
      m = RCAS.matrix([[RCAS.log(@x**2), RCAS.log(@x)], [2, 1]])
      assert_in_delta 2 * Math::PI, value(m.det, x: -1).abs, 1e-9
    end
  end

  # Not fixed in general (C3/L16). exp(-30)*gamma(1/3) is about 2.5e-13,
  # not 0. Decide cannot evaluate gamma(1/3) at high precision and answers
  # nil, and Scalar.vanishes? reads nil as zero - so the determinant of
  # diag(exp(-30)*gamma(1/3), 1) comes out as the exact 0.
  def test_a_tiny_constant_without_a_high_precision_value_is_not_zero
    c = RCAS.exp(-30) * RCAS.gamma(1/3r)
    refute RCAS::Scalar.zero?(c)
    m = RCAS.matrix([[c, 0], [0, 1]])
    assert_equal 2, m.rank
    refute_equal n(0), m.det
  end
end
