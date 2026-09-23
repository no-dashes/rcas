# frozen_string_literal: true

require "set"

module RCAS
  # The broad rescues in the mathematical code turn a failure into "not
  # decided here", which is right for the mathematics and wrong for a bug:
  # the third review's fault injection had 31 NoMethodErrors quietly turned
  # into unevaluated answers, and a caller's Timeout::Error (a
  # StandardError) swallowed. Every such rescue calls guard! first. A
  # timeout always goes through; with RCAS_STRICT=1 (the test task sets it)
  # so do NoMethodError and NameError, which are never mathematics.
  def self.strict? = ENV["RCAS_STRICT"] == "1"

  # What rcas raises when it cannot do something: "cannot" is an answer of
  # its own, never "none". A StandardError, so that a caller's `rescue => e`
  # catches it (it was a NotImplementedError, a ScriptError, until the
  # fourth review asked a second time); and since a broad rescue would now
  # see it, guard! passes it on, so it reaches the caller exactly as the
  # ScriptError did. A rescue that means to take a refusal names it, and
  # says so to guard! with `refused: true`.
  class Unsupported < StandardError; end

  # A refusal of either kind: Ruby's own NotImplementedError too.
  def self.refusal?(error) = error.is_a?(Unsupported) || error.is_a?(NotImplementedError)

  def self.guard!(error, refused: false)
    raise error if !refused && error.is_a?(Unsupported)
    raise error if defined?(::Timeout::Error) && error.is_a?(::Timeout::Error)
    # NoMethodError is a NameError; 1 + nil is a TypeError (fourth review)
    raise error if strict? && (error.is_a?(NameError) || error.is_a?(TypeError))
  end

  # The value of an expression or number as a real Float, or nil when it
  # has none (not constant, complex, undefined; infinite unless finite:
  # false). Six private copies of this read "Float or nil" slightly
  # differently (third review, section 5); they all delegate here now.
  def self.real_float(value, finite: true)
    return nil unless value.is_a?(Numeric) || value.is_a?(Expression) || value.is_a?(Symbol) # a family, a set
    v = value.is_a?(Numeric) ? value : Expression.lift(value).evalf
    v = v.value if v.is_a?(Num)
    return nil unless v.is_a?(Numeric) && v.real?
    f = v.to_f
    return nil if f.nan? || (finite && f.infinite?)
    f
  rescue StandardError, Math::DomainError => rescued
    guard!(rescued) if rescued.is_a?(StandardError)
    nil
  end

  # Base class of every node in an expression tree.
  #
  # Trees are immutable and built faithfully from the Ruby expression that
  # created them: `(:x + 1) * (1 - :x)` is Mul(Add(x, 1), Sub(1, x)). Nothing
  # is rewritten until you ask for it via #simplify, #expand or #diff.
  class Expression
    include Comparable

    # Turn a Symbol, Numeric or Expression into an Expression.
    def self.lift(obj)
      case obj
      when Expression then obj
      when Symbol     then Var.new(obj)
      when Numeric    then Num.new(obj)
      when Mod, GFElement then Num.new(obj)
      else raise TypeError, "can't convert #{obj.class} into RCAS::Expression"
      end
    end

    # ---- arithmetic -------------------------------------------------------

    def +(other) = binary(Add, :+, other)
    def -(other) = binary(Sub, :-, other)
    def *(other) = binary(Mul, :*, other)
    def /(other) = binary(Div, :/, other)
    def **(other) = binary(Pow, :**, other)
    def -@ = Neg.new(self)
    def +@ = self

    # x < 2 builds an Inequality (see Inequalities); <=> still orders canonically.
    def <(other) = Inequality.new(self, :<, other)
    def <=(other) = Inequality.new(self, :<=, other)
    def >(other) = Inequality.new(self, :>, other)
    def >=(other) = Inequality.new(self, :>=, other)

    # Called by Numeric operators when the left operand is a plain number:
    # `1 - :x` ends up here (via Symbol#coerce) as Num(1) - Var(x).
    def coerce(other) = [Expression.lift(other), self]

    def to_expr = self

    private

    # Polynomials, vectors and matrices on the right take over the operation.
    def binary(klass, op, other)
      return other.rop(op, self) if other.is_a?(Algebraic)
      klass.new(self, Expression.lift(other))
    end

    public

    # ---- tree protocol ----------------------------------------------------

    def children = []

    # Build a node of the same kind with new children.
    def rebuild(*_children) = self

    # Depth-first structural map.
    def map_children(&block)
      return self if children.empty?
      rebuild(*children.map(&block))
    end

    def leaf? = children.empty?

    def ==(other)
      return other == self if other.is_a?(Algebraic)
      other.is_a?(Expression) && other.class == self.class && other.children == children
    end

    # eql? compares the children with eql?, so that eql? implies equal
    # hashes: x + 1 and x + 1.0 are == (1 == 1.0) but not eql?, and they
    # hash differently (third review, C12).
    def eql?(other) = other.is_a?(Expression) && other.class == self.class && other.children.eql?(children)

    # Nodes are immutable, so the hash is computed once, in the constructor,
    # before the node is frozen: recomputing it walked the whole subtree on
    # every lookup, and the term tables are hashes of expressions. The
    # combination is by hand because building the array cost more than the
    # walk saved - a node is constructed far more often than it is hashed.
    # A node class that does not set it (the formal ones) falls back.
    #
    # FIXNUM is what keeps the combination from growing: multiplying a
    # child's hash by 31 at every level made the hash of a 20000-term sum a
    # 99000-bit integer and the sum itself 390 MB.
    FIXNUM = 0x3fff_ffff_ffff_ffff

    def hash = @hash || [self.class, *children].hash

    # Total order used for canonical sorting; see Simplify.sort_key.
    # A plain number is lifted, so that -oo..0 is a Range (Range.new asks
    # <=> and gave up on nil: third review, P-14).
    def <=>(other)
      other = Expression.lift(other) if other.is_a?(Numeric)
      return nil unless other.is_a?(Expression)
      Simplify.sort_key(self) <=> Simplify.sort_key(other)
    end

    # ---- queries ----------------------------------------------------------

    # Sorted array of the symbols appearing *free* in the expression: the x
    # of integral(f(x), x, 0, 1) is bound and is not one of them.
    def variables
      result = Set.new
      each_free_variable { |name| result << name }
      result.to_a.sort
    end

    # The variable this node binds in its first child, or nil. A definite
    # integral, a sum, a product and a limit bind theirs: the value of
    # integral(f(x), x, 0, 1) does not depend on x, and renaming the x
    # changes nothing. The bounds are outside the binding.
    def bound_variable = nil

    # Yields the name of every free occurrence of a variable (with
    # repetitions). Iterative, like each_node, so deep trees are safe.
    def each_free_variable
      stack = [[self, nil]]
      until stack.empty?
        node, bound = stack.pop
        if node.is_a?(Var)
          yield node.name unless bound&.include?(node.name)
        elsif (b = node.bound_variable)
          body, _var, *rest = node.children
          stack << [body, bound ? bound + [b.name] : [b.name]]
          rest.each { |c| stack << [c, bound] }
        else
          node.children.each { |c| stack << [c, bound] }
        end
      end
      self
    end

    def each_node(&block)
      return enum_for(:each_node) unless block
      stack = [self]
      until stack.empty?
        node = stack.pop
        yield node
        stack.concat(node.children.reverse)
      end
      self
    end

    # No Var anywhere. Asking `variables.empty?` built a Set and sorted it
    # to throw both away; this stops at the first one.
    def constant?
      each_free_variable { return false }
      true
    end

    # Nested-array view of the structure, handy for debugging in irb.
    def to_sexp = [self.class.name.split("::").last.downcase.to_sym, *children.map(&:to_sexp)]

    # ---- rewriting --------------------------------------------------------

    # Replace sub-expressions. Accepts a hash or a (pattern, replacement) pair.
    # Keys may be symbols, numbers or whole expressions; matching is structural.
    #
    #   (:x + :y).subs(x: 2)                 # => 2 + y
    #   (:x**2 + :x).subs(:x**2 => :z)       # => z + x
    def subs(pattern, replacement = nil)
      table = pattern.is_a?(Hash) ? pattern : { pattern => replacement }
      table = table.to_h { |k, v| [Expression.lift(k), Expression.lift(v)] }
      replace_with(table)
    end

    def simplify = Simplify.simplify(self)
    def expand = Expand.expand(self)

    # View as an element of a polynomial ring. Without a ring, undeclared
    # variables become ring variables and the coefficient domain is inferred.
    def to_poly(ring = nil)
      ring ||= begin
        # A declaration says which values x takes; x is still an
        # indeterminate. With x in ZZ, factor(x**2 - 1) found "no free
        # variables", and with a in ZZ, x**2 - a**2 had a**2 for a
        # coefficient the factorizer could not take (third review, A2).
        free = variables
        raise DomainError, "#{self} has no free variables to build a ring from" if free.empty?
        constant, table = Expand.table(self)
        base = NumberSet.of(constant)
        table.each do |factors, coeff|
          base = base.join(NumberSet.of(coeff))
          factors.each_key do |b|
            next if b.is_a?(Var) && free.include?(b.name)
            d = Infer.domain(b)
            base = base.join(d) if d
          end
        end
        PolynomialRing.new(base == NN ? ZZ : base, free)
      end
      Polynomial.from_expr(ring, self)
    end

    # Factor over ZZ or QQ and return the product as an expression.
    #
    #   (:x**2 - 1).factor   # => (-1 + x)*(1 + x)
    def factor(extension: nil) = to_poly.factor(extension: extension).to_expr

    # Minimal polynomial over QQ of a constant algebraic expression.
    def minpoly(var = :x) = Algebraic.minpoly_of(self, var).to_expr

    # Derivative with respect to +var+, taken +n+ times.
    def diff(var, n = 1)
      var = Expression.lift(var)
      raise ArgumentError, "can only differentiate with respect to a variable" unless var.is_a?(Var)
      n.times.reduce(self) { |e, _| Differentiate.diff(e, var) }.simplify
    end

    def trigsimp = Trigonometry.trigsimp(self)
    def expand_trig = Trigonometry.expand_trig(self)
    def expand_log = Trigonometry.expand_log(self)
    def logcombine = Trigonometry.logcombine(self)

    # One fraction with the polynomial gcd cancelled: ((x**2 - 1)/(x - 1)).cancel => 1 + x
    def cancel = Fraction.cancel(self)
    alias together cancel

    # Square roots out of denominators: (1/(1 + sqrt(2))).rationalize => -1 + 2**(1/2)
    def rationalize = Fraction.rationalize(self)

    # Evaluate the formal nodes a hold block left behind (MuPAD's eval):
    # integral(...) is integrated, D(f, x) differentiated (unknown functions
    # stay), sum(...) and limit(...) computed. Bottom-up, so nested nodes work.
    def evaluate
      e = map_children(&:evaluate)
      case e
      when Integral then e.definite? ? Integrate.definite(e.integrand, e.var, e.from, e.to) : Integrate.integrate(e.integrand, e.var)
      when Derivative then e.expr.is_a?(Var) ? e : e.expr.diff(e.var, e.order)
      when Sum then Summation.sum(e.term, e.var, e.from, e.to)
      when Product then Products.product(e.term, e.var, e.from, e.to)
      when Limit then Limits.limit(e.expr, e.var, e.point)
      # hold keeps discuss(f, x) as a call; doit answers it with the report
      # (not an Expression - a discussion is an answer, not a value).
      when Fn then e.name == :discuss ? Discussion.discuss(*e.args) : e
      else e
      end
    end
    alias unhold evaluate
    alias doit evaluate

    # x.eq(4) is the equation x = 4; solve(var) solves self = 0.
    def eq(other) = Equation.new(self, other)
    def solve(var = nil, all: true, principal: false, domain: nil) = Solve.solve(self, var, all: all, principal: principal, domain: domain)

    # re, im, conj, arg: the complex parts (see ComplexParts)
    def re = ComplexParts.re(self)
    def im = ComplexParts.im(self)
    def conj = ComplexParts.conj(self)
    def arg = ComplexParts.arg(self)

    def plot(var = nil, from = nil, to = nil, **opts) = Plotting.plot(self, var, from, to, **opts)
    def series(x, a = 0, n = 6) = Limits.series(self, x, a, n)
    def taylor(x, a = 0, n = 6) = Limits.taylor(self, x, a, n)
    def limit(x, a, dir = nil) = Limits.limit(self, x, a, dir)

    # Antiderivative with respect to +var+ (no integration constant). Pieces
    # that could not be integrated stay as unevaluated Integral nodes.
    #
    #   (:x * RCAS.exp(:x)).integrate(:x)   # => -exp(x) + x*exp(x)
    def integrate(var = nil, from = nil, to = nil, generic: false, **range)
      var, from, to = Functions.range_arguments(var, from, to, range, "integrate", discrete: false) if var.nil? || from
      from.nil? ? Integrate.with_special_cases(self, var, generic: generic) : Integrate.definite_with_special_cases(self, var, from, to, generic: generic)
    end

    # Numeric evaluation: every number becomes a Float so roots and function
    # values fold, then the bindings are applied.
    def evalf(digits = nil, **bindings)
      digits ||= bindings.delete(:digits)
      # a Sum or Product with numeric bounds is evaluated before it is
      # floated (its bounds as Floats were no bounds, and it stayed formal)
      if each_node.any? { |n| n.is_a?(Sum) || n.is_a?(Product) }
        target = bindings.empty? ? self : subs(bindings.to_h { |k, v| [k, Expression.lift(v)] })
        done = target.evaluate
        return done.evalf(digits) unless done == target
      end
      return Precision.evalf(self, digits, bindings) if digits
      value = Expression.floatify_tree(self).call(**bindings.transform_values { |v| Expression.floatify(v) })
      folded = value.is_a?(Expression) && value.constant? ? refloat(value) : nil
      value = folded if folded
      value = Numerics.resolve(value) if value.is_a?(Expression) && value.each_node.any? { |n| n.is_a?(Integral) }
      value = value.value if value.is_a?(Num)
      return wide(bindings) || value if overflowed?(value)
      return value unless cancelled?(value, bindings)
      wide(bindings) || (digitless?(value) ? self : value)
    end

    # Not one digit survived: the error bound is larger than the value, and
    # the Float is noise with a sign of its own. gamma(-1 + 10**-15) +
    # 10**15 + 5*10**11 came out as -3e11 against a true 5e11; with no
    # arbitrary precision for gamma there, the expression is the answer.
    def digitless?(value)
      _, error = Decide.float_with_error(self)
      !error.nil? && error >= value.abs
    end

    # A Float that lost most of its digits to cancellation: the running
    # error bound (Decide) says so for a constant. 1 - cdf(30) of
    # Poisson(2) is exact as written and came out as 0 or noise in Floats
    # (fourth review, P-11); the value is taken again in arbitrary
    # precision, which is certified.
    def cancelled?(value, bindings)
      return false unless value.is_a?(Float) && value.finite? && bindings.empty? && variables.empty?
      return false unless each_node.any? { |n| n.is_a?(Add) || n.is_a?(Sub) }
      found, error = Decide.float_with_error(self)
      !found.nil? && error > value.abs * 1e-9
    end

    # Every leaf a Float first is fast and fails on large parts: 200**200
    # and 200! are Infinity, so 200!/199! came out NaN and the Poisson(200)
    # pmf at 200 Infinity (third review, P-4). When that happens the value
    # is taken again in arbitrary precision, which carries the exponents.
    def overflowed?(value)
      value.is_a?(Float) ? !value.finite? : (value.is_a?(Complex) && !(value.real.to_f.finite? && value.imaginary.to_f.finite?))
    end

    def wide(bindings)
      return nil unless (variables - bindings.keys.map(&:to_sym)).empty?
      precise = Precision.evalf(self, Precision::FLOAT_DIGITS, bindings)
      v = precise.to_f
      v.finite? ? v : nil
    rescue StandardError, NotImplementedError, RCAS::Unsupported => rescued
      RCAS.guard!(rescued, refused: true)
      nil
    end

    # Folding can put an exact constant back after the floats went in:
    # exp(-1.0) is 1/e again, and the e never saw floatify. One more pass,
    # kept only when it really ends in a number.
    def refloat(value)
      again = Expression.floatify_tree(value).call
      again = again.value if again.is_a?(Num)
      again.is_a?(Numeric) ? again : nil
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      nil
    end

    # Every number becomes a Float, except integer exponents: x**2 stays
    # x**2 rather than x**2.0.
    def self.floatify_tree(node)
      case node
      when Const then node.name == :undefined ? node : Num.new(node.value.to_f)
      when RootOf then Num.new(floatify(node.value))
      when Num then node.value.is_a?(Float) || node.finite_field? ? node : Num.new(floatify(node.value))
      when Pow
        exp = node.exponent
        exp = floatify_tree(exp) unless exp.is_a?(Num) && exp.value.is_a?(Integer)
        Pow.new(floatify_tree(node.base), exp)
      else node.map_children { |c| floatify_tree(c) }
      end
    end

    # Numeric conversions of constant expressions: (PI**2/6).to_f, Num#to_r, Num#to_i
    def to_f
      value = evalf
      raise TypeError, "#{self} is not a constant expression" unless value.is_a?(Numeric)
      value.is_a?(Complex) ? value : value.to_f
    end

    def self.floatify(value)
      value.is_a?(Complex) ? Complex(float_of(value.real), float_of(value.imaginary)) : float_of(value)
    end

    # to_f without Ruby's "Integer out of Float range" warning: an integer
    # beyond the Floats is the infinity it rounds to, which evalf's wide
    # fallback then takes again in arbitrary precision.
    def self.float_of(value)
      return value.to_f unless value.is_a?(Integer) && value.bit_length > 1023
      value.positive? ? Float::INFINITY : -Float::INFINITY
    end

    # Substitute and simplify. Returns a plain Ruby number when everything is
    # bound, otherwise the remaining expression.
    #
    #   (:x**2 + :y).call(x: 3, y: 1)   # => 10
    #   (:x**2 + :y).call(x: 3)         # => 9 + y
    def call(*args, **bindings)
      unless args.empty?
        names = variables
        raise ArgumentError, "#{self} has #{names.size} variables, got #{args.size} values" unless names.size == args.size
        bindings = names.zip(args).to_h.merge(bindings)
      end
      result = subs(bindings).simplify
      result.is_a?(Num) ? result.value : result
    end

    # Turn the expression into a lambda over its variables (sorted by name).
    #
    #   [1, 2, 3].map(&(:x**2))   # => [1, 4, 9]
    def to_proc
      names = variables
      ->(*args) { call(**names.zip(args).to_h) }
    end

    # ---- display ----------------------------------------------------------

    def to_s = Printer.print(self)
    def inspect = to_s

    # ---- domains ----------------------------------------------------------

    # Smallest of NN, ZZ, QQ, RR, CC that must contain this expression's value,
    # given the declared domains of its variables; nil when unknown.
    def domain = Infer.domain(self)

    def in?(domain) = domain.include?(self)

    # Declare a variable's domain: `x.in(ZZ)`. Returns the variable.
    def in(domain)
      raise TypeError, "only variables can be declared members of a domain" unless is_a?(Var)
      RCAS.assume(name => domain)
      self
    end

    protected

    def replace_with(table)
      return table[self] if table.key?(self)
      return map_children { |c| c.replace_with(table) } unless (b = bound_variable)
      replace_under_binding(table, b)
    end

    # Substitution under a binder: the bounds take the table as it is; the
    # body does not see a pattern that mentions the bound variable (that is
    # another x), and when a replacement would bring in a free variable of
    # the bound name, the bound variable is renamed first so that it does
    # not capture it - integral(y*f(x), x, 0, 1) with y := x is
    # x*integral(f(x1), x1, 0, 1), not integral(x*f(x), x, 0, 1).
    def replace_under_binding(table, b)
      body, var, *rest = children
      rest = rest.map { |c| c.replace_with(table) }
      inner = table.reject { |k, _| k.variables.include?(b.name) }
      return rebuild(body, var, *rest) if inner.empty?
      if inner.each_value.any? { |v| v.variables.include?(b.name) }
        taken = Set.new
        body.each_node { |n| taken << n.name if n.is_a?(Var) }
        inner.each { |k, v| taken.merge(k.variables).merge(v.variables) }
        rest.each { |c| taken.merge(c.variables) }
        fresh = Expression.fresh_variable(b.name, taken)
        body = body.replace_with({ b => fresh })
        var = fresh
      end
      rebuild(body.replace_with(inner), var, *rest)
    end

    # x1, x2, ... : the first name built on +name+ that is not taken.
    def self.fresh_variable(name, taken)
      base = name.to_s.sub(/\d+\z/, "")
      base = "t" if base.empty?
      (1..).lazy.map { |i| :"#{base}#{i}" }.find { |candidate| !taken.include?(candidate) }.then { |n| Var.new(n) }
    end
  end

  # A symbolic variable, e.g. Var.new(:x). Created implicitly from Symbols.
  class Var < Expression
    attr_reader :name

    def initialize(name)
      @name = name.to_sym
      @hash = @name.hash ^ Var.hash
      freeze
    end

    def ==(other)
      case other
      when Var    then other.name == name
      when Symbol then other == name
      else false
      end
    end

    def eql?(other) = other.is_a?(Var) && other.name == name
    def to_sexp = name
  end

  # A numeric literal (Integer, Rational, Float, ...).
  class Num < Expression
    attr_reader :value

    def initialize(value)
      @value = Simplify.normalize_number(value)
      @hash = @value.hash ^ Num.hash
      freeze
    end

    def ==(other)
      case other
      when Num     then other.value == value
      when Numeric then other == value
      else false
      end
    end

    def eql?(other) = other.is_a?(Num) && other.value.eql?(value)
    def to_sexp = value
    def zero? = value.zero?
    def one? = value == 1
    def integer? = value.is_a?(Integer)
    def negative? = value.respond_to?(:negative?) && value.negative?
    def to_r = value.to_r
    def to_i = value.to_i
    def to_c = value.to_c
  end

  # Unary minus.
  class Neg < Expression
    attr_reader :arg

    def initialize(arg)
      @arg = arg
      @hash = arg.hash ^ Neg.hash
      freeze
    end

    def children = [arg]
    def rebuild(arg) = Neg.new(arg)
  end

  # Common base for the four binary operators and Pow.
  class BinaryOp < Expression
    attr_reader :left, :right

    def initialize(left, right)
      @left = left
      @right = right
      @hash = ((left.hash * 31 + right.hash) ^ self.class.hash) & FIXNUM
      freeze
    end

    def children = [left, right]
    def rebuild(left, right) = self.class.new(left, right)
  end

  class Add < BinaryOp; end
  class Sub < BinaryOp; end
  class Mul < BinaryOp; end
  class Div < BinaryOp; end
  class Pow < BinaryOp
    alias base left
    alias exponent right
  end

  # Application of a named function: Fn.new(:sin, [x]).
  class Fn < Expression
    attr_reader :name, :args

    def initialize(name, args)
      @name = name.to_sym
      @args = args.map { |a| Expression.lift(a) }.freeze
      @hash = @args.reduce(@name.hash ^ Fn.hash) { |h, a| (h * 31 + a.hash) & FIXNUM }
      freeze
    end

    def children = args
    def rebuild(*args) = Fn.new(name, args)
    def ==(other) = other.is_a?(Fn) && other.name == name && other.args == args
    def eql?(other) = other.is_a?(Fn) && other.name == name && other.args.eql?(args)
    def to_sexp = [name, *args.map(&:to_sexp)]
  end
end
