# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

# The third external review (23 Sept 2026, on 72c45e5): ten findings, each
# a wrong answer or a broken promise. The app race is test/js/app_race.js,
# run from app_test.rb; the chi-square cliff is in performance_test.rb.
class ReviewPeer3Test < Minitest::Test
  def setup
    @x, @y = %i[x y].map { |n| RCAS::Var.new(n) }
  end

  def teardown = RCAS.forget

  def n(v) = RCAS::Num.new(v)

  # ---- 1. certified digits never certify a zero -----------------------------

  def test_a_value_below_every_guard_is_not_certified_zero
    tiny = RCAS.exp(n(Rational(1, 10**1000))) - 1
    begin
      value = RCAS.evalf(tiny, 30)
      refute value.zero?, "exp(10**-1000) - 1 is positive"
    rescue RCAS::Precision::NoConvergence
      pass # honest: 600 guard digits cannot see 10**-1000
    end
  end

  def test_a_value_the_guard_reaches_is_computed
    assert_in_delta(-1.0, RCAS.evalf(RCAS.sin(RCAS::PI + n(Rational(1, 10**200))), 30).to_f * 1e200, 1e-12)
    assert_in_delta 1.0, RCAS.evalf(RCAS::Fn.new(:sin, [RCAS::PI]) + n(Rational(1, 10**200)), 30).to_f * 1e200, 1e-12
  end

  def test_a_proved_zero_is_still_zero
    assert RCAS.evalf(RCAS.sqrt(2) + RCAS.sqrt(3) - RCAS.sqrt(5 + 2 * RCAS.sqrt(6)), 30).zero?
    assert RCAS.evalf(RCAS.log(6) - RCAS.log(2) - RCAS.log(3), 30).zero?
  end

  def test_an_unproved_zero_is_refused
    identity = RCAS.atan(n(1/2r)) + RCAS.atan(n(1/3r)) - RCAS::PI / 4
    assert_raises(RCAS::Precision::NoConvergence) { RCAS.evalf(identity, 30) }
  end

  # ---- 2. exact ends of a numeric integral ----------------------------------

  def test_ends_one_float_apart_keep_their_width
    assert_in_delta 1.0, RCAS.nintegrate(1, :x, 10**20, 10**20 + 1), 1e-12
    assert_in_delta 1.0, RCAS.nintegrate(1, :x, 10**20, 10**20 + 1, digits: 30).to_f, 1e-12
    assert_in_delta 0.5, RCAS.nintegrate(@x - 10**20, :x, 10**20, 10**20 + 1), 1e-12
  end

  def test_a_width_below_the_floats_is_kept
    assert_in_delta 1.0, RCAS.nintegrate(10**400, :x, 0, Rational(1, 10**400), digits: 30).to_f, 1e-12
    assert_in_delta 1.0, RCAS.nintegrate(10**400, :x, 0, Rational(1, 10**400)), 1e-12
  end

  # ---- 3. complex least squares ---------------------------------------------

  def test_least_squares_uses_the_adjoint
    a = RCAS.matrix([[1], [2 * RCAS::I]])
    assert_equal [n(1/5r)], RCAS.least_squares(a, RCAS.vector(1, 0)).entries
    assert_equal [n(1/2r)], RCAS.least_squares(RCAS.matrix([[1], [RCAS::I]]), RCAS.vector(1, 0)).entries
  end

  # the residual is orthogonal to every column, in the Hermitian product
  def test_the_complex_residual_is_orthogonal_to_the_columns
    a = RCAS.matrix([[1, RCAS::I], [RCAS::I, 1], [1, 1]])
    b = RCAS.vector(1, 2 * RCAS::I, 0)
    z = RCAS.least_squares(a, b)
    r = RCAS.vector(*(a * z).entries.zip(b.entries).map { |p, q| (p - q).simplify })
    a.transpose.to_a.each { |column| assert RCAS::Scalar.zero?(RCAS::LinearAlgebra.dot(r, RCAS.vector(*column))) }
  end

  # ---- 4. mixed derivatives -------------------------------------------------

  def test_a_formal_derivative_depends_on_its_other_variables
    assert_equal n(1), RCAS.diff(RCAS.D(@x * @y, @x), @y)
    assert_equal n(1), RCAS.diff(RCAS.D(@x * @y, @y), @x)
    third = RCAS.diff(RCAS.D(RCAS.sin(@x * @y), @x, 2), @y)
    assert RCAS::Scalar.zero?(third - (-2 * @y * RCAS.sin(@x * @y) - @x * @y**2 * RCAS.cos(@x * @y)))
  end

  def test_an_unknown_function_depends_on_its_own_variable_only
    assert_equal n(0), RCAS.diff(RCAS.D(@y, @x), RCAS::Var.new(:t))
    formal = RCAS.diff(RCAS.D(RCAS.floor(@x * @y), @x), @y)
    assert_kind_of RCAS::Derivative, formal, "not 0: a derivative rcas cannot take stays formal"
  end

  # ---- 5. hold on every parser ----------------------------------------------

  def test_hold_keeps_the_block
    assert_equal "1/2", RCAS.hold { 1 / 2 }.to_s
    v = 3
    assert_equal "3/2", RCAS.hold { v / 2 }.to_s
  end

  # The route a Prism-compiled block takes (Ruby 3.4 and later by default):
  # the source cut out by the code location, parsed again. Asked directly,
  # so that it is tested under every Ruby.
  def test_the_source_of_a_block_is_found_by_its_code_location
    block = proc { 1 / 2 + :x }
    body = RCAS::Hold.reparsed_body(block)
    assert_equal "1/2 + x", RCAS::Hold::Builder.new(block.binding).build(body).to_s
    eval_block = eval("w = 7\n\nproc do\n  w / 5\nend", binding, "(rcas)", 40) # rubocop:disable Security/Eval
    body = RCAS::Hold.reparsed_body(eval_block)
    assert_equal "7/5", RCAS::Hold::Builder.new(eval_block.binding).build(body).to_s
  end

  def test_hold_refuses_a_block_without_source
    assert_raises(RCAS::Unsupported) { RCAS.hold(&:to_s) }
  end

  def test_hold_under_the_other_parser
    skip "--parser needs Ruby 3.4 (3.3's prism is experimental)" if RUBY_VERSION < "3.4"
    lib = File.expand_path("../lib", __dir__)
    Dir.mktmpdir do |dir|
      # a script file: code given with -e has no source to read back under Prism
      script = File.join(dir, "held.rb")
      File.write(script, "require \"rcas\"\nprint RCAS.hold { 1 / 2 }\n")
      %w[prism parse.y].each do |parser|
        out, status = Open3.capture2e(RbConfig.ruby, "--parser=#{parser}", "-I", lib, script)
        assert status.success?, out
        assert_equal "1/2", out.lines.last, parser
      end
    end
  end

  # ---- 6. real domains of constant powers -----------------------------------

  def test_a_constant_fractional_power_asks_for_a_base_that_is_not_negative
    assert_equal "[0, oo)", RCAS.real_domain(@x**0.5, @x).to_s
    assert_equal "[0, oo)", RCAS.real_domain(@x**RCAS::PI, @x).to_s
    assert_equal "[0, oo)", RCAS.real_domain(@x**RCAS.sqrt(2), @x).to_s
    assert_equal "(-oo, oo)", RCAS.real_domain(@x**2.0, @x).to_s
    assert_equal "(-oo, oo)", RCAS.real_domain(@x**RCAS.log(RCAS::E**2), @x).to_s
  end

  # ---- 7. distribution parameters -------------------------------------------

  def test_constants_that_cannot_be_parameters_are_refused
    assert_raises(ArgumentError) { RCAS.Exponential(-RCAS.sqrt(2)) }
    assert_raises(ArgumentError) { RCAS.Normal(0, RCAS::I) }
    assert_raises(ArgumentError) { RCAS.Normal(RCAS::I, 1) }
    assert_raises(ArgumentError) { RCAS.Binomial(10, RCAS::PI / 2) }
    assert_raises(ArgumentError) { RCAS.Binomial(RCAS.sqrt(2), 1/2r) }
    assert_raises(ArgumentError) { RCAS.Uniform(RCAS.sqrt(3), RCAS.sqrt(2)) }
    assert_raises(ArgumentError) { RCAS::Distributions::DiscreteUniform.new(1, RCAS.sqrt(2)) }
    assert_raises(ArgumentError) { RCAS::Distributions::DiscreteUniform.new(RCAS.sqrt(5), 1) }
    assert_equal "7/2", RCAS::Distributions::DiscreteUniform.new(1, 6).mean.to_s
  end

  def test_valid_constants_and_symbols_are_accepted
    assert_equal "2**(1/2)/2", RCAS.Exponential(RCAS.sqrt(2)).mean.to_s
    assert_equal "5*pi/2", RCAS.Binomial(10, RCAS::PI / 4).mean.to_s
    assert_equal "mu", RCAS.Normal(:mu, :sigma).mean.to_s
  end

  # ---- 8. vectors of different spaces ---------------------------------------

  def test_vectors_of_different_lengths_have_no_projection
    assert_raises(ArgumentError) { RCAS.project(RCAS.vector(1, 2), onto: RCAS.vector(1, 0, 3)) }
    assert_raises(ArgumentError) { RCAS.gram_schmidt([RCAS.vector(1, 2), RCAS.vector(1, 0, 3)]) }
    assert_raises(ArgumentError) { RCAS.least_squares(RCAS.matrix([[1], [2]]), RCAS.vector(1, 0, 3)) }
  end

  # ---- 10. the exact chi-square tail ----------------------------------------

  # the Integer sum over one common denominator; the timing is performance_test's
  def test_the_exponential_partial_sum_is_exact
    h = 7/3r
    assert_equal (0...9).sum { |m| h**m / (1..m).reduce(1, :*) }, RCAS::Distributions.exponential_partial_sum(h, 9)
    assert_equal 1, RCAS::Distributions.exponential_partial_sum(5r, 1)
  end
end
