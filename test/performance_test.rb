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

  def test_long_alternating_sums_keep_their_signs
    alt = (1..100).map { |i| (i.even? ? -1 : 1) * :x**i }.sum
    s = alt.simplify
    assert_equal alt.call(x: 2), s.call(x: 2)
    assert_equal alt.expand.to_s, s.to_s
    assert_equal "x - x**2 + x**3", (:x - :x**2 + :x**3).simplify.to_s
  end
end
