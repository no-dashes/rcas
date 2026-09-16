# frozen_string_literal: true

require_relative "test_helper"

class FourierTest < Minitest::Test
  include RCAS::Constants

  X = RCAS::Var.new(:x)

  def teardown = RCAS.forget(:k, :n, :m)

  def test_general_coefficients
    assert_equal "sum(-2*(-1)**k*sin(k*x)/k, k, 1, oo)", RCAS.fourier(X, x: -PI..PI, formal: true).to_s
    assert_equal "pi**2/3 + sum(4*(-1)**k*cos(k*x)/k**2, k, 1, oo)", RCAS.fourier(X**2, x: -PI..PI, formal: true).to_s
    square = RCAS.piecewise(X < 0 => -1, :else => 1)
    assert_equal "sum(sin(k*x)*(2/k - 2*(-1)**k/k)/pi, k, 1, oo)", RCAS.fourier(square, x: -PI..PI, formal: true).to_s
  end

  def test_the_index_is_only_an_integer_while_the_coefficients_are_found
    RCAS.fourier(X, x: -PI..PI, formal: true)
    assert_nil RCAS.assumption(:k), "the assumption on the index is taken back"
    RCAS.assume(k: RCAS::RR)
    RCAS.fourier(X, x: -PI..PI, formal: true)
    assert_equal RCAS::RR, RCAS.assumption(:k), "an assumption of the user's is restored"
  end

  def test_partial_sum
    assert_equal "-sin(2*x) + 2*sin(3*x)/3 - sin(4*x)/2 + 2*sin(x)", RCAS.fourier(X, x: -PI..PI).to_s
    assert_equal "4*sin(3*x)/(3*pi) + 4*sin(x)/pi", RCAS.fourier(RCAS.piecewise(X < 0 => -1, :else => 1), x: -PI..PI, n: 3).to_s
    assert_equal "1 - sin(2*pi*x)/pi - 2*sin(pi*x)/pi", RCAS.fourier(X, x: 0..2, n: 2).to_s, "a period that is not 2*pi"
  end

  def test_half_range_expansions
    assert_equal "sum(-2*(-1)**k*sin(pi*k*x)/(pi*k), k, 1, oo)", RCAS.fourier(X, x: 0..1, kind: :sine, formal: true).to_s
    cosine = RCAS.fourier(X, x: 0..1, kind: :cosine, n: 2)
    assert_in_delta 0.5 - 4 / (Math::PI**2), cosine.evalf(x: 0), 1e-12, "a0/2 + a1 at 0"
    assert_raises(ArgumentError) { RCAS.fourier(X, x: 0..1, kind: :tangent) }
  end

  def test_the_sum_approaches_the_function
    f = RCAS.fourier(X**2, x: -PI..PI, n: 8)
    [-2.0, -0.5, 1.0, 2.0].each { |v| assert_in_delta v**2, f.evalf(x: v), 0.05 }
    square = RCAS.fourier(RCAS.piecewise(X < 0 => -1, :else => 1), x: -PI..PI, n: 9)
    assert_in_delta 1, square.evalf(x: Math::PI / 2), 0.1
    assert_equal 0, square.call(x: 0), "at a jump the series gives the mean of the two sides"
  end

  def test_an_integral_that_is_not_elementary
    assert_raises(RCAS::SeriesError) { RCAS.fourier(RCAS.exp(X**2), x: -PI..PI, n: 1) }
  end

  def test_infinite_interval_is_refused
    assert_raises(ArgumentError) { RCAS.fourier(X, x: 0..) }
  end
end
