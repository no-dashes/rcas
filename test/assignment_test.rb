# frozen_string_literal: true

require_relative "test_helper"

# A solution of several unknowns is keyed by the indeterminates, and in a
# session a bare name is a Symbol: sol[x] asked with :x and answered nil
# (found on 23 Sept 2026, writing the linear optimization section of the
# manual). Assignment looks a Symbol up as the indeterminate it names.
class AssignmentTest < Minitest::Test
  def setup
    @x, @y = %i[x y].map { |n| RCAS::Var.new(n) }
  end

  def n(v) = RCAS::Num.new(v)

  def test_a_system_solution_is_read_by_the_bare_name
    sol = RCAS.solve([RCAS.eq(@x + @y, 3), RCAS.eq(@x - @y, 1)], [@x, @y]).first
    assert_kind_of RCAS::Assignment, sol
    assert_equal n(2), sol[:x]
    assert_equal n(2), sol[@x]
    assert_equal [n(2), n(1)], sol.values_at(:x, :y)
    assert sol.key?(:y)
    assert_equal n(1), sol.fetch(:y)
    assert_nil sol[:z]
  end

  # it is still the Hash it was: equal to one, and printed as one
  def test_it_compares_and_prints_as_a_hash
    sol = RCAS.solve([RCAS.eq(@x + @y, 3), RCAS.eq(@x - @y, 1)], [@x, @y]).first
    assert_equal({ @x => n(2), @y => n(1) }, sol)
    assert_equal({ @x => n(2), @y => n(1) }.inspect, sol.inspect)
  end

  def test_lagrange_and_the_optimum_of_a_linear_program
    points = RCAS.lagrange(@x + @y, [@x**2 + @y**2 - 1], [@x, @y])
    assert points.all? { |p| p[:x] == p[@x] && !p[:x].nil? }
    _, plan = RCAS.maximize(30 * @x + 20 * @y, [2 * @x + @y <= 100, @x + @y <= 80], nonnegative: true)
    assert_equal [n(20), n(60)], plan.values_at(:x, :y)
  end
end
