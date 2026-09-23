# frozen_string_literal: true

require_relative "test_helper"

class GroebnerTest < Minitest::Test
  include RCAS::Sets

  X = RCAS::Var.new(:x)
  Y = RCAS::Var.new(:y)
  Z = RCAS::Var.new(:z)

  def groebner(polys, vars = [:x, :y], order: :lex) = RCAS.groebner(polys, vars, order: order)
  def strings(polys) = polys.map(&:to_s)

  # Every generator and every S-polynomial reduces to zero modulo the basis.
  def assert_groebner(polys, basis, order = :lex)
    ring = basis.first.ring
    polys.each { |f| assert RCAS::Groebner.reduce(ring.call(f), basis, order).zero?, "#{f} does not reduce to 0" }
    basis.combination(2).each do |f, g|
      s = RCAS::Groebner.s_polynomial(f, g, order)
      assert RCAS::Groebner.reduce(s, basis, order).zero?, "S(#{f}, #{g}) does not reduce to 0"
    end
  end

  def test_lex_bases
    polys = [X**2 + Y**2 - 1, X - Y]
    basis = groebner(polys)
    assert_equal ["x - y", "-1/2 + y**2"], strings(basis)
    assert_groebner polys, basis

    polys = [X**2 + Y**2 + Z**2 - 1, X**2 + Z**2 - Y, X - Z] # [CLO15, ch. 2 §8]
    basis = groebner(polys, [:x, :y, :z])
    assert_equal ["x - z", "y - 2*z**2", "-1/4 + z**2/2 + z**4"], strings(basis)
    assert_groebner polys, basis

    polys = [X + Y + Z, X * Y + Y * Z + Z * X, X * Y * Z - 1] # cyclic-3
    basis = groebner(polys, [:x, :y, :z])
    assert_equal ["x + y + z", "y**2 + y*z + z**2", "-1 + z**3"], strings(basis)
    assert_groebner polys, basis
  end

  def test_orders_and_inputs
    assert_equal ["-1 + y**2", "x - y"], strings(groebner([X * Y - 1, Y**2 - 1], order: :grlex))
    assert_equal ["-y + x**2", "-x + y**2"], strings(groebner([X**2 - Y, Y**2 - X], order: :grevlex))
    assert_equal ["x - y**2", "-y + y**4"], strings(groebner([X**2 - Y, Y**2 - X], order: :lex))
    assert_equal ["x - y", "-1/2 + y**2"], strings(RCAS.groebner([X**2 + Y**2 - 1, X - Y])) # variables inferred, sorted
    ring = QQ[:x, :y]
    assert_equal ["x - y", "-1/2 + y**2"], strings(RCAS::Groebner.basis([ring.call(X**2 + Y**2 - 1), ring.call(X - Y)]))
    assert_equal ["1"], strings(groebner([X**2 + 1, X**2 - 1]))
    assert_equal [], RCAS::Groebner.basis([])
    assert_raises(ArgumentError) { groebner([X - Y], order: :degree) }
  end

  def test_parameters
    basis = groebner([X**2 - RCAS::Var.new(:a), X - Y])
    assert_equal ["x - y", "-a + y**2"], strings(basis)
    assert_equal "Frac(QQ[a])[x, y]", basis.first.ring.to_s
  end

  def test_normal_form_and_membership
    basis = groebner([X**2 + Y**2 - 1, X - Y])
    assert_equal "y", RCAS.reduce(X**3 + Y**3, basis, [:x, :y]).to_s
    assert_equal "y/2", RCAS.reduce(X**3, basis, [:x, :y]).to_s
    assert RCAS.reduce(X**2 - Y**2, basis, [:x, :y]).zero?
    assert RCAS.reduce((X - Y) * (X**5 + 3) + 7 * (X**2 + Y**2 - 1), basis, [:x, :y]).zero?
    refute RCAS.reduce(X + 1, basis, [:x, :y]).zero?
  end

  def test_dimension
    assert RCAS::Groebner.zero_dimensional?(groebner([X**2 + Y**2 - 1, X - Y]))
    refute RCAS::Groebner.zero_dimensional?(groebner([X * Y]))
    refute RCAS::Groebner.zero_dimensional?(groebner([X**2 + Y**2 - 1]))
  end

  def test_polynomial_systems
    sols = RCAS.solve([X**2 + Y**2 - 25, X + Y - 7], [X, Y])
    assert_equal "[{x=>4, y=>3}, {x=>3, y=>4}]", sols.inspect
    sols = RCAS.solve([X**2 - 1, Y - X, Z**2 - X], [X, Y, Z])
    assert_equal "[{x=>1, y=>1, z=>1}, {x=>1, y=>1, z=>-1}, {x=>-1, y=>-1, z=>-i}, {x=>-1, y=>-1, z=>i}]", sols.inspect
    sols = RCAS.solve([X**2 - Y, Y**2 - X], [X, Y])
    assert_equal 4, sols.size
    sols.each do |s|
      [X**2 - Y, Y**2 - X].each { |f| assert_in_delta 0.0, f.evalf(x: s[X].evalf, y: s[Y].evalf).abs, 1e-9 }
    end
    sols = RCAS.solve([X + Y + Z, X * Y + Y * Z + Z * X, X * Y * Z - 1], [X, Y, Z])
    assert_equal 6, sols.size
    sols.each do |s|
      [X + Y + Z, X * Y + Y * Z + Z * X, X * Y * Z - 1].each do |f|
        assert_in_delta 0.0, f.evalf(x: s[X].evalf, y: s[Y].evalf, z: s[Z].evalf).abs, 1e-9
      end
    end
    assert_equal [], RCAS.solve([X**2 + Y**2 - 1, X + Y - 3, X - Y], [X, Y])
    assert_equal "[{x=>0, y=>0}]", RCAS.solve([X * Y, X + Y], [X, Y]).inspect
    e = assert_raises(NotImplementedError, RCAS::Unsupported) { RCAS.solve([X * Y - 1], [X, Y]) }
    assert_match(/infinitely many solutions/, e.message)
  end

  def test_biquadratic_roots
    roots = RCAS.solve(X**4 - 4 * X**2 + 1, X)
    assert_equal ["-(2 + 3**(1/2))**(1/2)", "-(2 - 3**(1/2))**(1/2)", "(2 - 3**(1/2))**(1/2)", "(2 + 3**(1/2))**(1/2)"], roots.map(&:to_s)
    roots.each { |r| assert_in_delta 0.0, (r**4 - 4 * r**2 + 1).evalf.abs, 1e-12 }
    assert_equal ["-1", "-i", "1", "i"], RCAS.solve(X**4 - 1, X).map(&:to_s).sort
  end
end
