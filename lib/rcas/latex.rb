# frozen_string_literal: true

module RCAS
  # Renders rcas objects as LaTeX math (no surrounding $ delimiters).
  #
  #   ((:x + 1) / (:x - 1)).to_latex      # => "\\frac{x + 1}{x - 1}"
  #   RCAS::QQ[:x].to_latex               # => "\\mathbb{Q}[x]"
  #   RCAS::LaTeX.of([1, :x])             # => "\\left[1,\\; x\\right]"
  #   long_poly.to_latex(wrap: 60)        # => "\\begin{aligned} & ... \\\\ &\\quad {} + ... \\end{aligned}"
  #
  # Structure follows Printer: nothing is rewritten, parentheses are added
  # only where the tree needs them. A few display-only niceties are applied
  # on top: implicit multiplication, \frac for division, \sqrt for exponent
  # 1/2, \sin^{2}(x), e^{x}, \ln, and `a + (-1)` shown as `a - 1`.
  module LaTeX
    ADDITIVE       = Printer::ADDITIVE
    MULTIPLICATIVE = Printer::MULTIPLICATIVE
    UNARY          = Printer::UNARY
    POWER          = Printer::POWER
    ATOM           = Printer::ATOM

    GREEK = %w[
      alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi
      pi rho sigma tau upsilon phi chi psi omega
      Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega
      varepsilon vartheta varphi varrho varsigma
    ].freeze

    FUNCTIONS = {
      sin: '\sin', cos: '\cos', tan: '\tan', atan: '\arctan',
      sinh: '\sinh', cosh: '\cosh', tanh: '\tanh', log: '\ln'
    }.freeze

    # Functions written as \sin^{2}(x) rather than \left(\sin(x)\right)^{2}.
    POWER_FUNCTIONS = %i[sin cos tan sinh cosh tanh].freeze

    SETS = { "NN" => '\mathbb{N}', "ZZ" => '\mathbb{Z}', "QQ" => '\mathbb{Q}', "RR" => '\mathbb{R}', "CC" => '\mathbb{C}' }.freeze

    module_function

    # LaTeX for anything rcas produces, plus Ruby numbers, symbols, arrays,
    # hashes, booleans, nil and strings. +wrap+ is a line width in roughly
    # typeset characters; long sums, products and arrays are broken into an
    # aligned block that fits it (see #wrapped).
    def of(obj, wrap: nil)
      case obj
      when Expression, Polynomial, Factorization
        obj.to_latex(wrap: wrap)
      when ->(o) { defined?(Equation) && o.is_a?(Equation) }
        obj.to_latex(wrap: wrap)
      when Domain, Vector, Matrix, VectorSpace, MatrixSpace
        obj.to_latex
      when Symbol  then print(Var.new(obj))
      when Numeric then print(Num.new(obj))
      when Array   then array(obj, wrap: wrap)
      when Hash    then hash(obj)
      when true, false, nil then "\\mathrm{#{obj.inspect}}"
      when String  then text(obj)
      else
        obj.respond_to?(:to_latex) ? obj.to_latex : text(obj.to_s)
      end
    end

    # Elements side by side, or one per line when that would be too wide.
    def array(list, wrap: nil)
      return '\left[\,\right]' if list.empty?
      items = list.map { |e| of(e, wrap: wrap) }
      joined = "\\left[#{items.join(',\; ')}\\right]"
      return joined if wrap.nil? || width(joined) <= wrap || items.size == 1
      rows = items.each_with_index.map { |item, i| "& #{item}#{i == items.size - 1 ? '' : ','}" }
      "\\left[\\begin{aligned} #{rows.join(' \\\\ ')} \\end{aligned}\\right]"
    end

    # { x: ZZ } reads as a membership list, anything else as a mapping.
    def hash(table)
      return '\left\{\,\right\}' if table.empty?
      pairs = table.map do |k, v|
        v.is_a?(Domain) ? "#{of(k)} \\in #{of(v)}" : "#{of(k)} \\mapsto #{of(v)}"
      end
      pairs.join(',\; ')
    end

    def text(string)
      "\\text{#{escape(string)}}"
    end

    def escape(string)
      string.to_s.gsub(/[\\{}$&#^_%~]/) do |c|
        case c
        when "\\" then '\textbackslash{}'
        when "^"  then '\textasciicircum{}'
        when "~"  then '\textasciitilde{}'
        else "\\#{c}"
        end
      end
    end

    # ---- expressions -------------------------------------------------------

    def print(expr)
      case expr
      when Var      then variable(expr.name)
      when Num      then number(expr.value)
      when Neg      then "-#{wrap(expr.arg, UNARY, :inner)}"
      when Add, Sub then sum(expr)
      when Mul      then product(expr)
      when Div      then fraction(expr)
      when Pow      then power(expr)
      when Fn       then function(expr)
      when Integral then integral(expr)
      when Sum then "\\sum_{#{print(expr.var)}=#{print(expr.from)}}^{#{print(expr.to)}} #{wrap(expr.term, MULTIPLICATIVE, :right)}"
      when Product then "\\prod_{#{print(expr.var)}=#{print(expr.from)}}^{#{print(expr.to)}} #{wrap(expr.term, MULTIPLICATIVE, :right)}"
      when Limit then "\\lim_{#{print(expr.var)} \\to #{print(expr.point)}} #{wrap(expr.expr, MULTIPLICATIVE, :right)}"
      else
        return constant(expr) if defined?(Const) && expr.is_a?(Const)
        return derivative(expr) if defined?(Derivative) && expr.is_a?(Derivative)
        raise ArgumentError, "don't know how to typeset #{expr.class}"
      end
    end

    # pi as \pi; other named constants like variables.
    def constant(const)
      return "\\infty" if const.name == :oo
      const.name == :pi ? '\pi' : variable(const.name)
    end

    # d y / d x, d^{2} y / d x^{2}; a composite expression goes in parentheses.
    def derivative(d)
      n = d.order
      top = n == 1 ? "d" : "d^{#{n}}"
      bottom = n == 1 ? "d#{print(d.var)}" : "d#{print(d.var)}^{#{n}}"
      if d.expr.is_a?(Var) || (defined?(Fn) && d.expr.is_a?(Fn))
        "\\frac{#{top} #{print(d.expr)}}{#{bottom}}"
      else
        "\\frac{#{top}}{#{bottom}}\\left(#{print(d.expr)}\\right)"
      end
    end

    # x, \alpha, x_{1}, \mathit{foo}
    def variable(name)
      s = name.to_s
      base, index = s.match(/\A(.*?)_?(\d+)\z/)&.captures || [s, nil]
      base = s if base.empty?
      head =
        if base.size == 1 then base
        elsif GREEK.include?(base) then "\\#{base}"
        else "\\mathit{#{base.gsub('_', '\_')}}"
        end
      index && base != s ? "#{head}_{#{index}}" : head
    end

    def number(value)
      case value
      when Integer  then value.to_s
      when Rational then value.denominator == 1 ? value.numerator.to_s : "#{'-' if value.negative?}\\frac{#{value.numerator.abs}}{#{value.denominator}}"
      when Complex  then complex(value)
      when Float    then float(value)
      else value.to_s
      end
    end

    def float(value)
      return '\infty' if value == Float::INFINITY
      return '-\infty' if value == -Float::INFINITY
      return '\mathrm{NaN}' if value.nan?
      s = value.to_s
      if (m = s.match(/\A(-?[\d.]+)e([+-]?\d+)\z/))
        "#{m[1]} \\times 10^{#{m[2].to_i}}"
      else
        s
      end
    end

    def complex(value)
      re, im = value.real, value.imaginary
      imag =
        case im
        when 1  then "i"
        when -1 then "-i"
        else "#{number(im)}\\,i"
        end
      return imag if re.zero?
      Simplify.negative?(im) ? "#{number(re)} - #{imag.delete_prefix('-')}" : "#{number(re)} + #{imag}"
    end

    def precedence(expr)
      case expr
      when Add, Sub then ADDITIVE
      when Mul, Div then MULTIPLICATIVE
      when Neg      then UNARY
      when Pow      then POWER
      when Num      then Printer.number_precedence(expr.value)
      else ATOM
      end
    end

    # Sums and products are printed from their pieces (see #sum_pieces), so
    # long left-leaning chains stay iterative.
    def sum(expr)
      first, rest = sum_pieces(expr)
      rest.reduce(first) { |out, (op, term, _)| "#{out}#{op}#{term}" }
    end

    def product(expr)
      first, rest = product_pieces(expr)
      rest.reduce(first) { |out, (sep, part, _)| "#{out}#{sep}#{part}" }
    end

    # 2x and xy need nothing; x \cdot 2 and 2 \cdot 3 need a dot.
    def separator(left, right)
      right_numeric = right.is_a?(Num) || (right.is_a?(Pow) && right.base.is_a?(Num)) || right.is_a?(Neg)
      return ' \cdot ' if right_numeric
      return ' \cdot ' if left.is_a?(Num) && !left.value.is_a?(Integer) && !left.value.is_a?(Rational) && right.is_a?(Num)
      " "
    end

    # A negative numerator puts its sign in front of the fraction.
    def fraction(expr)
      num = expr.left
      if num.is_a?(Neg)
        "-\\frac{#{print(num.arg)}}{#{print(expr.right)}}"
      elsif num.is_a?(Num) && num.negative?
        "-\\frac{#{number(-num.value)}}{#{print(expr.right)}}"
      else
        "\\frac{#{print(num)}}{#{print(expr.right)}}"
      end
    end

    def power(expr)
      base, exp = expr.base, expr.exponent
      if exp.is_a?(Num) && exp.value.is_a?(Rational) && exp.value.numerator == 1 && exp.value.denominator >= 2
        n = exp.value.denominator
        return n == 2 ? "\\sqrt{#{print(base)}}" : "\\sqrt[#{n}]{#{print(base)}}"
      end
      if base.is_a?(Fn) && POWER_FUNCTIONS.include?(base.name) && base.args.size == 1 && exp.is_a?(Num) && exp.integer? && exp.value.positive?
        return "#{FUNCTIONS[base.name]}^{#{print(exp)}}#{function_argument(base.args.first)}"
      end
      "#{wrap(base, POWER, :left)}^{#{print(exp)}}"
    end

    def function(expr)
      args = expr.args
      case expr.name
      when :exp
        arg = args.first
        return "e" if arg.is_a?(Num) && arg.one?
        return "e^{#{print(arg)}}"
      when :sqrt
        return "\\sqrt{#{print(args.first)}}"
      end
      head = FUNCTIONS[expr.name] || "\\operatorname{#{escape(expr.name)}}"
      return "#{head}#{function_argument(args.first)}" if args.size == 1
      "#{head}\\left(#{args.map { |a| print(a) }.join(', ')}\\right)"
    end

    def function_argument(arg)
      arg.is_a?(Var) ? " #{print(arg)}" : "\\left(#{print(arg)}\\right)"
    end

    def integral(expr)
      body = expr.integrand
      inner = precedence(body) <= ADDITIVE ? "\\left(#{print(body)}\\right)" : print(body)
      bounds = expr.definite? ? "_{#{print(expr.from)}}^{#{print(expr.to)}}" : ""
      "\\int#{bounds} #{inner}\\, d#{print(expr.var)}"
    end

    # Same decisions as Printer#wrap, with \left( \right) as the parentheses.
    # Division needs no parentheses anywhere since it becomes a fraction, and
    # a fraction needs them only as the base of a power.
    def wrap(child, parent_prec, position, parent = nil)
      s = print(child)
      child_prec = precedence(child)
      needs =
        case position
        when :left
          if parent_prec == POWER
            !(child.is_a?(Var) || (child.is_a?(Num) && (child.value.is_a?(Integer) || child.value.is_a?(Float)) && !child.negative?) ||
              (child.is_a?(Fn) && child.name != :exp))
          else
            child_prec < parent_prec
          end
        when :right
          child_prec < parent_prec ||
            (child_prec == parent_prec && parent && !Printer.associative_right?(parent, child) && !child.is_a?(Div)) ||
            child.is_a?(Neg) || (child.is_a?(Num) && child.negative?)
        when :inner
          child_prec <= ADDITIVE || child.is_a?(Neg) || (child.is_a?(Num) && child.negative?)
        end
      needs ? "\\left(#{s}\\right)" : s
    end

    # ---- line breaking -----------------------------------------------------

    # +expr+ broken into lines of at most +width+ typeset characters at its
    # top-level sum or product, as an aligned block; unchanged when it fits.
    #
    #   1 + x + x^{2} + \cdots                                          (fits)
    #   \begin{aligned} & 1 + x + x^{2} \\ &\quad {} + x^{3} + \cdots \end{aligned}
    def wrapped(expr, width)
      if expr.is_a?(Neg) && !expr.arg.is_a?(Mul)
        inner = wrapped(expr.arg, width - 2)
        return print(expr) unless inner.include?('\begin{aligned}')
        return "-\\left(#{inner}\\right)"
      end
      first, rest = pieces(expr)
      return print(expr) if rest.empty?
      lines = [first]
      rest.each do |op, term, continuation|
        candidate = "#{lines.last}#{op}#{term}"
        if self.width(candidate) > width && self.width(lines.last) > 0
          lines << "#{continuation}#{term}"
        else
          lines[-1] = candidate
        end
      end
      return lines.first if lines.size == 1
      "\\begin{aligned} & #{lines.first} \\\\ #{lines.drop(1).map { |l| "&\\quad #{l}" }.join(' \\\\ ')} \\end{aligned}"
    end

    # => [first, [[joiner, latex, line_start], ...]] for the top-level sum or
    # product of +expr+; a lone piece for anything else.
    def pieces(expr)
      case expr
      when Add, Sub then sum_pieces(expr)
      when Mul then product_pieces(expr)
      when Neg
        first, rest = pieces(expr.arg)
        rest.empty? ? [print(expr), []] : ["-#{first}", rest]
      else [print(expr), []]
      end
    end

    # Walks the left spine like Printer#binary; each piece carries the
    # joiner used inside a line and the one used at the start of a new line.
    def sum_pieces(expr)
      spine = []
      node = expr
      while node.is_a?(Add) || node.is_a?(Sub)
        spine << node
        node = node.left
      end
      first = wrap(node, ADDITIVE, :left)
      rest = spine.reverse.map do |n|
        right = n.right
        if n.is_a?(Add) && (right.is_a?(Neg) || (right.is_a?(Num) && right.negative?))
          # a + (-b) reads better as a - b
          term = right.is_a?(Neg) ? wrap(right.arg, UNARY, :inner) : number(-right.value)
          [" - ", term, "{} - "]
        else
          op = n.is_a?(Add) ? "+" : "-"
          [" #{op} ", wrap(right, ADDITIVE, :right, n), "{} #{op} "]
        end
      end
      [first, rest]
    end

    def product_pieces(expr)
      factors = []
      node = expr
      while node.is_a?(Mul)
        factors.unshift(node.right)
        node = node.left
      end
      factors.unshift(node)
      parts = factors.each_with_index.map { |f, i| wrap(f, MULTIPLICATIVE, i.zero? ? :left : :right, expr) }
      rest = factors.each_cons(2).zip(parts.drop(1)).map { |(a, b), part| [separator(a, b), part, "{} \\times "] }
      [parts.first, rest]
    end

    # Rough visual width of a LaTeX fragment in characters: fences and
    # spacing commands vanish, a fraction is as wide as its wider half, any
    # other command counts as one glyph, braces and script marks are free.
    def width(latex)
      s = latex.dup
      s.gsub!(/\\(left|right|displaystyle|quad|qquad|begin\{[a-z*]+\}|end\{[a-z*]+\})/, "")
      s.gsub!(/\\[,;!]/, "")
      3.times { s.gsub!(/\\frac\{([^{}]*)\}\{([^{}]*)\}/) { "x" * [Regexp.last_match(1).size, Regexp.last_match(2).size].max } }
      s.gsub!(/\\[a-zA-Z]+/, "M")
      s.gsub!(/[{}^_&]/, "")
      s.size
    end

    # ---- algebraic structures ----------------------------------------------

    def domain(dom)
      case dom
      when NumberSet      then SETS.fetch(dom.name) { "\\mathbb{#{escape(dom.name)}}" }
      when PolynomialRing then "#{domain(dom.base)}[#{dom.vars.map { |v| variable(v) }.join(', ')}]"
      when FractionField  then "\\operatorname{Frac}\\left(#{domain(dom.ring)}\\right)"
      else text(dom.to_s)
      end
    end

    def matrix(rows)
      return '\left[\,\right]' if rows.empty? || rows.first.empty?
      body = rows.map { |r| r.map { |e| cell(e) }.join(" & ") }.join(' \\\\ ')
      "\\begin{pmatrix} #{body} \\end{pmatrix}"
    end

    # Fractions in a matrix are set at display size so they stay legible.
    def cell(entry)
      s = of(entry)
      s.include?('\frac') ? "\\displaystyle #{s}" : s
    end

    def vector(entries)
      matrix(entries.map { |e| [e] })
    end
  end

  # Mixin for every rcas value that can be typeset: #to_latex is defined by
  # the including class; #show renders it inline (see Render).
  module Typeset
    def to_latex(**) = raise(NotImplementedError, "#{self.class} has no LaTeX form")

    # Display typeset in the terminal (inline image in iTerm2).
    def show(**options) = Render.show(self, **options)

    # PNG bytes, or write them to +path+.
    def to_png(path = nil, **options) = Render.png(self, path, **options)
  end

  class Expression
    include Typeset
    # wrap: a line width in typeset characters; long top-level sums and
    # products are then broken into an aligned block.
    def to_latex(wrap: nil) = wrap ? LaTeX.wrapped(self, wrap) : LaTeX.print(self)
  end

  class Polynomial
    include Typeset
    def to_latex(wrap: nil) = to_expr.to_latex(wrap: wrap)
  end

  class Factorization
    include Typeset
    def to_latex(wrap: nil) = to_expr.to_latex(wrap: wrap)
  end

  class Domain
    include Typeset
    def to_latex = LaTeX.domain(self)
  end

  class VectorSpace
    include Typeset
    def to_latex = "#{domain.to_latex}^{#{dim}}"
  end

  class MatrixSpace
    include Typeset
    def to_latex = "#{domain.to_latex}^{#{rows} \\times #{cols}}"
  end

  class Vector
    include Typeset
    def to_latex = LaTeX.vector(entries)
  end

  class Matrix
    include Typeset
    def to_latex = LaTeX.matrix(entries)
  end

  if defined?(Equation)
    class Equation
      include Typeset
      # lhs = rhs; with wrap: each side may break into an aligned block.
      def to_latex(wrap: nil) = "#{lhs.to_latex(wrap: wrap)} = #{rhs.to_latex(wrap: wrap)}"
    end
  end
end

class Symbol
  def to_latex = RCAS::LaTeX.variable(self)
end

class Numeric
  def to_latex = RCAS::LaTeX.number(self)
end

class Array
  def to_latex(wrap: nil) = RCAS::LaTeX.array(self, wrap: wrap)
end

class Hash
  def to_latex = RCAS::LaTeX.hash(self)
end
