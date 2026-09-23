# frozen_string_literal: true

require_relative "test_helper"

# Linear optimization (linear_program.rb): the textbook problems with their
# known answers, the three outcomes, and a property check against brute
# force - for a random problem in two variables every vertex is the
# meeting point of two constraint lines, so the optimum over the feasible
# vertices is the answer the simplex method has to find; for a whole-number
# problem the grid is small enough to search.
class LinearProgramTest < Minitest::Test
  def setup
    @x, @y, @z, @w = %i[x y z w].map { |n| RCAS::Var.new(n) }
  end

  def n(v) = RCAS::Num.new(v)
  def max(...) = RCAS.maximize(...)
  def min(...) = RCAS.minimize(...)

  def test_a_textbook_maximum
    r = max(3 * @x + 5 * @y, [@x <= 4, 2 * @y <= 12, 3 * @x + 2 * @y <= 18], nonnegative: true)
    assert r.optimal?
    assert_equal n(36), r.value
    assert_equal({ @x => n(2), @y => n(6) }, r.point)
    assert_equal true, r.unique?
    assert_equal "maximum 36 at x = 2, y = 6", r.to_s
  end

  def test_a_textbook_minimum_needs_the_first_phase
    r = min(@x + @y, [@x + 2 * @y >= 3, 3 * @x + @y >= 4], nonnegative: true)
    assert_equal "minimum 2 at x = 1, y = 1", r.to_s
  end

  def test_the_result_spreads_like_an_array
    value, point = max(3 * @x + 2 * @y, [@x + @y <= 4, @x + 3 * @y <= 6], nonnegative: true)
    assert_equal n(12), value
    assert_equal({ @x => n(4), @y => n(0) }, point)
  end

  def test_equations_and_a_fractional_vertex
    r = max(@x + @y, [RCAS.eq(@x + 2 * @y, 4), @x <= 3], nonnegative: true)
    assert_equal "maximum 7/2 at x = 3, y = 1/2", r.to_s
  end

  def test_no_feasible_point
    r = max(@x, [@x + @y <= 1, @x + @y >= 2], nonnegative: true)
    assert r.infeasible?
    assert_nil r.value
    assert_equal "infeasible: no point satisfies the constraints", r.to_s
  end

  def test_an_objective_without_bound
    r = max(@x + @y, [@x - @y <= 1], nonnegative: true)
    assert r.unbounded?
    assert_equal RCAS::OO, r.value
    assert_equal RCAS::Neg.new(RCAS::OO).simplify, min(-@x, [@x >= 0]).value
  end

  # free variables: a lower bound shifts, no bound splits
  def test_free_variables
    assert_equal "minimum -5 at x = -5", min(@x, [@x >= -5]).to_s
    assert_equal "minimum -1 at x = 0, y = -1", min(@x + @y, [@x - @y <= 1, @x >= 0]).to_s
    assert min(@x, [@x <= 3]).unbounded?, "a free x has no minimum above"
  end

  # an edge of optimal points: the answer says the point is one of many
  def test_optimal_points_along_an_edge
    r = max(@x + @y, [@x + @y <= 4], nonnegative: true)
    assert_equal n(4), r.value
    assert_equal false, r.unique?
    assert_match(/one of infinitely many optimal points/, r.to_s)
    r = max(@x + @y, [-@x - @y >= -4, @x - @y <= -1], nonnegative: true)
    assert_equal false, r.unique?
  end

  # Chvatal's example on which the largest-coefficient rule cycles for
  # ever; Bland's rule reaches the optimum
  def test_a_problem_that_cycles_without_blands_rule
    r = max(10 * @x - 57 * @y - 9 * @z - 24 * @w,
            [@x / 2r - 11 * @y / 2 - 5 * @z / 2 + 9 * @w <= 0, @x / 2r - 3 * @y / 2 - @z / 2 + @w <= 0, @x <= 1],
            nonnegative: true)
    assert_equal n(1), r.value
  end

  # an equation that follows from the others leaves a row the first phase
  # cannot pivot out of; it is dropped
  def test_a_redundant_equation
    r = max(@x, [RCAS.eq(@x + @y, 2), RCAS.eq(2 * @x + 2 * @y, 4), @x >= 0, @y >= 0])
    assert_equal "maximum 2 at x = 2, y = 0", r.to_s
  end

  def test_whole_numbers
    r = max(5 * @x + 4 * @y, [6 * @x + 4 * @y <= 24, @x + 2 * @y <= 6], nonnegative: true, integer: true)
    assert_equal n(20), r.value
    assert r.point.values.all? { |v| v.value.is_a?(Integer) }
    relaxed = max(5 * @x + 4 * @y, [6 * @x + 4 * @y <= 24, @x + 2 * @y <= 6], nonnegative: true)
    assert_equal n(21), relaxed.value
    mixed = max(@x + @y, [2 * @x + 2 * @y <= 5, @x <= 3/2r], nonnegative: true, integer: [@y])
    assert_equal n(5/2r), mixed.value
    assert mixed.point[@y].value.is_a?(Integer)
    assert max(@x, [2 * @x >= 1, 2 * @x <= 3/2r], integer: true).infeasible?
  end

  def test_decimals_are_read_as_written
    r = max(0.5 * @x + @y, [@x + @y <= 1.5], nonnegative: true)
    assert_in_delta 1.5, r.value.value, 1e-15
    assert_kind_of Float, r.value.value
  end

  def test_refusals
    assert_raises(ArgumentError) { max(@x, [@x < 1]) }
    assert_raises(ArgumentError) { max(@x, [RCAS::Inequality.new(@x, :!=, 1)]) }
    assert_raises(ArgumentError) { max(@x * @y, [@x <= 1]) }
    assert_raises(ArgumentError) { max(RCAS::Var.new(:a) * @x, [@x <= 1], [@x]) }
    assert_raises(ArgumentError) { max(@x, [@x <= RCAS.sqrt(2)]) }
    assert_raises(ArgumentError) { max(@x, [@x <= 1], integer: [@y]) }
  end

  def test_typesetting
    assert_equal "\\max = 36\\ \\text{at}\\ x = 2,\\ y = 6",
                 max(3 * @x + 5 * @y, [@x <= 4, 2 * @y <= 12, 3 * @x + 2 * @y <= 18], nonnegative: true).to_latex
  end

  # ---- against brute force ------------------------------------------------------

  def random_problem(rng)
    rows = Array.new(rng.rand(1..4)) { [rng.rand(-5..5), rng.rand(-5..5), rng.rand(-10..20)] }
    box = [[1, 0, 10], [0, 1, 10], [-1, 0, 0], [0, -1, 0]] # 0 <= x, y <= 10
    [rows + box, [rng.rand(-5..5), rng.rand(-5..5)]]
  end

  def constraints(rows) = rows.map { |a, b, c| a * @x + b * @y <= c }

  def feasible?(rows, px, py) = rows.all? { |a, b, c| a * px + b * py <= c }

  # the best objective over the vertices: pairs of constraint lines
  def vertex_optimum(rows, cost)
    points = rows.combination(2).filter_map do |(a1, b1, c1), (a2, b2, c2)|
      det = a1 * b2 - a2 * b1
      next nil if det.zero?
      px = Rational(c1 * b2 - c2 * b1, det)
      py = Rational(a1 * c2 - a2 * c1, det)
      feasible?(rows, px, py) ? [px, py] : nil
    end
    points.map { |px, py| cost[0] * px + cost[1] * py }.max
  end

  def test_the_simplex_method_agrees_with_the_vertices
    rng = Random.new(20260923)
    60.times do
      rows, cost = random_problem(rng)
      r = max(cost[0] * @x + cost[1] * @y, constraints(rows), [@x, @y])
      best = vertex_optimum(rows, cost)
      if best.nil?
        assert r.infeasible?, "#{rows} #{cost}: #{r}"
      else
        assert r.optimal?, "#{rows} #{cost}: #{r}"
        assert_equal best, r.value.value, "#{rows} #{cost}: #{r}"
        px, py = r.point.values_at(@x, @y).map(&:value)
        assert feasible?(rows, px, py), "the point #{r.point} is not feasible"
      end
    end
  end

  def test_branch_and_bound_agrees_with_the_grid
    rng = Random.new(42)
    30.times do
      rows, cost = random_problem(rng)
      r = max(cost[0] * @x + cost[1] * @y, constraints(rows), [@x, @y], integer: true)
      grid = (0..10).to_a.product((0..10).to_a).select { |px, py| feasible?(rows, px, py) }
      if grid.empty?
        assert r.infeasible?, "#{rows} #{cost}: #{r}"
      else
        assert_equal grid.map { |px, py| cost[0] * px + cost[1] * py }.max, r.value.value, "#{rows} #{cost}: #{r}"
      end
    end
  end
end
