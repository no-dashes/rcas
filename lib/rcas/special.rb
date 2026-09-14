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

    def gamma_series(a, x)
      ap = a
      term = 1.0 / a
      sum = term
      MAX_ITERATIONS.times do
        ap += 1
        term *= x / ap
        sum += term
        break if term.abs < sum.abs * EPSILON
      end
      sum * Math.exp(-x + a * Math.log(x) - log_gamma(a))
    end

    # Q(a, x) as a continued fraction (Lentz), for x >= a + 1.
    def gamma_cf(a, x)
      b = x + 1.0 - a
      c = 1.0 / TINY
      d = 1.0 / b
      h = d
      (1..MAX_ITERATIONS).each do |i|
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        d = TINY if d.abs < TINY
        c = b + an / c
        c = TINY if c.abs < TINY
        d = 1.0 / d
        delta = d * c
        h *= delta
        break if (delta - 1.0).abs < EPSILON
      end
      Math.exp(-x + a * Math.log(x) - log_gamma(a)) * h
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
      (1..MAX_ITERATIONS).each do |m|
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
