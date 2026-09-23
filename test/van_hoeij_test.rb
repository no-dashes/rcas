# frozen_string_literal: true

require_relative "test_helper"

# Van Hoeij's recombination (van_hoeij.rb). The answers are checked three
# ways: the lattice itself decides (not the subsets it falls back to), it
# agrees with Zassenhaus's subsets on every product tried, and the bounds
# the lattice rests on hold for the true factors.
class VanHoeijTest < Minitest::Test
  Dense = RCAS::Factor::Dense
  VanHoeij = RCAS::Factor::VanHoeij

  def setup
    @x = RCAS::Var.new(:x)
  end

  def sd(k, shift = 0) = RCAS::Poly.swinnerton_dyer(k, @x).subs(@x => @x + shift)
  def dense(f) = Dense.from_poly(RCAS::ZZ[:x].(RCAS.expand(f)))

  # the local factors of a squarefree primitive f modulo a good prime, and
  # the precision Zassenhaus would lift to
  def local(f)
    lc = f.last
    RCAS::NumberTheory.each_prime do |p|
      next if p == 2 || (lc % p).zero?
      fp = Dense.mod(f, p)
      next unless Dense.deg(Dense.gcd_mod(fp, Dense.derivative(fp), p)).zero?
      return [RCAS::Factor::Zassenhaus.cantor_zassenhaus(fp, p), p]
    end
  end

  # Swinnerton-Dyer polynomials are irreducible and split into quadratics
  # modulo every prime: the case the subsets are exponential in
  def test_the_lattice_proves_a_swinnerton_dyer_polynomial_irreducible
    [3, 4, 5].each do |k|
      f = dense(sd(k))
      modular, p = local(f)
      assert_operator modular.size, :>=, 2**(k - 1), "SD(#{k}) should split into many local factors"
      assert_equal [f], VanHoeij.recombine(f, modular, p, 1), "SD(#{k}) was not decided by the lattice"
    end
  end

  def test_the_lattice_groups_the_local_factors_of_a_product
    g = dense(sd(4))
    h = dense(sd(3, 1))
    f = Dense.mul(Dense.mul(g, h), [1, 0, 1])
    modular, p = local(f)
    found = VanHoeij.recombine(f, modular, p, 1)
    refute_nil found, "the lattice did not decide"
    assert_equal [[1, 0, 1], h, g].sort_by { |a| [Dense.deg(a), a] }, found
  end

  def test_both_recombinations_agree_on_products
    polys = [
      sd(4) * sd(4, 1),
      sd(3) * sd(3, 1) * sd(3, 2),
      sd(4) * (@x**3 - 2) * (@x**2 + @x + 1),
      (@x**2 - 2) * (@x**2 - 3) * (@x**2 - 5) * (@x**2 - 7) * (@x**2 - 11)
    ]
    polys.each do |f|
      assert_equal RCAS.factor(f, recombination: :zassenhaus), RCAS.factor(f, recombination: :van_hoeij), f.to_s[0, 60]
    end
  end

  def test_random_products_agree_and_multiply_back
    rng = Random.new(20260924)
    12.times do
      parts = Array.new(rng.rand(2..4)) { (0..rng.rand(2..6)).map { rng.rand(-9..9) }.tap { |c| c[-1] = rng.rand(1..5) } }
      f = parts.map { |c| c.each_with_index.map { |a, i| a * @x**i }.reduce(:+) }.reduce(:*)
      next if RCAS.expand(f) == 0
      vh = RCAS.factor(f, recombination: :van_hoeij)
      assert_equal RCAS.factor(f, recombination: :zassenhaus), vh, f.to_s
      assert RCAS::Scalar.zero?(RCAS.expand(vh.expand.to_expr - f)), "#{vh} does not multiply back to #{f}"
    end
  end

  # f*g'/g has integer coefficients below B_j for every true factor g
  def test_the_bounds_hold_for_true_factors
    g = dense(sd(3))
    h = dense(@x**3 - 5 * @x + 7)
    f = Dense.mul(g, h)
    bounds = VanHoeij.cld_bounds(f)
    [g, h, f].each do |factor|
      cld = Dense.mul(Dense.div_exact(f, factor), Dense.derivative(factor))
      cld.each_with_index { |c, j| assert_operator c.abs, :<=, bounds[j], "coefficient #{j}" }
    end
  end

  def test_every_root_lies_within_the_fujiwara_bound
    [[-6, 11, -6, 1], [1, 0, 0, 0, 0, 1], [576, 0, -960, 0, 352, 0, -40, 0, 1], [7, -3, 0, 2]].each do |f|
      radius = VanHoeij.root_bound(f)
      roots = RCAS::Solve.float_roots(f.map { |c| RCAS::Num.new(c.to_f) })
      assert_equal f.size - 1, roots.size
      roots.each { |z| assert_operator RCAS::Expression.lift(z).evalf.abs, :<=, radius, "#{f}: root #{z}" }
    end
  end

  # when the lattice does not decide, the subsets answer
  def test_an_undecided_lattice_falls_back_to_the_subsets
    VanHoeij.singleton_class.alias_method :__attempt, :attempt
    VanHoeij.define_singleton_method(:attempt) { |*| nil }
    f = sd(4) * sd(4, 1)
    assert_equal RCAS.factor(f, recombination: :zassenhaus), RCAS.factor(f, recombination: :van_hoeij)
  ensure
    VanHoeij.singleton_class.alias_method :attempt, :__attempt
  end

  # the outer choice reached the inner call only once the inner default
  # stopped resetting it to :auto (found while comparing the two)
  def test_the_old_method_is_used_when_asked_for
    VanHoeij.singleton_class.alias_method :__recombine, :recombine
    VanHoeij.define_singleton_method(:recombine) { |*| raise "van Hoeij was called" }
    f = sd(5)
    assert RCAS.factor(f, recombination: :zassenhaus).to_expr
    assert RCAS::ZZ[:x].(RCAS.expand(f)).factor(recombination: :zassenhaus)
    assert RCAS.expand(f).factor(recombination: :zassenhaus)
    assert_raises(RuntimeError) { RCAS.factor(f, recombination: :van_hoeij) }
  ensure
    VanHoeij.singleton_class.alias_method :recombine, :__recombine
  end

  def test_auto_takes_the_lattice_only_for_many_local_factors
    assert_equal :auto, RCAS::Factor.recombination
    refute RCAS::Factor.van_hoeij?(RCAS::Factor::VAN_HOEIJ_FROM - 1)
    assert RCAS::Factor.van_hoeij?(RCAS::Factor::VAN_HOEIJ_FROM)
    RCAS::Factor.with_recombination(:van_hoeij) { assert RCAS::Factor.van_hoeij?(2) }
    RCAS::Factor.with_recombination(:zassenhaus) { refute RCAS::Factor.van_hoeij?(100) }
    assert_raises(ArgumentError) { RCAS.factor(@x**2 - 1, recombination: :lll) }
  end
end
