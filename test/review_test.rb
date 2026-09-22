# frozen_string_literal: true

require_relative "test_helper"

# Every counterexample from the two reviews of September 2026, written as
# the reports wrote it and checked against the value the reports derived.
#
#   MATHEMATICAL_REVIEW.md  eight findings, ten examples (22 Sept 2026)
#   PEER_REVIEW.md          six findings, twelve examples (22 Sept 2026)
#
# The behaviour behind each is tested where it belongs - in analysis_test,
# distributions_test, simplify_test and the rest, with the boundaries and
# the cases that must not change. This file is the audit trail: one test
# per published example, so that a reader of either report can check the
# whole list without reading the library. Keep both: a finding that is only
# pinned by its own example is pinned by a number, not by a rule.
class ReviewTest < Minitest::Test
  X = RCAS::Var.new(:x)
  T = RCAS::Var.new(:t)
  A = RCAS::Var.new(:a)
  Z = 2 * RCAS::I * RCAS::PI

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  # ---- first review: MATHEMATICAL_REVIEW.md --------------------------------

  # 1. [P1] Powers of exp lose their complex branch.
  # exp(2*pi*i) = 1 and its principal square root is 1; the rewritten
  # exp(pi*i) is -1, so the two evaluation orders disagreed.
  def test_m1_powers_of_exp_keep_their_branch
    f = RCAS.sqrt(RCAS.exp(X))
    assert_equal "1", f.subs(x: Z).simplify.to_s
    assert_equal "1", f.simplify.subs(x: Z).simplify.to_s
  end

  # 2. [P1] log(exp(z)) was reduced to z without restriction.
  # log(exp(2*pi*i)) is log(1) = 0, not 2*pi*i.
  def test_m2_log_of_exp_keeps_its_branch
    f = RCAS.log(RCAS.exp(X))
    assert_equal "0", f.subs(x: Z).simplify.to_s
    assert_equal "0", f.simplify.subs(x: Z).simplify.to_s
  end

  # 3. [P1] The projection onto a subspace assumed orthogonality.
  # (1, 0) and (1, 1) span R**2, so the projection onto them is the
  # identity; the sum of the single projections gave (3/2, 1/2).
  def test_m3_projection_onto_a_spanning_pair
    assert_equal RCAS.vector(1, 0),
                 RCAS.project(RCAS.vector(1, 0), onto: [RCAS.vector(1, 0), RCAS.vector(1, 1)])
  end

  # 4. [P1] Parameter derivatives of definite integrals came back zero.
  # integral(x*t, t, 0, 1) is x/2, so the derivative is 1/2. The answer is
  # the formal integral of the parameter derivative, which the second
  # review accepted as the equivalent form (PEER_REVIEW.md, section 4).
  def test_m4_differentiating_under_the_integral_sign
    f = RCAS::Integral.new(X * T, T, n(0), n(1))
    assert_equal "integral(t, t, 0, 1)", f.diff(X).to_s
    assert_equal "1/2", f.diff(X).doit.simplify.to_s
  end

  # 5. [P1] probability ignored the left side of an inequality.
  # -X <= 0 holds for every X in [0, 1].
  def test_m5_probability_reads_the_whole_inequality
    assert_equal "1", RCAS.Uniform(0, 1).probability(-X <= 0).to_s
    assert_equal "1", RCAS.Uniform(0, 1).probability(2 * X <= n(2)).to_s
  end

  # 6. [P2] The inflection test was inverted where f''' vanishes.
  # x**4 has f'' = 12*x**2, positive on both sides: no inflection.
  # x**5 has f'' = 20*x**3, which changes sign: an inflection at 0.
  def test_m6_inflections_of_x4_and_x5
    assert_empty RCAS.inflections(X**4, X)
    assert_equal ["0"], RCAS.inflections(X**5, X).map(&:to_s)
  end

  # 7. [P2] Surfaces and shell volumes could come out negative.
  # The cylinder of radius and length one has surface 2*pi; the cylinder of
  # radius and height one has volume pi.
  def test_m7_revolution_radii_are_distances
    assert_equal "2*pi", RCAS.revolution_surface(-1, x: 0..1).to_s
    assert_equal "pi", RCAS.revolution_volume(1, x: -1..0, axis: :y).to_s
  end

  # 8. [P2] real_domain overlooked constant impossible conditions.
  # log(-1) is undefined over R, and x + i*pi is real for no real x.
  def test_m8_a_constant_condition_is_not_skipped
    assert_equal RCAS::RealSet.empty, RCAS.real_domain(RCAS.log(-1) + X, X)
  end

  # ---- second review: PEER_REVIEW.md ---------------------------------------

  # R1. [P1] Samples still justified a wrong geometric integrand.
  # The five samples at 1/6..5/6 all find x - 1/10 positive, but it is
  # negative on [0, 1/10). With f' = 1 the surface is
  # 2*pi*sqrt(2)*int_0^1 |x - 1/10| dx = 2*pi*sqrt(2)*(1/200 + 81/200),
  # and the shell volume is 2*pi*int_0^1 x*|x - 1/10| dx.
  def test_r1_a_line_is_enough_to_break_the_sampled_sign
    f = X - Rational(1, 10)
    assert_equal "41*2**(1/2)*pi/50", RCAS.revolution_surface(f, x: 0..1).to_s
    assert_equal "851*pi/1500", RCAS.revolution_volume(f, x: 0..1, axis: :y).to_s
  end

  # R2. [P1] The branch test admitted a value outside the principal strip.
  # im(u) = pi*(1 + 10**-20) is strictly greater than pi, so Log(exp(u)) is
  # u - 2*pi*i. The float comparison rounded it onto Math::PI.
  def test_r2_the_strip_edge_is_not_decided_by_a_float
    u = (RCAS::I * RCAS::PI * (1 + Rational(1, 10**20))).simplify
    refute RCAS::Functions.principal_log?(u)
    assert_equal "log(exp(#{u}))", RCAS.log(RCAS.exp(u)).simplify.to_s
  end

  # R3. [P1] Event normalisation skipped a random variable on the right.
  # X <= -X is X <= 0, of probability 1/2; X <= X holds always.
  def test_r3_the_variable_may_stand_on_the_right
    assert_equal "1/2", RCAS.Uniform(-1, 1).probability(X <= -X).to_s
    assert_equal "1", RCAS.Uniform(0, 1).probability(X <= X).to_s
  end

  # R4. [P1] The infinity handling did not reach every probability path.
  # Both events contain the whole support, so both probabilities are 1; an
  # infinite probability breaks 0 <= P(A) <= 1 on its own.
  def test_r4_an_infinite_bound_is_still_a_probability
    assert_equal "1", RCAS.Uniform(0, 1).probability(X <= RCAS::OO).to_s
    assert_equal "1", RCAS.Uniform(0, 1).probability(0..RCAS::OO).to_s
  end

  # R5. [P2] Inflections stayed wrong next to a nearby root.
  # f'' = x**2*(x - a): even multiplicity at 0, so only a is an inflection.
  # f'' = x**3*(x - a): both multiplicities odd, so both are.
  def test_r5_inflections_with_a_root_next_door
    a = Rational(1, 100_000)
    assert_equal ["1/100000"], RCAS.inflections(X**5 / 20 - a * X**4 / 12, X).map(&:to_s)
    assert_equal ["0", "1/100000"], RCAS.inflections(X**6 / 30 - a * X**5 / 20, X).map(&:to_s)
  end

  # R6. [P2] real_domain returned too large a set.
  # Under assume(a < 0) the logarithm has no real value at all; and for
  # real x, im(i*x) = x, so only x = 0 is left.
  def test_r6_parameters_and_complex_expressions
    RCAS.assume(A < 0) do
      assert_equal RCAS::RealSet.empty, RCAS.real_domain(RCAS.log(A) + X, X)
    end
    assert_equal "{0}", RCAS.real_domain(RCAS::I * X, X).to_s
  end

  # The counts above, so that a reader can check none has gone missing.
  def test_every_published_example_is_here
    examples = methods.grep(/\Atest_m\d/).size + methods.grep(/\Atest_r\d/).size
    assert_equal 8 + 6, examples, "eight findings in the first review, six in the second"
  end
end
