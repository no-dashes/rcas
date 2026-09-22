# frozen_string_literal: true

# Findings the third review listed as plausible but wrote no test for,
# fixed on the way (22-23 Sept 2026). Each assertion is the mathematics.
require_relative "test_helper"

class ReviewFollowupsTest < Minitest::Test
  def setup
    @x, @y = %i[x y].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  # exp(-oo) = 0, exp(oo) = log(oo) = oo, atan(+-oo) = +-pi/2: the limits.
  def test_elementary_functions_at_infinity
    o = RCAS::OO
    assert_equal RCAS::Num.new(0), RCAS.exp(-o)
    assert_equal o, RCAS.exp(o)
    assert_equal o, RCAS.log(o)
    assert_equal (RCAS::PI / 2).simplify, RCAS.atan(o)
    assert_equal (-RCAS::PI / 2).simplify, RCAS.atan(-o)
  end

  # sqrt(-1/4) = i/2, the same principal value sqrt(-4) = 2*i has.
  def test_square_root_of_a_negative_rational
    assert_equal "i/2", RCAS.sqrt(RCAS::Num.new(Rational(-1, 4))).to_s
    assert_equal "2*i", RCAS.sqrt(-4).to_s
  end

  # sin(x)*tan(x) vanishes on pi*k once; the family is not listed twice.
  def test_a_family_is_listed_once
    roots = RCAS.solve(RCAS.sin(@x) * RCAS.tan(@x), @x)
    assert_equal 1, roots.size
  end

  # y' = y is solved by C*exp(x) for every C, 0 and negative C included.
  def test_a_linear_equation_keeps_its_zero_and_negative_solutions
    sol = RCAS.dsolve(RCAS.eq(RCAS.D(@y, @x), @y), @y, @x).first.rhs
    assert_equal RCAS::Num.new(0), sol.subs(C1: 0).simplify
    assert_equal RCAS::Num.new(-1), sol.subs(C1: -1, x: 0).simplify
  end

  # asin at 1 has no Taylor series; the refusal is a SeriesError, not a
  # ZeroDivisionError from the inside.
  def test_a_series_at_a_singular_point_is_refused
    assert_raises(RCAS::SeriesError) { RCAS.series(RCAS.asin(1 - @x), @x, 0) }
  end
end
