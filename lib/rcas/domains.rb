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

    # m.in?(ZZ**[3, 3]), f.in?(QQ[x]): the same question an expression
    # answers with x.in?(RR), and the same answer the domain gives to
    # include?. Only a variable can be *declared* with `in`, so that stays
    # on Expression.
    def in?(domain) = domain.include?(self)
  end

  # The double-struck letters. They are always available as input (ℤ[x] is
  # ZZ[x]); whether results print that way is the unicode setting, which is
  # off by default so that output stays ASCII and pastes anywhere.
  UNICODE = { "NN" => "ℕ", "ZZ" => "ℤ", "QQ" => "ℚ", "RR" => "ℝ", "CC" => "ℂ",
              "pi" => "π", "oo" => "∞" }.freeze

  class << self
    def unicode? = @unicode.nil? ? ENV["RCAS_UNICODE"] == "1" : @unicode

    # RCAS.unicode = true prints ℤ, π and ∞ instead of ZZ, pi and oo.
    def unicode=(value)
      @unicode = value.nil? ? nil : !(value == false || value.to_s == "off" || value.to_s == "false")
    end

    # The name to print for +ascii+ under the current setting.
    def symbol(ascii) = unicode? ? UNICODE.fetch(ascii.to_s, ascii.to_s) : ascii.to_s
  end

  # "x in ZZ": the statement, not the answer. `x.in?(ZZ)` decides membership
  # and returns true or false; inside hold { } the same call is kept as this,
  # the way `==` is kept as an Equation, so that a condition can be written
  # down, printed, typeset (x \in \mathbb{Z}) and carried around.
  #
  #   hold { x.in?(ZZ) }        # => x in ZZ
  #   assumptions               # => {:x=>x in ZZ}
  class Membership
    attr_reader :value, :domain

    def initialize(value, domain)
      @value = value.is_a?(Expression) || value.is_a?(Numeric) || value.is_a?(Symbol) ? Expression.lift(value) : value
      @domain = domain
      freeze
    end

    # Does it hold? The domain decides, exactly where it can.
    def holds? = domain.include?(value)

    def variables = value.respond_to?(:variables) ? value.variables : []
    def subs(*args) = Membership.new(value.subs(*args), domain)
    def simplify = Membership.new(value.simplify, domain)
    # hold { x.in?(ZZ) }.doit evaluates the formal nodes of the value (C9)
    def evaluate = Membership.new(value.respond_to?(:evaluate) ? value.evaluate : value, domain)
    alias doit evaluate
    alias unhold evaluate

    def ==(other) = other.is_a?(Membership) && other.value == value && other.domain == domain
    alias eql? ==
    def hash = [Membership, value, domain].hash

    def to_s = "#{value} in #{domain}"
    alias inspect to_s

    def to_latex(wrap: nil) = "#{LaTeX.of(value, wrap: wrap)} \\in #{LaTeX.of(domain)}"
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

    # A domain of numbers: its elements can be polynomial coefficients and
    # matrix entries. The spaces say no, and that is what keeps a polynomial
    # ring from being built over them.
    def scalar? = true

    # Smallest standard domain containing both.
    def join(_other) = raise(NotImplementedError)

    # ZZ[x], QQ[x, y]
    def [](*vars)
      bad = vars.flatten.reject { |v| v.is_a?(Symbol) || v.is_a?(Var) || v.is_a?(String) }
      unless bad.empty?
        raise DomainError, "#{self}[#{bad.first.inspect}]: the brackets name the indeterminates of a " \
                           "polynomial ring, as in #{self}[x]; for an element of #{self} write #{self}.(#{bad.first})"
      end
      PolynomialRing.new(self, vars)
    end

    # QQ**3 is a vector space, QQ**[2, 3] a space of 2x3 matrices.
    def **(shape)
      shape.is_a?(Array) ? MatrixSpace.new(self, *shape) : VectorSpace.new(self, shape)
    end

    # Declare a symbol to be an element of this domain and return it as a Var.
    def var(name) = RCAS.assume(name => self) && Var.new(name)

    def vector(*entries) = (self**entries.size)[*entries]
    def matrix(rows) = MatrixSpace.new(self, rows.size, rows.first.size)[*rows]

    def to_s = RCAS.symbol(name)
    def inspect = to_s
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
      when Expression then expression_member?(obj)
      when Polynomial then obj.constant? && include?(obj.constant_term)
      else false
      end
    end

    # The inferred domain answers first; a constant it cannot place is
    # simplified and looked at again: sqrt(2)**2 is 2 and pi - pi is 0,
    # both integers (third review, C13).
    def expression_member?(obj)
      d = obj.domain
      return true if d&.subset?(self)
      return false unless obj.constant?
      reduced = obj.simplify
      return include?(reduced.value) if reduced.is_a?(Num)
      reduced != obj && (d2 = reduced.domain) ? d2.subset?(self) : false
    rescue StandardError
      false
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

    # ZZ.(3), QQ.(1/2r): the value as an element of this set. The brackets
    # build a polynomial ring, so this is the way in for an element - the
    # same spelling a polynomial ring and a finite field already use.
    def call(value)
      lifted = Expression.lift(value)
      raise DomainError, "#{lifted} is not in #{name}" unless include?(lifted)
      lifted
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

  # The double-struck letters are constants, not methods: Ruby reads ℤ as an
  # uppercase letter and therefore as a constant. ℤ[x] is ZZ[x].
  ℕ = NN
  ℤ = ZZ
  ℚ = QQ
  ℝ = RR
  ℂ = CC

  # `include RCAS::Sets` brings NN, ZZ, QQ, RR, CC (and ℕ ℤ ℚ ℝ ℂ) into scope.
  module Sets
    NN = RCAS::NN
    ZZ = RCAS::ZZ
    QQ = RCAS::QQ
    RR = RCAS::RR
    CC = RCAS::CC
    ℕ = RCAS::NN
    ℤ = RCAS::ZZ
    ℚ = RCAS::QQ
    ℝ = RCAS::RR
    ℂ = RCAS::CC
    ALL = [NN, ZZ, QQ, RR, CC].freeze
  end

  # ---- variable assumptions ----------------------------------------------

  @assumptions = {}
  @signs = {}

  SIGNS = { :> => :positive, :>= => :nonnegative, :< => :negative, :<= => :nonpositive }.freeze

  class << self
    # RCAS.assume(x: ZZ, y: RR) declares domains, RCAS.assume(x > 0) a sign.
    # Both may be given at once: assume(x > 0, n: ZZ).
    #
    # With a block the assumptions hold for that block alone and whatever
    # was declared before comes back afterwards, however the block ends:
    #
    #   assume(x: ZZ) { solve(eq(x/3, 1/2), x) }   # => []
    #
    # which is Mathematica's Assuming and Maple's `assuming`, written the
    # way Ruby scopes anything else. The value is the block's.
    #
    # A statement is taken whole or not at all: everything is checked before
    # anything is recorded, so a refused `assume(x: ZZ, y: 3)` leaves x as it
    # was. A sign that no member of the declared domain has (x in NN and
    # x < 0) is refused as well.
    def assume(*facts, **table, &block)
      return assuming(facts, table, &block) if block
      signs = facts.map do |fact|
        raise TypeError, "#{fact.inspect} is not a domain or a sign like x > 0" unless fact.is_a?(Inequality)
        parse_sign(fact)
      end
      domains = table.map do |name, domain|
        name = name.name if name.is_a?(Var)
        raise TypeError, "#{name.inspect} is not a variable" unless name.is_a?(Symbol)
        raise TypeError, "#{domain.inspect} is not a number set" unless domain.is_a?(NumberSet)
        [name, domain]
      end
      new_domains = @assumptions.merge(domains.to_h)
      new_signs = @signs.merge(signs.to_h)
      new_signs.each do |name, sign|
        domain = new_domains[name]
        next unless domain && domain <= NN && %i[negative].include?(sign)
        raise ArgumentError, "assume: #{name} in #{domain} cannot be negative"
      end
      @assumptions.replace(new_domains)
      @signs.replace(new_signs)
      true
    end

    # The whole table is saved and put back, so that an assume or a forget
    # inside the block is local to it too - the dynamic scoping Mathematica
    # gives $Assumptions.
    def assuming(facts, table)
      saved_assumptions = @assumptions.dup
      saved_signs = @signs.dup
      assume(*facts, **table)
      yield
    ensure
      @assumptions.replace(saved_assumptions)
      @signs.replace(saved_signs)
    end

    # x > 0, x <= 0: the sign of a variable, which simplification and abs use.
    def parse_sign(fact)
      variable, relation = fact.lhs.is_a?(Var) ? [fact.lhs, fact.op] : [fact.rhs, Inequality::FLIP[fact.op]]
      other = fact.lhs.is_a?(Var) ? fact.rhs : fact.lhs
      sign = SIGNS[relation]
      unless variable.is_a?(Var) && sign && other.is_a?(Num) && other.value.zero?
        raise TypeError, "assume: a sign is x > 0, x >= 0, x < 0 or x <= 0, got #{fact}"
      end
      [variable.name, sign]
    end

    def forget(*names)
      if names.empty?
        @assumptions.clear
        @signs.clear
        return true
      end
      names.each do |n|
        key = n.is_a?(Var) ? n.name : n
        @assumptions.delete(key)
        @signs.delete(key)
      end
      true
    end

    # Domains as number sets, signs as the inequality they stand for.
    # Every assumption as the statement it is: a sign was already an
    # Inequality, and a domain is a Membership rather than the bare set.
    # `assumption(name)` is the domain itself, which is what Infer and solve
    # want.
    # A name with both a domain and a sign lists both, as an Array: merging
    # the two tables used to let the sign overwrite the domain.
    def assumptions
      domains = @assumptions.to_h { |name, domain| [name, Membership.new(Var.new(name), domain)] }
      domains.merge(@signs.to_h { |name, sign| [name, sign_statement(name, sign)] }) { |_, domain, sign| [domain, sign] }
    end

    def sign_statement(name, sign)
      relation = SIGNS.key(sign)
      Inequality.new(Var.new(name), relation, Num.new(0))
    end
    def assumption(name) = @assumptions[name]
    def signs = @signs.dup

    # :positive, :nonnegative, :negative, :nonpositive or nil, for a variable
    # or for an expression whose factors are all known.
    def sign_of(expr)
      case expr
      when Symbol then @signs[expr]
      when Var then @signs[expr.name] || (assumption(expr.name)&.<=(NN) ? :nonnegative : nil)
      when Num then numeric_sign(expr.value)
      when Const then numeric_sign(expr.value) # pi and oo are positive
      when Expression then expression_sign(expr)
      end
    end

    def numeric_sign(value)
      return nil unless value.is_a?(Numeric) && value.real?
      return nil if value.respond_to?(:nan?) && value.nan? # undefined has no sign
      return :positive if value.positive?
      return :negative if value.negative?
      :nonnegative
    end

    # A product of knowns, or an even power, or a sum of nonnegatives.
    def expression_sign(expr)
      case expr
      when Pow
        base_sign = sign_of(expr.base)
        return :positive if base_sign == :positive
        # An even power is not negative - of a real number. y**2 at y = 2i
        # is -4, and an undeclared y is not real (the branch-cut policy),
        # so abs(y**2 + 1) keeps its abs until y is declared.
        even = expr.exponent.is_a?(Num) && expr.exponent.value.is_a?(Integer) && expr.exponent.value.even?
        return :nonnegative if even && (base_sign || real?(expr.base))
        nil
      when Mul
        combine_signs(sign_of(expr.left), sign_of(expr.right))
      when Add
        left = sign_of(expr.left)
        right = sign_of(expr.right)
        return :positive if [left, right].all? { |s| %i[positive nonnegative].include?(s) } && [left, right].include?(:positive)
        %i[positive nonnegative].include?(left) && %i[positive nonnegative].include?(right) ? :nonnegative : nil
      end
    end

    def combine_signs(left, right)
      return nil if left.nil? || right.nil?
      return :positive if left == :positive && right == :positive
      return :nonnegative if %i[positive nonnegative].include?(left) && %i[positive nonnegative].include?(right)
      return :negative if [left, right].count(:negative) == 1 && [left, right].all? { |s| %i[positive negative].include?(s) }
      nil
    end

    def nonnegative?(expr) = %i[positive nonnegative].include?(sign_of(expr))

    def real?(expr)
      d = Infer.domain(expr)
      !d.nil? && d <= RR
    end
  end

  # Infers the smallest number set an expression's value must lie in, given
  # the declared domains of its variables. Returns nil when unknown.
  module Infer
    module_function

    def domain(expr)
      case expr
      when Num then expr.finite_field? ? expr.value.field : NumberSet.of(expr.value)
      when Const then %i[oo undefined].include?(expr.name) ? nil : RR
      when RootOf then expr.real? ? RR : CC
      when Var then RCAS.assumption(expr.name) || (RCAS.signs[expr.name] ? RR : nil) # a sign says real
      when Neg then no_naturals(domain(expr.arg))
      when Add, Mul then join(domain(expr.left), domain(expr.right))
      when Sub then no_naturals(join(domain(expr.left), domain(expr.right)))
      when Div then join(join(domain(expr.left), domain(expr.right)), QQ)
      when Pow then power(expr)
      when Fn  then function(expr)
      when Piecewise then expr.values.map { |v| domain(v) }.reduce { |a, b| join(a, b) }
      end
    end

    def join(a, b)
      return nil if a.nil? || b.nil?
      a.join(b)
    end

    # How far from an integer a Float has to be before it is one no longer.
    TOLERANCE = 1e-6

    # Is `value` demonstrably outside `domain`? Membership is decided where
    # it can be and left open where it cannot, so `false` means "not shown
    # to be outside" and never "inside": a solution dropped by mistake is
    # worse than one that should not be there. Solve filters its answers
    # with this, so that a declared domain is respected.
    def excluded?(value, domain)
      return false unless domain.is_a?(NumberSet)
      value = Expression.lift(value).simplify
      return !domain.include?(value.value) if value.is_a?(Num)
      return false unless value.variables.empty? # a parameter decides nothing
      return true if domain <= QQ && irrational?(value)
      numeric = value.evalf
      return false unless numeric.is_a?(Numeric)
      return domain <= RR if numeric.is_a?(Complex) && !numeric.imaginary.to_f.abs.zero?
      real = numeric.is_a?(Complex) ? numeric.real.to_f : numeric.to_f
      return true if domain == NN && real.negative?
      domain <= ZZ && (real - real.round).abs > TOLERANCE
    end

    # Irrational for a reason rcas can name: an algebraic number whose
    # minimal polynomial has degree above one (2**(1/2), a real RootOf), or
    # a rational multiple of pi or e, which their transcendence settles.
    # Everything else (pi + log(2)) is left open, as it is in the literature.
    def irrational?(value)
      algebraic = Algebraic.exact(value)
      return !algebraic.poly.constant? if algebraic
      coeff, factors = Simplify.factorize(value)
      return false if coeff.zero? || factors.size != 1
      base, exponent = factors.first
      exponent == 1 && (base == PI || base == E)
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
      when :Ei, :Si, :Ci, :li then arg <= RR ? RR : CC
      when :conj then arg
      when :fibonacci then arg <= NN ? NN : ZZ
      when :bernoulli, :harmonic then QQ
      when :log then log_domain(expr.args.first, arg)
      else CC
      end
    end
  end

  module Infer
    module_function

    # log(u) is real for a u shown to be positive; log(0) has no value at
    # all, so it lies in no set (it was RR, and so was log(x) for x in NN,
    # where 0 is a member: third review, C5); anything else may be complex.
    def log_domain(u, arg)
      return nil if u.is_a?(Num) && u.value.is_a?(Numeric) && u.value.zero?
      sign = u.variables.empty? ? Decide.sign(u) : RCAS.sign_of(u)
      return RR if sign == :positive
      return nil if sign == :nonnegative || (sign.nil? && arg <= NN) # 0 may be among the values
      CC
    end
  end

  # ZZ[x], QQ[x, y]: polynomials in the given variables with coefficients
  # in +base+. Other variables appearing in an element act as parameters and
  # must be declared members of the base domain.
  class PolynomialRing < Domain
    attr_reader :base, :vars

    def initialize(base, vars)
      raise DomainError, "#{base} is not a ring" unless base.ring?
      unless base.scalar?
        raise DomainError, "#{base} is not a domain of numbers: polynomial coefficients are scalars"
      end
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
