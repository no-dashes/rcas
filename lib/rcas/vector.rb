# frozen_string_literal: true

module RCAS
  # QQ**3: column vectors of fixed dimension over a domain, and a domain
  # itself: a vector answers `domain` with the space it lives in, and the
  # space answers `base` with the domain its entries come from. Over a ring
  # such as ZZ this is a free module rather than a vector space, but the API
  # is the same.
  class VectorSpace < Domain
    attr_reader :base, :dim

    def initialize(base, dim)
      raise ArgumentError, "dimension must be a non-negative integer" unless dim.is_a?(Integer) && dim >= 0
      @base = base
      @dim = dim
      freeze
    end

    # QQ**3 [1, 2, 3]  or  (QQ**3)[1, 2, 3]
    def [](*entries)
      entries = entries.flatten(1) if entries.size == 1 && entries.first.is_a?(Array)
      raise DomainError, "#{self} needs #{dim} entries, got #{entries.size}" unless entries.size == dim
      entries = entries.map { |e| Scalar.lift(e) }
      entries = entries.map { |e| base.normalize_coefficient(e) } if base.respond_to?(:normalize_coefficient)
      entries.each do |e|
        next if base.include?(e)
        hint = e.variables.reject { |v| RCAS.assumption(v) }
        hint = hint.empty? ? "" : " (declare #{hint.join(', ')} with assume(#{hint.first}: #{base}))"
        raise DomainError, "#{e} is not in #{base}#{hint}"
      end
      Vector.new(self, entries)
    end

    def unchecked(entries) = Vector.new(self, entries.map { |e| Scalar.lift(e) })

    def include?(obj)
      obj = self[*obj] if obj.is_a?(Array) && obj.size == dim
      obj.is_a?(Vector) && obj.dim == dim && obj.entries.all? { |e| base.include?(e) }
    rescue DomainError
      false
    end
    alias member? include?
    def ===(obj) = include?(obj)

    def zero = unchecked(Array.new(dim, 0))
    def basis = (0...dim).map { |i| unchecked(Array.new(dim) { |j| i == j ? 1 : 0 }) }

    # A module, not a ring: vectors have no multiplication between them.
    def ring? = false
    def field? = false

    def over(other_base) = VectorSpace.new(other_base, dim)

    # The same dimension over a larger base: (ZZ**3) < (QQ**3).
    def subset?(other) = other.is_a?(VectorSpace) && other.dim == dim && base.subset?(other.base)

    def join(other)
      return VectorSpace.new(base.join(other.base), dim) if other.is_a?(VectorSpace) && other.dim == dim
      raise DomainError, "no common domain for #{self} and #{other}" if other.is_a?(VectorSpace) || other.is_a?(MatrixSpace)
      VectorSpace.new(base.join(other), dim) # a domain of scalars: what scaling gives
    end

    def ==(other) = other.is_a?(VectorSpace) && other.base == base && other.dim == dim
    alias eql? ==
    def hash = [VectorSpace, base, dim].hash

    def name = "#{base}**#{dim}"
  end

  class Vector
    include Algebraic
    include Enumerable

    attr_reader :space, :entries

    def initialize(space, entries)
      @space = space
      @entries = entries.freeze
      freeze
    end

    def dim = entries.size
    alias size dim
    # The space is where the vector lives, base where its entries come from.
    def domain = space
    def base = space.base
    def [](i) = entries.fetch(i)
    def each(&block) = entries.each(&block)
    def to_a = entries.dup

    # ---- arithmetic -------------------------------------------------------

    def +(other) = zip_with(other, :+) { |a, b| Scalar.add(a, b) }
    def -(other) = zip_with(other, :-) { |a, b| Scalar.sub(a, b) }
    def -@ = space.unchecked(entries.map { |e| Scalar.neg(e) })

    # Vector * Vector is the dot product, Vector * Matrix a row-vector product,
    # anything else scales.
    def *(other)
      case other
      when Vector then dot(other)
      when Matrix then Matrix.row_times(self, other)
      else scale(other)
      end
    end

    def /(scalar)
      s = Scalar.lift(scalar)
      space.over(result_domain(s).fraction_field).unchecked(entries.map { |e| Scalar.div(e, s) })
    end

    def scale(scalar)
      s = Scalar.lift(scalar)
      space.over(result_domain(s)).unchecked(entries.map { |e| Scalar.mul(e, s) })
    end

    def coerce(other) = [ScalarProxy.new(other), self]
    def rop(op, left) = op == :* ? scale(left) : super

    def dot(other)
      check_dim!(other)
      entries.zip(other.entries).map { |a, b| Scalar.mul(a, b) }.reduce { |s, x| Scalar.add(s, x) } || Num.new(0)
    end

    def cross(other)
      check_dim!(other)
      raise ArgumentError, "cross product needs dimension 3" unless dim == 3
      a, b = entries, other.entries
      VectorSpace.new(base.join(other.base), 3).unchecked([
        Scalar.sub(Scalar.mul(a[1], b[2]), Scalar.mul(a[2], b[1])),
        Scalar.sub(Scalar.mul(a[2], b[0]), Scalar.mul(a[0], b[2])),
        Scalar.sub(Scalar.mul(a[0], b[1]), Scalar.mul(a[1], b[0]))
      ])
    end

    def norm = RCAS.sqrt(dot(self)).simplify
    def zero? = entries.all? { |e| Scalar.zero?(e) }

    def ==(other)
      other = space.unchecked(other) if other.is_a?(Array) && other.size == dim
      other.is_a?(Vector) && other.dim == dim &&
        entries.zip(other.entries).all? { |a, b| Scalar.zero?(Scalar.sub(a, b)) }
    end
    alias eql? ==
    def hash = [Vector, entries.map(&:simplify)].hash

    def simplify = space.unchecked(entries.map(&:simplify))
    def subs(*args) = space.unchecked(entries.map { |e| e.subs(*args) })
    def call(**bindings) = space.unchecked(entries.map { |e| Scalar.lift(e.call(**bindings)) })

    def to_s = "(#{entries.join(', ')})"
    alias inspect to_s

    private

    def check_dim!(other)
      raise TypeError, "expected a Vector, got #{other.class}" unless other.is_a?(Vector)
      raise ArgumentError, "dimension mismatch: #{dim} vs #{other.dim}" unless dim == other.dim
    end

    def zip_with(other, op)
      raise TypeError, "can't apply #{op} to Vector and #{other.class}" unless other.is_a?(Vector)
      check_dim!(other)
      VectorSpace.new(base.join(other.base), dim).unchecked(entries.zip(other.entries).map { |a, b| yield a, b })
    end

    def result_domain(scalar)
      d = Scalar.domain(scalar)
      d ? base.join(d) : base
    end
  end
end
