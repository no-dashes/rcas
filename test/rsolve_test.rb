# frozen_string_literal: true

require_relative "test_helper"

class RsolveTest < Minitest::Test
  N = RCAS::Var.new(:n)

  def u(arg) = RCAS::Fn.new(:u, [arg])
  def rsolve(lhs, rhs, **opts) = RCAS.rsolve(RCAS::Equation.new(lhs, rhs), :u, :n, **opts)

  # The closed form satisfies the recurrence for n = 0..5 (constants set to 1).
  def assert_recurrence(lhs, rhs, solution, **init)
    assert_equal "u(n)", solution.lhs.to_s
    f = solution.rhs.subs(C1: 1, C2: 1, C3: 1)
    values = ->(k) { f.evalf(n: k) }
    (0..5).each do |k|
      pattern = { u(N + 2) => values.call(k + 2), u(N + 1) => values.call(k + 1), u(N) => values.call(k), N => k }
      l = lhs.subs(pattern).evalf
      r = RCAS::Expression.lift(rhs).subs(pattern).evalf
      assert_in_delta l, r, 1e-9 * [1, l.abs].max, "#{solution} fails at n = #{k}"
    end
    init.each { |k, v| assert_in_delta v, values.call(k), 1e-9 }
  end

  def test_homogeneous
    sol = rsolve(u(N + 2), u(N + 1) + u(N))
    assert_equal "u(n) = C2*(1/2 + 5**(1/2)/2)**n + C1*(1/2 - 5**(1/2)/2)**n", sol.to_s
    assert_recurrence u(N + 2), u(N + 1) + u(N), sol
    assert_equal "u(n) = 2**n*C1", rsolve(u(N + 1), 2 * u(N)).to_s
    assert_equal "u(n) = C1 + C2*n", rsolve(u(N + 2), 2 * u(N + 1) - u(N)).to_s
    assert_equal "u(n) = (-i)**n*C1 + i**n*C2", rsolve(u(N + 2), -u(N)).to_s
    # u(n - 1) style shifts are renumbered
    assert_equal rsolve(u(N + 2), u(N + 1) + u(N)).to_s, rsolve(u(N), u(N - 1) + u(N - 2)).to_s
  end

  def test_initial_values
    sol = rsolve(u(N + 2), u(N + 1) + u(N), init: { 0 => 0, 1 => 1 })
    assert_equal "u(n) = 5**(1/2)*(1/2 + 5**(1/2)/2)**n/5 - 5**(1/2)*(1/2 - 5**(1/2)/2)**n/5", sol.to_s
    (0..10).each { |k| assert_in_delta RCAS.fibonacci(k).value, sol.rhs.evalf(n: k), 1e-9 }
    assert_equal "u(n) = 2**n*(1 + n)", rsolve(u(N + 2), 4 * u(N + 1) - 4 * u(N), init: { 0 => 1, 1 => 4 }).to_s
    assert_raises(ArgumentError) { rsolve(u(N + 1), 2 * u(N), init: { 0 => 1, 1 => 3 }) }
  end

  def test_forcing_terms
    cases = {
      [u(N + 1), 2 * u(N) + 1, { 0 => 0 }] => "u(n) = -1 + 2**n",
      [u(N + 1), u(N) + N, { 0 => 0 }] => "u(n) = -n/2 + n**2/2",
      [u(N + 1), 3 * u(N) + 2**N, {}] => "u(n) = -2**n + 3**n*C1",
      [u(N + 1), 2 * u(N) + 2**N, { 0 => 1 }] => "u(n) = 2**n + 2**n*n/2", # resonance
      [u(N + 2), u(N + 1) + u(N) + 1, { 0 => 0, 1 => 0 }] => nil
    }
    cases.each do |(lhs, rhs, init), expected|
      sol = rsolve(lhs, rhs, init: init)
      assert_equal expected, sol.to_s if expected
      assert_recurrence lhs, rhs, sol, **init
    end
  end

  def test_unsupported
    assert_raises(NotImplementedError) { rsolve(u(N + 1), N * u(N)) }
    assert_raises(NotImplementedError) { rsolve(u(N + 1), u(N)**2) }
    assert_raises(ArgumentError) { rsolve(u(N), 3) }
    assert_raises(NotImplementedError) { rsolve(u(2 * N), u(N)) }
  end
end
