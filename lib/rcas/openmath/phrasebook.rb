# frozen_string_literal: true

module RCAS
  module OpenMath
    # The phrasebook: the one place where rcas and OpenMath are told about
    # each other. Nothing outside this file knows an OpenMath symbol, and no
    # expression class carries a to_openmath of its own - the table below is
    # the whole vocabulary, in both directions.
    #
    # One declaration, two indexes. Most rows are symmetric and say so in a
    # line; the ones where the two systems disagree carry a pair of
    # procedures instead. They disagree in three ways:
    #
    # - decoding is many to one. arith1.root(x, 2) and arith1.power(x, 1/2)
    #   are both Pow, transc1.ln and transc1.log both reach rcas's log.
    # - OpenMath's operators are n-ary, rcas's are binary. Decoding folds
    #   left, encoding writes the tree it was given: construction never
    #   rewrites, so a + b + c stays the tree that was typed.
    # - the interesting nodes are bindings, not applications. An integral,
    #   a sum, a derivative and a limit all carry fns1.lambda in OpenMath
    #   and a bound variable in rcas.
    #
    # Nothing is dropped in silence. A symbol with no row decodes to a held
    # Fn named "cd.name" (an unknown function, exactly as u(n + 1) is), and
    # an unknown function encodes back to the symbol it came from, so a
    # document rcas does not understand survives the round trip. What rcas
    # cannot express at all - a one-sided limit, a bare lambda - stays as
    # such an Fn rather than being bent into the nearest node.
    #
    # Sources: the official content dictionaries [OM19]; arith1, nums1,
    # transc1, relation1, logic1, fns1, calculus1, limit1, integer1,
    # combinat1, complex1, rounding1, setname1, interval1, piece1, linalg2.
    # The names rcas has and OpenMath has not (gamma, zeta, erf, Ei, Si, Ci,
    # li, harmonic, sign, RootOf) are in rcas's own CD, RCAS_CD.
    module Phrasebook
      DECODE_APPLY = {} # ["cd", "name"] => ->(args, node) { rcas object or nil }
      DECODE_CONST = {} # ["cd", "name"] => rcas object, for a symbol on its own
      ENCODE_CLASS = {} # Expression subclass => ->(e) { OpenMath node }
      ENCODE_FN    = {} # rcas function name => ["cd", "name"]
      ENCODE_CONST = {} # Const name => ["cd", "name"]

      module_function

      # ---- how a row is declared ------------------------------------------

      # An n-ary OpenMath operator and the binary rcas node it becomes.
      def operator(klass, cd, name)
        DECODE_APPLY[[cd, name]] = ->(args, _) { args.map { |a| decode(a) }.reduce { |l, r| klass.new(l, r) } }
        ENCODE_CLASS[klass] = ->(e) { Application.new(OpenMath.sym(cd, name), encode(e.left), encode(e.right)) }
      end

      def unary(klass, cd, name)
        DECODE_APPLY[[cd, name]] = ->(args, _) { klass.new(decode(args.first)) }
        ENCODE_CLASS[klass] = ->(e) { Application.new(OpenMath.sym(cd, name), encode(e.arg)) }
      end

      # A named function on both sides: sin, gamma, binomial, ...
      def function(fn, cd, name)
        DECODE_APPLY[[cd, name]] = ->(args, _) { Fn.new(fn, args.map { |a| decode(a) }) }
        ENCODE_FN[fn] = [cd, name]
      end

      # The same, in rcas's own content dictionary.
      def rcas_function(fn, name = fn.to_s) = function(fn, RCAS_CD, name)

      # A symbol standing on its own: nums1.pi, setname1.Z.
      def constant(value, cd, name, encode_as: nil)
        DECODE_CONST[[cd, name]] = value
        ENCODE_CONST[encode_as] = [cd, name] if encode_as
      end

      # A row the two systems do not see the same way.
      def special(cd, name, decode: nil, encode: nil, klass: nil)
        DECODE_APPLY[[cd, name]] = decode if decode
        ENCODE_CLASS[klass] = encode if klass && encode
      end

      # ---- the table -------------------------------------------------------

      operator Add, "arith1", "plus"
      operator Sub, "arith1", "minus"
      operator Mul, "arith1", "times"
      operator Div, "arith1", "divide"
      operator Pow, "arith1", "power"
      unary    Neg, "arith1", "unary_minus"

      function :abs,  "arith1", "abs"
      function :gcd,  "arith1", "gcd"
      function :lcm,  "arith1", "lcm"

      function :exp,   "transc1", "exp"
      function :log,   "transc1", "ln"
      function :sin,   "transc1", "sin"
      function :cos,   "transc1", "cos"
      function :tan,   "transc1", "tan"
      function :sinh,  "transc1", "sinh"
      function :cosh,  "transc1", "cosh"
      function :tanh,  "transc1", "tanh"
      function :asin,  "transc1", "arcsin"
      function :acos,  "transc1", "arccos"
      function :atan,  "transc1", "arctan"

      function :factorial, "integer1", "factorial"
      function :quo,       "integer1", "quotient"
      function :rem,       "integer1", "remainder"
      function :binomial,  "combinat1", "binomial"
      function :fibonacci, "combinat1", "Fibonacci"

      function :floor, "rounding1", "floor"
      function :ceil,  "rounding1", "ceiling"

      function :re,   "complex1", "real"
      function :im,   "complex1", "imaginary"
      function :conj, "complex1", "conjugate"
      function :arg,  "complex1", "argument"

      # No official CD names these, so they are ours.
      rcas_function :gamma
      rcas_function :zeta
      rcas_function :erf
      rcas_function :erfc
      rcas_function :sign
      rcas_function :harmonic
      rcas_function :Ei
      rcas_function :Si
      rcas_function :Ci
      rcas_function :li

      constant PI, "nums1", "pi", encode_as: :pi
      constant OO, "nums1", "infinity", encode_as: :oo
      constant E,  "nums1", "e"
      constant I,  "nums1", "i"
      constant Num.new(Float::NAN), "nums1", "NaN"

      constant NN, "setname1", "N"
      constant ZZ, "setname1", "Z"
      constant QQ, "setname1", "Q"
      constant RR, "setname1", "R"
      constant CC, "setname1", "C"

      # nums1.rational and complex1.complex_cartesian build a number rather
      # than an operation; a Num goes back through #number, which picks the
      # form the value calls for.
      special "nums1", "rational", decode: lambda { |args, _|
        p, q = args
        return nil unless p.is_a?(Int) && q.is_a?(Int)
        Num.new(Rational(p.value, q.value))
      }

      special "complex1", "complex_cartesian", decode: lambda { |args, _|
        re, im = args.map { |a| decode(a) }
        return Num.new(Complex(re.value, im.value)) if re.is_a?(Num) && im.is_a?(Num)
        Add.new(re, Mul.new(im, I))
      }

      # transc1.log is the logarithm to a base, which rcas writes as a
      # quotient of natural logarithms.
      special "transc1", "log", decode: lambda { |args, _|
        base, x = args.map { |a| decode(a) }
        Div.new(Fn.new(:log, [x]), Fn.new(:log, [base]))
      }

      # arith1.root(x, n) is x**(1/n).
      special "arith1", "root", decode: lambda { |args, _|
        x, n = args
        exponent = n.is_a?(Int) ? Num.new(Rational(1, n.value)) : Div.new(Num.new(1), decode(n))
        Pow.new(decode(x), exponent)
      }

      # sum and product: a range and a lambda in OpenMath, a bound variable
      # in rcas.
      special "arith1", "sum", klass: Sum,
        decode: ->(args, _) { range_binding(args) { |term, var, from, to| Sum.new(term, var, from, to) } },
        encode: ->(e) { range_application("sum", e.from, e.to, e.var, e.term) }

      special "arith1", "product", klass: Product,
        decode: ->(args, _) { range_binding(args) { |term, var, from, to| Product.new(term, var, from, to) } },
        encode: ->(e) { range_application("product", e.from, e.to, e.var, e.term) }

      # calculus1: int and defint are one symbol in rcas, whose Integral
      # node carries the bounds when it has them.
      special "calculus1", "int", klass: Integral,
        decode: lambda { |args, _|
          pair = lambda_parts(args.first)
          return nil unless pair
          var, body = pair
          Integral.new(body, var)
        },
        encode: lambda { |e|
          return Application.new(OpenMath.sym("calculus1", "int"), lambda_of(e.var, e.integrand)) unless e.definite?
          Application.new(OpenMath.sym("calculus1", "defint"),
                          Application.new(OpenMath.sym("interval1", "interval"), encode(e.from), encode(e.to)),
                          lambda_of(e.var, e.integrand))
        }

      special "calculus1", "defint", decode: lambda { |args, _|
        range, fn = args
        pair = interval_bounds(range)
        return nil unless pair
        from, to = pair
        pair = lambda_parts(fn)
        return nil unless pair
        var, body = pair
        Integral.new(body, var, from, to)
      }

      special "calculus1", "diff", klass: Derivative,
        decode: lambda { |args, _|
          pair = lambda_parts(args.first)
          return nil unless pair
          var, body = pair
          Derivative.new(body, var)
        },
        encode: lambda { |e|
          return Application.new(OpenMath.sym("calculus1", "diff"), lambda_of(e.var, e.expr)) if e.order == 1
          Application.new(OpenMath.sym("calculus1", "nthdiff"), Int.new(e.order), lambda_of(e.var, e.expr))
        }

      special "calculus1", "nthdiff", decode: lambda { |args, _|
        order, fn = args
        return nil unless order.is_a?(Int)
        pair = lambda_parts(fn)
        return nil unless pair
        var, body = pair
        Derivative.new(body, var, order.value)
      }

      # limit1.limit(x0, direction, lambda). rcas's Limit node has no
      # direction, so only the two-sided limits become one; above and below
      # stay as they came, held.
      special "limit1", "limit", klass: Limit,
        decode: lambda { |args, _|
          point, direction, fn = args
          return nil unless direction.is_a?(ContentSymbol) && %w[both_sides null].include?(direction.name)
          pair = lambda_parts(fn)
          return nil unless pair
          var, body = pair
          Limit.new(body, var, decode(point))
        },
        encode: lambda { |e|
          Application.new(OpenMath.sym("limit1", "limit"), encode(e.point),
                          OpenMath.sym("limit1", "both_sides"), lambda_of(e.var, e.expr))
        }

      # piece1.piece is (value, condition) - that way round.
      special "piece1", "piecewise", klass: Piecewise,
        decode: lambda { |args, _|
          branches = args.map { |a| piece_branch(a) }
          return nil if branches.any?(&:nil?)
          Piecewise.new(branches)
        },
        encode: lambda { |e|
          pieces = e.branches.map do |condition, value|
            if condition == Piecewise::OTHERWISE
              Application.new(OpenMath.sym("piece1", "otherwise"), encode(value))
            else
              Application.new(OpenMath.sym("piece1", "piece"), encode(value), encode(condition))
            end
          end
          Application.new(OpenMath.sym("piece1", "piecewise"), pieces)
        }

      # RootOf: the algebraic number that is the index-th root of a
      # polynomial. No official CD names it.
      special RCAS_CD, "root_of", klass: RootOf,
        decode: lambda { |args, _|
          poly, index = args
          return nil unless index.is_a?(Int)
          begin
            RootOf.new(decode(poly).to_poly, index.value)
          rescue StandardError
            nil
          end
        },
        encode: ->(e) { Application.new(OpenMath.rcas_sym("root_of"), encode(e.poly.to_expr), Int.new(e.index)) }

      # The intervals, on their own rather than as the range of a sum.
      { "interval_oo" => [true, true], "interval_cc" => [false, false],
        "interval_oc" => [true, false], "interval_co" => [false, true],
        "interval" => [false, false], "integer_interval" => [false, false] }.each do |name, (left, right)|
        DECODE_APPLY[["interval1", name]] = lambda { |args, _|
          low, high = args.map { |a| decode(a) }
          Interval.new(low, high, left_open: left, right_open: right)
        }
      end

      # The leaves and the two nodes that are not operations.
      ENCODE_CLASS[Num] = ->(e) { number(e.value) }
      ENCODE_CLASS[Var] = ->(e) { name_head(e.name) }
      ENCODE_CLASS[Const] = lambda { |e|
        cd, name = ENCODE_CONST[e.name]
        raise EncodeError, "no OpenMath symbol for the constant #{e}" unless cd
        OpenMath.sym(cd, name)
      }
      ENCODE_CLASS[Fn] = lambda { |e|
        return Error.new(encode(e.args.first), e.args[1..].map { |a| encode(a) }) if e.name == :openmath_error
        return lambda_of(e.args.first, e.args.last) if e.name == :lambda && e.args.size == 2 && e.args.first.is_a?(Var)
        cd, name = ENCODE_FN[e.name]
        head = cd ? OpenMath.sym(cd, name, cdbase: (RCAS_CDBASE if cd == RCAS_CD)) : name_head(e.name)
        Application.new(head, e.args.map { |a| encode(a) })
      }

      # ---- encoding --------------------------------------------------------

      # The OpenMath object for an rcas object, wrapped in its OMOBJ.
      def to_openmath(obj) = Root.new(encode(obj))

      def encode(obj)
        case obj
        when Node        then obj
        when Expression  then encode_expression(obj)
        when Equation    then Application.new(OpenMath.sym("relation1", "eq"), encode(obj.lhs), encode(obj.rhs))
        when Inequality  then encode_inequality(obj)
        when Interval    then encode_interval(obj)
        when NumberSet   then encode_number_set(obj)
        when Matrix      then encode_matrix(obj)
        when Vector      then Application.new(OpenMath.sym("linalg2", "vector"), obj.entries.map { |v| encode(v) })
        when Numeric     then number(obj)
        when Symbol      then name_head(obj)
        when Array       then Application.new(OpenMath.sym("list1", "list"), obj.map { |v| encode(v) })
        else raise EncodeError, "no OpenMath encoding for #{obj.class}"
        end
      end

      def encode_expression(e)
        rule = ENCODE_CLASS[e.class]
        raise EncodeError, "no OpenMath symbol for #{e.class} (#{e})" unless rule
        rule.call(e)
      end

      RELATIONS = { :< => "lt", :<= => "leq", :> => "gt", :>= => "geq", :!= => "neq" }.freeze

      def encode_inequality(ineq)
        name = RELATIONS.fetch(ineq.op) { raise EncodeError, "no OpenMath symbol for #{ineq.op}" }
        Application.new(OpenMath.sym("relation1", name), encode(ineq.lhs), encode(ineq.rhs))
      end

      def encode_interval(interval)
        name = "interval_#{interval.left_open ? 'o' : 'c'}#{interval.right_open ? 'o' : 'c'}"
        Application.new(OpenMath.sym("interval1", name), encode(interval.low), encode(interval.high))
      end

      SET_NAMES = { NN: "N", ZZ: "Z", QQ: "Q", RR: "R", CC: "C" }.freeze

      def encode_number_set(set)
        name = SET_NAMES.fetch(set.name.to_sym) { raise EncodeError, "no OpenMath symbol for #{set}" }
        OpenMath.sym("setname1", name)
      end

      def encode_matrix(matrix)
        rows = matrix.entries.map do |row|
          Application.new(OpenMath.sym("linalg2", "matrixrow"), row.map { |v| encode(v) })
        end
        Application.new(OpenMath.sym("linalg2", "matrix"), rows)
      end

      # An indeterminate is an OMV; a name carrying a content dictionary
      # ("arith3.foo", the way an unmapped symbol decodes) goes back to the
      # symbol it came from.
      def name_head(name)
        text = name.to_s
        return Variable.new(text) unless text.include?(".")
        cd, symbol = text.split(".", 2)
        OpenMath.sym(cd, symbol, cdbase: (RCAS_CDBASE if cd == RCAS_CD))
      end

      # Ruby numbers. Integers and floats are objects of their own in
      # OpenMath; a rational is an application, and so is a complex number
      # unless it is exactly i.
      def number(value)
        case value
        when Integer  then Int.new(value)
        when Rational then Application.new(OpenMath.sym("nums1", "rational"), Int.new(value.numerator), Int.new(value.denominator))
        when Float    then Double.new(value)
        when Complex  then complex_number(value)
        else
          raise EncodeError, "no OpenMath encoding for #{value.class}" unless value.respond_to?(:to_r)
          number(value.to_r)
        end
      end

      def complex_number(value)
        return OpenMath.sym("nums1", "i") if value.real.zero? && value.imaginary == 1
        Application.new(OpenMath.sym("complex1", "complex_cartesian"), number(value.real), number(value.imaginary))
      end

      def range_application(name, from, to, var, term)
        Application.new(OpenMath.sym("arith1", name),
                        Application.new(OpenMath.sym("interval1", "integer_interval"), encode(from), encode(to)),
                        lambda_of(var, term))
      end

      def lambda_of(var, body)
        Bind.new(OpenMath.sym("fns1", "lambda"), BVar.new(Variable.new(var.name)), encode(body))
      end

      # ---- decoding --------------------------------------------------------

      # The rcas object an OpenMath object stands for. Not always an
      # Expression: relation1.eq is an Equation, interval1.interval_cc an
      # Interval, setname1.Z a number set.
      def to_expression(node)
        node = OpenMath.dereference(node)
        decode(node.is_a?(Root) ? node.object : node)
      end

      def decode(node)
        case node
        when Root          then decode(node.object)
        when Int, Double   then Num.new(node.value)
        when Variable      then Var.new(node.name.to_sym)
        when ContentSymbol then DECODE_CONST.fetch(node.key) { Var.new(:"#{node.cd}.#{node.name}") }
        when Application   then decode_application(node)
        when Bind          then decode_binding(node)
        when Attribution   then decode(node.object)
        when Error         then Fn.new(:openmath_error, [decode(node.symbol), *node.args.map { |a| decode(a) }])
        when Reference     then raise ParseError, "reference #{node.href} points nowhere"
        when Text          then raise ParseError, "no rcas expression for the string #{node.value.inspect}"
        when Bytes         then raise ParseError, "no rcas expression for a byte array"
        else raise ParseError, "can't decode #{node.class}"
        end
      end

      def decode_application(node)
        head = node.head
        if head.is_a?(ContentSymbol) && (rule = DECODE_APPLY[head.key])
          result = rule.call(node.args, node)
          return result if result
        end
        Fn.new(unmapped_name(head), node.args.map { |a| decode(a) })
      end

      # A binding rcas has no node for stays a held call, so re-encoding
      # gives back what arrived.
      def decode_binding(node)
        var, body = lambda_parts(node)
        return Fn.new(:lambda, [var, body]) if var
        Fn.new(unmapped_name(node.binder), [*node.vars.map { |v| decode(v) }, decode(node.body)])
      end

      def unmapped_name(head)
        case head
        when ContentSymbol then :"#{head.cd}.#{head.name}"
        when Variable      then head.name.to_sym
        else raise ParseError, "can't apply #{head}"
        end
      end

      # fns1.lambda[x -> body] as [Var, expression]; nil for anything else.
      def lambda_parts(node)
        return nil unless node.is_a?(Bind) && node.binder.is_a?(ContentSymbol) && node.binder.key == %w[fns1 lambda]
        return nil unless node.vars.size == 1 && node.vars.first.is_a?(Variable)
        [Var.new(node.vars.first.name.to_sym), decode(node.body)]
      end

      def interval_bounds(node)
        return nil unless node.is_a?(Application) && node.head.is_a?(ContentSymbol)
        return nil unless node.head.cd == "interval1" && node.args.size == 2
        node.args.map { |a| decode(a) }
      end

      # The shape shared by arith1.sum and arith1.product.
      def range_binding(args)
        range, fn = args
        pair = interval_bounds(range)
        return nil unless pair
        from, to = pair
        pair = lambda_parts(fn)
        return nil unless pair
        var, term = pair
        yield term, var, from, to
      end

      def piece_branch(node)
        return nil unless node.is_a?(Application) && node.head.is_a?(ContentSymbol)
        case node.head.key
        when %w[piece1 piece]
          value, condition = node.args
          return nil unless value && condition
          decoded = piece_condition(condition)
          decoded ? [decoded, decode(value)] : nil
        when %w[piece1 otherwise]
          [Piecewise::OTHERWISE, decode(node.args.first)]
        end
      end

      def piece_condition(node)
        return Piecewise::OTHERWISE if node.is_a?(ContentSymbol) && node.key == %w[logic1 true]
        condition = decode_relation(node)
        condition if condition.is_a?(Inequality) || condition.is_a?(Equation)
      end

      DECODE_RELATIONS = { "lt" => :<, "leq" => :<=, "gt" => :>, "geq" => :>=, "neq" => :!= }.freeze

      def decode_relation(node)
        return nil unless node.is_a?(Application) && node.head.is_a?(ContentSymbol) && node.head.cd == "relation1"
        lhs, rhs = node.args.map { |a| decode(a) }
        return Equation.new(lhs, rhs) if node.head.name == "eq"
        op = DECODE_RELATIONS[node.head.name] or return nil
        Inequality.new(lhs, op, rhs)
      end

      # relation1 builds an Equation or an Inequality, neither of which is
      # an Expression, so it cannot go through the ordinary table.
      %w[eq lt leq gt geq neq].each do |name|
        DECODE_APPLY[["relation1", name]] = ->(args, node) { decode_relation(node) }
      end

      # linalg2: a matrix of matrixrows, and a vector.
      DECODE_APPLY[%w[linalg2 matrix]] = lambda { |args, _|
        rows = args.map do |row|
          return nil unless row.is_a?(Application) && row.head.is_a?(ContentSymbol) && row.head.key == %w[linalg2 matrixrow]
          row.args.map { |v| decode(v) }
        end
        RCAS.matrix(rows)
      }

      DECODE_APPLY[%w[linalg2 vector]] = ->(args, _) { RCAS.vector(args.map { |v| decode(v) }) }
      DECODE_APPLY[%w[list1 list]] = ->(args, _) { args.map { |v| decode(v) } }
    end
  end
end
