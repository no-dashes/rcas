# frozen_string_literal: true

require_relative "test_helper"

class FiniteFieldTest < Minitest::Test
  def gf(*a) = RCAS.GF(*a)

  def test_prime_field_elements
    f = gf(7)
    assert_equal "GF(7)", f.to_s
    assert_equal 7, f.order
    assert f.field?
    assert_equal [0, 1, 2, 3, 4, 5, 6], f.elements.map(&:to_i)
    assert_equal 3, f.call(10)
    assert_equal 4, f.call(Rational(1, 2))
    assert_equal 6, f.call(-1)
    a, b = f.call(3), f.call(5)
    assert_equal [1, 1, 2, 5, 4, 5, 6], [a + b, a * b, a / b, a**-1, a**100, a - 5, 2 * a].map(&:to_i)
    assert_equal 5, (1 / a).to_i
    assert a == 10
    assert_raises(ZeroDivisionError) { f.call(0).inverse }
    assert_equal "GF(7)", RCAS::Num.new(a).domain.to_s
    assert_nil (a * :x).domain, "x is undeclared"
  end

  def test_elements_promote_into_expressions
    f = gf(7)
    a = f.call(3)
    assert_equal "3*x + 1", (a * :x + 1).to_s
    assert_equal "x", (a * :x + f.call(5) * :x).simplify.to_s
    assert_equal "6*x**2", (a * :x * f.call(2) * :x).simplify.to_s
  end

  def test_structure
    f = gf(7)
    assert_equal 3, f.primitive_element.to_i
    assert_equal 3, f.log(6)
    assert_equal 6, f.call(3).order
    assert_equal 2, f.call(6).order
    assert_raises(ArgumentError) { gf(6) }
  end

  def test_polynomials_over_gf_p
    r = gf(7)[:x]
    f = r.call(:x**2 + 10 * :x + 1)
    assert_equal "1 + 3*x + x**2", f.to_s
    assert_equal "(1 + x)*(6 + x)", r.call(:x**2 - 1).factor.to_s
    assert_equal "(1 + x)*(2 + x)*(3 + x)*(4 + x)*(5 + x)*(6 + x)*x", r.call(:x**7 - :x).factor.to_s
    assert r.call(:x**2 + 1).irreducible?
    assert_equal [3, 4], r.call(:x**2 - 2).roots.map(&:to_i)
    assert_equal [2, 4], gf(7).solve(:x**2 + :x + 1, :x).map(&:to_i)
    assert_equal "1 + x", r.call(:x**2 - 1).gcd(:x**2 + 2 * :x + 1).to_s
    q, rem = r.call(:x**3).divmod(r.call(:x + 1))
    assert_equal "1 + 6*x + x**2", q.to_s
    assert_equal 6, rem
    assert_equal "(1 + x**2)**3", gf(3)[:x].call(:x**6 + 1).factor.to_s, "squarefree decomposition in characteristic 3"
    assert_equal "(1 + x)*x*(1 + x + x**3)*(1 + x**2 + x**3)", gf(2)[:x].call(:x**8 + :x).factor.to_s
    assert_equal "(5 + 2*x + 2*x**2 + x**3)*(8 + 2*x + 11*x**2 + x**3)", gf(13)[:x].call(:x**6 - 3 * :x**2 + 1).factor.to_s
    assert_equal "1", gf(2)[:x].call(:x**4 + :x**2 + 1).gcd(:x**2 + 1).to_s
  end

  def test_linear_algebra_over_gf_p
    f = gf(7)
    m = (f**[2, 2])[[1, 2], [3, 4]]
    assert_equal 5, m.det
    assert_equal "[5 1]\n[5 3]", m.inverse.to_s
    assert m * m.inverse == (f**[2, 2]).identity
    assert_equal 2, m.rank
    assert_equal "(5, 5)", m.solve([1, 0]).to_s
    assert_equal ["(5, 1)"], (f**[2, 2])[[1, 2], [2, 4]].kernel.map(&:to_s)
    assert_equal "5 + 2*x + x**2", m.charpoly.to_s
    assert_equal [], m.eigenvalues, "x**2 + 2x + 5 has no roots mod 7"
    assert_equal [2, 3], (f**[2, 2])[[2, 0], [0, 3]].eigenvalues.map(&:to_i).sort
    v = (f**3)[1, 2, 3]
    assert_equal 0, (v * v).to_i
    assert_equal "(5, 3, 1)", (5 * v).to_s
  end

  def test_extension_fields
    k = gf(8)
    assert_equal "GF(8)", k.to_s
    assert_equal [1, 1, 0, 1], k.modulus
    assert_equal 8, k.elements.size
    a = k.gen
    assert_equal "1 + a", (a**3).to_s
    assert_equal "1", (a**7).to_s
    assert_equal "1 + a**2", (a**-1).to_s
    assert_equal "a + a**2", k.call(:a**5 + 1).to_s
    assert_equal "a", k.primitive_element.to_s
    assert_equal 5, k.log(a**5)
    assert_equal 7, a.order
    assert_equal "1 + x + x**3", k.minpoly(a).to_s
    assert_equal "1 + x**2 + x**3", k.minpoly(a**3).to_s
    assert_equal "a**2", k.frobenius(a).to_s
    l = gf(9, :b)
    assert_equal [1, 0, 1], l.modulus
    assert_equal "2", (l.gen**2).to_s
    assert_equal "(2*b + x)*(b + x)", l[:x].call(:x**2 + 1).factor.to_s
    assert_equal "((a + a**2) + x)*(a + x)*(a**2 + x)", k[:x].call(:x**3 + :x + 1).factor.to_s
    assert_equal 8, k[:x].call(:x**8 - :x).factor.size
    m = (k**[2, 2])[[a, 1], [0, a]]
    assert_equal "a**2", m.det.to_s
    assert (m * m.inverse).identity?
    assert_equal "1 + a", gf(25).primitive_element.to_s
    assert_equal "(1 + a)*x + a", ((a + 1) * :x + a).to_s
  end
end
