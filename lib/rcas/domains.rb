# frozen_string_literal: true

module RCAS
  # Raised when an object is not an element of the domain it is used in.
  class DomainError < ArgumentError; end

  # Marker for algebraic objects (Polynomial, Vector, Matrix) that know how to
  # combine with a plain Expression on their left: `x * v`, `2 + f`.
  module Algebraic
    def rop(op, left)
      raise TypeError, "can't apply #{op} to #{left.class} and #{self.class}"
    end
  end

  # Common protocol of NN, ZZ, QQ, RR, CC, polynomial rings and fraction fields.
  class Domain
    def include?(_obj) = raise(NotImplementedError)
    alias member? include?
    def ===(obj) = include?(obj)

    def subset?(_other) = raise(NotImplementedError)
    def superset?(other) = other.subset?(self)
    def <=(other) = subset?(other)
    def >=(other) = superset?(other)
    def <(other) = subset?(other) && self != other
    def >(other) = superset?(other) && self != other

    def ring? = true
    def field? = false
    def fraction_field = self

    # Smallest standard domain containing both.
    def join(_other) = raise(NotImplementedError)

    # ZZ[x], QQ[x, y]
    def [](*vars) = PolynomialRing.new(self, vars)

    # QQ**3 is a vector space, QQ**[2, 3] a space of 2x3 matrices.
    def **(shape)
      shape.is_a?(Array) ? MatrixSpace.new(self, *shape) : VectorSpace.new(self, shape)
    end

    # Declare a symbol to be an element of this domain and return it as a Var.
    def var(name) = RCAS.assume(name => self) && Var.new(name)

    def vector(*entries) = (self**entries.size)[*entries]
    def matrix(rows) = MatrixSpace.new(self, rows.size, rows.first.size)[*rows]

    def to_s = name
    def inspect = name
  end

  # NN, ZZ, QQ, RR, CC. Membership is by value for exact types (2/1 is an
  # integer) and by type for floats (floats are reals).
  class NumberSet < Domain
    attr_reader :name, :rank

    def initialize(name, rank)
      @name = name.to_s
      @rank = rank
      freeze
    end

    def include?(obj)
      case obj
      when Integer    then obj >= 0 || rank >= 1
      when Rational   then obj.denominator == 1 ? include?(obj.numerator) : rank >= 2
      when Complex    then obj.imaginary.zero? ? include?(obj.real) : rank >= 4
      when Numeric    then obj.real? ? rank >= 3 : rank >= 4
      when Symbol     then include?(Var.new(obj))
      when Expression then (d = obj.domain) ? d.subset?(self) : false
      when Polynomial then obj.constant? && include?(obj.constant_term)
      else false
      end
    end

    def subset?(other)
      case other
      when NumberSet      then rank <= other.rank
      when PolynomialRing then subset?(other.base)
      when FractionField  then subset?(other.ring)
      else false
      end
    end

    def ring? = rank >= 1
    def field? = rank >= 2
    def fraction_field = field? ? self : QQ

    def join(other)
      case other
      when NumberSet then rank >= other.rank ? self : other
      else other.join(self)
      end
    end

    def [](*vars)
      raise DomainError, "#{name} is not a ring; use ZZ or a field" unless ring?
      super
    end

    # Smallest number set containing a Ruby number.
    def self.of(value)
      Sets::ALL.find { |s| s.include?(value) } or raise DomainError, "#{value.inspect} is not a number"
    end
  end

  NN = NumberSet.new(:NN, 0) # 0, 1, 2, ...
  ZZ = NumberSet.new(:ZZ, 1)
  QQ = NumberSet.new(:QQ, 2)
  RR = NumberSet.new(:RR, 3)
  CC = NumberSet.new(:CC, 4)

  # `include RCAS::Sets` brings NN, ZZ, QQ, RR, CC into scope.
  module Sets
    NN = RCAS::NN
    ZZ = RCAS::ZZ
    QQ = RCAS::QQ
    RR = RCAS::RR
    CC = RCAS::CC
    ALL = [NN, ZZ, QQ, RR, CC].freeze
  end

  # ---- variable assumptions ----------------------------------------------

  @assumptions = {}

  class << self
    # RCAS.assume(x: ZZ, y: RR)
    def assume(table)
      table.each do |name, domain|
        name = name.name if name.is_a?(Var)
        raise TypeError, "#{name.inspect} is not a variable" unless name.is_a?(Symbol)
        raise TypeError, "#{domain.inspect} is not a number set" unless domain.is_a?(NumberSet)
        @assumptions[name] = domain
      end
      true
    end

    def forget(*names)
      names = @assumptions.keys if names.empty?
      names.each { |n| @assumptions.delete(n.is_a?(Var) ? n.name : n) }
      true
    end

    def assumptions = @assumptions.dup
    def assumption(name) = @assumptions[name]
  end

  # Infers the smallest number set an expression's value must lie in, given
  # the declared domains of its variables. Returns nil when unknown.
  module Infer
    module_function

    def domain(expr)
      case expr
      when Num then expr.finite_field? ? expr.value.field : NumberSet.of(expr.value)
      when Const then expr.name == :oo ? nil : RR
      when RootOf then expr.real? ? RR : CC
      when Var then RCAS.assumption(expr.name)
      when Neg then no_naturals(domain(expr.arg))
      when Add, Mul then join(domain(expr.left), domain(expr.right))
      when Sub then no_naturals(join(domain(expr.left), domain(expr.right)))
      when Div then join(join(domain(expr.left), domain(expr.right)), QQ)
      when Pow then power(expr)
      when Fn  then function(expr)
      end
    end

    def join(a, b)
      return nil if a.nil? || b.nil?
      a.join(b)
    end

    def no_naturals(d) = d == NN ? ZZ : d

    def power(expr)
      base = domain(expr.base)
      exp = expr.exponent
      return nil if base.nil?

      if exp.is_a?(Num)
        v = exp.value
        return base if v.is_a?(Integer) && v >= 0
        return base.join(QQ) if v.is_a?(Integer)
        return CC unless v.real?
        return base <= NN ? RR : CC
      end

      ed = domain(exp)
      return nil if ed.nil?
      return base if ed <= NN
      return base.join(QQ) if ed <= ZZ
      return RR if ed <= RR && base <= NN
      CC
    end

    def function(expr)
      arg = expr.args.size == 1 ? domain(expr.args.first) : nil
      return nil if arg.nil?

      case expr.name
      when :sin, :cos, :tan, :exp then arg <= RR ? RR : CC
      when :abs then arg <= ZZ ? NN : arg
      when :sign, :floor, :ceil, :round then ZZ
      when :re, :im, :arg then RR
      when :erf, :erfc then arg <= RR ? RR : CC
      when :conj then arg
      when :fibonacci then arg <= NN ? NN : ZZ
      when :bernoulli, :harmonic then QQ
      when :log then arg <= NN ? RR : CC
      else CC
      end
    end
  end

  # ZZ[x], QQ[x, y]: polynomials in the given variables with coefficients
  # in +base+. Other variables appearing in an element act as parameters and
  # must be declared members of the base domain.
  class PolynomialRing < Domain
    attr_reader :base, :vars

    def initialize(base, vars)
      raise DomainError, "#{base} is not a ring" unless base.ring?
      names = vars.flatten.map { |v| v.is_a?(Var) ? v.name : v.to_sym }
      raise ArgumentError, "a polynomial ring needs at least one variable" if names.empty?
      if base.is_a?(PolynomialRing)
        names = base.vars + names
        base = base.base
      end
      @base = base
      @vars = names.uniq.freeze
      freeze
    end

    def name = "#{base}[#{vars.join(', ')}]"

    def include?(obj)
      case obj
      when Polynomial then obj.ring.subset?(self) || include?(obj.to_expr)
      when Numeric, Symbol then base.include?(obj) || (obj.is_a?(Symbol) && vars.include?(obj))
      when Expression
        call(obj)
        true
      else false
      end
    rescue DomainError, ZeroDivisionError
      false
    end

    # Convert an expression to an element of this ring.
    def call(expr) = Polynomial.from_expr(self, expr)
    alias poly call

    def subset?(other)
      case other
      when PolynomialRing then base.subset?(other.base) && (vars - other.vars).empty?
      when FractionField  then subset?(other.ring)
      else false
      end
    end

    def join(other)
      case other
      when NumberSet      then PolynomialRing.new(base.join(other), vars)
      when PolynomialRing then PolynomialRing.new(base.join(other.base), vars | other.vars)
      when FractionField
        # Frac(QQ[a])[x] joined with its own coefficient field stays a
        # polynomial ring in x; only shared variables force a fraction field.
        (other.ring.vars & vars).empty? ? PolynomialRing.new(base.join(other), vars) : other.join(self)
      else other.join(self)
      end
    end

    def fraction_field = FractionField.new(self)
    def index(var) = vars.index(var)
    def univariate? = vars.size == 1

    def zero = Polynomial.new(self, {})
    def one = Polynomial.new(self, { Array.new(vars.size, 0) => Num.new(1) })
    def gens = vars.map { |v| call(Var.new(v)) }
    def gen = gens.first

    def ==(other) = other.is_a?(PolynomialRing) && other.base == base && other.vars == vars
    alias eql? ==
    def hash = [PolynomialRing, base, vars].hash
  end

  # Frac(ZZ[x]): rational functions. Results of division, inversion and
  # elimination over a polynomial ring live here.
  class FractionField < Domain
    attr_reader :ring

    def initialize(ring)
      @ring = ring
      freeze
    end

    def name = "Frac(#{ring})"
    def field? = true

    def include?(obj)
      case obj
      when Polynomial then ring.include?(obj)
      when Numeric, Symbol then ring.include?(obj) || ring.base.fraction_field.include?(obj)
      when Expression then rational_function?(obj)
      else false
      end
    end

    def subset?(other) = other.is_a?(FractionField) && ring.subset?(other.ring)

    def join(other)
      case other
      when FractionField then FractionField.new(ring.join(other.ring))
      else FractionField.new(ring.join(other))
      end
    end

    def ==(other) = other.is_a?(FractionField) && other.ring == ring
    alias eql? ==
    def hash = [FractionField, ring].hash

    private

    def rational_function?(expr)
      coefficients = ring.base.fraction_field
      case expr
      when Num then coefficients.include?(expr)
      when Var then ring.vars.include?(expr.name) || coefficients.include?(expr)
      when Neg, Add, Sub, Mul, Div then expr.children.all? { |c| rational_function?(c) }
      when Pow
        if (expr.exponent.variables & ring.vars).empty? && expr.exponent.is_a?(Num) && expr.exponent.integer?
          rational_function?(expr.base)
        else
          (expr.variables & ring.vars).empty? && coefficients.include?(expr)
        end
      when Fn then (expr.variables & ring.vars).empty? && coefficients.include?(expr)
      else false
      end
    end
  end
end
