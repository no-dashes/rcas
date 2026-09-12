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
    r = exp(-:x**2).integrate(:x)
    assert_kind_of RCAS::Integral, r
    assert_equal "integral(exp(-x**2), x)", r.to_s
    assert_equal exp(-:x**2), r.diff(:x)

    r = (exp(-:x**2) + :x).integrate(:x)
    assert_equal "integral(exp(-x**2), x) + x**2/2", r.to_s
    assert_equal "integral(sin(x)/x, x)", (sin(:x) / :x).integrate(:x).to_s
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
