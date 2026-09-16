# frozen_string_literal: true

module RCAS
  # Fourier series on an interval.
  #
  #   fourier(x, x: -pi..pi)                  # the partial sum, four harmonics
  #   fourier(x, x: -pi..pi, formal: true)    # the general coefficient
  #
  # On [a, b] with T = b - a and omega = 2*pi/T,
  #
  #   f ~ a_0/2 + sum_k a_k*cos(k*omega*x) + b_k*sin(k*omega*x)
  #   a_k = (2/T) * integral(f(x)*cos(k*omega*x), x, a, b)
  #   b_k = (2/T) * integral(f(x)*sin(k*omega*x), x, a, b)
  #
  # `kind: :sine` and `kind: :cosine` are the half-range expansions on
  # [0, L]: the odd and the even extension of f, with omega = pi/L.
  #
  # The coefficients are the integrals rcas already does; what makes the
  # general one come out is that the index is assumed to be an integer
  # while they are computed, so that sin(k*pi) folds to 0 and cos(k*pi) to
  # (-1)**k (constants.rb, Trig.integer_pi_multiple).
  #
  # Sources (keys: MANUAL.md, Sources): [Spi08, ch. 13] for the series and
  # the half-range expansions; convergence is not checked - the series is
  # written down formally, as every table does.
  module Fourier
    module_function

    DEFAULT_TERMS = 4

    def series(f, x, from, to, n: DEFAULT_TERMS, kind: :full, formal: false, index: nil)
      f = Expression.lift(f)
      x = Expression.lift(x)
      from = Expression.lift(from)
      to = Expression.lift(to)
      raise ArgumentError, "fourier: kind must be :full, :sine or :cosine" unless %i[full sine cosine].include?(kind)
      length = (to - from).simplify
      raise ArgumentError, "fourier: the interval needs two finite ends" if length.each_node.any? { |node| node == OO }
      omega = ((kind == :full ? 2 : 1) * PI / length).simplify
      formal ? formal_series(f, x, from, to, omega, length, kind, index) : partial_sum(f, x, from, to, omega, length, kind, n)
    end

    # The constant term a_0/2: the mean value of f over the interval.
    def constant_term(f, x, from, to, length, kind)
      return Num.new(0) if kind == :sine
      value = coefficient(f, x, from, to, Num.new(1), length) || missing!(f, x, Num.new(1))
      (value / 2).simplify
    end

    # (2/T) * integral(f*weight, x, from, to), or nil when the integral is
    # not elementary.
    def coefficient(f, x, from, to, weight, length)
      value = Integrate.definite((f * weight).simplify, x, from, to)
      return nil unless value.each_node.none? { |node| node.is_a?(Integral) }
      (2 * value / length).simplify
    end

    def missing!(f, x, weight)
      raise SeriesError, "fourier: integral(#{(f * weight).simplify}, #{x}) is not elementary, " \
                         "so this coefficient has no closed form"
    end

    # ---- the partial sum ----------------------------------------------------

    def partial_sum(f, x, from, to, omega, length, kind, n)
      raise ArgumentError, "fourier: n must be a positive integer" unless n.is_a?(Integer) && n.positive?
      total = constant_term(f, x, from, to, length, kind)
      (1..n).each do |k|
        harmonic(kind, Num.new(k) * omega * x).each do |weight|
          value = coefficient(f, x, from, to, weight, length) || missing!(f, x, weight)
          total += value * weight
        end
      end
      total.simplify
    end

    # The weights of one harmonic: cos and sin for the full series, one of
    # them for a half-range expansion.
    def harmonic(kind, angle)
      case kind
      when :sine then [Fn.new(:sin, [angle.simplify])]
      when :cosine then [Fn.new(:cos, [angle.simplify])]
      else [Fn.new(:cos, [angle.simplify]), Fn.new(:sin, [angle.simplify])]
      end
    end

    # ---- the general coefficient --------------------------------------------

    def formal_series(f, x, from, to, omega, length, kind, index)
      k = index_variable(f, x, index)
      angle = (k * omega * x).simplify
      term = integer_index(k.name) do
        harmonic(kind, angle).sum(Num.new(0)) do |weight|
          value = coefficient(f, x, from, to, weight, length) || missing!(f, x, weight)
          value * weight
        end
      end
      (constant_term(f, x, from, to, length, kind) + Sum.new(term.simplify, k, Num.new(1), OO)).simplify
    end

    def index_variable(f, x, index)
      return Var.new(index.to_sym) if index
      taken = f.variables | [x.name]
      name = %i[k n m j].find { |candidate| !taken.include?(candidate) }
      Var.new(name || :k)
    end

    # The index is a positive integer while the coefficients are computed:
    # that is what turns sin(k*pi) into 0 and cos(k*pi) into (-1)**k.
    def integer_index(name)
      previous = RCAS.assumption(name)
      RCAS.assume(name => NN)
      yield
    ensure
      previous ? RCAS.assume(name => previous) : RCAS.forget(name)
    end
  end
end
