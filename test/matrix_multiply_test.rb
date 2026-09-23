# frozen_string_literal: true

require_relative "test_helper"

# The matrix product (24 Sept 2026): Integer and Rational entries on the
# bare numbers, and Strassen's algorithm in Winograd's form beside the
# schoolbook product, so that the two can be compared.
class MatrixMultiplyTest < Minitest::Test
  include RCAS::Sets
  MM = RCAS::MatrixMultiply

  def random_rows(m, n, big = 9, rational: false)
    Array.new(m) { Array.new(n) { v = rand(-big..big); rational ? Rational(v, rand(1..6)) : v } }
  end

  # the product through Scalar, as Matrix#* computed it before
  def reference(a, b)
    MM::SCALAR.leaf(a.map { |r| r.map { |v| RCAS::Num.new(v) } }, b.map { |r| r.map { |v| RCAS::Num.new(v) } }).map { |r| r.map(&:value) }
  end

  def test_rational_matrices_multiply_on_the_bare_numbers_to_the_same_product
    srand 11
    [[3, 4, 5], [7, 7, 7], [1, 6, 2]].each do |m, k, n|
      a = random_rows(m, k, rational: true)
      b = random_rows(k, n, rational: true)
      assert_equal reference(a, b), MM.product(a, b, :schoolbook)
      assert_equal reference(a, b), (QQ**[m, k])[a].multiply((QQ**[k, n])[b]).entries.map { |r| r.map(&:value) }
    end
  end

  # every shape: odd dimensions are padded with zeros for one level, and a
  # cutoff of 1 sends the recursion all the way down
  def test_strassen_agrees_with_the_schoolbook_product_on_any_shape
    srand 12
    [[2, 2, 2], [5, 7, 3], [8, 1, 8], [9, 10, 11], [16, 16, 16]].each do |m, k, n|
      a = random_rows(m, k)
      b = random_rows(k, n)
      expected = MM::INTEGER.leaf(a, b)
      [1, 2, 3].each { |cutoff| assert_equal expected, MM.strassen(a, b, MM::INTEGER, cutoff), "#{m}x#{k}x#{n}, cutoff #{cutoff}" }
    end
    a = random_rows(6, 5, 10**40, rational: true)
    b = random_rows(5, 9, 10**40, rational: true)
    assert_equal reference(a, b), MM.product(a, b, :strassen)
  end

  def test_strassen_on_symbolic_entries_gives_the_same_matrix
    a = (ZZ[:a, :b, :c, :d]**[2, 2])[[:a, :b], [:c, :d]]
    b = (ZZ[:e, :f, :g, :h]**[2, 2])[[:e, :f], [:g, :h]]
    assert_equal a.multiply(b, algorithm: :schoolbook), a.multiply(b, algorithm: :strassen)
    assert_equal "[a*e + b*g a*f + b*h]\n[c*e + d*g c*f + d*h]", a.multiply(b, algorithm: :strassen).to_s
  end

  # the whole point: seven products for two 2x2 matrices, not eight
  def test_strassen_multiplies_two_by_two_matrices_with_seven_products
    a = (ZZ[:a, :b, :c, :d]**[2, 2])[[:a, :b], [:c, :d]]
    b = (ZZ[:e, :f, :g, :h]**[2, 2])[[:e, :f], [:g, :h]]
    counts = %i[schoolbook strassen].to_h do |algorithm|
      count = 0
      original = RCAS::Scalar.method(:mul)
      TestSupport.replacing(RCAS::Scalar, :mul, ->(x, y) { count += 1; original.call(x, y) }) { a.multiply(b, algorithm: algorithm) }
      [algorithm, count]
    end
    assert_equal({ schoolbook: 8, strassen: 7 }, counts)
  end

  def test_the_algorithm_is_chosen_for_a_block_and_restored_after_it
    assert_equal :auto, MM.algorithm
    MM.with_algorithm(:strassen) do
      assert_equal :strassen, MM.algorithm
      MM.with_algorithm(nil) { assert_equal :strassen, MM.algorithm }
    end
    assert_equal :auto, MM.algorithm
    assert_raises(ArgumentError) { MM.with_algorithm(:coppersmith) {} }
    assert_raises(ArgumentError) { MM.product([[1]], [[1]], :galactic) }
  end

  # :auto takes Strassen where it was measured to win: from 64 with entries
  # past a machine word, from 192 with small ones, never for symbols
  def test_auto_takes_strassen_only_where_it_wins
    small = ->(n) { Array.new(n) { Array.new(n, 7) } }
    large = ->(n) { Array.new(n) { Array.new(n, 10**30) } }
    refute MM.strassen?(small.(128), small.(128), :auto)
    assert MM.strassen?(small.(192), small.(192), :auto)
    refute MM.strassen?(large.(32), large.(32), :auto)
    assert MM.strassen?(large.(64), large.(64), :auto)
    refute MM.strassen?(large.(64), large.(64), :schoolbook)
    assert_equal MM::CUTOFF_LARGE, MM.cutoff_for(large.(4), small.(4))
    assert_equal MM::CUTOFF, MM.cutoff_for(small.(4), small.(4))
  end

  def test_empty_shapes
    product = (QQ**[2, 0]).zero * (QQ**[0, 3]).zero
    assert_equal [[0, 0, 0], [0, 0, 0]], product.entries.map { |r| r.map(&:value) }
    assert_equal [2, 3], [product.rows, product.cols]
    product = (QQ**[0, 2]).zero * (QQ**[2, 3]).zero
    assert_equal [0, 3], [product.rows, product.cols]
  end

  def test_matrix_times_vector_and_vector_times_matrix
    m = (QQ**[2, 3])[[1, 1/2r, 0], [2, 0, -1/3r]]
    v = (QQ**3)[6, 4, 3]
    assert_equal (QQ**2)[8, 11], m * v
    w = (QQ**2)[1/2r, 3]
    assert_equal (QQ**3)[13/2r, 1/4r, -1], w * m
  end

  # entries that are not Integer or Rational keep the old route, and a
  # Float product is the same Float sum in the same order
  def test_float_and_symbolic_entries_keep_the_scalar_route
    m = (RR**[2, 2])[[0.1, 0.2], [0.3, 0.4]]
    assert_equal [[0.1 * 0.1 + 0.2 * 0.3, 0.1 * 0.2 + 0.2 * 0.4], [0.3 * 0.1 + 0.4 * 0.3, 0.3 * 0.2 + 0.4 * 0.4]],
                 (m * m).entries.map { |r| r.map(&:value) }
    s = (ZZ[:x]**[2, 2])[[:x, 1], [0, :x]]
    assert_equal "[x**2  2*x]\n[   0 x**2]", (s * s).to_s
  end

  def test_rational_products_are_normalized
    product = (QQ**[1, 2])[[1/2r, 1/3r]] * (QQ**[2, 1])[[2], [3]]
    assert_equal 2, product[0, 0].value
    assert_kind_of Integer, product[0, 0].value
  end

  # powers go through the same product
  def test_powers
    f = (ZZ**[2, 2])[[1, 1], [1, 0]]
    assert_equal 354224848179261915075, (f**100)[0, 1].value
    assert_equal f**100, MM.with_algorithm(:strassen) { f**100 }
  end
end
