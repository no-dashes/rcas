# frozen_string_literal: true

# What came with the fifth review's design decisions (23 Sept 2026) beyond
# its own tests: the pieces a decision needed elsewhere, and the places it
# reached. Each assertion is the mathematics.
require_relative "test_helper"

class Review5FollowupsTest < Minitest::Test
  def setup
    @x, @y, @a, @k, @n = %i[x y a k n].map { |s| RCAS::Var.new(s) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  # ---- 2.1 surd -------------------------------------------------------------

  # The real root differentiates, typesets, infers and survives OpenMath;
  # an even root of a negative number has no value.
  def test_surd_is_a_function_like_the_others
    assert_equal "1/(3*surd(x, 3)**2)", RCAS.surd(@x, 3).diff(@x).to_s
    assert_equal "\\sqrt[3]{x}", RCAS::LaTeX.of(RCAS.surd(@x, 3))
    RCAS.assume(x: RCAS::RR) { assert_equal RCAS::RR, RCAS.surd(@x, 3).domain }
    assert_equal RCAS::UNDEFINED, RCAS.surd(-4, 2)
    assert_in_delta(-2.0, RCAS.surd(@x, 3).evalf(x: -8), 1e-15)
    assert_equal "-2.0", RCAS.surd(@x, 3).evalf(20, x: -8).to_s
    assert_equal RCAS.surd(@x, 3), RCAS.from_openmath(RCAS.openmath(RCAS.surd(@x, 3)).to_xml)
  end

  # discuss and plot of the principal root say where the real one is.
  def test_the_principal_root_points_at_surd
    note = "x**(1/3) has no real value where x < 0; surd(x, 3) is the real cube root"
    assert_includes RCAS.discuss(@x**n(1r / 3), @x).hints, note
    assert_includes RCAS.plot(@x**n(1r / 3), x: -2..2).notes, note
    assert_empty RCAS.plot(@x**n(1r / 3), x: 0..2).notes
  end

  # ---- 2.2 every subexpression real ----------------------------------------------

  # A scattered real domain is an answer: x**x, (-2)**x, gamma(x).
  def test_scattered_real_domains
    d = RCAS.real_domain(@x**@x, @x)
    assert d.include?(n(-1)) && d.include?(n(1r / 2))
    refute d.include?(n(-1r / 2))
    d = RCAS.real_domain(n(-2)**@x, @x)
    assert d.include?(n(3))
    refute d.include?(n(1r / 2))
    d = RCAS.real_domain(RCAS.gamma(@x), @x)
    refute d.include?(n(-2))
    assert d.include?(n(-5r / 2))
    assert_equal "(-oo, oo) \\ {-k | k in NN}", d.to_s
  end

  # A constant that is not real leaves an empty real domain, however the
  # value falls; a constant that simplifies to a real one does not.
  def test_every_subexpression_real
    assert_equal RCAS::RealSet.empty, RCAS.real_domain(@x * RCAS.log(-2), @x)
    assert_equal RCAS::RealSet.reals, RCAS.real_domain((1 + RCAS::I) * (1 - RCAS::I) * @x, @x)
  end

  # ---- 2.3 complete over CC -------------------------------------------------------

  # log of a negative number is its principal value, which solve needs.
  def test_the_logarithm_of_a_negative_number
    assert_equal (RCAS::I * RCAS::PI).simplify, RCAS.log(-1)
    assert_equal (RCAS.log(2) + RCAS::I * RCAS::PI).simplify, RCAS.log(-2)
  end

  # Several exponentials are powers of one: exp(x/2) and exp(x/3) of
  # exp(x/6); a fractional power of the atom would lose the branch.
  def test_exponentials_by_their_common_measure
    assert_equal [n(0)], RCAS.solve(RCAS.exp(@x / 2) + RCAS.exp(@x / 3) - 2, @x, domain: RCAS::RR)
    all = RCAS.solve(RCAS.exp(2 * @x) - 3 * RCAS.exp(@x) + 2, @x)
    all.each do |family|
      (-2..2).each do |k|
        v = family.at(k).evalf
        assert_in_delta 0, (Math::E**(2 * v) - 3 * Math::E**v + 2).abs, 1e-9, "#{family} at #{k}"
      end
    end
  end

  # domain: RR keeps the real members of a family with a complex step, and
  # a real function's discussion only real points.
  def test_real_members_of_complex_families
    assert_equal [], RCAS.solve(RCAS.exp(@x) + 1, @x, domain: RCAS::RR)
    report = RCAS.discuss(1 / (1 + RCAS.exp(@x)), @x)
    assert_empty report.gaps
    assert_kind_of RCAS::Expression, RCAS.integrate(1 / (1 + RCAS.exp(@x)), @x, 0, 1)
    refute_kind_of RCAS::Integral, RCAS.integrate(1 / (1 + RCAS.exp(@x)), @x, 0, 1)
  end

  # The logarithmic equations still combine their logarithms: the
  # candidates are verified against the equation.
  def test_a_logarithmic_equation_is_solved
    roots = RCAS.solve(RCAS::Equation.new(RCAS.log(@x) + RCAS.log(@x - 3), 1), @x)
    assert_equal 1, roots.size
    assert_in_delta (3 + Math.sqrt(9 + 4 * Math::E)) / 2, roots.first.evalf, 1e-12
  end

  # ---- 2.4 Karr ---------------------------------------------------------------

  def test_karr_on_the_formal_nodes_and_the_empty_product
    assert_equal n(1), RCAS.product(@k, @k, 3, 2)
    assert_in_delta 14.0, RCAS::Sum.new(@k**2, @k, n(1), n(3)).evalf, 1e-12
    assert_in_delta(-1.0 / 2, RCAS::Sum.new(1 / @k, @k, n(3), n(1)).evalf, 1e-12)
  end

  # ---- 2.5 coordinates ---------------------------------------------------------

  # A field names its coordinates by its component count; other names are
  # refused for every operator.
  def test_coordinates_of_fields
    u, v = %i[u v].map { |s| RCAS::Var.new(s) }
    assert_equal n(2), RCAS.divergence([u, v])
    %i[hessian laplacian].each do |name|
      assert_raises(ArgumentError) { RCAS.public_send(name, @x**2 * @a) }
    end
    assert_raises(ArgumentError) { RCAS.divergence([@x * @a, @y, @a]) }
  end

  # ---- 2.6 special parameter values ------------------------------------------------

  def test_special_values_of_other_antiderivatives
    f = RCAS.integrate(@a**@x, @x)
    assert_equal @x, f.subs(a: 1).simplify
    g = RCAS.integrate(RCAS.cos(@a * @x), @x)
    assert_equal @x, g.subs(a: 0).simplify
    assert_equal "log(a + x)", RCAS.integrate(1 / (@x + @a), @x).to_s # no special value
  end

  # ---- 2.7 logs -----------------------------------------------------------------

  # A positive factor splits off, what is not known stays inside.
  def test_log_rules_split_only_what_is_positive
    assert_equal "log(2) + log(x)", RCAS.expand_log(RCAS.log(2 * @x)).to_s
    assert_equal "log(x**2)", RCAS.expand_log(RCAS.log(@x**2)).to_s
    assert_equal "log(2*x)", RCAS.logcombine(RCAS.log(2) + RCAS.log(@x)).to_s
    RCAS.assume(@x < 0) { assert_equal "2*log(-x)", RCAS.expand_log(RCAS.log(@x**2)).to_s }
  end

  # ---- 2.8 domains ---------------------------------------------------------------

  # The domain makes no claim where there is no value, the matrix builder
  # asks whether an entry is real where it has one.
  def test_matrices_of_entries_with_removable_poles
    RCAS.assume(x: RCAS::RR) do
      assert_nil (1 / @x).domain
      assert_equal 1, RCAS.matrix([[1 / @x]]).rank
      assert_equal RCAS::RR, (1 / (@x**2 + 1)).domain
    end
  end
end
