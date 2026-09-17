# frozen_string_literal: true

module RCAS
  # Ruby keeps the source of eval'd code (and so lets us read a block's
  # syntax tree) only while this is on. irb turns it on itself; other hosts
  # such as the chat REPL evaluate input with eval, so we turn it on here.
  RubyVM.keep_script_lines = true

  # hold { 1 + 2 } builds the expression tree of the block's source instead of
  # letting Ruby evaluate it, so numeric arithmetic is kept symbolic:
  #
  #   hold { 1 + 2 }            # => 1 + 2
  #   hold { 1 / 2 }.simplify   # => 1/2   (Ruby alone would give 0)
  #   hold { 2 * x**2 / 2 }     # => 2*x**2/2
  #
  # Inside the block: literals become Num, bare identifiers and symbols
  # become Var, the arithmetic operators build nodes, sin/cos/... build Fn,
  # local variables and constants are read from the block's binding, and any
  # other method call is performed normally on the held arguments.
  module Hold
    OPERATORS = { :+ => Add, :- => Sub, :* => Mul, :/ => Div, :** => Pow }.freeze
    LITERALS = %i[LIT INTEGER FLOAT RATIONAL IMAGINARY SYM].freeze
    # Calls kept as formal nodes instead of being evaluated; see Expression#evaluate.
    FORMAL = %i[integrate diff sum product limit discuss].freeze

    module_function

    IDENTIFIER = RCAS::IDENTIFIER

    def hold(block)
      ast = begin
        RubyVM::AbstractSyntaxTree.of(block, keep_script_lines: true)
      rescue ArgumentError, RuntimeError, IOError, Errno::ENOENT
        nil
      end
      if ast.nil?
        warn "rcas: hold could not read the block's source, evaluating it instead"
        return Expression.lift(block.call)
      end
      Builder.new(block.binding).build(ast.children.last)
    end

    # The same for a line of source text instead of a block: the expression
    # the line builds, held. +context+ is the binding its names are read in.
    # nil for an empty line; raises SyntaxError on one that does not parse
    # and ArgumentError on a node hold cannot keep. RCAS::Results uses it
    # for In[n].
    def source(text, context = nil)
      body = RubyVM::AbstractSyntaxTree.parse(text).children.last
      body = body.children.first if body&.type == :BEGIN # an empty line, or a comment
      body.nil? ? nil : Builder.new(context || TOPLEVEL_BINDING).build(body)
    end

    class Builder
      def initialize(binding)
        @binding = binding
      end

      def build(node)
        case node.type
        when *LITERALS then literal(node.children.first)
        when :OPCALL then operator(node)
        when :LVAR, :DVAR then lift(@binding.local_variable_get(node.children.first))
        when :VCALL then identifier(node.children.first)
        when :FCALL then function(node.children[0], arguments(node.children[1]))
        when :CALL then call(build(node.children[0]), node.children[1], arguments(node.children[2]))
        when :BLOCK then node.children.map { |c| build(c) }.last
        when :BEGIN then build(node.children.first)
        when :HASH then hash_node(node)
        when :DOT2, :DOT3 then range_node(node)
        when :CONST, :COLON2, :COLON3 then lift(@binding.eval(constant_path(node)))
        when :SELF then lift(@binding.receiver)
        else evaluate(node)
        end
      end

      private

      # Anything else (a block call, a string, an array, ...) is evaluated as
      # written and the value is used.
      def evaluate(node)
        source = begin
          node.source
        rescue StandardError
          nil
        end
        raise ArgumentError, "hold: can't keep a #{node.type} node (line #{node.first_lineno})" if source.nil?
        lift(@binding.eval(source))
      end

      def literal(value)
        case value
        when Symbol then Var.new(value)
        when Numeric then Num.new(value)
        else raise ArgumentError, "hold: unsupported literal #{value.inspect}"
        end
      end

      def operator(node)
        receiver, op, list = node.children
        left = build(receiver)
        if list.nil?
          return Neg.new(left) if op == :-@
          return left if op == :+@
          raise ArgumentError, "hold: unsupported unary operator #{op}"
        end
        right = build(list.children.first)
        return Equation.new(left, right) if op == :== # hold { x**2 - 3 == 0 } is the equation
        return Inequality.new(left, :!=, right) if op == :!=
        klass = OPERATORS[op]
        klass ? klass.new(left, right) : lift(left.public_send(op, right))
      end

      # A bare name: a real method of the block's self if there is one
      # (irb's auto-symbols included), otherwise a variable.
      # A bare name: a local of the block's binding when one is set (irb
      # re-parses each line on its own, so earlier locals show up as bare
      # names), else a real method of the block's self (irb's auto-symbols
      # included), else a variable. A hoisted-but-unassigned local is nil
      # and is skipped.
      def identifier(name)
        if @binding.local_variable_defined?(name) && !(value = @binding.local_variable_get(name)).nil?
          return lift(value)
        end
        value = @binding.receiver.__send__(name)
        value.nil? ? Var.new(name) : lift(value) # Kernel#p without arguments returns nil: an indeterminate
      rescue NameError
        Var.new(name)
      end

      def function(name, args)
        return Pow.new(args.first, Num.new(Rational(1, 2))) if name == :sqrt && args.size == 1
        return Fn.new(name, args) if Functions::NAMES.include?(name)
        return formal(name, args) if FORMAL.include?(name)
        receiver = @binding.receiver
        target = receiver.respond_to?(name, true) ? receiver : RCAS
        lift(target.__send__(name, *args))
      end

      def call(receiver, name, args)
        klass = OPERATORS[name]
        return klass.new(receiver, args.first) if klass && args.size == 1
        return Neg.new(receiver) if name == :-@
        # RCAS.integrate(f, x) is the same call as a bare integrate(f, x):
        # outside bin/rcas that qualified form is how the manual writes it.
        # x.in?(ZZ) inside a block is the statement, not the answer, the way
        # == is an Equation here and != an Inequality.
        return Membership.new(receiver, args.first) if name == :in? && args.size == 1 && args.first.is_a?(Domain)
        return function(name, args) if receiver.equal?(RCAS)
        return formal(name, [receiver] + args) if FORMAL.include?(name) && receiver.is_a?(Expression)
        lift(receiver.public_send(name, *args))
      end

      # integrate(f, x) / integrate(f, x: 0..1), diff(f, x, n), sum(f, k, a, b) /
      # sum(f, k: 1..n), limit(f, x, a) / limit(f, x: 0), discuss(f, x) as
      # unevaluated nodes.
      def formal(name, args)
        opts = args.last.is_a?(Hash) ? args.pop : {}
        f = Expression.lift(args.shift)
        case name
        when :integrate
          var, from, to = Functions.range_arguments(*args.values_at(0, 1, 2), opts, "integrate", discrete: false) if args.size < 2 && (opts.any? || args.size == 1)
          var, from, to = args.values_at(0, 1, 2) if args.size >= 2
          Integral.new(f, Expression.lift(var), from && Expression.lift(from), to && Expression.lift(to))
        when :diff
          var, n = args
          Derivative.new(f, Expression.lift(var), n.is_a?(Num) ? n.value : (n || 1))
        when :sum, :product
          var, from, to = Functions.range_arguments(*args.values_at(0, 1, 2), opts, name.to_s, discrete: true)
          (name == :sum ? Sum : Product).new(f, Expression.lift(var), Expression.lift(from), Expression.lift(to))
        when :limit
          opts = opts.dup
          opts.delete(:dir)
          var, point, = Functions.point_arguments(args[0], args[1], nil, opts, "limit")
          Limit.new(f, Expression.lift(var), Expression.lift(point))
        when :discuss
          # A curve discussion has no node of its own: it is a question,
          # not a value, and steps { discuss(f, x) } is what holds it.
          Fn.new(:discuss, args.first ? [f, Expression.lift(args.first)] : [f])
        end
      end

      # Keyword arguments such as `x: 0..1` (symbol keys stay symbols).
      def hash_node(node)
        list = node.children.first
        return {} if list.nil?
        list.children.compact.each_slice(2).to_h do |key, value|
          k = LITERALS.include?(key.type) && key.children.first.is_a?(Symbol) ? key.children.first : build(key)
          [k, build(value)]
        end
      end

      def range_node(node)
        lo, hi = node.children.map { |c| c.nil? ? nil : build(c) }
        Range.new(lo, hi, node.type == :DOT3)
      end

      def arguments(list)
        return [] if list.nil?
        list.children.compact.map { |c| build(c) }
      end

      def constant_path(node)
        case node.type
        when :CONST then node.children.first.to_s
        when :COLON3 then "::#{node.children.first}"
        when :COLON2 then "#{constant_path(node.children[0])}::#{node.children[1]}"
        end
      end

      # Expressions, symbols and numbers become nodes; anything else
      # (a polynomial, a matrix, a string) is passed through untouched.
      def lift(value)
        Expression.lift(value)
      rescue TypeError
        value
      end
    end
  end

  def self.hold(&block) = Hold.hold(block)
end
