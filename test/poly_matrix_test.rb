# frozen_string_literal: true

require_relative "test_helper"

# Evaluation/interpolation linear algebra for polynomial matrices
# (Horn 2008, chapter 6). The examples are 6.2 and 6.4 of the thesis.
class PolyMatrixTest < Minitest::Test
  include RCAS::Sets

  def setup
    @x = :x
    @m = QQ[:x].matrix([[1, @x**2], [@x**2 + 1, @x - 2]])
  end

  def teardown = RCAS.forget

  def test_det_example_6_2
    assert_equal "-2 + x - x**2 - x**4", @m.det.to_s
    assert_equal @m.det, RCAS::Elimination.cofactor_det(@m.entries).expand
  end

  def test_det_matches_cofactor_expansion
    srand(7)
    rnd = -> { (0..2).map { |k| rand(-5..5) * :x**k }.reduce(:+) }
    4.times do
      m = QQ[:x].matrix(Array.new(4) { Array.new(4) { rnd.call } })
      assert_equal RCAS::Elimination.cofactor_det(m.entries).expand, m.det
    end
  end

  def test_det_of_singular_and_special_shapes
    assert_equal "0", QQ[:x].matrix([[@x, @x], [1, 1]]).det.to_s
    assert_equal "0", QQ[:x].matrix([[@x, 0], [1, 0]]).det.to_s
    assert_equal "x", QQ[:x].matrix([[@x]]).det.to_s
    assert_equal "-y + x**2", QQ[:x, :y].matrix([[@x, :y], [1, @x]]).det.to_s # two variables: cofactor path
  end

  def test_rat_det_clears_denominators
    m = QQ[:x].fraction_field.matrix([[1 / @x, 1], [1, 1 / (@x + 1)]])
    assert_equal "(1 - x - x**2)/(x + x**2)", m.det.to_s
  end

  def test_solve_example_6_4
    y = @m.solve([@x - 1, @x + 1])
    assert_equal ["(-2 + 3*x + x**3)/(2 - x + x**2 + x**4)", "(-2 - x**2 + x**3)/(2 - x + x**2 + x**4)"], y.entries.map(&:to_s)
    residual = (@m * y).entries.zip([@x - 1, @x + 1]).map { |lhs, rhs| (lhs - rhs).cancel.to_s }
    assert_equal %w[0 0], residual
  end

  def test_solve_singular_falls_back_to_elimination
    assert_equal ["1", "0"], QQ[:x].matrix([[@x, @x], [1, 1]]).solve([@x, 1]).entries.map(&:to_s)
    assert_raises(RCAS::DomainError) { QQ[:x].matrix([[@x, @x], [1, 1]]).solve([1, 1]) }
  end

  def test_inverse
    inv = @m.inverse
    expected = [["(2 - x)/(2 - x + x**2 + x**4)", "x**2/(2 - x + x**2 + x**4)"],
                ["(1 + x**2)/(2 - x + x**2 + x**4)", "-1/(2 - x + x**2 + x**4)"]]
    assert_equal expected, inv.entries.map { |r| r.map(&:to_s) }
    assert_equal [%w[1 0], %w[0 1]], (@m * inv).entries.map { |r| r.map { |e| e.cancel.to_s } }
    assert_raises(RCAS::DomainError) { QQ[:x].matrix([[@x, @x], [1, 1]]).inverse }
  end

  def test_kernel
    k = QQ[:x].matrix([[@x, 1, @x**2], [1, @x, @x**3]])
    basis = k.kernel
    assert_equal 1, basis.size
    assert_equal "1", basis.first.entries.last.to_s
    assert (k * basis.first).entries.all? { |e| e.cancel.to_s == "0" }
    wide = QQ[:x].matrix([[@x, 1, 0, @x**2 + 1], [@x**2, @x, 1, 0], [1, 0, @x, 1]])
    basis = wide.kernel
    assert_equal 1, basis.size
    assert (wide * basis.first).entries.all? { |e| e.cancel.to_s == "0" }
  end

  def test_kernel_with_dependent_rows
    m = QQ[:x].matrix([[@x, 1, 0], [@x**2, @x, 0]])
    basis = m.kernel
    assert_equal 2, basis.size
    assert basis.all? { |v| (m * v).entries.all? { |e| e.cancel.to_s == "0" } }
    assert_equal [], QQ[:x].matrix([[@x, 1], [1, @x]]).kernel
  end

  def test_charpoly_through_interpolation
    a = RCAS.matrix([[1, 2, 0, 1], [3, 4, 1, 0], [0, 1, 1, 1], [2, 0, 1, 3]])
    assert_equal "-20 + 12*t + 17*t**2 - 9*t**3 + t**4", a.charpoly(:t).to_s
    assert_equal [2, 3], RCAS.matrix([[2, 0], [0, 3]]).eigenvalues
  end

  def test_internals
    pm = RCAS::PolyMatrix
    assert_equal [1r, 2r], pm.interpolate([0r, 1r], [1r, 3r]) # 1 + 2x
    assert_equal [-2r, 1r, -1r, 0r, -1r], pm.interpolate([0r, 1r, -1r, 2r, -2r], [-2r, -3r, -5r, -20r, -24r])
    assert_equal 4, pm.degree_bound([[[1r], [0r, 0r, 1r]], [[1r, 0r, 1r], [-2r, 1r]]])
    assert_equal(-1, pm.degree_bound([[[1r], []], [[1r], []]]))
    assert_equal 9r, pm.evaluate([1r, 2r, 1r], 2r) # 1 + 2*2 + 2**2
  end

  def test_performance
    srand(3)
    rnd = -> { (0..3).map { |k| rand(-9..9) * :x**k }.reduce(:+) }
    m = QQ[:x].matrix(Array.new(8) { Array.new(8) { rnd.call } })
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    d = m.det
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
    assert_equal 24, RCAS.degree(d, :x)
    assert_operator elapsed, :<, 2.0, "8x8 degree-3 determinant took #{elapsed.round(2)}s"
  end
end
