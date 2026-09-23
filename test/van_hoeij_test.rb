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
    f = sd(4) * sd(4, 1)
    TestSupport.replacing(VanHoeij, :attempt, ->(*) {}) do
      assert_equal RCAS.factor(f, recombination: :zassenhaus), RCAS.factor(f, recombination: :van_hoeij)
    end
  end

  # the outer choice reached the inner call only once the inner default
  # stopped resetting it to :auto (found while comparing the two)
  def test_the_old_method_is_used_when_asked_for
    f = sd(5)
    TestSupport.replacing(VanHoeij, :recombine, ->(*, **) { raise "van Hoeij was called" }) do
      assert RCAS.factor(f, recombination: :zassenhaus).to_expr
      assert RCAS::ZZ[:x].(RCAS.expand(f)).factor(recombination: :zassenhaus)
      assert RCAS.expand(f).factor(recombination: :zassenhaus)
      assert_raises(RuntimeError) { RCAS.factor(f, recombination: :van_hoeij) }
    end
  end

  def test_only_auto_has_a_subset_budget
    assert_equal :auto, RCAS::Factor.recombination
    assert_equal RCAS::Factor::SUBSET_BUDGET, RCAS::Factor.subset_budget
    RCAS::Factor.with_recombination(:zassenhaus) { assert_nil RCAS::Factor.subset_budget }
    RCAS::Factor.with_recombination(:van_hoeij) { assert_nil RCAS::Factor.subset_budget }
    assert_raises(ArgumentError) { RCAS.factor(@x**2 - 1, recombination: :lll) }
  end

  # :auto tries subsets while the next size is cheap and hands the rest to
  # the lattice, with the local factors already lifted. A budget of 50 lets
  # the single factors through (about 15 of them) and stops at the pairs,
  # so the linear factor is found and taken out first - the cofactor and
  # its lifted factors must fit.
  def with_budget(budget)
    saved = RCAS::Factor::SUBSET_BUDGET
    RCAS::Factor.send(:remove_const, :SUBSET_BUDGET)
    RCAS::Factor.const_set(:SUBSET_BUDGET, budget)
    yield
  ensure
    RCAS::Factor.send(:remove_const, :SUBSET_BUDGET)
    RCAS::Factor.const_set(:SUBSET_BUDGET, saved)
  end

  def test_auto_hands_the_rest_to_the_lattice
    handed = []
    original = VanHoeij.method(:recombine)
    spy = lambda do |f, modular, p, k, lifted: nil|
      handed << [Dense.deg(f), modular.size, !lifted.nil?]
      original.call(f, modular, p, k, lifted: lifted)
    end
    f = sd(4) * sd(3, 1) * (@x - 3) * (@x**2 + 1)
    auto = TestSupport.replacing(VanHoeij, :recombine, spy) { with_budget(50) { RCAS.factor(f) } }
    refute_empty handed, "no handover"
    assert handed.all? { |_, _, lifted| lifted }, "the lifted factors were not passed on"
    assert_operator handed.first[0], :<, Dense.deg(dense(f)), "the linear factor should be taken out before the handover"
    assert_equal RCAS.factor(f, recombination: :zassenhaus), auto
  end

  def test_the_handover_agrees_on_random_products
    rng = Random.new(20260925)
    with_budget(10) do
      10.times do
        parts = [sd(3, rng.rand(-2..2))] + Array.new(rng.rand(1..3)) { (0..rng.rand(1..4)).map { rng.rand(-9..9) }.tap { |c| c[-1] = rng.rand(1..4) } }.map { |c| c.each_with_index.map { |a, i| a * @x**i }.reduce(:+) }
        f = parts.reduce(:*)
        assert_equal RCAS.factor(f, recombination: :zassenhaus), RCAS.factor(f), f.to_s[0, 80]
      end
    end
  end
end
