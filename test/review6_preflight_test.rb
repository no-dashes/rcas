# frozen_string_literal: true

require_relative "test_helper"

# Before the sixth review: the round-4 and round-5 machinery attacked from
# the list the fifth review announced (REVIEW.md, section 4) and the one
# the reply added. Each test is a wrong answer that was found and fixed.
class Review6PreflightTest < Minitest::Test
  def setup
    @x, @a, @k = %i[x a k].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  # ---- Decide ---------------------------------------------------------------

  # gamma(x + 1) = x*gamma(x), so this is exactly 0; an ulp of error in the
  # argument next to the pole at -1 is a large error in gamma, and the
  # fallback slope 1e3*(|v| + 1) made the Float -8e11 look certain.
  def test_a_zero_next_to_a_pole_of_gamma_is_not_called_nonzero
    e = 10**-15r
    z = RCAS.gamma(n(-1 + e)) - RCAS.gamma(n(1 + e)) / (n(-1 + e) * n(e))
    refute_equal false, RCAS::Decide.zero?(z)
  end

  def test_a_sign_next_to_a_pole_is_not_guessed
    e = 10**-15r
    # gamma(-1 + e) is about -1/e + 1 - euler_gamma, so this is about +5e11
    refute_equal :negative, RCAS::Decide.sign(RCAS.gamma(n(-1 + e)) + 10**15 + 5 * 10**11)
    # zeta(1 + e) is about 1/e, so this is about +5e13
    refute_equal :negative, RCAS::Decide.sign(RCAS.zeta(n(1 + e)) - 95 * 10**13)
  end

  def test_evalf_with_no_digit_left_keeps_the_expression
    e = 10**-15r
    value = (RCAS.gamma(n(-1 + e)) + 10**15 + 5 * 10**11).evalf
    refute_kind_of Float, value
    assert_in_delta 0.6789385347077479, (RCAS.gamma(n(1/3r)) - 2).evalf, 1e-12
  end

  def test_decided_signs_away_from_the_poles_stay
    assert_equal :positive, RCAS::Decide.sign(RCAS.gamma(n(1/3r)) - 2)
    assert_equal :negative, RCAS::Decide.sign(RCAS.gamma(n(1/3r)) - 3)
  end

  # sin(30*pi*x) vanishes at every rational with denominator 2, 3, 5 or
  # 10, which is where the samples were; and one decided zero among poles
  # was enough for a true.
  def test_identically_zero_is_not_read_off_a_few_lucky_points
    assert_equal false, RCAS::Decide.identically_zero?(RCAS.sin(30 * RCAS::PI * @x))
    e = (@x - 53/2r) / ((@x - 19/3r) * (@x - 9/10r) * (@x - 69/10r))
    assert_equal false, RCAS::Decide.identically_zero?(e)
  end

  def test_identically_zero_still_proves_zeros
    assert_equal true, RCAS::Decide.identically_zero?(RCAS.gamma(1 - @a) / RCAS.gamma(-@a) + @a)
    assert_equal true, RCAS::Decide.identically_zero?(RCAS.sin(@x)**2 + RCAS.cos(@x)**2 - 1)
    assert_equal true, RCAS::Decide.zero?(RCAS.gamma(n(-42/5r)) / RCAS.gamma(n(-47/5r)) + n(47/5r))
  end

  def test_a_large_multiple_under_sin_does_not_stall_zero
    started = Time.now
    refute RCAS::Scalar.zero?(RCAS.sin(27720 * RCAS::PI * @x))
    assert_operator Time.now - started, :<, 5
    assert RCAS::Scalar.zero?(RCAS.sin(3 * @x) - 3 * RCAS.sin(@x) + 4 * RCAS.sin(@x)**3)
  end

  # ---- nsolve ---------------------------------------------------------------

  def test_a_logarithmic_pole_is_not_a_root
    f = -RCAS.sign(@x - 1) * RCAS.log(RCAS.abs(@x - 1))
    error = assert_raises(ArgumentError) { RCAS.nsolve(f, x: 0.5..1.5) }
    assert_match(/pole/, error.message)
  end

  def test_a_steep_jump_is_not_a_root
    f = RCAS.floor(@x) - n(1/2r) + 10**7 * (@x - 1)
    error = assert_raises(ArgumentError) { RCAS.nsolve(f, x: 0..3) }
    assert_match(/jump/, error.message)
  end

  def test_a_root_of_small_order_is_not_a_jump
    assert_in_delta 1.0, RCAS.nsolve(RCAS.surd(@x - 1, 51), x: 0..3), 1e-12
    assert_in_delta 1.0, RCAS.nsolve(RCAS.sign(@x - 1) * RCAS.abs(@x - 1)**(1/50r), x: 0..3), 1e-12
  end

  def test_a_crossing_at_zero_where_f_has_no_value
    assert_equal 0.0, RCAS.nsolve(@x * RCAS.log(RCAS.abs(@x)), x: -0.5..0.3)
    assert_raises(ArgumentError) { RCAS.nsolve(1 / @x, x: -1..1) }
    assert_in_delta 1e-20, RCAS.nsolve(@x - 10**-20, x: -1..1), 1e-35
  end

  # ---- definite integrals of an integrand that is complex on part of the range

  # log|u| is right only where the integrand is real: 1/sqrt(x**2 - 1)
  # over 0..1 is -i*pi/2, and it came out 0.
  def test_a_partly_complex_integrand_is_not_made_real
    [[1 / RCAS.sqrt(@x**2 - 1), 0, 1], [RCAS.sqrt(@x**2 - 1), 0, 2], [RCAS.log(@x), -1, 1],
     [1 / RCAS.sqrt(1 - @x**2), 0, 2]].each do |f, from, to|
      value = RCAS.integrate(f, @x, from, to)
      assert_kind_of RCAS::Integral, value, "#{f} over #{from}..#{to}"
    end
  end

  def test_a_real_integrand_still_takes_the_real_logarithm
    assert_equal "log(abs(cos(2))) - log(abs(cos(3)))", RCAS.integrate(RCAS.tan(@x), @x, 2, 3).to_s
    assert_equal "-log(2)", RCAS.integrate(1 / @x, @x, -2, -1).to_s
    assert_equal "pi/2", RCAS.integrate(1 / RCAS.sqrt(1 - @x**2), @x, 0, 1).to_s
  end

  # ---- solve ----------------------------------------------------------------

  def test_float_polynomials_keep_their_roots
    assert_equal [2.0], RCAS.solve(1.0 * @x**3 - 6.0 * @x**2 + 12.0 * @x - 8.0, @x).map(&:value)
    assert_equal 3, RCAS.solve(@x**3 - 2.0, @x).size
    assert_equal [0.0, 0.5], RCAS.solve(@x**3 - 0.5 * @x**2, @x).map(&:value)
    assert_equal 3, RCAS.solve(@x**3 - 1e-9 * @x, @x).size
  end

  def test_float_eigenvalues_with_small_scale_and_multiplicity
    small = RCAS.matrix([[1e-8, 0, 0], [0, 3e-8, 0], [0, 0, 5e-8]]).eigenvalues
    assert_equal [1e-8, 3e-8, 5e-8], small.map { |v| v.value.round(20) }
    close = RCAS.matrix([[1.0, 0, 0], [0, 1.000001, 0], [0, 0, 3.0]]).eigenvalues.map(&:value)
    assert_in_delta 1.0, close[0], 1e-9
    assert_in_delta 1.000001, close[1], 1e-9
    scalar = RCAS.matrix([[2.0, 0, 0], [0, 2.0, 0], [0, 0, 2.0]])
    assert_equal [2.0, 2.0, 2.0], scalar.eigenvalues.map(&:value)
    assert_equal 3, scalar.eigenvectors.first[1]
    jordan = RCAS.matrix([[3.0, 1, 0, 0], [0, 3.0, 1, 0], [0, 0, 3.0, 1], [0, 0, 0, 3.0]]).eigenvalues
    jordan.each { |v| assert_in_delta 3.0, v.value, 1e-12 }
    assert_equal "[1.0, -i, i]", RCAS.matrix([[0.0, -1.0, 0], [1.0, 0.0, 0], [0, 0, 1.0]]).eigenvalues.inspect
  end

  # the principal root reaches only the sector |arg| < pi/n
  def test_a_principal_root_does_not_take_negative_values
    assert_equal [], RCAS.solve(RCAS.exp(@x)**(1/3r) + 1, @x)
    assert_equal [], RCAS.solve(RCAS.sqrt(RCAS.exp(@x)) + 1, @x)
    assert_equal [], RCAS.solve(RCAS.sqrt(RCAS.sin(@x)) + 1, @x)
    assert_equal [], RCAS.solve(@x**(-1/2r) + 2, @x)
    assert_equal [n(Complex(-2, 2))], RCAS.solve(@x**(1/3r) - n(Complex(1, 1)), @x)
    assert_equal [n(8)], RCAS.solve(@x**(2/3r) - 4, @x)
  end

  def test_a_radical_equation_keeps_its_families
    assert_equal "[{2*i*pi*k | k in ZZ}]", RCAS.solve(RCAS.sqrt(RCAS.exp(@x)) - RCAS.exp(@x), @x).inspect
    assert_equal [], RCAS.solve(RCAS.sqrt(RCAS.exp(@x)) + RCAS.exp(@x), @x)
    assert_equal [n(0)], RCAS.solve(RCAS.sqrt(RCAS.exp(@x)) - RCAS.exp(@x), @x, domain: RCAS::RR)
  end

  def test_domain_rr_takes_the_real_members_of_every_family
    rr = RCAS::RR
    assert_equal [n(2)], RCAS.solve(n(-2)**@x - 4, @x, domain: rr)
    assert_equal [n(3)], RCAS.solve(n(-2)**@x + 8, @x, domain: rr)
    assert_equal [n(2)], RCAS.solve(n(-3)**@x - 9, @x, domain: rr)
    assert_equal [], RCAS.solve(n(-2)**@x - 3, @x, domain: rr)
    assert_equal "[-log(2)**(1/2), log(2)**(1/2)]", RCAS.solve(RCAS.exp(@x**2) - 2, @x, domain: rr).inspect
    assert_equal "[1/log(2)]", RCAS.solve(RCAS.exp(1 / @x) - 2, @x, domain: rr).inspect
    assert_equal [], RCAS.solve(RCAS.exp(1 / @x) + 2, @x, domain: rr)
    zeros = RCAS.solve(RCAS.sin(@x**2), @x, domain: rr)
    assert(zeros.all? { |z| z.is_a?(RCAS::ImageSet) && z.domain == RCAS::NN }, zeros.inspect)
  end

  def test_discuss_draws_no_complex_asymptotes
    report = RCAS.discuss(1 / (RCAS.exp(@x**2) - 2), @x).to_s
    assert_match(/x = -log\(2\)\*\*\(1\/2\), x = log\(2\)\*\*\(1\/2\)/, report)
    refute_match(/i\*pi/, report)
  end

  def test_the_real_part_of_a_quotient_is_split
    s = 2 * RCAS::PI * RCAS::I / (RCAS::I * RCAS::PI + RCAS.log(2))
    assert_equal "2*pi*log(2)/(pi**2 + log(2)**2)", RCAS::ComplexParts.im(s).to_s
  end

  # ---- special parameter values -------------------------------------------

  def test_special_values_of_a_whole_family
    found = RCAS.integrate(1 / (RCAS.sin(@a) * @x + 1), @x)
    assert_equal "piecewise(sin(a).eq(0) => x, :else => log(1 + x*sin(a))/sin(a))", found.to_s
    assert_equal "x", found.subs(@a => 2 * RCAS::PI).simplify.to_s
    assert_equal "piecewise(cos(a).eq(0) => x, :else => log(1 + x*cos(a))/cos(a))",
                 RCAS.integrate(1 / (RCAS.cos(@a) * @x + 1), @x).to_s
  end

  def test_no_branch_where_the_integrand_has_no_value
    assert_equal "(-(a*x) + a*x*log(a*x))/a", RCAS.integrate(RCAS.log(@a * @x), @x).to_s
    assert_equal "x**2/(2*(-1 + exp(a)))", RCAS.integrate(@x / (RCAS.exp(@a) - 1), @x).to_s
  end

  def test_a_condition_on_a_sum_prints_its_brackets
    pw = RCAS::Piecewise.new([[RCAS::Equation.new(RCAS.exp(@a) - 1, n(0)), @x], [RCAS::Piecewise::OTHERWISE, @a]])
    assert_equal "piecewise((exp(a) - 1).eq(0) => x, :else => a)", pw.to_s
  end

  # ---- printing -------------------------------------------------------------

  def test_a_scattered_set_prints_one_way
    assert_equal "{k | k in ZZ} ∩ ((-oo, 0) ∪ (0, oo))", RCAS.real_domain(n(-2)**@x + 1 / @x, @x).to_s
    assert_equal "(-oo, oo) \\ {-k | k in NN}", RCAS.real_domain(RCAS.gamma(@x), @x).to_s
    assert_equal "\\left(-\\infty, \\infty\\right) \\setminus \\left\\{ -k \\mid k \\in \\mathbb{N} \\right\\}",
                 RCAS::LaTeX.of(RCAS.real_domain(RCAS.gamma(@x), @x))
  end
end
