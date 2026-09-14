# frozen_string_literal: true

require_relative "test_helper"

class LaplaceTest < Minitest::Test
  T = RCAS::Var.new(:t)
  S = RCAS::Var.new(:s)

  def test_the_table
    assert_equal "1/s", RCAS.laplace(1, :t, :s).to_s
    assert_equal "1/s**2", RCAS.laplace(T, :t, :s).to_s
    assert_equal "2/s**3", RCAS.laplace(T**2, :t, :s).to_s
    assert_equal "1/(-3 + s)", RCAS.laplace(RCAS.exp(3 * T), :t, :s).to_s
    assert_equal "2/(4 + s**2)", RCAS.laplace(RCAS.sin(2 * T), :t, :s).to_s
    assert_equal "s/(1 + s**2)", RCAS.laplace(RCAS.cos(T), :t, :s).to_s
    assert_equal "s/(-4 + s**2)", RCAS.laplace(RCAS.cosh(2 * T), :t, :s).to_s
  end

  def test_the_two_rules
    assert_equal "2/(4 + (1 + s)**2)", RCAS.laplace(RCAS.exp(-T) * RCAS.sin(2 * T), :t, :s).to_s, "the first shift"
    assert_equal "1/(-3 + s)**2", RCAS.laplace(T * RCAS.exp(3 * T), :t, :s).to_s
    assert_equal "2*s/(1 + s**2)**2", RCAS.laplace(T * RCAS.sin(T), :t, :s).to_s, "multiplying by t differentiates in s"
    assert_equal "6/s**3 + 2/(-1 + s)", RCAS.laplace(3 * T**2 + 2 * RCAS.exp(T), :t, :s).to_s, "linearity"
    assert_raises(RCAS::Laplace::Error) { RCAS.laplace(RCAS.log(T), :t, :s) }
  end

  def test_the_inverse
    assert_equal "1", RCAS.inverse_laplace(1 / S, :s, :t).to_s
    assert_equal "t**2/2", RCAS.inverse_laplace(1 / S**3, :s, :t).to_s
    assert_equal "exp(3*t)", RCAS.inverse_laplace(1 / (S - 3), :s, :t).to_s
    assert_equal "t*exp(3*t)", RCAS.inverse_laplace(1 / (S - 3)**2, :s, :t).to_s
    assert_equal "sin(t)", RCAS.inverse_laplace(1 / (S**2 + 1), :s, :t).to_s
    assert_equal "cos(2*t)", RCAS.inverse_laplace(S / (S**2 + 4), :s, :t).to_s
    assert_equal "exp(2*t) - exp(t)", RCAS.inverse_laplace(1 / ((S - 1) * (S - 2)), :s, :t).to_s
    assert_equal "exp(-t)*sin(2*t)/2", RCAS.inverse_laplace(1 / (S**2 + 2 * S + 5), :s, :t).to_s
  end

  # Transforming and inverting returns the function it started from.
  def test_the_round_trip
    [RCAS.exp(2 * T), RCAS.sin(3 * T), RCAS.cos(T), T, T**2, RCAS.exp(-T) * RCAS.cos(T)].each do |f|
      back = RCAS.inverse_laplace(RCAS.laplace(f, :t, :s), :s, :t)
      difference = (back - f).simplify
      [0.3, 1.7].each { |point| assert_in_delta 0.0, difference.evalf(t: point).abs, 1e-9, "#{f} did not survive the round trip" }
    end
  end
end
