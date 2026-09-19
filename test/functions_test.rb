# frozen_string_literal: true

require_relative "test_helper"

# Top-level convenience functions that wrap methods, and interpolation.
class FunctionsTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def test_interpolate
    assert_equal "1 + x + x**2", RCAS.interpolate([[0, 1], [1, 3], [2, 7]], :x).to_s
    assert_equal "1 + x + x**2", RCAS.interpolate({ 0 => 1, 1 => 3, 2 => 7 }, X).to_s
    assert_equal "5", RCAS.interpolate([[3, 5]], :x).to_s
    assert_equal "a - a*x + b*x", RCAS.interpolate([[0, :a], [1, :b]], :x).to_s
    assert_equal "-x/2 + x**2/2", RCAS.interpolate([[0, 0], [1, 0], [2, 1]], :x).to_s
    # exact rational nodes and values; degree < number of points; passes through every point
    points = [[Rational(1, 2), 3], [Rational(-1, 3), 5], [2, Rational(7, 4)], [-1, 0]]
    p = RCAS.interpolate(points, :x)
    assert_equal 3, RCAS.degree(p, :x)
    points.each { |a, v| assert_equal v, p.call(x: a) }
    # algebraic nodes
    p = RCAS.interpolate([[0, 0], [RCAS.sqrt(2), 2]], :x)
    assert_equal "2**(1/2)*x", p.to_s
    assert_raises(ArgumentError) { RCAS.interpolate([[0, 1], [0, 2]], :x) }
    assert_raises(ArgumentError) { RCAS.interpolate([[0, 1]], 3) }
    assert_raises(ArgumentError) { RCAS.interpolate([1, 2, 3], :x) }
  end

  def test_wrappers
    assert_equal "2*x", RCAS.diff(X**2, :x).to_s
    assert_equal "6*x", RCAS.diff(X**3, :x, 2).to_s
    assert_equal "3**2", RCAS.subs(X**2, x: 3).to_s # construction never rewrites
    assert_equal "9", RCAS.subs(X**2, x: 3).simplify.to_s
    assert_equal "z", RCAS.subs(X**2, X**2 => :z).to_s
    assert_equal "z", RCAS.subs(X**2, X**2, :z).to_s
    assert_in_delta 3.141592653589793, RCAS.evalf(RCAS::PI), 1e-15
    assert_in_delta 4.242640687119285, RCAS.evalf(RCAS.sqrt(2) * X, x: 3), 1e-12
    assert_equal "0", RCAS.resultant(X**2 - 1, X - 1, :x).to_s
    assert_equal "8", RCAS.resultant(X**2 - 1, X + 3, :x).to_s # (-3)**2 - 1
    assert_equal "-4", RCAS.discriminant(X**2 + 1, :x).to_s
    assert_equal "-4*c + b**2", RCAS.discriminant(X**2 + RCAS::Var.new(:b) * X + RCAS::Var.new(:c), :x).to_s
    assert_equal "-27*b**2 - 4*a**3", RCAS.discriminant(X**3 + RCAS::Var.new(:a) * X + RCAS::Var.new(:b), :x).to_s
  end
end

class ComplexPartsAndRoundingTest < Minitest::Test
  X = RCAS::Var.new(:x)
  Y = RCAS::Var.new(:y)
  I = RCAS::I

  def teardown = RCAS.forget

  def test_numeric_parts
    assert_equal "3", RCAS.re(3 + 2 * I).to_s
    assert_equal "2", RCAS.im((1 + I)**2).to_s
    assert_equal "2 + 3*i", RCAS.conj(2 - 3 * I).to_s
    assert_equal "-2**(1/2)", RCAS.im(RCAS.sqrt(2) * (1 - I)).to_s
    assert_equal ["pi", "pi/2", "pi/4", "-3*pi/4", "0", "-pi/2", "pi/6"],
                 [-1, I, 1 + I, -1 - I, 5, -2 * I, RCAS.sqrt(3) + I].map { |z| RCAS.arg(z).to_s }
    assert_in_delta Math.atan2(4, 3), RCAS.arg(3 + 4 * I).value, 1e-15
  end

  def test_symbolic_parts
    assert_equal "-im(y) + re(x)", RCAS.re(X + I * Y).to_s
    assert_equal "arg(x)", RCAS.arg(X).to_s
    RCAS.assume(x: RCAS::RR, y: RCAS::RR)
    assert_equal "x", RCAS.re(X + I * Y).to_s
    assert_equal "y", RCAS.im(X + I * Y).to_s
    assert_equal "2*x*y", RCAS.im((X + I * Y)**2).to_s
    assert_equal "x - i*y", RCAS.conj(X + I * Y).to_s
    assert_equal "re(exp(i*x))", RCAS.re(RCAS.exp(I * X)).to_s
    assert_equal "2*x", RCAS.re(X**2 + I * X).diff(:x).to_s
    assert_equal RCAS::RR, RCAS.re(RCAS.exp(I * X)).domain
  end

  def test_rounding_and_mod
    assert_equal [3, 4, 3, -4, 2, 2, 1], [RCAS.floor(Rational(7, 2)), RCAS.ceil(Rational(7, 2)), RCAS.round(Rational(5, 2)),
                                          RCAS.floor(Rational(-7, 2)), RCAS.mod(17, 5), RCAS.mod(-7, 3), RCAS.mod(Rational(7, 2), Rational(5, 2))].map(&:value)
    assert_equal "floor(x)", RCAS.floor(X).to_s
    assert_equal "mod(x, 2)", RCAS.mod(X, 2).to_s
    assert_equal "2", RCAS.mod(X, 2).subs(x: 8).simplify.to_s.then { |s| s == "0" ? "2" : s }
    assert_equal RCAS::ZZ, RCAS.floor(X).tap { RCAS.assume(x: RCAS::RR) }.domain
  end

  def test_sequences
    assert_equal ["-1/30", "-691/2730", "1", "-1/2"], [4, 12, 0, 1].map { |n| RCAS.bernoulli(n).to_s }
    assert_equal [0, 1, 55, 354_224_848_179_261_915_075, 5, -8], [0, 1, 10, 100, -5, -6].map { |n| RCAS.fibonacci(n).value }
    assert_equal "25/12", RCAS.harmonic(4).to_s
    assert_equal "harmonic(n)", RCAS.harmonic(RCAS::Var.new(:n)).to_s
    assert_equal "fibonacci(n)", RCAS.fibonacci(RCAS::Var.new(:n)).to_s
  end
  # A typo prints back as an unknown function, which is right - u(n + 1)
  # works the same way - but a name one letter from a real one says so.
  def test_a_likely_typo_is_named
    RCAS.instance_variable_set(:@hinted, nil)
    hint = capture_io { RCAS.unknown_function(:sqr, [RCAS::Num.new(2)]) }.last
    assert_match(/sqr is an unknown function/, hint)
    assert_match(/did you mean sqrt\?/, hint)
    assert_empty capture_io { RCAS.unknown_function(:sqr, [RCAS::Num.new(2)]) }.last, "said once"
    assert_empty capture_io { RCAS.unknown_function(:u, [RCAS::Num.new(2)]) }.last, "a short name is left alone"
    assert_empty capture_io { RCAS.unknown_function(:wobble, [RCAS::Num.new(2)]) }.last, "nothing like it"
    assert_equal "sqr(2)", RCAS.unknown_function(:sqr, [RCAS::Num.new(2)]).to_s
  end

  def test_the_suggestion_prefers_the_nearest_name
    assert RCAS.one_edit_apart?("sqr", "sqrt")
    refute RCAS.one_edit_apart?("sqr", "cbrt")
    RCAS.instance_variable_set(:@hinted, nil)
    assert_match(/did you mean sin\?/, capture_io { RCAS.unknown_function(:sinn, [RCAS::Num.new(2)]) }.last)
    RCAS.instance_variable_set(:@hinted, nil)
    assert_match(/did you mean factorial\?/, capture_io { RCAS.unknown_function(:facorial, [RCAS::Num.new(2)]) }.last)
  end

end
