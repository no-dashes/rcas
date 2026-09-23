# frozen_string_literal: true

require_relative "test_helper"

# LLL lattice reduction (lattice.rb). Every answer is checked for what LLL
# promises - size-reduced, Lovasz's condition, the same lattice through a
# unimodular transformation - as well as for the exact rows where they are
# known.
class LatticeTest < Minitest::Test
  def n(v) = RCAS::Num.new(v)

  # the reduced basis is LLL-reduced and spans the same lattice
  def assert_reduction(basis, delta: RCAS::Lattice::DELTA)
    reduced, trans = RCAS.lll(basis, delta: delta, transform: true)
    assert RCAS::Lattice.reduced?(reduced, delta: delta), "not reduced: #{reduced.inspect}"
    assert_equal reduced, trans * basis, "U*B is not the reduced basis"
    assert_includes [n(1), n(-1)], trans.det, "U is not unimodular"
    assert trans.to_a.flatten.all? { |e| e.is_a?(RCAS::Num) && e.value.is_a?(Integer) }, "U has non-integer entries"
    reduced
  end

  def test_the_textbook_example
    lat = RCAS.matrix([[1, 1, 1], [-1, 0, 2], [3, 5, 6]])
    reduced = assert_reduction(lat)
    assert_equal [[0, 1, 0], [1, 0, 1], [-2, 0, 1]], reduced.to_a.map { |row| row.map(&:value) }
    assert_equal lat.det, reduced.det
  end

  def test_a_unimodular_basis_reduces_to_the_standard_one
    assert_equal [RCAS.vector(-1, 0), RCAS.vector(0, -1)], RCAS.lll([RCAS.vector(5, 3), RCAS.vector(8, 5)])
  end

  def test_random_lattices
    srand(20260923)
    [[2, 2], [3, 3], [4, 6], [6, 6], [10, 10]].each do |rows, cols|
      lat = RCAS.matrix(Array.new(rows) { Array.new(cols) { rand(-99..99) } })
      assert_reduction(lat)
      assert_reduction(lat, delta: 99/100r)
    end
  end

  # a basis of long, nearly parallel vectors, the case LLL exists for
  def test_a_skewed_basis_becomes_short
    lat = RCAS.matrix([[1, 0, 0, 10**6], [0, 1, 0, 2 * 10**6 + 1], [0, 0, 1, 3 * 10**6 - 1]])
    reduced = assert_reduction(lat)
    # the volume, about 3.7e6, is carried by the whole basis: two vectors
    # become short and the third takes up the rest
    shortest_before = lat.to_a.map { |r| r.sum { |e| e.value**2 } }.min
    first_after = reduced.to_a.first.sum { |e| e.value**2 }
    assert_operator first_after, :<, shortest_before / 10**10
  end

  def test_rational_entries
    reduced = RCAS.lll([RCAS.vector(1, 2/3r), RCAS.vector(3, 5)])
    assert RCAS::Lattice.reduced?(reduced)
    assert_equal [RCAS.vector(1, 2/3r), RCAS.vector(-1, 7/3r)], reduced
  end

  # the application of the manual: the minimal polynomial of
  # sqrt(2) + sqrt(3) from forty digits
  def test_an_integer_relation_from_a_decimal_expansion
    alpha = RCAS.evalf(RCAS.sqrt(2) + RCAS.sqrt(3), 40)
    big = (0..4).map { |i| (alpha**i * 10**20).round }
    rows = (0..4).map { |i| Array.new(5) { |j| i == j ? 1 : 0 } + [big[i]] }
    first = RCAS.lll(RCAS.matrix(rows)).to_a.first.map(&:value)
    assert_equal [1, 0, -10, 0, 1], first.first(5)
  end

  def test_the_method_on_a_matrix
    lat = RCAS.matrix([[1, 1, 1], [-1, 0, 2], [3, 5, 6]])
    assert_equal RCAS.lll(lat), lat.lll
  end

  def test_refusals
    assert_raises(ArgumentError) { RCAS.lll([RCAS.vector(1, 2), RCAS.vector(2, 4)]) }
    assert_raises(ArgumentError) { RCAS.lll([RCAS.vector(1, 2), RCAS.vector(1, 2, 3)]) }
    assert_raises(ArgumentError) { RCAS.lll([RCAS.vector(1, RCAS.sqrt(2)), RCAS.vector(0, 1)]) }
    assert_raises(ArgumentError) { RCAS.lll(RCAS.matrix([[1, 0], [0, 1]]), delta: 1/4r) }
    assert_raises(ArgumentError) { RCAS.lll(RCAS.matrix([[1, 0], [0, 1]]), delta: 2) }
    assert_raises(ArgumentError) { RCAS.lll([]) }
  end

  # (evalf(a, 40)*10**20).round was a Decimal, which LLL rightly refused:
  # Numeric#round without digits is an Integer everywhere else in Ruby
  def test_a_decimal_rounds_to_an_integer
    d = RCAS.evalf(RCAS::PI, 30)
    assert_equal 3, d.round
    assert_kind_of Integer, d.round
    assert_equal 314_159_265_358_979_323_846, (d * 10**20).round
    assert_kind_of RCAS::Decimal, d.round(3)
    assert_equal "3.142", d.round(3).to_s
  end
end
