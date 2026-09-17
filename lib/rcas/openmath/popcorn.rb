# frozen_string_literal: true

require "strscan"

module RCAS
  module OpenMath
    # POPCORN [HR09]: a linear notation for OpenMath objects meant for people
    # to read and write, where XML is meant for machines.
    #
    #   RCAS.openmath(:x + 1).to_popcorn     # => "$x + 1"
    #   RCAS.from_popcorn("$x^2 + 1")        # => x**2 + 1, unevaluated
    #
    # A third encoding of the objects in objects.rb, beside XML - and the one
    # a person types. Variables carry a $ so that a bare name can be short for
    # a symbol (`sin` for transc1.sin), which is the trick the whole notation
    # turns on.
    #
    # Two spellings of the same object: `render` sugars what it can, and
    # `render(sugar: false)` writes every symbol out as cd.name, which is what
    # Node#to_s uses - a beginner should see arith1.plus before they see +.
    #
    #   plain:   arith1.plus(arith1.power($x, 2), 1)
    #   sugared: $x^2 + 1
    #
    # The grammar is the one of the reference implementation
    # (org.symcomp.openmath, Apache-2.0; this is an independent
    # implementation from the published grammar, not a translation of it).
    # Two details of it are easy to get wrong: ~ is relation2.approx, not
    # relation1, and a minus sign in front of a literal is part of the
    # literal - -17 is the integer -17, not unary_minus(17).
    #
    # Not supported: the typed-expression form `a::b`. It raises rather than
    # guessing.
    module Popcorn
      # symbol => [text, precedence, association]. The levels are the ones of
      # the published grammar; the associations are what keep the writing
      # faithful, which the reference implementation's precedences do not:
      # it gives plus 70 and minus 75, and then writes plus($a, minus($b, $c))
      # as "$a + $b - $c", which reads back as minus(plus($a, $b), $c). Here
      # the two share a level and the right operand is written one level
      # tighter, so the tree that is read is the tree that was written.
      INFIX = {
        %w[prog1 block]                => [";",   10,  :flat],
        %w[prog1 assign]               => [":=",  20,  :single],
        %w[logic1 implies]             => ["==>", 30,  :single],
        %w[logic1 equivalent]          => ["<=>", 30,  :single],
        %w[logic1 or]                  => ["or",  40,  :left],
        %w[logic1 and]                 => ["and", 50,  :left],
        %w[relation1 eq]               => ["=",   60,  :single],
        %w[relation1 lt]               => ["<",   60,  :single],
        %w[relation1 leq]              => ["<=",  60,  :single],
        %w[relation1 gt]               => [">",   60,  :single],
        %w[relation1 geq]              => [">=",  60,  :single],
        %w[relation1 neq]              => ["!=",  60,  :single],
        %w[relation2 approx]           => ["~",   60,  :single],
        %w[interval1 interval]         => ["..",  70,  :single],
        %w[arith1 plus]                => ["+",   80,  :flat],
        %w[arith1 minus]               => ["-",   80,  :left],
        %w[arith1 times]               => ["*",   90,  :flat],
        %w[arith1 divide]              => ["/",   90,  :left],
        %w[arith1 power]               => ["^",   100, :single],
        %w[complex1 complex_cartesian] => ["|",   110, :single],
        %w[nums1 rational]             => ["//",  120, :single]
      }.freeze

      UNARY_MINUS = %w[arith1 unary_minus].freeze
      UNARY_PRECEDENCE = 85
      ATOM = 130

      BRACKETS = { %w[list1 list] => %w{[ ]}, %w[set1 set] => %w[{ }] }.freeze

      # The reference renderer spaces the additive operators and writes the
      # multiplicative ones tight: a + b, but a*b and a^2. We follow it.
      TIGHT = ["*", "/", "^", "|", "//"].freeze

      KEYWORDS = %w[and or if then else endif while do endwhile].freeze

      IDENTIFIER = /[A-Za-z_][A-Za-z0-9_]*/.freeze

      # A bare name stands for a symbol. The reference implementation carries
      # a table of some 570 of them; ours is derived from the phrasebook, so
      # every symbol rcas knows may be written short and nothing else may.
      # Names of our own content dictionary never sugar - rcas1.gamma is
      # written out, because no one else would know what `gamma` meant.
      def self.sugar_table
        @sugar_table ||= begin
          keys = Phrasebook::DECODE_APPLY.keys + Phrasebook::DECODE_CONST.keys +
                 [%w[fns1 lambda], %w[list1 list], %w[set1 set], UNARY_MINUS]
          counts = Hash.new(0)
          keys.each { |cd, name| counts[name] += 1 unless cd == RCAS_CD }
          keys.reject { |cd, _| cd == RCAS_CD }
              .select { |_, name| counts[name] == 1 }
              .to_h { |cd, name| [name, [cd, name]] }
              .freeze
        end
      end

      def self.symbol_for(name) = sugar_table[name]
      def self.sugar_for(key) = sugar_table[key.last] == key ? key.last : nil

      module_function

      # ---- writing -----------------------------------------------------------

      def render(node, sugar: true)
        node = node.object while node.is_a?(Root)
        emit(node, 0, sugar)
      end

      def emit(node, prec, sugar)
        text, own = emit_bare(node, sugar)
        text = "#{atomic(text, own)}:#{node.id}" if node.id
        own = ATOM if node.id
        own < prec ? "(#{text})" : text
      end

      def atomic(text, own) = own < ATOM ? "(#{text})" : text

      # The rendered text and the precedence it binds at.
      def emit_bare(node, sugar)
        case node
        when Int           then [node.value.to_s, node.value.negative? ? UNARY_PRECEDENCE : ATOM]
        when Double        then [float_text(node.value), node.value.negative? ? UNARY_PRECEDENCE : ATOM]
        when Text          then [string_text(node.value), ATOM]
        when Bytes         then ["%#{[node.value].pack('m0')}%", ATOM]
        when Variable      then ["$#{node.name}", ATOM]
        when ContentSymbol then [symbol_text(node, sugar), ATOM]
        when Application   then application(node, sugar)
        when Bind          then [binding_text(node, sugar), ATOM]
        when Attribution   then [attribution_text(node, sugar), ATOM]
        when Error         then ["#{emit(node.symbol, ATOM, sugar)}!(#{list_text(node.args, sugar)})", ATOM]
        when Reference     then [reference_text(node), ATOM]
        when Foreign       then ["`#{node.content}`", ATOM]
        else raise EncodeError, "no POPCORN notation for #{node.class}"
        end
      end

      def symbol_text(node, sugar)
        short = sugar && node.official? ? Popcorn.sugar_for(node.key) : nil
        short || "#{node.cd}.#{node.name}"
      end

      def application(node, sugar)
        head = node.head
        return [plain_call(node, sugar), ATOM] unless head.is_a?(ContentSymbol) && sugar && head.official?

        if (brackets = BRACKETS[head.key])
          return ["#{brackets.first}#{list_text(node.args, sugar)}#{brackets.last}", ATOM]
        end
        if head.key == UNARY_MINUS && node.args.size == 1
          return ["-#{emit(node.args.first, UNARY_PRECEDENCE, sugar)}", UNARY_PRECEDENCE]
        end
        if (op = INFIX[head.key]) && infix?(op, node.args.size)
          return [infix_text(op, node.args, sugar), op[1]]
        end
        [plain_call(node, sugar), ATOM]
      end

      def infix?(op, count) = op.last == :flat ? count >= 2 : count == 2

      def infix_text(op, args, sugar)
        text, precedence, association = op
        parts = args.each_with_index.map do |arg, i|
          # the first operand of a left-associative or n-ary operator may
          # share its level; everything else is written one level tighter
          inner = precedence + (i.zero? && association != :single ? 0 : 1)
          # a + (-b) is written a - b, as the reference implementation does
          if i.positive? && text == "+" && negated(arg)
            " - #{emit(negated(arg), inner, sugar)}"
          else
            separator = i.zero? ? "" : (TIGHT.include?(text) ? text : " #{text} ")
            "#{separator}#{emit(arg, inner, sugar)}"
          end
        end
        parts.join
      end

      # The argument of an arith1.unary_minus application, or nil.
      def negated(node)
        return nil unless node.is_a?(Application) && node.head.is_a?(ContentSymbol)
        return nil unless node.head.key == UNARY_MINUS && node.args.size == 1
        node.args.first
      end

      def plain_call(node, sugar) = "#{emit(node.head, ATOM, sugar)}(#{list_text(node.args, sugar)})"

      def binding_text(node, sugar)
        vars = node.vars.map { |v| emit(v, 0, sugar) }.join(", ")
        "#{emit(node.binder, ATOM, sugar)}[#{vars} -> #{emit(node.body, 0, sugar)}]"
      end

      def attribution_text(node, sugar)
        pairs = node.pairs.map { |p| "#{emit(p.key, 0, sugar)} -> #{emit(p.value, 0, sugar)}" }
        "#{emit(node.object, ATOM, sugar)}{#{pairs.join(', ')}}"
      end

      def reference_text(node)
        name = node.href.sub(/\A#/, "")
        node.href.start_with?("#") && name.match?(/\A#{IDENTIFIER}\z/o) ? "##{name}" : "###{node.href}##"
      end

      def list_text(nodes, sugar) = nodes.map { |n| emit(n, 0, sugar) }.join(", ")

      def float_text(value)
        raise EncodeError, "POPCORN has no notation for #{value}" unless value.finite?
        text = value.to_s.sub("e+", "e")
        text.include?(".") ? text : "#{text}.0"
      end

      def string_text(value) = %("#{value.gsub('\\', '\\\\\\\\').gsub('"', '\"')}")

      # ---- reading -----------------------------------------------------------

      def parse(source) = Root.new(Parser.new(source).parse)

      # Recursive descent over the published grammar, one method per level of
      # the precedence chain.
      class Parser
        def initialize(source)
          @s = StringScanner.new(source.to_s)
        end

        def parse
          value = expression
          skip
          raise ParseError, "unexpected #{@s.rest[0, 20].inspect}" unless @s.eos?
          value
        end

        def expression = block

        private

        def skip
          loop do
            @s.skip(/\s+/)
            break unless @s.scan(%r{/\*.*?\*/}m)
          end
        end

        def accept(pattern)
          skip
          @s.scan(pattern)
        end

        # An operator that must not swallow the start of a longer one, and a
        # word operator that must not swallow an identifier.
        def operator(*texts)
          skip
          texts.sort_by { |t| -t.size }.each do |text|
            next unless @s.check(/#{Regexp.escape(text)}/)
            next if text.match?(/\A\w+\z/) && @s.check(/#{text}#{Popcorn::IDENTIFIER}/o)
            next if text == "<" && @s.check(/<[=>]/)
            next if text == ">" && @s.check(/>=/)
            next if text == "<=" && @s.check(/<=>/)
            next if text == "-" && @s.check(/->/)
            next if text == "/" && @s.check(%r{//})
            next if text == "!" && @s.check(/!=/)
            next if text == ":" && @s.check(/:[:=]/)
            next if text == "=" && @s.check(/==>/)
            return @s.scan(/#{Regexp.escape(text)}/)
          end
          nil
        end

        def apply(cd, name, *args) = Application.new(OpenMath.sym(cd, name), args)

        # arith1.plus, arith1.times and prog1.block are n-ary: a + b + c is
        # one application of three arguments, not two of two.
        def flat(cd, name, left, right)
          key = [cd, name]
          if left.is_a?(Application) && left.head.is_a?(ContentSymbol) && left.head.key == key
            Application.new(left.head, [*left.args, right])
          else
            apply(cd, name, left, right)
          end
        end

        def block
          value = assign
          value = flat("prog1", "block", value, assign) while operator(";")
          value
        end

        def assign
          value = implication
          operator(":=") ? apply("prog1", "assign", value, implication) : value
        end

        def implication
          value = disjunction
          if (op = operator("==>", "<=>"))
            return apply("logic1", op == "==>" ? "implies" : "equivalent", value, disjunction)
          end
          value
        end

        def disjunction
          value = conjunction
          value = apply("logic1", "or", value, conjunction) while operator("or")
          value
        end

        def conjunction
          value = relation
          value = apply("logic1", "and", value, relation) while operator("and")
          value
        end

        RELATIONS = { "=" => %w[relation1 eq], "<" => %w[relation1 lt], "<=" => %w[relation1 leq],
                      ">" => %w[relation1 gt], ">=" => %w[relation1 geq], "!=" => %w[relation1 neq],
                      "<>" => %w[relation1 neq], "~" => %w[relation2 approx] }.freeze

        def relation
          value = interval
          return value unless (op = operator(*RELATIONS.keys))
          cd, name = RELATIONS[op]
          apply(cd, name, value, interval)
        end

        def interval
          value = sum
          operator("..") ? apply("interval1", "interval", value, sum) : value
        end

        def sum
          value = negation
          loop do
            if operator("+")
              value = flat("arith1", "plus", value, negation)
            elsif operator("-")
              value = apply("arith1", "minus", value, negation)
            else
              return value
            end
          end
        end

        # -17 is the integer -17; -$x is an application of unary_minus.
        def negation
          return product unless operator("-")
          value = product
          case value
          when Int then Int.new(-value.value)
          when Double then Double.new(-value.value)
          else apply("arith1", "unary_minus", value)
          end
        end

        def product
          value = power
          loop do
            if operator("*")
              value = flat("arith1", "times", value, power)
            elsif operator("/")
              value = apply("arith1", "divide", value, power)
            else
              return value
            end
          end
        end

        def power
          value = complex
          operator("^") ? apply("arith1", "power", value, complex) : value
        end

        def complex
          value = rational
          operator("|") ? apply("complex1", "complex_cartesian", value, rational) : value
        end

        def rational
          value = postfix
          operator("//") ? apply("nums1", "rational", value, postfix) : value
        end

        # Everything that attaches to an atom: a call, an error call, an
        # attribution, a binding and an id.
        def postfix
          value = atom
          loop do
            if operator("!")
              expect("(")
              value = Error.new(value, arguments(")"))
            elsif accept(/\(/)
              value = Application.new(value, arguments(")"))
            elsif accept(/\{/)
              value = attribution(value)
            elsif accept(/\[/)
              value = binding(value)
            elsif operator(":")
              name = accept(Popcorn::IDENTIFIER) or raise ParseError, "expected an id after :"
              value = value.identified(name)
            elsif @s.check(/\s*::/)
              raise ParseError, "typed expressions (a::b) are not supported"
            else
              return value
            end
          end
        end

        def arguments(closing)
          return [] if accept(/#{Regexp.escape(closing)}/)
          args = [expression]
          args << expression while operator(",")
          expect(closing)
          args
        end

        def attribution(object)
          pairs = []
          loop do
            key = expression
            expect("->")
            pairs << AttrPair.new(key, expression)
            break unless operator(",")
          end
          expect("}")
          Attribution.new(pairs, object)
        end

        def binding(binder)
          vars = [expression]
          vars << expression while operator(",")
          expect("->")
          body = expression
          expect("]")
          raise ParseError, "a binding binds variables" unless vars.all? { |v| v.is_a?(Variable) }
          Bind.new(binder, BVar.new(vars), body)
        end

        def expect(text)
          operator(text) or raise ParseError, "expected #{text} at #{@s.rest[0, 20].inspect}"
        end

        def atom
          skip
          if accept(/\(/)
            value = expression
            expect(")")
            return value
          end
          literal || bracketed || conditional || name_atom ||
            raise(ParseError, "expected an object at #{@s.rest[0, 20].inspect}")
        end

        def literal
          if (hex = accept(/0f\h+/))       then Double.new([hex[2..]].pack("H*").unpack1("G"))
          elsif (hex = accept(/0x\h+/))    then Int.new(hex[2..].to_i(16))
          elsif (f = accept(/\d+\.\d+(?:[eE]-?\d+)?/)) then Double.new(Float(f))
          elsif (i = accept(/\d+/))        then Int.new(i.to_i)
          elsif (s = accept(/"(?:[^"\\]|\\.)*"/)) then Text.new(unescape(s[1..-2]))
          elsif (b = accept(%r{%[A-Za-z0-9+/=]*%})) then Bytes.new(b[1..-2].unpack1("m") || "")
          elsif (f = accept(/`[^`]*`/))    then Foreign.new(f[1..-2])
          elsif (g = accept(/##.*?##/m))   then Reference.new(g[2..-3])
          elsif (r = accept(/\##{Popcorn::IDENTIFIER}/o)) then Reference.new(r)
          end
        end

        def bracketed
          if accept(/\[/) then apply("list1", "list", *arguments("]"))
          elsif accept(/\{/) then apply("set1", "set", *arguments("}"))
          end
        end

        def conditional
          if operator("if")
            condition = expression
            expect("then")
            yes = expression
            expect("else")
            no = expression
            expect("endif")
            apply("prog1", "if", condition, yes, no)
          elsif operator("while")
            condition = expression
            expect("do")
            body = expression
            expect("endwhile")
            apply("prog1", "while", condition, body)
          end
        end

        # $x is a variable, cd.name a symbol, and a bare name is short for a
        # symbol the phrasebook knows.
        def name_atom
          if accept(/\$/)
            Variable.new(identifier || raise(ParseError, "expected a name after $"))
          elsif (name = identifier)
            raise ParseError, "#{name} is a keyword" if Popcorn::KEYWORDS.include?(name)
            if accept(/\./)
              ContentSymbol.new(name, identifier || raise(ParseError, "expected a symbol name"))
            else
              key = Popcorn.symbol_for(name) or raise ParseError, "unknown symbol #{name}"
              OpenMath.sym(*key)
            end
          end
        end

        def identifier
          quoted = accept(/'[^']*'/)
          return quoted[1..-2] if quoted
          accept(Popcorn::IDENTIFIER)
        end

        def unescape(text) = text.gsub(/\\(.)/) { Regexp.last_match(1) }
      end
    end
  end
end
