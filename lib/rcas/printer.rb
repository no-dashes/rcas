# frozen_string_literal: true

module RCAS
  # Renders an expression tree as Ruby-flavoured infix text with the minimum
  # number of parentheses needed to preserve the tree structure.
  module Printer
    ADDITIVE       = 1 # + -
    MULTIPLICATIVE = 2 # * /
    UNARY          = 3 # -x
    POWER          = 4 # **
    ATOM           = 5

    module_function

    def negative_number?(e) = e.is_a?(Num) && e.value.is_a?(Numeric) && e.value.real? && e.value.negative?

    def print(expr)
      case expr
      when Var then expr.name.to_s
      when Num then number(expr.value)
      when Neg then "-#{wrap(expr.arg, UNARY, :inner)}"
      when Add then negative_number?(expr.right) ? binary(Sub.new(expr.left, Num.new(-expr.right.value)), " - ") : binary(expr, " + ")
      # a negative number on the right reads as the other sign: x - (-7/10)
      # is x + 7/10 (fifth review, 3.3); the tree itself is unchanged
      when Sub then negative_number?(expr.right) ? binary(Add.new(expr.left, Num.new(-expr.right.value)), " + ") : binary(expr, " - ")
      when Mul then binary(expr, "*")
      when Div then binary(expr, "/")
      when Pow then "#{wrap(expr.base, POWER, :left)}**#{wrap(expr.exponent, POWER, :right)}"
      when Const then RCAS.symbol(expr.name)
      when RootOf then "RootOf(#{print(expr.poly.to_expr.subs(Var.new(expr.var) => Var.new(:x)))}, #{expr.index})"
      when Fn
        return "e" if expr.name == :exp && expr.args == [Num.new(1)]
        if expr.name == :factorial && expr.args.size == 1
          arg = expr.args.first
          atom = arg.is_a?(Var) || (arg.is_a?(Num) && number_precedence(arg.value) == ATOM)
          return atom ? "#{print(arg)}!" : "(#{print(arg)})!"
        end
        "#{expr.name}(#{expr.args.map { |a| print(a) }.join(', ')})"
      when Integral then "integral(#{expr.children.map { |c| print(c) }.join(', ')})"
      when Limit then "limit(#{print(expr.expr)}, #{print(expr.var)}, #{print(expr.point)})"
      when Sum then "sum(#{expr.children.map { |c| print(c) }.join(', ')})"
      when Product then "product(#{expr.children.map { |c| print(c) }.join(', ')})"
      when Derivative then "D(#{print(expr.expr)}, #{print(expr.var)}#{expr.order == 1 ? '' : ", #{expr.order}"})"
      when Piecewise then "piecewise(#{expr.branches.map { |cond, value| "#{condition(cond)} => #{print(value)}" }.join(', ')})"
      else raise ArgumentError, "don't know how to print #{expr.class}"
      end
    end

    # The condition of a piecewise branch, written so that the whole node
    # can be typed back in: `x < 0`, `x.eq(0)`, `interval(0, 1)`, `:else`.
    def condition(cond)
      case cond
      when Inequality then "#{print(cond.lhs)} #{Inequality::OPS[cond.op]} #{print(cond.rhs)}"
      when Equation then "#{print(cond.lhs)}.eq(#{print(cond.rhs)})"
      when Interval then interval(cond)
      when RealSet then cond.intervals.map { |i| interval(i) }.join(" | ")
      else cond.inspect
      end
    end

    def interval(i)
      opens = [("left_open: true" if i.left_open), ("right_open: true" if i.right_open)].compact
      "interval(#{print(i.low)}, #{print(i.high)}#{opens.empty? ? '' : ", #{opens.join(', ')}"})"
    end

    def precedence(expr)
      case expr
      when Add, Sub then ADDITIVE
      when Mul, Div then MULTIPLICATIVE
      when Neg      then UNARY
      when Pow      then POWER
      when Num      then number_precedence(expr.value)
      else ATOM
      end
    end

    OPERATORS = { Add => " + ", Sub => " - ", Mul => "*", Div => "/" }.freeze

    # Walks the left spine of same-precedence operators iteratively so that
    # long chains like a + b + c + ... don't recurse once per term.
    def binary(expr, _op)
      prec = precedence(expr)
      spine = []
      node = expr
      while OPERATORS.key?(node.class) && precedence(node) == prec
        spine << node
        node = node.left
      end
      out = wrap(node, prec, :left)
      spine.reverse_each { |n| out = "#{out}#{OPERATORS[n.class]}#{wrap(n.right, prec, :right, n)}" }
      out
    end

    # Parenthesize +child+ when it binds looser than its parent, or when it
    # binds equally but sits in a position where that would change meaning.
    def wrap(child, parent_prec, position, parent = nil)
      s = print(child)
      child_prec = precedence(child)
      needs_parens =
        case position
        when :left  then child_prec < parent_prec || (parent_prec == POWER && child_prec == POWER) || (child_prec == parent_prec && child.is_a?(Num))
        when :right then child_prec < parent_prec || (child_prec == parent_prec && !associative_right?(parent, child)) || child.is_a?(Neg) || (child.is_a?(Num) && child_prec == UNARY)
        when :inner then child_prec <= parent_prec
        end
      needs_parens ? "(#{s})" : s
    end

    # a + (b - c) and a*(b*c) read fine without parentheses; a - (b + c) and
    # a/(b*c) do not.
    def associative_right?(parent, child)
      (parent.is_a?(Add) && (child.is_a?(Add) || child.is_a?(Sub))) || (parent.is_a?(Mul) && child.is_a?(Mul))
    end

    def number(value)
      case value
      when Rational then value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
      when Complex  then complex(value)
      else value.to_s
      end
    end

    def complex(value)
      re, im = value.real, value.imaginary
      im_s =
        case im
        when 1 then "i"
        when -1 then "-i"
        else "#{number(im)}*i"
        end
      return im_s if re.zero?
      sign = im.negative? ? " - " : " + "
      "#{number(re)}#{sign}#{im_s.delete_prefix('-')}"
    end

    def number_precedence(value)
      return value.printer_precedence if value.respond_to?(:printer_precedence)
      if value.is_a?(Complex)
        return ADDITIVE unless value.real.zero?
        return value.imaginary == 1 ? ATOM : (value.imaginary == -1 ? UNARY : MULTIPLICATIVE)
      end
      return UNARY if value.respond_to?(:negative?) && value.negative?
      return MULTIPLICATIVE if value.is_a?(Rational) && value.denominator != 1
      ATOM
    end
  end
end
