# frozen_string_literal: true

module RCAS
  # Polynomial interpolation.
  #
  #   interpolate([[0, 1], [1, 3], [2, 7]], x)   # => 1 + x + x**2
  #   interpolate({ 0 => a, 1 => b }, x)         # => a + (b - a)*x  (expanded)
  #
  # Newton's divided differences, exact in the coefficient arithmetic
  # (rationals, algebraic numbers, parameters). The result is the unique
  # polynomial of degree < n through the n points, expanded.
  #
  # Sources (keys: MANUAL.md, Sources): [Knu98, §4.6.4]; [vzGG13, ch. 5].
  module Interpolate
    module_function

    def newton(points, var)
      x = Expression.lift(var)
      raise ArgumentError, "interpolate: the indeterminate must be a symbol, got #{x}" unless x.is_a?(Var)
      pairs = points.is_a?(Hash) ? points.to_a : Array(points)
      raise ArgumentError, "interpolate: give the points as [[x0, y0], [x1, y1], ...] or a hash" unless pairs.all? { |p| p.is_a?(Array) && p.size == 2 }
      nodes = pairs.map { |p, _| Expression.lift(p) }
      values = pairs.map { |_, v| Expression.lift(v) }
      nodes.combination(2).each do |a, b|
        raise ArgumentError, "interpolate: the points #{a} and #{b} coincide" if Scalar.zero?(Scalar.sub(a, b))
      end

      n = nodes.size
      coeffs = values.dup
      (1...n).each do |level|
        (n - 1).downto(level) do |i|
          coeffs[i] = Scalar.div(Scalar.sub(coeffs[i], coeffs[i - 1]), Scalar.sub(nodes[i], nodes[i - level]))
        end
      end
      poly = Num.new(0)
      (n - 1).downto(0) { |i| poly = poly * (x - nodes[i]) + coeffs[i] }
      poly.expand
    end
  end
end
