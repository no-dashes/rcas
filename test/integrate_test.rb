# frozen_string_literal: true

require_relative "test_helper"

class IntegrateTest < Minitest::Test
  include RCAS::Sets

  X = RCAS::Var.new(:x)
  POINTS = [0.4, 0.9, 1.7].freeze

  # The antiderivative must be free of Integral nodes and its derivative must
  # agree numerically with the integrand.
  def antiderivative(f)
    f = RCAS::Expression.lift(f)
    result = f.integrate(:x)
    assert RCAS::Integrate.complete?(result), "unevaluated: #{result}"
    d = result.diff(:x)
    POINTS.each do |p|
      assert_in_delta f.evalf(x: p), d.evalf(x: p), 1e-8, "d/dx #{result} != #{f} at #{p}"
    end
    result
  end

  def sin(e) = RCAS.sin(e)
  def cos(e) = RCAS.cos(e)
  def exp(e) = RCAS.exp(e)
  def log(e) = RCAS.log(e)

  def test_table
    assert_equal "x**2/2", antiderivative(:x).to_s
    assert_equal "x + x**2 + x**3", antiderivative(3 * :x**2 + 2 * :x + 1).to_s
    assert_equal "(1 + 2*x)**6/12", antiderivative((2 * :x + 1)**5).to_s
    assert_equal "log(1 + 2*x)/2", antiderivative(1 / (2 * :x + 1)).to_s
    assert_equal "2*x**(3/2)/3", antiderivative(RCAS.sqrt(:x)).to_s
    assert_equal "exp(3*x)/3", antiderivative(exp(3 * :x)).to_s
    assert_equal "-cos(1 + 2*x)/2", antiderivative(sin(2 * :x + 1)).to_s
    assert_equal "-log(cos(x))", antiderivative(RCAS.tan(:x)).to_s
    assert_equal "-x + x*log(x)", antiderivative(log(:x)).to_s
    assert_equal "-log(1 + x**2)/2 + x*atan(x)", antiderivative(RCAS.atan(:x)).to_s
    assert_equal "2**x/log(2)", antiderivative(2**:x).to_s
    assert_equal "tan(x)", antiderivative(1 / cos(:x)**2).to_s
    assert_equal "x*y", (:y).to_expr.integrate(:x).to_s
  end

  def test_rational_functions
    assert_equal "atan(x)", antiderivative(1 / (:x**2 + 1)).to_s
    assert_equal "log(-1 + x)/2 - log(1 + x)/2", antiderivative(1 / (:x**2 - 1)).to_s
    assert_equal "log(1 + x**2)/2", antiderivative(:x / (:x**2 + 1)).to_s
    assert_equal "-1/(1 + x)", antiderivative(1 / (:x + 1)**2).to_s
    assert_equal "-1/x + 3*log(1 + x) - 2*log(x)", antiderivative((:x**3 + 1) / (:x**2 * (:x + 1)**2)).to_s
    assert_equal "log(1 + x**2)/2 - x**2/2 + x**4/4", antiderivative(:x**5 / (:x**2 + 1)).to_s
    assert_equal "x/(2*(1 + x**2)) + atan(x)/2", antiderivative(1 / (:x**2 + 1)**2).to_s
    antiderivative(1 / (:x**2 + 2))            # irrational atan
    antiderivative(1 / (:x**2 - 2))            # irrational logs
    antiderivative(1 / (:x**2 + :x + 1))
    antiderivative(1 / (:x**4 - 1))
    antiderivative((3 * :x + 2) / (:x**2 + 4 * :x + 5))
    antiderivative(1 / (:x**3 + 1))
    antiderivative(1 / (:x**3 - :x))           # several roots of the resultant
    antiderivative((:x**2 + 1) / (:x**4 + :x**2 + 1))
    antiderivative((:x**7 + 3) / ((:x**2 + 1)**2 * (:x - 2)**3))
  end

  def test_substitution_and_parts
    assert_equal "exp(x**2)/2", antiderivative(:x * exp(:x**2)).to_s
    assert_equal "-cos(x)**4/4", antiderivative(sin(:x) * cos(:x)**3).to_s
    assert_equal "-x**2/4 + x**2*log(x)/2", antiderivative(:x * log(:x)).to_s
    assert_equal "2*exp(x) - 2*x*exp(x) + x**2*exp(x)", antiderivative(:x**2 * exp(:x)).to_s
    assert_equal "sin(x) - x*cos(x)", antiderivative(:x * sin(:x)).to_s
    assert_equal "log(log(x))", antiderivative(1 / (:x * log(:x))).to_s
    assert_equal "log(x)**2/2", antiderivative(log(:x) / :x).to_s
    assert_equal "log(1 + exp(x))", antiderivative(exp(:x) / (1 + exp(:x))).to_s
    antiderivative(log(:x)**2)
    antiderivative(:x * RCAS.atan(:x))
    antiderivative(:x**3 * exp(:x**2))
    antiderivative(log(:x + 1))
    antiderivative(RCAS.sqrt(:x) * log(:x))
    antiderivative(exp(RCAS.sqrt(:x)) / RCAS.sqrt(:x))
  end

  def test_risch_norman_heuristic
    assert_equal "-(cos(x)*exp(x))/2 + exp(x)*sin(x)/2", antiderivative(exp(:x) * sin(:x)).to_s
    assert_equal "x/2 - cos(x)*sin(x)/2", antiderivative(sin(:x)**2).to_s
    assert_equal "sin(x) - sin(x)**3/3", antiderivative(cos(:x)**3).to_s
    assert_equal "exp(3*x)/3", antiderivative(exp(2 * :x) * exp(:x)).to_s
    assert_equal "exp(x)/(1 + x)", antiderivative(:x * exp(:x) / (:x + 1)**2).to_s
    antiderivative(sin(:x)**2 * cos(:x)**2)
    antiderivative(:x * exp(:x) * sin(:x))
    antiderivative(:x**2 * cos(2 * :x))
    antiderivative(RCAS.sinh(:x) * RCAS.cosh(:x))
    antiderivative(sin(:x) / cos(:x)**2)
    antiderivative(exp(:x) * (1 + :x) / :x**2 * :x**2)
  end

  def test_unevaluated_pieces_are_kept
    r = exp(-:x**4).integrate(:x)
    assert_kind_of RCAS::Integral, r
    assert_equal "integral(exp(-x**4), x)", r.to_s
    assert_equal exp(-:x**4), r.diff(:x)
    assert_equal "pi**(1/2)*erf(x)/2", exp(-:x**2).integrate(:x).to_s

    r = (exp(-:x**4) + :x).integrate(:x)
    assert_equal "integral(exp(-x**4), x) + x**2/2", r.to_s
    assert_equal "integral(log(x)/(1 + x), x)", (log(:x) / (1 + :x)).integrate(:x).to_s
  end

  # |u| and sign(u) for a linear u: sign is a constant on each side of the
  # root, and the antiderivative is made continuous there.
  def test_absolute_values_and_signs
    assert_equal "x**2*sign(x)/2", RCAS.integrate(RCAS.abs(:x), :x).to_s
    assert_equal "x*sign(x)", RCAS.integrate(RCAS.sign(:x), :x).to_s
    assert_equal "x**3*sign(x)/3", RCAS.integrate(:x * RCAS.abs(:x), :x).to_s
    assert_equal "sign(-1 + x)*(1/2 - x + x**2/2)", RCAS.integrate(RCAS.abs(:x - 1), :x).to_s
    assert_equal "x**2*sign(x)/2 + x**3/3", RCAS.integrate(RCAS.abs(:x) + :x**2, :x).to_s

    [RCAS.abs(X), RCAS.abs(2 * X + 3), X * RCAS.abs(X), RCAS.sign(X) * X**2, RCAS.abs(X) * RCAS.exp(X)].each do |f|
      g = f.integrate(:x)
      assert RCAS::Integrate.complete?(g), "unevaluated: #{g}"
      [-1.6, -0.3, 0.7, 2.2].each do |p|
        assert_in_delta f.evalf(x: p), g.diff(:x).evalf(x: p), 1e-8, "d/dx #{g} != #{f} at #{p}"
      end
    end

    # continuous across the root, so definite integrals over it are right
    assert_equal "1", RCAS.integrate(RCAS.abs(:x), x: -1..1).to_s
    assert_equal "5/2", RCAS.integrate(RCAS.abs(:x - 1), x: 0..3).to_s
    assert_equal "1", RCAS.integrate(RCAS.sign(:x), x: -1..2).to_s
    assert_equal "17/4", RCAS.integrate(RCAS.abs(:x)**3, x: -2..1).to_s
  end

  def test_by_parts_with_inverse_functions
    assert_equal "exp(-x**2)/pi**(1/2) + x*erf(x)", antiderivative(RCAS.erf(:x)).to_s
    assert_equal "-exp(-x**2)/pi**(1/2) + x*erfc(x)", antiderivative(RCAS.erfc(:x)).to_s
    assert_equal "-(1 + x**2)**(1/2) + x*log((1 + x**2)**(1/2) + x)",
                 antiderivative(log(:x + RCAS.sqrt(:x**2 + 1))).to_s
    antiderivative(:x * RCAS.erf(:x))
    # asin and acos are real only on [-1, 1], so check those there
    [X**2 * RCAS.asin(X), RCAS.acos(X), RCAS.asin(2 * X), X * RCAS.acos(X)].each do |f|
      g = f.integrate(:x)
      assert RCAS::Integrate.complete?(g), "unevaluated: #{g}"
      [-0.4, 0.15, 0.45].each { |p| assert_in_delta f.evalf(x: p), g.diff(:x).evalf(x: p), 1e-8, "d/dx #{g} != #{f} at #{p}" }
    end
  end

  # The Lazard-Rioboo-Trager step gives up when a root of the resultant has
  # degree three or more; a biquadratic denominator then goes through its real
  # quadratic factors instead.
  def test_real_quadratic_factors
    g = antiderivative(1 / (:x**4 + 1))
    assert_equal 2, g.each_node.count { |n| n.is_a?(RCAS::Fn) && n.name == :atan }
    assert_equal 2, g.each_node.count { |n| n.is_a?(RCAS::Fn) && n.name == :log }
    assert_equal "2**(1/2)*pi/4", RCAS.integrate(1 / (:x**4 + 1), x: 0..RCAS::OO).to_s

    [1 / (X**4 + 1), X**2 / (X**4 + 1), (X + 1) / (X**4 + 1), 1 / (X**6 + 1), 1 / (X**4 + 2),
     1 / (X**4 + 3 * X**2 + 1), 1 / (X**4 - 3 * X**2 + 1), X**2 / (X**4 + 3 * X**2 + 1),
     1 / ((X**2 + 1) * (X**4 + 1))].each { |f| antiderivative(f) }

    # the classic that needs the quartic denominator after t = sqrt(tan(x))
    f = RCAS.sqrt(RCAS.tan(:x))
    g = f.integrate(:x)
    assert RCAS::Integrate.complete?(g), "unevaluated: #{g}"
    [0.3, 0.9, 1.2].each { |p| assert_in_delta f.evalf(x: p), g.diff(:x).evalf(x: p), 1e-8 }

    # still out of reach, and honest about it
    assert_includes RCAS.integrate(1 / (:x**8 + 1), :x).to_s, "integral("
    assert_includes RCAS.integrate(1 / (:x**3 - 2), :x).to_s, "integral("
  end

  def test_root_of_a_ratio_of_linear_forms
    [RCAS.sqrt((1 - X) / (1 + X)), RCAS.sqrt(X / (1 - X)), RCAS.root((X + 1) / (X + 2), 3),
     1 / (X * RCAS.sqrt((1 - X) / (1 + X)))].each do |f|
      g = f.integrate(:x)
      assert RCAS::Integrate.complete?(g), "unevaluated: #{g}"
      [0.11, 0.37, 0.62].each { |p| assert_in_delta f.evalf(x: p), g.diff(:x).evalf(x: p), 1e-8, "d/dx #{g} != #{f} at #{p}" }
    end
  end

  def test_an_integrand_we_cannot_differentiate_stays_formal
    assert_equal "integral(floor(x), x)", RCAS.integrate(RCAS.floor(:x), :x).to_s
    assert_equal "integral(x*floor(x), x)", RCAS.integrate(:x * RCAS.floor(:x), :x).to_s
  end

  # F(b) - F(a) is the answer only where f is continuous. Without the split
  # at an interior pole, integrate(1/x**2, x, -1, 1) was -2: a negative area
  # under a positive integrand.
  def test_definite_integrals_split_at_interior_poles
    assert_equal "oo", RCAS.integrate(1 / X**2, X, -1, 1).to_s
    assert_equal "oo", RCAS.integrate(1 / X**2, X, -2, 3).to_s
    assert_equal "undefined", RCAS.integrate(1 / X**3, X, -1, 1).to_s, "+oo and -oo"
    assert_equal "undefined", RCAS.integrate(1 / X, X, -1, 1).to_s
    assert_equal "undefined", RCAS.integrate(RCAS.tan(X), X, 0, RCAS::PI).to_s
    assert_equal "undefined", RCAS.integrate(1 / (X - 3), X, 0, 5).to_s
    # the bounds the other way round are the same integral with a sign
    assert_equal "-oo", RCAS.integrate(1 / X**2, X, 1, -1).to_s
    assert_equal "-1/2", RCAS.integrate(1 / X**2, X, 2, 1).to_s
  end

  # An interval that avoids the pole is untouched, and a removable gap is
  # not a pole: sin(x)/x integrates across 0 as it always did.
  def test_definite_integrals_without_an_interior_pole
    assert_equal "1/2", RCAS.integrate(1 / X**2, X, 1, 2).to_s
    assert_equal "1", RCAS.integrate(1 / X**2, X, 1, RCAS::OO).to_s
    assert_equal "2", RCAS.integrate(1 / RCAS.sqrt(X), X, 0, 1).to_s
    assert_equal "log(2) - log(3)", RCAS.integrate(1 / (X - 3), X, 0, 1).to_s
    assert_equal "2*Si(1)", RCAS.integrate(RCAS.sin(X) / X, X, -1, 1).to_s, "Si is odd"
  end

  # log|u| is the real antiderivative of u'/u; log(u) sends an integral over
  # negative x into the complex numbers and it used to come back that way.
  # The parity of cos is what makes the symmetric tan integral come out.
  def test_a_real_integral_stays_real
    assert_equal "0", RCAS.integrate(RCAS.tan(X), X, -1, 1).to_s
    assert_equal "-log(2)", RCAS.integrate(1 / X, X, -2, -1).to_s
    assert_equal "log(1/2)", RCAS.integrate(1 / X, X, -1, -1r / 2).to_s
    assert_equal "0", RCAS.integrate(RCAS.tan(X), X, RCAS::PI * 3 / 4, RCAS::PI * 5 / 4).to_s
  end

  # "I cannot place the pole" has to reach the caller: the nil said so, but
  # the caller splatted it into the bounds list, where it vanished.
  def test_a_pole_we_cannot_place_keeps_the_integral_formal
    f = 1 / (X - RCAS.cos(X))
    assert_nil RCAS::Integrate.singular_points(f.simplify, X, RCAS::Num.new(0), RCAS::Num.new(2)),
               "x - cos(x) vanishes at 0.739 and Solve cannot name it"
    assert_equal [], RCAS::Integrate.singular_points(f.simplify, X, RCAS::Num.new(1), RCAS::Num.new(2)),
                 "and does not vanish between 1 and 2"
    assert_instance_of RCAS::Integral, RCAS.integrate(f, X, 0, 2)
  end

  # A product in the denominator vanishes where any factor does, even when
  # Solve can make nothing of the product: 1/(x*log(x)) over 1/2..2 spans
  # the pole at 1 and used to answer with a complex number.
  def test_poles_of_a_factored_denominator
    f = 1 / (X * RCAS.log(X))
    assert_equal "undefined", RCAS.integrate(f, X, 1r / 2, 2).to_s
    assert_equal "-log(log(2)) + log(log(3))", RCAS.integrate(f, X, 2, 3).to_s, "no pole between 2 and 3"
    assert_equal [3], RCAS::Integrate.singular_points((1 / ((X - 3) * RCAS.exp(X))).simplify, X,
                                                      RCAS::Num.new(0), RCAS::Num.new(5)).map { |r| r.value }
    assert_equal "undefined", RCAS.integrate(1 / (X * (X - 1)), X, 1r / 2, 3).to_s
    assert_equal "2*log(2) - log(3)", RCAS.integrate(1 / (X * (X - 1)), X, 2, 3).to_s
  end

  # The Weierstrass substitution puts tan(x/2) into the antiderivative,
  # which jumps at every odd multiple of pi although 1/(2 + cos(x)) is
  # smooth there: F(b) - F(a) over a whole period came back as 0, and over
  # half of one it carried tan(pi/2), which is not a value at all.
  def test_the_antiderivative_may_jump_where_the_integrand_does_not
    f = 1 / (2 + RCAS.cos(X))
    assert_equal "2*3**(1/2)*pi/3", RCAS.integrate(f, X, 0, 2 * RCAS::PI).to_s
    assert_equal "3**(1/2)*pi/3", RCAS.integrate(f, X, 0, RCAS::PI).to_s
    assert_equal "4*3**(1/2)*pi/3", RCAS.integrate(f, X, 0, 4 * RCAS::PI).to_s
    assert_equal "2*3**(1/2)*pi/3", RCAS.integrate(1 / (2 + RCAS.sin(X)), X, 0, 2 * RCAS::PI).to_s
    assert_in_delta 2 * Math::PI / Math.sqrt(3), RCAS.nintegrate(f, x: 0..2 * Math::PI), 1e-9
    # an interval that crosses no break is left alone
    assert_equal "2*3**(1/2)*atan(3**(1/2)*tan(1/2)/3)/3", RCAS.integrate(f, X, 0, 1).to_s
  end

  # An endpoint that substitutes to something undefined is not an answer.
  def test_an_undefined_endpoint_takes_the_limit
    refute RCAS::Integrate.defined_value?(RCAS.tan(RCAS::PI / 2))
    refute RCAS::Integrate.defined_value?(RCAS.log(RCAS::Num.new(0)))
    refute RCAS::Integrate.defined_value?(RCAS::UNDEFINED)
    assert RCAS::Integrate.defined_value?(RCAS.tan(RCAS::PI / 4))
    assert RCAS::Integrate.defined_value?((2 * X + 1).simplify)
  end

  def test_helpers
    assert_equal "x**3/3", RCAS.integrate(:x**2, :x).to_s
    assert_equal "x**2/2", (:x).to_expr.integrate(:x).to_s
    assert_equal "x/2 + x**3/3", QQ[:x].call(:x**2 + Rational(1, 2)).integrate.to_s
    assert_equal QQ[:x], ZZ[:x].call(:x**2).integrate.ring
    assert_in_delta Math.exp(0.5) * 0.5, (:x * exp(:x)).evalf(x: 0.5), 1e-12
    assert_raises(ArgumentError) { (:x**2).integrate(2) }
  end

  def test_canonical_form_improvements
    assert_equal "4*2**(1/2)", RCAS.sqrt(32).simplify.to_s
    assert_equal "exp(3*x)", (exp(2 * :x) * exp(:x)).simplify.to_s
    assert_equal "exp(2*x)", (exp(:x)**2).simplify.to_s
    assert_equal "1", (exp(:x) * exp(-:x)).simplify.to_s
    assert_equal "-2 - x", ((-4 - 2 * :x) / 2).simplify.to_s
    assert_equal "-atan(2 + x)", RCAS.atan(-2 - :x).simplify.to_s
    assert_equal "-sin(x)", sin(-:x).simplify.to_s
    assert_equal "cos(x)", cos(-:x).simplify.to_s
  end
end
