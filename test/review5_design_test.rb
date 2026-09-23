# Round 5: the design questions, resolved as review/DESIGN_QUESTIONS.md
# recommends. Each test encodes the recommended behaviour, so every one
# fails on ebe57ae until the decision is implemented. The expectations are
# derived from the definitions, not from another CAS; the comparison with
# other systems is in DESIGN_QUESTIONS.md.
require_relative 'test_helper'
require 'rcas'

class Review5DesignTest < Minitest::Test
  def setup
    @x, @y, @a, @k = %i[x y a k].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)
  def third = n(Rational(1, 3))

  # The value of a constant as a Complex, or nil when it is not a number.
  def value(e)
    v = RCAS::Expression.lift(e).evalf
    v = v.value if v.is_a?(RCAS::Num)
    v.is_a?(Numeric) ? Complex(v) : nil
  rescue StandardError, Math::DomainError
    nil
  end

  def assert_value(expected, e, msg = nil)
    v = value(e)
    refute_nil v, "#{e.inspect} did not evaluate to a number #{msg}"
    assert_in_delta 0, (v - expected).abs, 1e-9, "#{e.inspect} = #{v}, expected #{expected} #{msg}"
  end

  # Points, and each family over its own parameter domain.
  def members(solutions, ks = -2..2)
    solutions.flat_map do |s|
      next [s] unless s.is_a?(RCAS::ImageSet)
      range = (s.domain == RCAS::NN ? (0..ks.max) : ks).to_a
      range.repeated_permutation(s.parameters.size).map { |values| s.at(*values) }
    end
  end

  def derivative_at(f, x0, h = 1e-6)
    (value(f.subs(x: x0 + h)) - value(f.subs(x: x0 - h))) / (2 * h)
  end

  def refused?
    yield
    false
  rescue RCAS::Unsupported, NotImplementedError, ArgumentError => e
    e
  end

  # ---- 1. odd roots: ** is principal, surd/cbrt are the real root ----------

  # surd(x, n) = -|x|**(1/n) for negative x and odd n (MuPAD, Maple): -2, 2, -2.
  def test_surd_is_the_real_odd_root
    assert_value(-2, RCAS.surd(-8, 3))
    assert_value(2, RCAS.surd(8, 3))
    assert_value(-2, RCAS.surd(-32, 5))
  end

  # cbrt is the name a student reaches for; it is surd(x, 3), as
  # Mathematica's CubeRoot is: cbrt(-8) = -2, cbrt(-27/8) = -3/2.
  def test_cbrt_is_the_real_cube_root
    assert_value(-2, RCAS.cbrt(-8))
    assert_value(Rational(-3, 2), RCAS.cbrt(Rational(-27, 8)))
  end

  # (-8)**(1/3) is the principal root 2*exp(i*pi/3) = 1 + i*sqrt(3), on the
  # Float path and on the arbitrary-precision path alike (today evalf(20)
  # gives the real root -2.0).
  def test_the_principal_power_is_the_same_on_every_evaluation_path
    e = n(-8)**third
    principal = Complex(1, Math.sqrt(3))
    assert_value principal, e
    v = begin
      d = e.evalf(20)
      d = d.value if d.is_a?(RCAS::Num)
      d.is_a?(Numeric) ? Complex(d.to_c.real.to_f, d.to_c.imaginary.to_f) : nil
    rescue RCAS::Unsupported, NotImplementedError
      nil # refusing to certify a complex value is acceptable; the real root is not
    end
    assert_in_delta 0, (v - principal).abs, 1e-12, "evalf(20) = #{v}" if v
  end

  # x**(1/3) is not real for x < 0 (principal branch); surd(x, 3) is real
  # everywhere, and surd(x, 3) = -2 at x = -8 only.
  def test_real_domain_and_solve_follow_the_root
    d = RCAS.real_domain(@x**third, @x)
    refute d.include?(n(-1)), "real_domain(x**(1/3)) = #{d} contains -1"
    assert d.include?(n(1))
    assert RCAS.real_domain(RCAS.surd(@x, 3), @x).include?(n(-8))
    assert_equal [n(-8)], RCAS.solve(RCAS.surd(@x, 3) + 2, @x)
    assert_equal [], RCAS.solve(@x**third + 2, @x) # principal root: never -2
  end

  # sqrt(x) is not real for x < 0, so i*sqrt(x) is a real function nowhere
  # (0 aside, where sqrt is real but i*0 is the real 0: the component rule
  # asks for i itself to be real, which it never is).
  def test_a_real_domain_needs_every_subexpression_real
    d = RCAS.real_domain(RCAS::I * RCAS.sqrt(@x), @x)
    assert d.respond_to?(:empty?) && d.empty?, "real_domain(i*sqrt(x)) = #{d.inspect}"
  end

  # exp(x) = 2 is solved by log(2) + 2*pi*i*k for every integer k; the
  # answer must contain the non-real members, and domain: RR only log(2).
  def test_an_exponential_equation_has_all_its_complex_solutions
    ms = members(RCAS.solve(RCAS.exp(@x) - 2, @x))
    vs = ms.map { |m| value(m) }
    assert vs.all? { |v| v && (Math::E**v - 2).abs < 1e-9 }, "not all solutions: #{ms.inspect}"
    assert vs.any? { |v| v.imaginary.abs > 1 }, "only the principal solution: #{ms.inspect}"
    real = RCAS.solve(RCAS.exp(@x) - 2, @x, domain: RCAS::RR)
    assert_equal 1, real.size
    assert_value Math.log(2), real.first
  end

  # exp(x) = -1 is solved by i*pi*(2k + 1); every member must be a number.
  def test_minus_one_as_an_exponential_has_its_family
    ms = members(RCAS.solve(RCAS.exp(@x) + 1, @x))
    vs = ms.map { |m| value(m) }
    assert vs.size >= 3 && vs.all? { |v| v && (Math::E**v + 1).abs < 1e-9 }, ms.inspect
  end

  # (-1)**x = exp(i*pi*x) = 2 for x = 2k - i*log(2)/pi: [] says "no solution",
  # which is false.
  def test_a_power_of_minus_one_equal_to_two_has_solutions
    ms = members(RCAS.solve(n(-1)**@x - 2, @x))
    refute_empty ms
    ms.each do |m|
      v = value(m)
      assert v && (Math::E**(Complex(0, Math::PI) * v) - 2).abs < 1e-9, "#{m.inspect} is no solution"
    end
  end

  # sum_{k=a}^{b} = -sum_{k=b+1}^{a-1} for b < a - 1 [Karr 1981]: from 3 to 1
  # that is -sum_{k=2}^{2}: -1/2 for 1/k, -4 for k**2, -sin(2) for sin(k).
  # b = a - 1 is the empty sum 0 under either convention.
  def test_reversed_sums_follow_karr_on_every_path
    assert_equal n(Rational(-1, 2)), RCAS.sum(1 / @k, @k, 3, 1)
    assert_equal n(-4), RCAS.sum(@k**2, @k, 3, 1)
    assert_value(-Math.sin(2), RCAS.sum(RCAS.sin(@k), @k, 3, 1))
    assert_value(-4, RCAS::Sum.new(@k**2, @k, n(3), n(1)))
    assert_equal n(0), RCAS.sum(@k, @k, @a, @a - 1).simplify
  end

  # The product twin: prod_{k=3}^{1} = 1/prod_{k=2}^{2}.
  def test_reversed_products_follow_karr
    assert_equal n(Rational(1, 2)), RCAS.product(@k, @k, 3, 1)
    assert_value(0.5, RCAS::Product.new(@k, @k, n(3), n(1)))
  end

  # In x**2 + a*y the name a is not a coordinate a student meant; without
  # vars: rcas refuses and names it. Fields in x, y, z alone, and explicit
  # lists, work as before.
  def test_a_parameter_is_not_taken_for_a_coordinate
    e = refused? { RCAS.gradient(@x**2 + @a * @y) }
    assert e, 'gradient(x**2 + a*y) answered instead of asking which names are coordinates'
    assert_match(/\ba\b/, e.message)
    assert refused? { RCAS.laplacian(@a**2 * @x**2) }, 'laplacian(a**2*x**2) differentiated by a'
    assert_equal [2 * @x, 2 * @y].map(&:to_s), RCAS.gradient(@x**2 + @y**2).to_a.map(&:to_s)
    assert_equal [2 * @x, @a].map { |c| c.simplify.to_s }, RCAS.gradient(@x**2 + @a * @y, [@x, @y]).to_a.map(&:to_s)
  end

  # The generic antiderivative of sin(a*x)*cos(x) divides by 1 - a and 1 + a;
  # at a = 1 the integrand is sin(x)*cos(x) and an antiderivative must still
  # come out (sin(x)**2/2 up to a constant). The same for x**a at a = -1
  # (log(x)).
  def test_an_antiderivative_covers_the_special_parameter_values
    f = RCAS.integrate(RCAS.sin(@a * @x) * RCAS.cos(@x), @x)
    [1, -1, 2].each do |a0|
      g = f.subs(a: a0).simplify
      expected = Math.sin(a0 * 0.7) * Math.cos(0.7)
      assert_in_delta expected, derivative_at(g, 0.7).real, 1e-5, "a = #{a0}: #{g.inspect}"
    end
    g = RCAS.integrate(@x**@a, @x).subs(a: -1).simplify
    assert_in_delta 1 / 1.3, derivative_at(g, 1.3).real, 1e-5, "a = -1: #{g.inspect}"
  end

  # generic: true keeps the short answer (MuPAD's IgnoreSpecialCases).
  def test_the_generic_answer_is_available_on_request
    f = RCAS.integrate(RCAS.sin(@a * @x) * RCAS.cos(@x), @x, generic: true)
    refute_kind_of RCAS::Piecewise, f
    g = f.subs(a: 2).simplify
    assert_in_delta Math.sin(1.4) * Math.cos(0.7), derivative_at(g, 0.7).real, 1e-5
  end

  # At x = y = -1: log(x) + log(y) = 2*i*pi, log(x*y) = log(1) = 0; and
  # log(x**2) = 0 while 2*log(x) = 2*i*pi. Without assumptions the rules must
  # keep the value; with positive x, y or with force: true they apply.
  def test_log_rules_keep_the_value_without_assumptions
    c = RCAS.logcombine(RCAS.log(@x) + RCAS.log(@y))
    assert_value Complex(0, 2 * Math::PI), c.subs(x: -1, y: -1)
    e = RCAS.expand_log(RCAS.log(@x**2))
    assert_value 0, e.subs(x: -1)
  end

  def test_log_rules_apply_under_positivity_or_on_request
    RCAS.assume(@x > 0, @y > 0) do
      assert_equal 'log(x*y)', RCAS.logcombine(RCAS.log(@x) + RCAS.log(@y)).to_s
    end
    assert_equal 'log(x*y)', RCAS.logcombine(RCAS.log(@x) + RCAS.log(@y), force: true).to_s
    assert_equal '2*log(x)', RCAS.expand_log(RCAS.log(@x**2), force: true).to_s
  end

  # 1/x has no value at x = 0, which RR contains; as for x in NN, rcas makes
  # no claim until x != 0 is known (SymPy: is_real is None).
  def test_no_domain_claim_where_the_expression_has_no_value
    RCAS.assume(x: RCAS::RR) do
      d = (1 / @x).domain
      refute d && d <= RCAS::RR, "1/x for x in RR inferred as #{d}"
    end
    RCAS.assume(@x > 0) do
      d = (1 / @x).domain
      assert d && d <= RCAS::RR, "1/x for x > 0 is real, got #{d.inspect}"
    end
  end
end
