# Two tests of round 3 (review/round3/tests/solve_test.rb) whose helper was
# wrong, not rcas: `members` evaluated every family at k = -3..3 whatever the
# family's own parameter domain, and could not evaluate a family with two
# parameters. The assertions are unchanged; only the helper now iterates each
# family over its OWN domain (NN: 0..n, ZZ: -n..n) and over every parameter.
# These replace test_every_family_member_lies_in_the_domain and
# test_nested_inversion_keeps_every_period in round 3.
require_relative 'test_helper'
require 'rcas'

class ReviewSolveCorrectedTest < Minitest::Test
  def setup
    @x = RCAS::Var.new(:x)
  end

  def teardown = RCAS.forget

  def real(e)
    v = RCAS::Expression.lift(e).evalf
    v = v.value if v.is_a?(RCAS::Num)
    return nil unless v.is_a?(Numeric)
    v = v.real if v.is_a?(Complex) && v.imaginary.abs < 1e-12
    v.is_a?(Complex) || !v.finite? ? nil : v.to_f
  rescue StandardError, Math::DomainError
    nil
  end

  def value_at(f, var, v)
    real(RCAS::Expression.lift(f).subs(var.name => RCAS::Expression.lift(v)))
  end

  # The members of a solution list: points, and each family over its own
  # parameter domain, every parameter varied.
  def members(solutions, ks = -3..3)
    solutions.flat_map do |s|
      next [s] unless s.is_a?(RCAS::ImageSet)
      range = (s.domain == RCAS::NN ? (0..ks.max) : ks).to_a
      range.repeated_permutation(s.parameters.size).map { |values| s.at(*values) }
    end
  end

  def covers?(solutions, target, ks = -6..6)
    members(solutions, ks).any? { |m| (v = real(m)) && (v - target).abs < 1e-9 }
  end

  # A family member is a solution only where the expression is defined.
  # sin(0)/0, (1 - cos 0)/sin 0, sin(2*pi)/sin(pi) are 0/0; tan(pi/2) does
  # not exist.
  def test_every_family_member_lies_in_the_domain
    [RCAS.sin(@x) / @x, (1 - RCAS.cos(@x)) / RCAS.sin(@x), RCAS.sin(2 * @x) / RCAS.sin(@x),
     RCAS.tan(@x) * RCAS.cos(@x), RCAS.sin(@x) / (1 + RCAS.cos(@x))].each do |f|
      members(RCAS.solve(f, @x)).each do |m|
        v = value_at(f, @x, RCAS::Expression.lift(m).evalf)
        assert v && v.abs < 1e-9, "#{f.inspect} is not zero (or undefined) at the member #{m.inspect}"
      end
    end
  end

  # exp(sin(2*pi)) = 1, log(sin(5*pi/2)) = 0, sin(cos(3*pi/2)) = sin(0) = 0.
  def test_nested_inversion_keeps_every_period
    assert covers?(RCAS.solve(RCAS.exp(RCAS.sin(@x)) - 1, @x), 2 * Math::PI)
    assert covers?(RCAS.solve(RCAS.log(RCAS.sin(@x)), @x), 5 * Math::PI / 2)
    assert covers?(RCAS.solve(RCAS.sin(RCAS.cos(@x)), @x), 3 * Math::PI / 2)
  end
end
