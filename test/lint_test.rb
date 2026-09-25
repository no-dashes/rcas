# frozen_string_literal: true

require_relative "test_helper"

# Ruby folds `1/3` to 0 before rcas sees it; the front ends warn at once.
class LintTest < Minitest::Test
  def teardown
    RCAS.lint = nil
  end

  def test_an_integer_division_that_is_not_whole_is_warned
    assert_equal ["1/3 is 0: Ruby divides two Integers as integers, rounding down; write 1/3r for the fraction"],
                 RCAS::Lint.warnings("x + 1/3")
    assert_equal ["-1/3 is -1: Ruby divides two Integers as integers, rounding down; write -1/3r for the fraction"],
                 RCAS::Lint.warnings("-1/3*x")
  end

  def test_an_exponent_says_what_the_power_became
    assert_equal ["1/2 is 0: Ruby divides two Integers as integers, rounding down (so the exponent is 0); write 1/2r for the fraction"],
                 RCAS::Lint.warnings("2**(1/2)")
    assert_equal ["1/2 is 0: Ruby divides two Integers as integers, rounding down; write 1/2r for the fraction"],
                 RCAS::Lint.warnings("(1/2)**x"), "the base is not the exponent"
  end

  def test_whole_divisions_rationals_and_variables_are_left_alone
    assert_empty RCAS::Lint.warnings("6/3 + x")
    assert_empty RCAS::Lint.warnings("1/3r + Rational(1, 3) + 1.0/3")
    assert_empty RCAS::Lint.warnings("n = 7; n/2")
    assert_empty RCAS::Lint.warnings("1/0"), "Ruby says that itself"
  end

  def test_hold_and_steps_keep_the_division
    assert_empty RCAS::Lint.warnings("hold { 1/2 + x }")
    assert_empty RCAS::Lint.warnings("RCAS.hold { 1/2 }")
    assert_empty RCAS::Lint.warnings("steps { integrate(x**(1/2), x) }")
    assert_equal 1, RCAS::Lint.warnings("hold { 1/2 } + 1/3").size, "only outside the block"
  end

  def test_one_message_per_division_and_none_for_bad_syntax
    assert_equal 1, RCAS::Lint.warnings("1/3 + 1/3").size
    assert_empty RCAS::Lint.warnings("def f(")
  end

  def test_it_can_be_turned_off
    RCAS.lint = false
    assert_empty RCAS::Lint.warnings("x + 1/3")
  end
end
