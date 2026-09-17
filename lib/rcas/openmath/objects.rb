# frozen_string_literal: true

module RCAS
  # OpenMath [OM19]: the abstract objects of the standard.
  #
  # An OpenMath object is not XML. XML is one of its encodings - the binary
  # encoding and strict content MathML are others - so the classes below are
  # the thing itself, and OpenMath::XML is one way of writing it down:
  #
  #   om = RCAS.openmath(:x**2 + 1)   # => arith1.plus(arith1.power(x, 2), 1)
  #   om.to_xml                       # => "<OMOBJ ...>...</OMOBJ>"
  #   RCAS.from_openmath(om.to_xml)   # => x**2 + 1, unevaluated
  #
  # Thirteen classes for the standard's thirteen kinds of object. Six of the
  # standard's own words would shadow something inside this module - Integer,
  # Float, String and Object are Ruby's, Binding is Ruby's too, and Symbol
  # already means the indeterminate :x in rcas - so those are Int, Double,
  # Text, Root, Bind and ContentSymbol. The other seven keep their word.
  #
  # Note that OpenMath::Error is a *node*, not an exception: OME is the
  # object you get back for a symbol the sender could not evaluate. The
  # exceptions here are ParseError and EncodeError.
  #
  # Sources: the OpenMath 2.0 standard [OM19, ch. 2] for the objects, [OM19,
  # ch. 4] for the XML encoding, the official content dictionaries for the
  # phrasebook.
  module OpenMath
    # Where the official content dictionaries live, and a private CD of our
    # own for the names rcas has and OpenMath has not (gamma, zeta, erf, the
    # integral functions, RootOf). A cdbase is an identifier, not a URL that
    # has to resolve.
    CDBASE      = "http://www.openmath.org/cd"
    RCAS_CDBASE = "https://github.com/no-dashes/rubyCAS/cd"
    RCAS_CD     = "rcas1"

    OBJECT_VERSION = "2.0"

    class ParseError < StandardError; end
    class EncodeError < StandardError; end

    # Common behaviour: frozen, structurally compared, walkable.
    class Node
      # An optional xml:id, carried so structure sharing survives a round
      # trip. Never part of equality: two objects are equal when they say
      # the same thing, whatever they are called.
      attr_reader :id

      def children = []
      def leaf? = children.empty?

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

      # A copy carrying an xml:id (the nodes themselves are frozen).
      def identified(id)
        copy = dup
        copy.instance_variable_set(:@id, id&.to_s&.freeze)
        copy.freeze
      end

      def ==(other) = other.class == self.class && other.state == state
      alias eql? ==
      def hash = [self.class, *state].hash

      def to_xml(**opts) = XML.encode(self, **opts)

      # The rcas object this stands for (see Phrasebook).
      def to_expression = Phrasebook.to_expression(self)

      def inspect = to_s

      protected

      # What equality and #hash look at; the children unless said otherwise.
      def state = children
    end

    # OMI, OMF, OMSTR, OMB: an object that is just its value.
    class Value < Node
      attr_reader :value

      def initialize(value)
        @value = convert(value)
        freeze
      end

      def to_s = value.to_s

      protected

      def state = [value]
    end

    # OMI: an integer of any size.
    class Int < Value
      private def convert(v) = Integer(v)
    end

    # OMF: an IEEE 754 double.
    class Double < Value
      private def convert(v) = Float(v)
    end

    # OMSTR: a string of Unicode characters.
    class Text < Value
      def to_s = value.inspect
      private def convert(v) = v.to_s.dup.freeze
    end

    # OMB: a byte array.
    class Bytes < Value
      def to_s = "bytes(#{value.bytesize})"
      private def convert(v) = v.to_s.b.freeze
    end

    # OMV: a variable. rcas calls this an indeterminate.
    class Variable < Node
      attr_reader :name

      def initialize(name)
        @name = name.to_s.dup.freeze
        freeze
      end

      def to_s = name

      protected

      def state = [name]
    end

    # OMS: a symbol, i.e. the name of a mathematical object in a content
    # dictionary. arith1.plus is the addition of the CD arith1, whatever the
    # sender happens to call it.
    class ContentSymbol < Node
      attr_reader :cd, :name, :cdbase

      def initialize(cd, name, cdbase: nil)
        @cd = cd.to_s.dup.freeze
        @name = name.to_s.dup.freeze
        @cdbase = cdbase&.to_s&.dup&.freeze
        freeze
      end

      def key = [cd, name]
      def official? = cdbase.nil? || cdbase == CDBASE
      def to_s = "#{cd}.#{name}"

      protected

      def state = [cd, name, cdbase]
    end

    # OMA: an application, head first.
    class Application < Node
      attr_reader :head, :args

      def initialize(head, *args)
        args = args.first if args.size == 1 && args.first.is_a?(Array)
        @head = OpenMath.lift(head)
        @args = args.map { |a| OpenMath.lift(a) }.freeze
        freeze
      end

      def children = [head, *args]
      def to_s = "#{head}(#{args.join(', ')})"
    end

    # OMBVAR: the bound variables of a binding.
    class BVar < Node
      attr_reader :vars

      def initialize(*vars)
        vars = vars.first if vars.size == 1 && vars.first.is_a?(Array)
        @vars = vars.map { |v| v.is_a?(Node) ? v : Variable.new(v) }.freeze
        freeze
      end

      def children = vars
      def to_s = vars.join(", ")
    end

    # OMBIND: a binding - fns1.lambda[x -> x^2] and everything built on it.
    class Bind < Node
      attr_reader :binder, :bvar, :body

      def initialize(binder, bvar, body)
        @binder = OpenMath.lift(binder)
        @bvar = bvar.is_a?(BVar) ? bvar : BVar.new(bvar)
        @body = OpenMath.lift(body)
        freeze
      end

      def vars = bvar.vars
      def children = [binder, bvar, body]
      def to_s = "#{binder}[#{bvar} -> #{body}]"
    end

    # One key/value pair of an attribution.
    class AttrPair < Node
      attr_reader :key, :value

      def initialize(key, value)
        @key = OpenMath.lift(key)
        @value = OpenMath.lift(value)
        freeze
      end

      def children = [key, value]
      def to_s = "#{key}: #{value}"
    end

    # OMATTR: an object with attributes attached.
    class Attribution < Node
      attr_reader :pairs, :object

      def initialize(pairs, object)
        @pairs = pairs.map { |p| p.is_a?(AttrPair) ? p : AttrPair.new(*p) }.freeze
        @object = OpenMath.lift(object)
        freeze
      end

      def children = [*pairs, object]
      def to_s = "#{object}{#{pairs.join(', ')}}"
    end

    # OME: an error object. Data, not an exception - it is what a sender
    # hands back for a symbol it could not deal with.
    class Error < Node
      attr_reader :symbol, :args

      def initialize(symbol, *args)
        args = args.first if args.size == 1 && args.first.is_a?(Array)
        @symbol = OpenMath.lift(symbol)
        @args = args.map { |a| OpenMath.lift(a) }.freeze
        freeze
      end

      def children = [symbol, *args]
      def to_s = "error(#{[symbol, *args].join(', ')})"
    end

    # OMR: a reference to another object, by which a tree becomes a DAG.
    class Reference < Node
      attr_reader :href

      def initialize(href)
        @href = href.to_s.dup.freeze
        freeze
      end

      def to_s = "&#{href}"

      protected

      def state = [href]
    end

    # OMOBJ: the wrapper that says "what follows is an OpenMath object".
    # It carries the version and nothing mathematical, so it prints as its
    # own contents.
    class Root < Node
      attr_reader :object, :version

      def initialize(object, version: OBJECT_VERSION)
        @object = OpenMath.lift(object)
        @version = version.to_s.dup.freeze
        freeze
      end

      def children = [object]
      def to_s = object.to_s
    end

    module_function

    # Ruby values as OpenMath objects: 3, 2.5, "text", :x. Anything more
    # mathematical than that goes through the Phrasebook.
    def lift(obj)
      case obj
      when Node    then obj
      when Integer then Int.new(obj)
      when Float   then Double.new(obj)
      when String  then Text.new(obj)
      when Symbol  then Variable.new(obj)
      else raise TypeError, "can't turn #{obj.class} into an OpenMath object"
      end
    end

    # The symbol +name+ of the content dictionary +cd+: sym("arith1", "plus")
    def sym(cd, name, cdbase: nil) = ContentSymbol.new(cd, name, cdbase: cdbase)

    # A symbol of rcas's own content dictionary, for what OpenMath has no
    # official name for.
    def rcas_sym(name) = ContentSymbol.new(RCAS_CD, name, cdbase: RCAS_CDBASE)

    # Replace every OMR by the object it points at, so the result is a tree.
    # Unknown targets are left alone.
    def dereference(node, table = nil)
      table ||= node.each_node.filter_map { |n| [n.id, n] if n.id }.to_h
      return node if table.empty?
      expand(node, table, 0)
    end

    def expand(node, table, depth)
      raise ParseError, "cyclic references" if depth > 64
      if node.is_a?(Reference)
        target = table[node.href.sub(/\A#/, "")]
        return node unless target
        return expand(target, table, depth + 1)
      end
      children = node.children.map { |c| expand(c, table, depth + 1) }
      children == node.children ? node : rebuild(node, children)
    end

    def rebuild(node, children)
      case node
      when Root        then Root.new(children.first, version: node.version)
      when Application then Application.new(children.first, children[1..])
      when BVar        then BVar.new(children)
      when Bind        then Bind.new(children[0], children[1], children[2])
      when AttrPair    then AttrPair.new(children[0], children[1])
      when Attribution then Attribution.new(children[0..-2], children.last)
      when Error       then Error.new(children.first, children[1..])
      else node
      end
    end
  end
end
