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

  def test_a_jordan_chain_of_length_three_solves_the_system
    # x' = x + y, y' = y + z, z' = z: the third solution is e^t (t^2/2, t, 1).
    sol = RCAS.dsolve([RCAS.eq(RCAS.D(@x, @t), @x + @y), RCAS.eq(RCAS.D(@y, @t), @y + @z),
                       RCAS.eq(RCAS.D(@z, @t), @z)], [@x, @y, @z], @t).to_h { |e| [e.lhs, e.rhs] }
    fx, fy, fz = sol.values_at(@x, @y, @z)
    bind = { C1: 0.37, C2: -0.61, C3: 0.23, t: 0.8 }
    [[fx, fx + fy], [fy, fy + fz], [fz, fz]].each do |f, rhs|
      assert_in_delta 0, value(RCAS.diff(f, @t) - rhs, bind), 1e-9
    end
  end

  def test_a_nonlinear_system_is_not_linearised
    # x' = x**2 has x = -1/(C + t); x = constant is not a solution. Refusing is fine.
    begin
      sol = RCAS.dsolve([RCAS.eq(RCAS.D(@x, @t), @x**2), RCAS.eq(RCAS.D(@y, @t), @y)], [@x, @y], @t)
    rescue NotImplementedError, ArgumentError
      return assert true
    end
    fx = sol.find { |e| e.lhs == @x }.rhs
    assert_in_delta 0, value(RCAS.diff(fx, @t) - fx**2, C1: 0.37, C2: -0.61, t: 0.8), 1e-9
  end

  def test_complex_characteristic_roots_give_a_solution_of_the_right_order
    # y'' - 2i y' - y = (D - i)^2 y: the solutions are (C1 + C2 x) exp(i x), two constants.
    y = RCAS::Var.new(:y)
    f = RCAS.dsolve(RCAS.D(y, @x, 2) - 2 * RCAS::I * RCAS.D(y, @x) - y, y, @x).first.rhs
    constants = f.variables.select { |v| v.to_s.start_with?("C") }
    assert_equal 2, constants.size, "#{f}"
    residual = RCAS.diff(f, @x, 2) - 2 * RCAS::I * RCAS.diff(f, @x) - f
    assert_in_delta 0, value(residual, C1: 0.37, C2: -0.61, C3: 0.23, C4: 0.9, x: 0.7).abs, 1e-9
  end

  def test_laplace_is_linear_in_symbolic_constants
    # L{a} = a/s and L{a*t} = a/s**2.
    assert zero?(RCAS.cancel(RCAS.laplace(@a, @t, @s) - @a / @s))
    assert zero?(RCAS.cancel(RCAS.laplace(@a * @t, @t, @s) - @a / @s**2))
  end

  def test_a_parameter_in_a_field_is_not_a_coordinate
    # The field is read in x, y, z (MANUAL 1.6): the work of (a*y, -x, 0) around the
    # unit circle is the integral of -a sin^2 - cos^2, i.e. -pi*(1 + a).
    circle = [RCAS.cos(@t), RCAS.sin(@t), 0]
    work = RCAS.line_integral([@a * @y, -@x, 0], circle, t: 0..2 * RCAS::PI)
    assert zero?(work + RCAS::PI * (1 + @a)), "#{work}"
    # (y, x, a) is the gradient of x*y + a*z.
    phi = RCAS.potential([@y, @x, @a])
    assert zero?(RCAS.diff(phi, @z) - @a), "#{phi}"
  end

  def test_rank_agrees_with_the_determinant_for_symbolic_matrices
    # Each matrix has det 0 identically, so its rank is 1 and its kernel is a line.
    RCAS.assume(x: RCAS::RR, a: RCAS::RR, b: RCAS::RR) do
      [[[@x + 1, @x - 1], [@x**2 - 1, (@x - 1)**2]],
       [[@x - 1, @x**2 - 1], [1, @x + 1]],
       [[@a + @b, @a**2 - @b**2], [1, @a - @b]]].each do |rows|
        m = RCAS.matrix(rows)
        assert zero?(m.det)
        assert_equal 1, m.rank, "rank of #{rows}"
        assert_equal 1, m.kernel.size, "kernel of #{rows}"
      end
      # sin(2x) - 2 sin(x) cos(x) = 0: there is no inverse.
      assert_raises(RCAS::DomainError, ZeroDivisionError) do
        RCAS.matrix([[RCAS.sin(2 * @x), 2 * RCAS.sin(@x)], [RCAS.cos(@x), 1]]).inverse
      end
    end
  end
end
