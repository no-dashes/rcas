# frozen_string_literal: true

require_relative "test_helper"

class NumericsTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def test_roots_by_bracketing
    assert_in_delta 0.7390851332151607, RCAS.nsolve(RCAS.cos(X) - X, x: 0..1), 1e-12
    assert_in_delta Math.sqrt(2), RCAS.nsolve(X**2 - 2, x: 0..2), 1e-12
    assert_in_delta Math.log(5), RCAS.nsolve(RCAS.exp(X) - 5, x: 0..3), 1e-12
    assert_in_delta 0.0, RCAS.nsolve(RCAS.sin(X), x: -1..1), 1e-12
    assert_raises(ArgumentError, "no sign change, no root") { RCAS.nsolve(X**2 + 1, x: 0..1) }
  end

  def test_roots_from_a_guess
    assert_in_delta 2.0945514815423265, RCAS.nsolve(X**3 - 2 * X - 5, :x, 2), 1e-12
    assert_in_delta 0.7390851332151607, RCAS.nsolve(RCAS.cos(X) - X, :x, 1), 1e-12
    assert_in_delta(-1.0, RCAS.nsolve(X**3 + 1, :x, -2), 1e-9)
    assert_in_delta 1.0, RCAS.nsolve(RCAS.log(X), :x, 2), 1e-9
    assert_raises(ArgumentError, "a function without a root") { RCAS.nsolve(RCAS.exp(X) + 1, :x, 0) }
  end

  def test_quadrature
    assert_in_delta 0.9460830703671830, RCAS.nintegrate(RCAS.sin(X) / X, x: 0..1), 1e-9
    assert_in_delta 1.0 / 3, RCAS.nintegrate(X**2, x: 0..1), 1e-12
    assert_in_delta Math.sqrt(Math::PI), RCAS.nintegrate(RCAS.exp(-X**2), x: -RCAS::OO..RCAS::OO), 1e-9
    assert_in_delta 1.0, RCAS.nintegrate(RCAS.exp(-X), x: 0..), 1e-6
    assert_in_delta 2.0, RCAS.nintegrate(1 / RCAS.sqrt(X), x: 0..1), 1e-6, "an integrable singularity"
    assert_in_delta(-1.0 / 3, RCAS.nintegrate(X**2, x: 1..0), 1e-12, "the bounds may be the other way round")
    assert_in_delta Math::PI, RCAS.nintegrate(1 / (1 + X**2), x: -RCAS::OO..RCAS::OO), 1e-8
  end

  def test_evalf_finishes_what_integrate_could_not
    formal = RCAS.integrate(RCAS.exp(-X**4), x: 0..1)
    assert_kind_of RCAS::Integral, formal
    assert_in_delta 0.8448385947571027, formal.evalf, 1e-9
    assert_in_delta 0.29469818224, RCAS.integrate(RCAS.exp(-X**2) * RCAS.sin(X), x: 0..1).evalf, 1e-9
    # an exact answer is never replaced by a float
    assert_equal Rational(1, 3), RCAS.integrate(X**2, x: 0..1)
    # a free parameter keeps the integral unevaluated
    assert_kind_of RCAS::Integral, RCAS.integrate(RCAS.exp(-RCAS::Var.new(:a) * X**4), x: 0..1).evalf
  end

  def test_the_results_are_honest_floats
    assert_instance_of Float, RCAS.nsolve(X**2 - 2, x: 0..2)
    assert_instance_of Float, RCAS.nintegrate(X, x: 0..1)
    assert_raises(ArgumentError) { RCAS.nsolve(X * RCAS::Var.new(:y), x: 0..1) }
  end

  # A function changes sign across a pole as it does across a root, and
  # bisection walked straight into it: nsolve(1/x, x: -1..1) was 0.0.
  def test_a_pole_is_not_a_root
    x = RCAS::Var.new(:x)
    [[1 / x, -1..1], [RCAS.tan(x), 1..2], [1 / (x - 1r / 2), 0..1]].each do |f, range|
      e = assert_raises(ArgumentError) { RCAS.nsolve(f, x: range) }
      assert_match(/has a pole at/, e.message)
    end
    # and the roots on either side are still found
    assert_in_delta 0.5, RCAS.nsolve(1 / x - 2, x: 0.1..2), 1e-9
    assert_in_delta Math::PI, RCAS.nsolve(RCAS.tan(x), x: 3..4), 1e-9
    assert_in_delta 0.7390851332151607, RCAS.nsolve(RCAS.cos(x) - x, x: 0..1), 1e-12
  end
  # Adaptive Simpson halved the interval down to MAX_DEPTH, so a singular
  # integrand reached 2**50 subintervals and never returned. The default is
  # the tanh-sinh quadrature now: accurate at an endpoint singularity, and
  # it says when it cannot settle instead of subdividing for ever.
  def test_a_singular_integrand_settles_or_says_so
    x = RCAS::Var.new(:x)
    assert_in_delta 2.0, RCAS.nintegrate(1 / RCAS.sqrt(x), x: 0..1), 1e-15
    assert_in_delta Math.sqrt(Math::PI), RCAS.nintegrate(RCAS.exp(-x**2), x: -RCAS::OO..RCAS::OO), 1e-15
    assert_in_delta(-1.0, RCAS.nintegrate(RCAS.log(x), x: 0..1), 1e-15)
    [[1 / x**2, 0..1], [RCAS.tan(x), 0..3.14]].each do |f, range|
      e = assert_raises(ArgumentError) { RCAS.nintegrate(f, x: range) }
      assert_match(/did not settle/, e.message)
    end
  end

end
