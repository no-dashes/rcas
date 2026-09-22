# Round 3: mathematical expectations, independently derived in PEER_REVIEW.md.
require_relative 'test_helper'
require 'rcas'

class ThirdReviewAdversarialTest < Minitest::Test
  def setup
    @x, @y, @t, @s, @a = %i[x y t s a].map { |n| RCAS::Var.new(n) }
  end
  def n(v) = RCAS::Num.new(v)

  def test_leibniz_substitution_must_avoid_variable_capture
    expected = (@x+Rational(1,2)).simplify
    assert_equal expected, nested_integral(@x).diff(@x).doit.simplify
  end

  def test_bound_variable_renaming_preserves_derivative
    assert_equal nested_integral(@s).diff(@x).doit.simplify,
                 nested_integral(@x).diff(@x).doit.simplify
  end

  def nested_integral(inner_var)
    inner = RCAS::Integral.new(@t+inner_var,inner_var,n(0),n(1))
    RCAS::Integral.new(inner,@t,n(0),@x)
  end

  def test_real_locus_can_contain_negative_root_arguments
    # Principal sqrt(-1)=i; i*sqrt(-1)=-1 is a real value.
    begin
      result = RCAS.real_domain(RCAS::I*RCAS.sqrt(@x),@x)
    rescue NotImplementedError
      return assert true
    end
    assert result.include?(-1), 'The correct real locus is (-infinity,0].'
  end

  def test_periodic_radius_has_positive_volume
    f = RCAS.cos(16*RCAS::PI*@x)
    # Integral_1^2 x*|cos(16*pi*x)| dx = 3/pi, hence V = 6.
    assert_equal n(6), RCAS.revolution_volume(f, x: 1..2, axis: :y)
  end

  def test_poles_prevent_a_global_sign_certificate
    f = 1 / ((@x-Rational(1,100))*(@x-Rational(1,50)))
    distance = RCAS::Analysis.distance(f,@x,0,1)
    assert_equal n(40_000), distance.subs(x: Rational(3,200)).simplify
  end

  def test_multivariate_norm_cannot_be_negative
    v = @x+@y-Rational(1,10)
    norm = RCAS::VectorCalculus.norm([v,0], [[@x,0,1],[@y,0,1]])
    assert_equal n(Rational(1,10)), norm.subs(x:0,y:0).simplify
  end

  def test_symbolic_cdf_bound_respects_support_after_substitution
    d=RCAS.Uniform(0,1)
    symbolic=d.probability(@x<=@a)
    assert_equal d.probability(@x<=2), symbolic.subs(a:2).simplify
  end

  def test_empty_range_has_zero_probability
    assert_equal n(0), RCAS.Uniform(0,1).probability(Rational(3,4)..Rational(1,4))
  end

  def test_nonzero_rescaling_preserves_polynomial_inflection
    assert_equal ['0'], RCAS.inflections(@x**17/10**300,@x).map(&:to_s)
  end

  def test_unsolved_curvature_must_not_be_reported_as_no_inflections
    # g=f''=2*cos(x)-x*sin(x), g(0)=2 and g(pi)=-2.
    # Returning an explicit refusal is acceptable; an empty solution list is not.
    begin
      result = RCAS.inflections(@x*RCAS.sin(@x),@x)
    rescue NotImplementedError
      return assert true
    end
    refute_empty result
  end

  def test_parameter_dependent_multiplicity_requires_a_condition
    begin
      result = RCAS::Analysis.inflections(@a*@x**3+@x**4,@x,points:[n(0)])
    rescue NotImplementedError
      return assert true
    end
    # The current array has no means of carrying the necessary a != 0 condition.
    refute_equal [n(0)], result
  end

  def test_implicit_complex_power_is_not_real_everywhere
    f = n(-1)**RCAS.sqrt(2)+@x
    begin
      result = RCAS.real_domain(f,@x)
    rescue NotImplementedError
      return assert true
    end
    assert_equal RCAS::RealSet.empty, result
  end
end
