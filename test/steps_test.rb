# frozen_string_literal: true

require_relative "test_helper"

class StepsTest < Minitest::Test
  include RCAS::Constants

  X = RCAS::Var.new(:x)

  def text_of(derivation) = derivation.lines.map(&:text).join("\n")

  def test_the_rules_of_differentiation_are_named
    d = RCAS.steps(RCAS::Derivative.new(X**2 * RCAS.sin(X), X, 1))
    assert_includes text_of(d), "product rule"
    assert_includes text_of(d), "u = x**2 and v = sin(x)"
    assert_includes text_of(d), "power rule"
    assert_includes text_of(d), "d/du sin(u) = cos(u), from the table"
    assert_equal "2*x*sin(x) + x**2*cos(x)", d.result.to_s
  end

  def test_chain_and_quotient_rules
    chain = RCAS.steps(RCAS::Derivative.new(RCAS.sin(X**2 + 1), X, 1))
    assert_includes text_of(chain), "chain rule"
    assert_includes text_of(chain), "u = 1 + x**2"
    quotient = RCAS.steps(RCAS::Derivative.new(RCAS.exp(X) / X, X, 1))
    assert_includes text_of(quotient), "quotient rule"
  end

  # Whatever the working says, the answer is the one diff gives.
  def test_every_derivation_agrees_with_diff
    [X**3, X**2 * RCAS.sin(X), RCAS.exp(X) / X, RCAS.sin(X**2 + 1), RCAS.log(X) * X,
     1 / (1 + X**2), RCAS.sqrt(X), RCAS.exp(RCAS.sin(X)), 2**X, X**2 + 3 * X - 1].each do |f|
      d = RCAS.steps(RCAS::Derivative.new(f, X, 1))
      assert_equal f.diff(:x), d.result, "the working for #{f} ends somewhere else"
    end
  end

  def test_a_second_derivative
    d = RCAS.steps(RCAS::Derivative.new(X**2 * RCAS.sin(X), X, 2))
    assert_includes text_of(d), "the derivative number 2"
    assert_equal (X**2 * RCAS.sin(X)).diff(:x, 2), d.result
  end

  def test_integration_names_its_method
    parts = RCAS.steps { RCAS.integrate(:x * RCAS.exp(:x), :x) }
    assert_includes text_of(parts), "by parts with u = x and dv = exp(x) dx"
    substitution = RCAS.steps { RCAS.integrate(:x * RCAS.exp(:x**2), :x) }
    assert_includes text_of(substitution), "substitute u = x**2, so du = 2*x dx"
    table = RCAS.steps { RCAS.integrate(RCAS.sin(2 * :x + 1), :x) }
    assert_includes text_of(table), "from the table"
    assert_includes text_of(table), "divide by 2"
    power = RCAS.steps { RCAS.integrate(:x**3, :x) }
    assert_includes text_of(power), "power rule"
    logarithm = RCAS.steps { RCAS.integrate(1 / :x, :x) }
    assert_includes text_of(logarithm), "log(x)"
  end

  def test_every_antiderivative_agrees_with_integrate
    [X**3, X * RCAS.exp(X), RCAS.sin(2 * X + 1), X / (1 + X**2), RCAS.log(X),
     X * RCAS.exp(X**2), 1 / X, X**2 + 3 * X, RCAS.sin(X) * RCAS.cos(X)].each do |f|
      d = RCAS.steps(RCAS::Integral.new(f, X))
      assert_equal RCAS.integrate(f, :x), d.result, "the working for #{f} ends somewhere else"
    end
  end

  def test_an_integral_with_no_textbook_rule_says_so
    d = RCAS.steps(RCAS::Integral.new(1 / (X**4 + 1), X))
    assert_includes text_of(d), "no textbook rule"
    assert_equal RCAS.integrate(1 / (X**4 + 1), :x), d.result
  end

  def test_a_definite_integral_puts_in_the_ends
    d = RCAS.steps(RCAS::Integral.new(X**2, X, RCAS::Num.new(0), RCAS::Num.new(3)))
    assert_includes text_of(d), "put in the two ends"
    assert_equal 9, d.result
  end

  def test_solving_shows_the_formula_and_its_numbers
    d = RCAS.steps(X**2 - 5 * X + 6, :solve)
    assert_includes text_of(d), "a = 1, b = -5, c = 6"
    assert_includes text_of(d), "the discriminant b**2 - 4*a*c = 1"
    assert_equal [2, 3], d.result
    assert_includes text_of(RCAS.steps(2 * X + 6, :solve)), "a linear equation"
    assert_includes text_of(RCAS.steps(X**2 + X + 1, :solve)), "negative"
    assert_includes text_of(RCAS.steps(RCAS.eq(X**2, 4), :solve)), "everything on one side"
    assert_includes text_of(RCAS.steps(X**3 - X, :solve)), "degree 3"
    assert_equal RCAS.solve(X**3 - X, :x), RCAS.steps(X**3 - X, :solve).result
  end

  def test_partial_fractions_work_the_ansatz_out
    d = RCAS.steps(1 / (X**2 - 1), :apart)
    assert_includes text_of(d), "factor the denominator"
    assert_includes text_of(d), "the ansatz: (1)/(-1 + x**2) = A/(-1 + x) + B/(1 + x)"
    assert_includes text_of(d), "A = 1/2, B = -1/2"
    assert_equal RCAS.apart(1 / (X**2 - 1)), d.result

    repeated = RCAS.steps(1 / (X * (X + 1)**2), :apart)
    assert_includes text_of(repeated), "A/(1 + x) + B/(1 + x)**2 + C/x"
    quadratic = RCAS.steps((X + 1) / (X**3 + X), :apart)
    assert_includes text_of(quadratic), "(B + C*x)/(1 + x**2)", "an irreducible quadratic gets a linear numerator"
  end

  def test_elimination_lists_the_row_operations
    m = RCAS.matrix([[1, 2, 3], [4, 5, 6], [7, 8, 10]])
    d = RCAS.steps(m, :rref)
    assert_includes text_of(d), "R2 := R2 - (4)*R1"
    assert_includes text_of(d), "R2 := R2/(-3)"
    assert_equal m.rref, d.result
    assert_includes d.lines.last.text, d.result.to_s, "the working ends at the answer"
  end

  def test_euclid_on_numbers_and_polynomials
    d = RCAS.steps(1071, 462, :gcd)
    assert_includes text_of(d), "1071 = 2*462 + 147"
    assert_includes text_of(d), "462 = 3*147 + 21"
    assert_equal 21, d.result
    polynomials = RCAS.steps(X**4 - 1, X**2 - 1, :gcd)
    assert_equal RCAS.gcd(X**4 - 1, X**2 - 1), polynomials.result
  end

  def test_factoring_a_polynomial_hunts_for_roots
    d = RCAS.steps(X**3 - 2 * X**2 - 5 * X + 6, :factor)
    assert_includes text_of(d), "a rational root p/q has p dividing 6 and q dividing 1"
    assert_includes text_of(d), "f(-2) = 0, so 2 + x divides it"
    assert_includes text_of(d), "the quadratic 3 - 4*x + x**2"
    assert_equal (X**3 - 2 * X**2 - 5 * X + 6).factor, d.result
  end

  def test_the_shapes_that_have_their_own_name
    assert_includes text_of(RCAS.steps(X**2 - 9, :factor)), "a difference of squares"
    assert_includes text_of(RCAS.steps(3 * X**2 - 27, :factor)), "every term has 3 in it"
    assert_includes text_of(RCAS.steps(2 * X**3 + 4 * X**2, :factor)), "every term has 2*x**2 in it"
    assert_includes text_of(RCAS.steps(X**2 + X + 1, :factor)), "does not factor over the rationals"
    assert_includes text_of(RCAS.steps(X**4 + 1, :factor)), "no rational root"
    assert_includes text_of(RCAS.steps(X**2 - 2 * X * RCAS::Var.new(:y) + RCAS::Var.new(:y)**2, :factor)), "several variables"
  end

  def test_every_factorization_agrees_with_factor
    [X**2 - 9, X**3 - 1, 3 * X**2 - 27, 2 * X**3 + 4 * X**2, X**2 + X + 1, X**4 + 1,
     6 * X**2 - 5 * X + 1, X**4 - 1, X**3 - 2 * X**2 - 5 * X + 6].each do |f|
      assert_equal f.factor, RCAS.steps(f, :factor).result, "the working for #{f} ends somewhere else"
    end
  end

  def test_factoring_a_number_divides_by_the_primes
    d = RCAS.steps(360, :factor)
    assert_includes text_of(d), "360 = 2*180"
    assert_includes text_of(d), "45 = 3*15"
    assert_equal RCAS.factor(360), d.result
    assert_includes text_of(RCAS.steps(97, :factor)), "97 is prime"
    assert_includes text_of(RCAS.steps(-12, :factor)), "a minus sign comes out in front"
    assert_equal RCAS.factor(-12), RCAS.steps(-12, :factor).result
    # what trial division cannot finish says so, and rcas finishes it
    big = RCAS.steps(1_000_003 * 1_000_033, :factor)
    assert_includes text_of(big), "Pollard"
    assert_equal RCAS.factor(1_000_003 * 1_000_033), big.result
  end

  def test_the_block_form_and_printing
    d = RCAS.steps { RCAS.diff(:x**2, :x) }
    assert_equal "D(x**2, x)", d.problem.to_s
    assert_equal "2*x", d.result.to_s
    assert_equal ["D(x**2, x)", "  power rule (u**n)' = n*u**(n - 1)*u', with u = x and n = 2", "= 2*x"], d.to_s.lines.map(&:chomp)
    assert_includes RCAS::LaTeX.of(d), "\\begin{aligned}"
    assert_includes RCAS::LaTeX.of(d), "\\text{"
  end

  def test_bad_requests
    assert_raises(ArgumentError) { RCAS.steps }
    assert_raises(ArgumentError) { RCAS.steps(X**2, :integrate) }
    assert_raises(ArgumentError) { RCAS.steps(1071, :gcd) }
  end
end
