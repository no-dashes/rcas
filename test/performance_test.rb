# frozen_string_literal: true

require_relative "test_helper"

# Regression tests for inputs that used to blow the stack or take minutes.
class PerformanceTest < Minitest::Test
  include RCAS::Sets

  # A tripwire, not a benchmark: the bounds are generous enough for a slow
  # machine and would still catch a hundredfold regression, which the shape
  # assertions below would not. Allocations as well as time - though the
  # regression that got through this file was neither: a hash that grew
  # with the depth of the tree turned a 20 000-term sum into 390 MB of
  # bignums, which is *fewer* objects and only a few times slower. The size
  # of a node's hash is asserted directly below for that reason.
  def timed(limit, what, objects: nil)
    GC.start
    before = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocated = GC.stat(:total_allocated_objects) - before
    assert_operator elapsed, :<, limit, "#{what} took #{elapsed.round(2)} s"
    assert_operator allocated, :<, objects, "#{what} allocated #{allocated} objects" if objects
    result
  end

  def random_product(seed, max_degree, factors)
    rng = Random.new(seed)
    (1..factors).reduce(1) do |acc, _|
      acc * (0..rng.rand(1..max_degree)).map { |i| rng.rand(-20..20) * :x**i }.sum
    end
  end

  def test_expand_of_a_product_of_many_sums
    u = random_product(1, 10, 10)
    e = timed(2, "expand of a product of ten sums") { u.expand }
    poly = ZZ[:x].call(u)
    assert_operator poly.degree, :>, 30
    assert_equal poly.to_expr, e
    assert_equal poly.call(x: 3), u.call(x: 3)
  end

  def test_factor_recovers_the_product
    u = random_product(1, 6, 6)
    poly = ZZ[:x].call(u)
    fact = timed(5, "factoring a degree-30 product") { poly.factor }
    assert_equal poly, fact.expand
    assert_operator fact.size, :>=, 3
  end

  def test_factor_with_a_leading_coefficient_divisible_by_small_primes
    # every prime below 20 divides the leading coefficient 2*3*5*7*11*13*17*19
    lc = 9_699_690
    f = ZZ[:x].call((lc * :x**2 + 1) * (:x**3 - :x - 1))
    assert_equal "(1 + 9699690*x**2)*(-1 - x + x**3)", f.factor.to_s
  end

  def test_long_sums_stay_shallow
    # the building is inside the tripwire: that is where the hash
    # regression landed, and timing only the simplify let it through
    big = timed(3, "building a 20 000-term sum", objects: 1_500_000) { (1..20_000).map { |i| i * :x**i }.sum }
    assert_operator big.hash.bit_length, :<=, 64, "a node's hash is a fixnum, however deep the tree"
    s = timed(3, "simplify of a 20 000-term sum") { big.simplify }
    assert_equal 20_000, s.each_node.count { |n| n.is_a?(RCAS::Var) }
    assert s.to_s.start_with?("x + 2*x**2 + 3*x**3")
    assert_equal s, big.simplify
    assert_equal 20_000, big.to_poly.degree
    assert_equal (1..20_000).sum, s.call(x: 1)
    assert big.to_s.size > 100_000, "printing an unsimplified deep chain works too"
  end

  # The performance cliffs of the third review (22 Sept 2026), each tens
  # of seconds to minutes before and well under one now; the bounds are
  # generous, so only a return of the cliff fails.
  # Found by the fourth review (23 Sept 2026): a full-rank symbolic matrix
  # is decided at one point, the even chi-square cdf is a term recurrence,
  # and the Weierstrass integral's series coefficients are not zero-tested
  # in a number field when a Float already shows they are not 0.
  def test_the_fourth_reviews_slow_spots_stay_fast
    syms = (1..36).map { |i| RCAS::Var.new(:"a#{i}") }
    RCAS.assume(**syms.to_h { |s| [s.name, RCAS::QQ] }) do
      m = RCAS.matrix(Array.new(6) { |i| Array.new(6) { |j| syms[6 * i + j] } })
      timed(1, "rank of a generic 6x6") { assert_equal 6, m.rank }
    end
    timed(5, "ChiSquare(10**4).cdf(10**4)") { RCAS::Distributions::ChiSquare.new(10**4).cdf(10**4) }
    x = RCAS::Var.new(:x)
    timed(3, "integrate(1/(sin**4 + cos**4), x, 0, 2*pi)") do
      assert_equal "2*2**(1/2)*pi", RCAS.integrate(1 / (RCAS.sin(x)**4 + RCAS.cos(x)**4), x, 0, 2 * RCAS::PI).to_s
    end
  end

  # A Swinnerton-Dyer polynomial of degree 64 is irreducible and splits into
  # 32 quadratics modulo every prime: more than three minutes of subsets,
  # about three seconds of van Hoeij's lattice (24 Sept 2026). :auto has to
  # take the lattice here.
  def test_van_hoeij_recombines_what_the_subsets_cannot
    x = RCAS::Var.new(:x)
    f = RCAS::Poly.swinnerton_dyer(6, x)
    timed(30, "factor(Poly.swinnerton_dyer(6, x))") { assert RCAS::ZZ[:x].(f).factor.irreducible? }
  end

  # Two translated SD(5)s: 32 local factors, sixteen to each true factor.
  # More than two minutes of subsets, under three seconds of lattice; the
  # two factors have to be told apart after the handover, which SD(6),
  # with one factor, does not ask.
  def test_van_hoeij_groups_the_factors_of_translated_swinnerton_dyer_polynomials
    x = RCAS::Var.new(:x)
    sd = RCAS::Poly.swinnerton_dyer(5, x)
    f = RCAS::ZZ[:x].(RCAS.expand(sd * sd.subs(x => x + 1)))
    fact = timed(30, "factor(SD(5)*SD(5)(x + 1))") { f.factor }
    assert_equal 2, fact.size
    assert_equal f, fact.expand
  end

  def test_the_third_reviews_cliffs_stay_flat
    x = RCAS::Var.new(:x)
    y = RCAS::Var.new(:y)
    k = RCAS::Var.new(:k)
    timed(3, "expand_trig(sin(16*x))") { RCAS.expand_trig(RCAS.sin(16 * x)) }
    q = timed(3, "cancel of (x + y + 1)**12 over x + y + 1") { RCAS.cancel(RCAS.expand((x + y + 1)**12) / (x + y + 1)) }
    assert_equal RCAS::Num.new(0), RCAS.expand(q - (x + y + 1)**11)
    f = timed(3, "factor(x**210 - 1)") { RCAS.factor(x**210 - 1) }
    assert_equal RCAS::Num.new(0), RCAS.expand(f - (x**210 - 1))
    timed(3, "a direct sum of 3000 symbolic terms") { RCAS.sum(RCAS.sin(k), k, 1, 3000) }
    v = timed(3, "nintegrate(sin(1000*x), x: 0..1)") { RCAS.nintegrate(RCAS.sin(1000 * x), x: 0..1) }
    assert_in_delta (1 - Math.cos(1000)) / 1000, v, 1e-12
    a = RCAS::Var.new(:a)
    timed(3, "integrate(sin(a*x)*cos(x), x)") { RCAS.integrate(RCAS.sin(a * x) * RCAS.cos(x), x) }
    timed(3, "a sum whose dispersion needs a 10 x 10 resultant") { RCAS.sum((k**5 + 3 * k) / RCAS.factorial(k + 7), k, 0, RCAS::Var.new(:n)) }
    b = RCAS::Var.new(:b)
    c = RCAS::Var.new(:c)
    RCAS.assume(a: RCAS::RR, b: RCAS::RR, c: RCAS::RR) do
      m = RCAS.matrix([[a, 1, 0, b], [1, b, c, 0], [0, c, a, 1], [b, 0, 1, c]])
      timed(3, "refusing the eigenvalues of a 4 x 4 matrix with three parameters") do
        assert_raises(NotImplementedError, RCAS::Unsupported) { m.eigenvalues }
      end
    end
  end

  def test_long_alternating_sums_keep_their_signs
    alt = (1..100).map { |i| (i.even? ? -1 : 1) * :x**i }.sum
    s = alt.simplify
    assert_equal alt.call(x: 2), s.call(x: 2)
    assert_equal alt.expand.to_s, s.to_s
    assert_equal "x - x**2 + x**3", (:x - :x**2 + :x**3).simplify.to_s
  end
  # a product of Rational matrices is taken on the bare numbers: through
  # Scalar, every one of the n**3 products and sums built a Num, 1.16
  # million objects for this one where 12 thousand do (24 Sept 2026)
  def test_rational_matrix_products_do_not_build_a_node_per_product
    rng = Random.new(3)
    m = RCAS::Sets::QQ**[60, 60]
    a = m[Array.new(60) { Array.new(60) { Rational(rng.rand(-9..9), rng.rand(1..5)) } }]
    product = timed(2, "a 60 x 60 product over QQ", objects: 100_000) { a * a }
    assert_equal a.entries[7].zip(a.entries.map { |r| r[11] }).sum { |x, y| x.value * y.value }, product[7, 11].value
  end
  # the inverse of an integer matrix is taken modulo many primes: the
  # elimination over QQ built 2.6 million objects for this one, and the
  # primes build 125 thousand (24 Sept 2026)
  def test_integer_inverses_go_through_the_primes
    rng = Random.new(3)
    m = (RCAS::Sets::QQ**[40, 40])[Array.new(40) { Array.new(40) { rng.rand(-9..9) } }]
    inverse = timed(3, "the inverse of a 40 x 40 integer matrix", objects: 600_000) { m.inverse }
    assert_equal (RCAS::Sets::QQ**[40, 40]).identity, m * inverse
  end
end
