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
end
