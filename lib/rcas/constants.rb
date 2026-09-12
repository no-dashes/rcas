# frozen_string_literal: true

module RCAS
  # A named mathematical constant such as pi. `e` is exp(1) and `i` is the
  # number Complex(0, 1), so both reuse existing machinery.
  class Const < Expression
    attr_reader :name, :value

    def initialize(name, value)
      @name = name.to_sym
      @value = value
      freeze
    end

    def ==(other) = other.is_a?(Const) && other.name == name
    alias eql? ==
    def hash = [Const, name].hash
    def to_sexp = name
  end

  PI = Const.new(:pi, Math::PI)
  E = Fn.new(:exp, [Num.new(1)])
  I = Num.new(Complex(0, 1))

  # `include RCAS::Constants` brings PI, E and I into scope (bin/rcas does).
  module Constants
    PI = RCAS::PI
    E = RCAS::E
    I = RCAS::I
  end

  # OO (infinity) is defined in series.rb and added here once loaded.
  def self.register_infinity = Constants.const_set(:OO, OO) unless Constants.const_defined?(:OO)

  # Exact values of the trigonometric functions at rational multiples of pi.
  module Trig
    module_function

    # arg == r * pi for a rational r?  => r or nil
    def pi_multiple(arg)
      coeff, factors = Simplify.factorize(arg)
      return nil unless factors == { PI => 1 }
      coeff.is_a?(Integer) || coeff.is_a?(Rational) ? Rational(coeff) : nil
    end

    # arg == r * i * pi?  => r or nil
    def imaginary_pi_multiple(arg)
      coeff, factors = Simplify.factorize(arg)
      return nil unless factors == { PI => 1 } && coeff.is_a?(Complex) && coeff.real.zero?
      im = coeff.imaginary
      im.is_a?(Integer) || im.is_a?(Rational) ? Rational(im) : nil
    end

    # sin(r*pi) as an exact expression, or nil when not in the table.
    def sin_pi(r)
      r %= 2
      return Simplify.negate(sin_pi(r - 1)) if r > 1 && (sin_pi(r - 1))
      return nil if r > 1
      r = 1 - r if r > Rational(1, 2)
      case r
      when 0 then Num.new(0)
      when Rational(1, 6) then Num.new(Rational(1, 2))
      when Rational(1, 4) then (RCAS.sqrt(2) / 2).simplify
      when Rational(1, 3) then (RCAS.sqrt(3) / 2).simplify
      when Rational(1, 2) then Num.new(1)
      end
    end

    def cos_pi(r) = sin_pi(r + Rational(1, 2))

    def tan_pi(r)
      s = sin_pi(r)
      c = cos_pi(r)
      return nil if s.nil? || c.nil? || Scalar.zero?(c)
      (s / c).simplify
    end

    # exp(r*i*pi) = cos(r*pi) + i*sin(r*pi)
    def exp_i_pi(r)
      c = cos_pi(r)
      s = sin_pi(r)
      return nil if c.nil? || s.nil?
      (c + I * s).simplify
    end

    # Inverse table: value => asin(value) as a multiple of pi.
    def asin_exact(arg)
      table = {
        Num.new(0) => Num.new(0),
        Num.new(Rational(1, 2)) => PI / 6,
        (RCAS.sqrt(2) / 2).simplify => PI / 4,
        (RCAS.sqrt(3) / 2).simplify => PI / 3,
        Num.new(1) => PI / 2
      }
      table[arg]
    end

    def atan_exact(arg)
      table = {
        Num.new(0) => Num.new(0),
        Num.new(1) => PI / 4,
        RCAS.sqrt(3).simplify => PI / 3,
        (RCAS.sqrt(3) / 3).simplify => PI / 6
      }
      table[arg]
    end
  end
end
