# frozen_string_literal: true

module RCAS
  # The incomplete gamma and beta functions, numerically. They are what the
  # chi-square, Student t and F distributions need for their CDFs; everything
  # here returns Floats and is labelled as numeric where it surfaces.
  #
  #   Special.gamma_p(2.0, 1.5)    # regularized lower incomplete gamma P(a, x)
  #   Special.beta_i(0.3, 2.0, 5)  # regularized incomplete beta I_x(a, b)
  #
  # P(a, x) by the series for x < a + 1 and by the continued fraction for
  # Q(a, x) beyond; I_x(a, b) by the continued fraction with the symmetry
  # I_x(a, b) = 1 - I_(1-x)(b, a) picking the fast side. Both are evaluated
  # with the modified Lentz algorithm.
  #
  # Sources (keys: MANUAL.md, Sources): [AS64, §6.5, §26.5]; [PTVF07, §6.2,
  # §6.4]; Lentz's method [Len76].
  module Special
    EPSILON = 1e-16
    TINY = 1e-300
    MAX_ITERATIONS = 300

    module_function

    def float(x, name)
      v = x.is_a?(Numeric) ? x : Expression.lift(x).evalf
      raise ArgumentError, "#{name}: a real number is needed, got #{x}" unless v.is_a?(Numeric) && !v.is_a?(Complex)
      v.to_f
    end

    def log_gamma(x) = Math.lgamma(x).first

    # Regularized lower incomplete gamma P(a, x) = gamma(a, x) / Gamma(a).
    def gamma_p(a, x)
      a = float(a, "gamma_p")
      x = float(x, "gamma_p")
      raise ArgumentError, "gamma_p: a must be positive" unless a.positive?
      return 0.0 if x <= 0
      x < a + 1.0 ? gamma_series(a, x) : 1.0 - gamma_cf(a, x)
    end

    # Regularized upper incomplete gamma Q(a, x) = 1 - P(a, x).
    def gamma_q(a, x)
      a = float(a, "gamma_q")
      x = float(x, "gamma_q")
      return 1.0 if x <= 0
      x < a + 1.0 ? 1.0 - gamma_series(a, x) : gamma_cf(a, x)
    end

    # The series needs about sqrt(a) terms near x = a, and stopping at a
    # fixed 300 without a word gave ChiSquare(10**6 + 1).cdf(10**6 + 1) as
    # 0.16 instead of 0.5 (third review, P-5): the budget grows with a, and
    # running out of it is a refusal.
    def budget(a) = MAX_ITERATIONS + (40 * Math.sqrt(a.abs)).ceil

    def gamma_series(a, x)
      ap = a
      term = 1.0 / a
      sum = term
      converged = false
      budget(a).times do
        ap += 1
        term *= x / ap
        sum += term
        if term.abs < sum.abs * EPSILON
          converged = true
          break
        end
      end
      raise ArgumentError, "gamma_p: the series did not converge for a = #{a}, x = #{x}" unless converged
      sum * Math.exp(log_prefactor(a, x))
    end

    # log(x**a * exp(-x) / Gamma(a)). For a large a the three terms are each
    # of size a*log(a) and their sum is of size log(a): computed directly it
    # loses nine digits at a = 10**6. Stirling's series for log Gamma(a)
    # [AS64, 6.1.41] lets the large parts cancel on paper instead:
    # a*(log1p(t) - t) - log(2*pi*a)/2 + ... with t = (x - a)/a.
    def log_prefactor(a, x)
      return -x + a * Math.log(x) - log_gamma(a) if a < 100
      t = (x - a) / a
      core = if t.abs < 0.1
               # log1p(t) - t by its series, without the cancellation
               (2..60).reduce(0.0) { |acc, k| acc + ((k.even? ? -1 : 1) * t**k / k) }
             else
               Math.log(1 + t) - t
             end
      stirling = 1.0 / (12 * a) - 1.0 / (360 * a**3) + 1.0 / (1260 * a**5)
      a * core + 0.5 * Math.log(a) - 0.5 * Math.log(2 * Math::PI) - stirling
    end

    # Q(a, x) as a continued fraction (Lentz), for x >= a + 1.
    def gamma_cf(a, x)
      b = x + 1.0 - a
      c = 1.0 / TINY
      d = 1.0 / b
      h = d
      converged = false
      (1..budget(a)).each do |i|
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        d = TINY if d.abs < TINY
        c = b + an / c
        c = TINY if c.abs < TINY
        d = 1.0 / d
        delta = d * c
        h *= delta
        if (delta - 1.0).abs < EPSILON
          converged = true
          break
        end
      end
      raise ArgumentError, "gamma_q: the continued fraction did not converge for a = #{a}, x = #{x}" unless converged
      Math.exp(log_prefactor(a, x)) * h
    end

    # Regularized incomplete beta I_x(a, b).
    def beta_i(x, a, b)
      x = float(x, "beta_i")
      a = float(a, "beta_i")
      b = float(b, "beta_i")
      raise ArgumentError, "beta_i: a and b must be positive" unless a.positive? && b.positive?
      return 0.0 if x <= 0
      return 1.0 if x >= 1
      front = Math.exp(log_gamma(a + b) - log_gamma(a) - log_gamma(b) + a * Math.log(x) + b * Math.log(1.0 - x))
      x < (a + 1.0) / (a + b + 2.0) ? front * beta_cf(x, a, b) / a : 1.0 - front * beta_cf(1.0 - x, b, a) / b
    end

    def beta_cf(x, a, b)
      qab = a + b
      qap = a + 1.0
      qam = a - 1.0
      c = 1.0
      d = 1.0 - qab * x / qap
      d = TINY if d.abs < TINY
      d = 1.0 / d
      h = d
      (1..budget([a, b].max)).each do |m|
        m2 = 2 * m
        an = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + an * d
        d = TINY if d.abs < TINY
        c = 1.0 + an / c
        c = TINY if c.abs < TINY
        d = 1.0 / d
        h *= d * c
        an = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + an * d
        d = TINY if d.abs < TINY
        c = 1.0 + an / c
        c = TINY if c.abs < TINY
        d = 1.0 / d
        delta = d * c
        h *= delta
        break if (delta - 1.0).abs < EPSILON
      end
      h
    end
  end
end
