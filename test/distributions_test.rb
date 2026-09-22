# frozen_string_literal: true

require_relative "test_helper"

class DistributionsTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def test_normal
    n = RCAS.Normal(0, 1)
    assert_equal "Normal(0, 1)", n.to_s
    assert_equal "2**(1/2)*exp(-x**2/2)/(2*pi**(1/2))", n.pdf(X).to_s
    assert_equal "1/2 + erf(2**(1/2)*x/2)/2", n.cdf(X).to_s
    assert_in_delta 0.841344746068543, n.cdf(1).evalf, 1e-12
    assert_in_delta 1.959963984540054, n.quantile(0.975).value, 1e-9
    assert_equal "0", n.quantile(Rational(1, 2)).to_s
    assert_in_delta 0.6826894921370861, n.probability(-1..1).evalf, 1e-12
    # the upper tail as erfc, whose digits survive far out (third review, P-11)
    assert_equal "erfc(2**(1/2)/2)/2", n.probability(X > 1).to_s
    assert_equal ["0", "1", "0", "3"], [n.mean, n.variance, n.skewness, n.kurtosis].map(&:to_s)
    assert_equal ["1", "0", "3"], [n.moment(2), n.moment(3), n.moment(4)].map(&:to_s)
    assert_equal "1", n.expectation(X**2, X).to_s, "the Gaussian integral is done exactly"
    g = RCAS.Normal(:mu, :sigma)
    assert_equal "sigma**2", g.variance.to_s
    assert_equal "mu**2 + sigma**2", g.moment(2).to_s
    assert_equal "2**(1/2)*exp(-(-mu + x)**2/(2*sigma**2))/(2*pi**(1/2)*sigma)", g.pdf(X).to_s
    assert_equal '\mathrm{Normal}\left(0, 1\right)', n.to_latex
  end

  def test_uniform_and_exponential
    u = RCAS.Uniform(0, 1)
    assert_equal ["1/2", "1/12", "1/3", "1/3", "3/4"], [u.mean, u.variance, u.expectation(X**2, X), u.moment(2), u.quantile(Rational(3, 4))].map(&:to_s)
    assert_equal ["0", "1/2", "1"], [u.pdf(2), u.cdf(Rational(1, 2)), u.cdf(3)].map(&:to_s)
    # a symbolic point carries the support with it, so that substituting
    # later cannot leave it (third review, T6)
    assert_equal "piecewise(x < a => 0, x <= b => 1/(-a + b), :else => 0)", RCAS.Uniform(:a, :b).pdf(X).to_s
    e = RCAS.Exponential(2)
    assert_equal ["1/2", "1/4", "log(2)/2", "piecewise(x < 0 => 0, :else => 1 - exp(-2*x))"], [e.mean, e.variance, e.quantile(Rational(1, 2)), e.cdf(X)].map(&:to_s)
    assert_equal "piecewise(x < 0 => 0, :else => 1 - exp(-(l*x)))", RCAS.Exponential(:l).cdf(X).to_s
    RCAS.assume(X > 0) { assert_equal "1 - exp(-2*x)", e.cdf(X).to_s, "on the support the formula is all there is" }
    assert_equal ["1/l", "2/l**2"], [RCAS.Exponential(:l).moment(1), RCAS.Exponential(:l).moment(2)].map(&:to_s)
    assert_in_delta Math.exp(-2), e.probability(X > 1).evalf, 1e-12
    assert_equal "0", e.pdf(-1).to_s
  end

  def test_discrete
    b = RCAS.Binomial(10, Rational(1, 2))
    assert_equal "Binomial(10, 1/2)", b.to_s
    assert_equal ["15/128", "11/64", "7/128", "5", "5/2", "0"], [b.pdf(3), b.cdf(3), b.probability(X >= 8), b.mean, b.variance, b.pdf(11)].map(&:to_s)
    assert_equal "1", b.cdf(10).to_s
    assert_equal "1", (0..10).map { |k| b.pdf(k) }.reduce(:+).simplify.to_s
    assert_equal "p**k*binomial(n, k)*(1 - p)**(-k + n)", RCAS.Binomial(:n, :p).pdf(:k).to_s
    assert_equal "n*p*(1 - p)", RCAS.Binomial(:n, :p).variance.to_s
    p = RCAS.Poisson(2)
    assert_equal ["1/exp(2)", "3/exp(2)", "2", "2"], [p.pdf(0), p.cdf(1), p.mean, p.variance].map(&:to_s)
    assert_equal "l**k*exp(-l)/k!", RCAS.Poisson(:l).pdf(:k).to_s
    assert_equal "sum(l**j*exp(-l)/j!, j, 0, k)", RCAS.Poisson(:l).cdf(:k).to_s
    g = RCAS.Geometric(Rational(1, 2))
    assert_equal ["1 - (1/2)**k/2", "1", "1/8", "7/8"], [g.cdf(:k), g.mean, g.pdf(2), g.cdf(2)].map(&:to_s)
    d = RCAS.DiscreteUniform(1, 6)
    assert_equal ["7/2", "35/12", "1/3", "1/6", "0", "1/2"], [d.mean, d.variance, d.probability(X >= 5), d.pdf(3), d.pdf(7), d.probability(2..4)].map(&:to_s)
    assert_equal "5", d.quantile(0.75).to_s
    assert_equal ["p", "p*(1 - p)"], [RCAS.Bernoulli(:p).mean, RCAS.Bernoulli(:p).variance].map(&:to_s)
    assert_equal "1/3", RCAS.Bernoulli(Rational(1, 3)).pdf(1).to_s
  end

  def test_top_level_dispatch_and_sampling
    d = RCAS.DiscreteUniform(1, 6)
    assert_equal "7/2", RCAS.mean(d).to_s
    assert_equal "2", RCAS.stdev(RCAS.Normal(0, 2)).to_s
    assert_equal "1/6", RCAS.pdf(d, 4).to_s
    assert_equal "1/2", RCAS.cdf(d, 3).to_s
    assert_equal "1/3", RCAS.probability(d, X >= 5).to_s
    assert_equal [3, 5, 1, 2, 1], d.sample(5, random: Random.new(1))
    values = RCAS.Normal(10, 2).sample(4000, random: Random.new(7))
    assert_in_delta 10.0, values.sum / values.size, 0.15
    assert_in_delta 2.0, Math.sqrt(values.sum { |v| (v - 10)**2 } / values.size), 0.15
    assert_raises(ArgumentError) { RCAS.Normal(:mu, 1).sample }
    assert_raises(ArgumentError) { d.probability(3) }
  end

  def test_erf
    assert_equal ["0", "1", "-1", "2", "1"], [RCAS.erf(0), RCAS.erf(RCAS::OO), RCAS.erf(-RCAS::OO), RCAS.erfc(-RCAS::OO), RCAS.erfc(0)].map(&:to_s)
    assert_in_delta Math.erf(0.5), RCAS.erf(0.5).value, 1e-15
    assert_equal "2*exp(-x**2)/pi**(1/2)", RCAS.erf(X).diff(:x).to_s
    assert_equal "pi**(1/2)*erf(x)/2", RCAS.integrate(RCAS.exp(-X**2), :x).to_s
    assert_equal "pi**(1/2)", RCAS.integrate(RCAS.exp(-X**2), :x, -RCAS::OO, RCAS::OO).to_s
    assert_equal "-(x*exp(-x**2))/2 + pi**(1/2)*erf(x)/4", RCAS.integrate(X**2 * RCAS.exp(-X**2), :x).to_s
    assert_equal "1", RCAS.limit(RCAS.erf(X), :x, RCAS::OO).to_s
    assert_equal "2*x/pi**(1/2) - 2*x**3/(3*pi**(1/2)) + x**5/(5*pi**(1/2)) + O(x**6)", RCAS.series(RCAS.erf(X), :x, 0, 6).to_s
    assert_equal RCAS::RR, RCAS.erf(X).tap { RCAS.assume(x: RCAS::RR) }.domain
    RCAS.forget
  end
  # A parameter that cannot be one is refused when the distribution is
  # built: Binomial(10, 1.5).pdf(3) was -3.1640625, a negative probability.
  def test_impossible_parameters_are_refused
    d = RCAS::Distributions
    [[d::Binomial, [10, 1.5]], [d::Binomial, [2.5, 0.5]], [d::Normal, [0, 0]], [d::Normal, [0, -1]],
     [d::Uniform, [2, 1]], [d::Poisson, [-1]], [d::Exponential, [0]], [d::Bernoulli, [2]],
     [d::ChiSquare, [0]], [d::StudentT, [-1]], [d::FRatio, [1, 0]]].each do |klass, params|
      assert_raises(ArgumentError, "#{klass}#{params.inspect}") { klass.new(*params) }
    end
    # a symbolic parameter is not a number and is left alone
    assert_equal "Normal(mu, sigma)", d::Normal.new(:mu, :sigma).to_s
    assert_equal "Binomial(n, p)", d::Binomial.new(:n, :p).to_s
  end

  # The event is a statement about the random variable, not a pair of an
  # operator and a right-hand side: P(-X <= 0) is P(X >= 0), and reading
  # only the operator and the bound answered 0 for a variable that is never
  # negative (22 Sept 2026, from a review).
  def test_an_event_is_solved_for_the_random_variable
    u = RCAS.Uniform(0, 1)
    assert_equal "1", u.probability(-X <= 0).to_s
    assert_equal "0", u.probability(-X > 0).to_s
    assert_equal "1", RCAS.Exponential(1).probability(-X < 0).to_s
    assert_equal "1/2", RCAS.Normal(0, 1).probability(-X <= 0).to_s
  end

  # A scaled or shifted left side has to be divided out first; every such
  # event is checked against the plain one it is equivalent to.
  def test_a_scaled_event_agrees_with_the_plain_one
    half = RCAS::Num.new(Rational(1, 2))
    {
      RCAS.Uniform(0, 4) => [[2 * X <= RCAS::Num.new(3), X <= RCAS::Num.new(Rational(3, 2))],
                             [-X >= RCAS::Num.new(-1), X <= RCAS::Num.new(1)],
                             [X + 1 < RCAS::Num.new(3), X < RCAS::Num.new(2)]],
      RCAS.Exponential(1) => [[2 * X <= RCAS::Num.new(2), X <= RCAS::Num.new(1)]],
      RCAS.Normal(0, 1) => [[-X <= RCAS::Num.new(-1), X >= RCAS::Num.new(1)]],
      RCAS.Binomial(5, half) => [[2 * X >= RCAS::Num.new(8), X >= RCAS::Num.new(4)],
                                 [-X > RCAS::Num.new(-2), X < RCAS::Num.new(2)],
                                 [-X <= RCAS::Num.new(-3), X >= RCAS::Num.new(3)]],
      RCAS.Poisson(1) => [[-X <= RCAS::Num.new(-2), X >= RCAS::Num.new(2)]]
    }.each do |d, pairs|
      pairs.each do |solved, plain|
        assert_equal d.probability(plain).to_s, d.probability(solved).to_s, "#{d}: #{solved} is #{plain}"
      end
    end
    assert_equal "3/8", RCAS.Uniform(0, 4).probability(2 * X <= RCAS::Num.new(3)).to_s
    assert_equal "3/16", RCAS.Binomial(5, half).probability(2 * X >= RCAS::Num.new(8)).to_s
  end

  # An event whose solution is not one half-line: the probability is taken
  # over the whole set that comes out, piece by piece.
  def test_an_event_that_solves_to_an_interval
    assert_equal "1/2", RCAS.Uniform(0, 1).probability(X**2 <= RCAS::Num.new(Rational(1, 4))).to_s
    assert_equal "1/2", RCAS.Uniform(0, 4).probability(X**2 <= RCAS::Num.new(4)).to_s, "[-2, 2] meets [0, 4] in [0, 2]"
    assert_equal "1/4", RCAS.Uniform(0, 4).probability(X**2 <= RCAS::Num.new(1)).to_s
    # the complement of an interval: two pieces, and they add up to one
    inside = RCAS.Uniform(0, 4).probability(X**2 <= RCAS::Num.new(1))
    outside = RCAS.Uniform(0, 4).probability(X**2 > RCAS::Num.new(1))
    assert_equal "1", (inside + outside).simplify.to_s
  end

  # An event rcas cannot read as a statement about one variable is refused
  # rather than answered.
  def test_an_event_that_is_not_about_one_variable
    u = RCAS.Uniform(0, 1)
    assert_raises(ArgumentError) { u.probability(X * RCAS::Var.new(:y) <= RCAS::Num.new(1)) }
    assert_raises(ArgumentError) { u.probability(X != RCAS::Num.new(1)) }
    assert_raises(ArgumentError) { u.probability(2) }
  end

  # R3. The direct cdf route is for "X op c" alone: the right side must be
  # free of the random variable too. P(X <= X) is 1, not X, and
  # P(X <= -X) is P(X >= 0) (22 Sept 2026, the second review).
  def test_the_variable_may_stand_on_either_side
    assert_equal "1/2", RCAS.Uniform(-1, 1).probability(X <= -X).to_s
    assert_equal "1", RCAS.Uniform(0, 1).probability(X <= X).to_s, "a tautology"
    assert_equal "0", RCAS.Uniform(0, 1).probability(X < X).to_s, "and an impossible event"
    assert_equal "1", RCAS.Uniform(0, 1).probability(X >= X).to_s
    assert_equal "1/2", RCAS.Normal(0, 1).probability(X <= -X).to_s
    assert_equal "1", RCAS.Binomial(5, RCAS::Num.new(Rational(1, 2))).probability(X <= X).to_s
    assert_equal "0", RCAS.Poisson(1).probability(2 * X < X).to_s, "X < 0 for a Poisson variable"
    # both sides moving, and the same event written three ways
    u = RCAS.Uniform(0, 4)
    half = RCAS::Num.new(Rational(1, 2))
    assert_equal u.probability(X <= RCAS::Num.new(1)).to_s, u.probability(2 * X <= X + RCAS::Num.new(1)).to_s
    assert_equal u.probability(X <= RCAS::Num.new(1)).to_s, u.probability(half * X <= half).to_s
  end

  # R4. The two infinities are probability 1 and 0 on every public form of
  # the event, not only on the set route: P(X <= oo) came back as oo, which
  # is not a probability at all (22 Sept 2026, the second review).
  def test_infinite_bounds_on_every_form_of_event
    [RCAS.Uniform(0, 1), RCAS.Normal(0, 1), RCAS.Exponential(1),
     RCAS.Poisson(1), RCAS.Binomial(5, RCAS::Num.new(Rational(1, 2)))].each do |d|
      assert_equal "1", d.probability(X <= RCAS::OO).to_s, "#{d}: P(X <= oo)"
      assert_equal "1", d.probability(X < RCAS::OO).to_s, "#{d}: P(X < oo)"
      assert_equal "1", d.probability(X >= RCAS::Neg.new(RCAS::OO).simplify).to_s, "#{d}: P(X >= -oo)"
      assert_equal "0", d.probability(X > RCAS::OO).to_s, "#{d}: P(X > oo)"
      assert_equal "0", d.probability(X <= RCAS::Neg.new(RCAS::OO).simplify).to_s, "#{d}: P(X <= -oo)"
      assert_equal "1", d.probability(RCAS::Neg.new(RCAS::OO).simplify..RCAS::OO).to_s, "#{d}: the whole line as a range"
      assert_equal "1", d.probability(-X <= RCAS::OO).to_s, "#{d}: through the solved route"
    end
    assert_equal "1", RCAS.Uniform(0, 1).probability(0..RCAS::OO).to_s
    assert_equal "1", RCAS.Poisson(1).probability(0..RCAS::OO).to_s
  end

  # Whatever the route, a probability is a number between 0 and 1.
  def test_every_answer_is_a_probability
    half = RCAS::Num.new(Rational(1, 2))
    events = [X <= RCAS::OO, X > RCAS::OO, X <= X, X < X, -X <= 0, 2 * X <= X + half,
              X <= half, X**2 <= RCAS::Num.new(4), 0..RCAS::OO, 0..1]
    [RCAS.Uniform(0, 1), RCAS.Normal(0, 1), RCAS.Poisson(1), RCAS.Binomial(5, half)].each do |d|
      events.each do |event|
        value = d.probability(event).evalf
        next unless value.is_a?(Numeric) && !value.is_a?(Complex)
        assert_operator value, :>=, -1e-12, "#{d}: P(#{event}) = #{value}"
        assert_operator value, :<=, 1 + 1e-12, "#{d}: P(#{event}) = #{value}"
      end
    end
  end
end
