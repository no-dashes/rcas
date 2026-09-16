# frozen_string_literal: true

require_relative "test_helper"

class DecompositionsTest < Minitest::Test
  include RCAS::Constants

  def m(rows) = RCAS.matrix(rows)

  def test_lu_with_a_row_swap
    a = m([[0, 1], [2, 3]])
    l, u, p = a.lu
    assert_equal "[1 0]\n[0 1]", l.to_s
    assert_equal "[2 3]\n[0 1]", u.to_s
    assert_equal (p * a).simplify, (l * u).simplify
    assert_equal a.det, (u[0, 0] * u[1, 1] * -1).simplify, "one swap flips the sign of the determinant"
  end

  def test_lu_without_a_swap
    a = m([[2, 1, 1], [4, -6, 0], [-2, 7, 2]])
    l, u, p = a.lu
    assert_equal p, p.space.identity
    assert_equal a, (l * u).simplify
    assert l.entries.each_with_index.all? { |row, i| row.each_with_index.all? { |e, j| j <= i || RCAS::Scalar.zero?(e) } }, "L is lower triangular"
    assert u.entries.each_with_index.all? { |row, i| row.each_with_index.all? { |e, j| j >= i || RCAS::Scalar.zero?(e) } }, "U is upper triangular"
  end

  def test_qr
    a = m([[1, 1], [1, 0]])
    q, r = a.qr
    assert_equal "[2**(1/2)/2  2**(1/2)/2]\n[2**(1/2)/2 -2**(1/2)/2]", q.to_s
    assert_equal a, (q * r).simplify
    assert_equal q.space.identity, (q.transpose * q).simplify, "the columns of Q are orthonormal"
    assert RCAS::Scalar.zero?(r[1, 0]), "R is upper triangular"
    assert_raises(ArgumentError) { m([[1, 2], [2, 4]]).qr }
  end

  def test_cholesky
    a = m([[4, 12], [12, 37]])
    l = a.cholesky
    assert_equal "[2 0]\n[6 1]", l.to_s
    assert_equal a, (l * l.transpose).simplify
    b = m([[2, 1], [1, 2]])
    assert_equal b, (b.cholesky * b.cholesky.transpose).simplify
    assert_raises(ArgumentError, "not symmetric") { m([[1, 2], [3, 4]]).cholesky }
    assert_raises(ArgumentError, "not positive definite") { m([[-1, 0], [0, 1]]).cholesky }
  end

  def test_diagonalize
    a = m([[1, 2], [2, 1]])
    p, d = a.diagonalize
    assert_equal "[3  0]\n[0 -1]", d.to_s
    assert_equal a, (p * d * p.inverse).simplify
    assert_raises(ArgumentError) { m([[1, 1], [0, 1]]).diagonalize }
  end

  def test_jordan_blocks
    a = m([[1, 1], [0, 1]])
    p, j = a.jordan
    assert_equal "[1 1]\n[0 1]", j.to_s
    assert_equal a, (p * j * p.inverse).simplify

    nilpotent = m([[0, 1, 0], [0, 0, 1], [0, 0, 0]])
    p, j = nilpotent.jordan
    assert_equal "[0 1 0]\n[0 0 1]\n[0 0 0]", j.to_s, "one chain of length three"
    assert_equal nilpotent, (p * j * p.inverse).simplify

    mixed = m([[5, 4, 2, 1], [0, 1, -1, -1], [-1, -1, 3, 0], [1, 1, -1, 2]])
    p, j = mixed.jordan
    assert_equal "[1 0 0 0]\n[0 2 0 0]\n[0 0 4 1]\n[0 0 0 4]", j.to_s
    assert_equal mixed, (p * j * p.inverse).simplify
  end

  def test_jordan_of_a_diagonalizable_matrix_is_diagonal
    a = m([[1, 2], [2, 1]])
    _, j = a.jordan
    assert_equal "[3  0]\n[0 -1]", j.to_s
  end

  def test_shapes_are_checked
    assert_raises(ArgumentError) { m([[1, 2, 3], [4, 5, 6]]).lu }
    assert_raises(ArgumentError) { m([[1, 2, 3], [4, 5, 6]]).jordan }
  end
end
