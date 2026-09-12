# frozen_string_literal: true

require_relative "test_helper"

class ConstantsTest < Minitest::Test
  include RCAS::Constants

  def test_exact_trigonometric_values
    assert_equal "1/2", RCAS.sin(PI / 6).simplify.to_s
    assert_equal "1/2", RCAS.cos(PI / 3).simplify.to_s
    assert_equal "1", RCAS.tan(PI / 4).simplify.to_s
    assert_equal "0", RCAS.sin(PI).simplify.to_s
    assert_equal "1", RCAS.cos(2 * PI).simplify.to_s
    assert_equal "-1/2", RCAS.sin(7 * PI / 6).simplify.to_s
    assert_equal "2**(1/2)/2", RCAS.cos(PI / 4).simplify.to_s
    assert_equal "sin(pi/5)", RCAS.sin(PI / 5).simplify.to_s
    assert_equal "pi/6", RCAS.asin(Rational(1, 2)).simplify.to_s
    assert_equal "pi/2", RCAS.acos(0).simplify.to_s
    assert_equal "pi/4", RCAS.atan(1).simplify.to_s
  end

  def test_e_and_i
    assert_equal "e", E.to_s
    assert_equal "exp(x)", (E**:x).simplify.to_s
    assert_equal "exp(3)", (E**2 * E).simplify.to_s
    assert_equal "1", RCAS.log(E).simplify.to_s
    assert_equal "-1", RCAS.exp(I * PI).simplify.to_s
    assert_equal "i", RCAS.exp(I * PI / 2).simplify.to_s
    assert_equal "-1", (I**2).simplify.to_s
    assert_equal "-i", (I**3).simplify.to_s
    assert_equal "-6", (2 * I * 3 * I).simplify.to_s
    assert_equal "2*i", RCAS.sqrt(-4).simplify.to_s
    assert_equal "i*2**(1/2)", RCAS.sqrt(-2).simplify.to_s
    assert_equal "(1 + 2*i)*x", ((1 + 2 * I) * :x).simplify.to_s
    assert_equal "1", (I + 1 - I).simplify.to_s
  end

  def test_numbers
    assert_equal "4*2**(1/2)", RCAS.sqrt(32).simplify.to_s
    assert_equal "3*log(2)", RCAS.log(8).simplify.to_s
    assert_equal "3", (RCAS.log(8) / RCAS.log(2)).simplify.to_s
    assert_in_delta Math::PI, PI.evalf, 1e-15
    assert_in_delta 2 * Math::PI, (2 * PI * I).evalf.imaginary, 1e-12
    assert_equal RCAS::RR, PI.domain
    assert_equal RCAS::CC, (I * :x).tap { RCAS.assume(x: RCAS::ZZ) }.domain
    RCAS.forget
  end
end
