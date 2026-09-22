# frozen_string_literal: true

module RCAS
  # One line of a worked solution: how deep it sits, what it says, and the
  # expression it is about (for typesetting).
  Step = Struct.new(:depth, :text, :expr)

  # A worked solution: the problem as it was asked, the lines of working,
  # and the answer. It prints as a student would write it out.
  #
  #   steps { diff(x**2*sin(x), x) }
  #   steps { integrate(x*exp(x), x) }
  #   steps(x**2 - 5*x + 6, :solve)
  class Derivation
    attr_reader :problem, :lines, :result

    def initialize(problem, lines, result)
      @problem = problem
      @lines = lines.freeze
      @result = result
      freeze
    end

    def to_s
      body = lines.flat_map do |step|
        indent = "  " * (step.depth + 1)
        step.text.to_s.lines.map { |l| "#{indent}#{l.chomp}" }
      end
      ([problem.to_s] + body + ["= #{result}"]).join("\n")
    end
    alias inspect to_s

    def to_latex(wrap: nil)
      rows = lines.map do |step|
        indent = "\\quad " * step.depth
        text = "#{indent}\\text{#{LaTeX.escape(step.text)}}"
        step.expr ? "#{text} \\quad #{LaTeX.of(step.expr)}" : text
      end
      rows = [LaTeX.of(problem)] + rows + ["= #{LaTeX.of(result)}"]
      "\\begin{aligned} #{rows.join(' \\\\ ')} \\end{aligned}"
    end

    # How many lines of working there are.
    def size = lines.size
  end

  # Worked solutions: the working, not only the answer.
  #
  #   steps { diff(x**2*sin(x), x) }     the rules, named, as they are used
  #   steps { integrate(x*exp(x), x) }   substitution and parts spelled out
  #   steps(x**2 - 5*x + 6, :solve)      the quadratic formula with its numbers
  #   steps(x**3 - 5*x + 6, :factor)     common factors, then the roots
  #   steps(1/(x**2 - 1), :apart)        the partial-fraction ansatz
  #   steps(m, :rref)                    the row operations, one at a time
  #   steps(1071, 462, :gcd)             Euclid's algorithm
  #   steps(f, x, :discuss)              a whole curve discussion, question by question
  #
  # Each narrator decides which rule applies and then asks the library for
  # the piece it names, so the working can never disagree with the answer
  # `diff`, `integrate` or `solve` would give on its own. Where no rule is
  # recognised, the line says so instead of inventing a derivation.
  #
  # Sources (keys: MANUAL.md, Sources): the rules are the textbook ones
  # [Spi08, ch. 10, 18, 19]; Euclid's algorithm [Knu98, §4.5.2].
  module Steps
    module_function

    # steps(target, ..., how) or steps { ... }
    def of(*args, &block)
      return of(Hold.hold(block)) if block
      how = args.last.is_a?(Symbol) ? args.pop : nil
      target = args.first
      raise ArgumentError, "steps: nothing to work through" if target.nil?
      how ||= default_for(target, args)
      case how
      when :diff      then derivative(target)
      when :integrate then antiderivative(target)
      when :solve     then solution(target, args[1])
      when :apart     then fractions(target, args[1])
      when :rref      then elimination(target)
      when :gcd       then euclid(target, args[1])
      when :factor    then factorization(target, args[1])
      when :discuss   then discussion(target, args[1])
      else raise ArgumentError, "steps: don't know how to work through #{how || target.class}"
      end
    end

    def default_for(target, rest = [])
      case target
      when Derivative then :diff
      when Integral   then :integrate
      when Equation   then :solve
      when Matrix     then :rref
      when Fn         then target.name == :discuss ? :discuss : :solve
      when Expression then :solve
      when Integer    then rest.size > 1 ? :gcd : :factor
      end
    end

    # ---- building blocks -----------------------------------------------------

    def line(out, depth, text, expr = nil)
      out << Step.new(depth, text, expr)
      out
    end

    def constant?(expr, var) = !expr.variables.include?(var.name)

    # ---- curve discussion ----------------------------------------------------

    # The ritual, question by question. Every answer comes from the report
    # discuss builds, so the working and the summary cannot disagree; what
    # rcas cannot decide is said out loud rather than left out.
    def discussion(target, var)
      f = Expression.lift(target)
      if f.is_a?(Fn) && f.name == :discuss
        # steps { discuss(f, x) }: hold kept the call, so unpack it.
        var ||= f.args[1]
        f = f.args.first
      end
      x = Expression.lift(var || Solve.variable(f, nil))
      report = Discussion.discuss(f, x)
      out = []
      @section = 0
      discussion_domain(out, report, f, x)
      discussion_symmetry(out, report, f, x)
      discussion_zeros(out, report, x)
      discussion_gaps(out, report, x)
      discussion_infinity(out, report, x)
      discussion_derivatives(out, report)
      discussion_extrema(out, report, x)
      discussion_chart(out, report, report.monotonicity, "f'", "the monotonicity: the sign of f' between its zeros")
      discussion_inflections(out, report, x)
      discussion_chart(out, report, report.curvature, "f''", "the curvature: the sign of f''")
      Derivation.new(Fn.new(:discuss, [f, x]), out, report)
    end

    # "1. the domain: ...", with the working under it.
    def section(out, text) = line(out, 0, "#{@section += 1}. #{text}")

    def discussion_domain(out, report, f, x)
      conditions = Analysis.domain_conditions(f, x)
      if conditions.empty?
        section(out, "the domain: nothing to exclude, so every real #{x}")
      else
        section(out, "the domain: what must not happen")
        conditions.each { |condition| line(out, 1, condition.to_s) }
      end
      line(out, 1, "D = #{report.domain || 'not determined'}")
    end

    def discussion_symmetry(out, report, f, x)
      section(out, "symmetry: put -#{x} in for #{x}")
      line(out, 1, "f(-#{x}) = #{Discussion.reflect(f, x)}")
      line(out, 1, case report.symmetry
                   when :even then "that is f(#{x}): the graph is symmetric about the vertical axis"
                   when :odd then "that is -f(#{x}): the graph is symmetric about the origin"
                   else "neither f(#{x}) nor -f(#{x}): no symmetry of either kind"
                   end)
      line(out, 1, "f(#{x} + #{report.period}) = f(#{x}): the period is #{report.period}") if report.period
    end

    def discussion_zeros(out, report, x)
      section(out, "the zeros: solve f(#{x}) = 0")
      line(out, 1, if report.zeros.nil? then "rcas cannot solve f(#{x}) = 0"
                   elsif report.zeros.empty? then "no real zero"
                   else "#{x} = #{report.zeros.join(', ')}"
                   end)
      line(out, 1, "and every #{report.period} on from each of them") if report.period && report.zeros&.any?
      line(out, 1, "f(0) = #{report.intercept}, where the graph crosses the vertical axis") if report.intercept
    end

    def discussion_gaps(out, report, x)
      return if report.gaps.empty?
      section(out, "the gaps: where a denominator vanishes")
      report.gaps.each do |point, kind, left, right|
        line(out, 1, "#{x} = #{point}: f -> #{left || '?'} from the left, f -> #{right || '?'} from the right")
        line(out, 1, case kind
                     when :pole then "the graph runs away there: a pole"
                     when :removable then "the same value from both sides: the gap can be filled"
                     else "rcas cannot tell what happens there"
                     end)
      end
    end

    def discussion_infinity(out, report, x)
      section(out, "at infinity: the limits, and the lines the graph approaches")
      report.limits.each do |point, value|
        line(out, 1, if value then "limit(f, #{x}, #{point}) = #{value}"
                     elsif report.period then "f repeats every #{report.period}, so it has no limit as #{x} -> #{point}"
                     else "limit(f, #{x}, #{point}): rcas cannot decide it"
                     end)
      end
      lines = report.asymptotes
      (lines[:vertical] || []).each { |p| line(out, 1, "the pole at #{p} makes #{x} = #{p} a vertical asymptote") }
      (lines[:horizontal] || []).each { |c| line(out, 1, "the limit #{c} makes y = #{c} a horizontal asymptote") }
      (lines[:oblique] || []).each { |l| line(out, 1, "f - (#{l}) -> 0, so y = #{l} is an oblique asymptote") }
    end

    def discussion_derivatives(out, report)
      section(out, "the derivatives")
      line(out, 1, "rcas cannot differentiate this one") if report.derivatives.first.nil?
      ["f'", "f''", "f'''"].zip(report.derivatives).each do |name, value|
        line(out, 1, "#{name}(#{report.var}) = #{value}", value) if value
      end
    end

    def discussion_extrema(out, report, x)
      section(out, "the extrema: solve f'(#{x}) = 0, then the second derivative decides")
      if report.extrema.nil?
        line(out, 1, "rcas cannot solve f'(#{x}) = 0, so the extrema stay open")
        return
      end
      points = Discussion.solutions(report.derivatives[0], x)
      line(out, 1, "f'(#{x}) = 0 at #{x} = #{Analysis.sort_points(points).join(', ')}") if points&.any?
      line(out, 1, "no #{x} with f'(#{x}) = 0: no extremum") if report.extrema.empty?
      second = report.derivatives[1]
      report.extrema.each do |point, value, kind|
        curvature = second.subs(x => point).simplify
        sign = Analysis.numeric(curvature)
        test = if Scalar.zero?(curvature) || sign&.zero?
                 "f''(#{point}) = 0, so the sign of f' on either side decides"
               elsif sign
                 "f''(#{point}) = #{curvature} #{sign.positive? ? '>' : '<'} 0"
               else
                 "f''(#{point}) = #{curvature}"
               end
        line(out, 1, "#{test}: a #{kind} at (#{point}, #{value})")
      end
    end

    def discussion_inflections(out, report, x)
      section(out, "the inflections: solve f''(#{x}) = 0")
      if report.inflections.nil?
        line(out, 1, "rcas cannot solve f''(#{x}) = 0, so the inflections stay open")
        return
      end
      points = Discussion.solutions(report.derivatives[1], x)
      line(out, 1, "f''(#{x}) = 0 at #{x} = #{Analysis.sort_points(points).join(', ')}") if points&.any?
      line(out, 1, "no #{x} with f''(#{x}) = 0: the curvature never turns") if report.inflections.empty?
      third = report.derivatives[2]
      report.inflections.each do |point, value|
        rate = third.subs(x => point).simplify
        test = if Scalar.zero?(rate)
                 "f'''(#{point}) = 0, so the sign of f'' on either side decides"
               else
                 "f'''(#{point}) = #{rate}, not 0"
               end
        line(out, 1, "#{test}: an inflection at (#{point}, #{value})")
      end
    end

    def discussion_chart(out, report, chart, name, headline)
      section(out, headline)
      if chart.nil?
        line(out, 1, "the sign of #{name} is not decided on every piece")
        return
      end
      line(out, 1, "#{name} is zero throughout: nothing to report") if chart.empty?
      chart.each do |interval, kind|
        sign = %i[increasing convex].include?(kind) ? ">" : "<"
        line(out, 1, "#{name} #{sign} 0 on #{interval}: #{kind}")
      end
      line(out, 1, "one period, and it repeats every #{report.period}") if report.period && chart.any?
    end

    # ---- derivatives ---------------------------------------------------------

    def derivative(target)
      expr, var = target.is_a?(Derivative) ? [target.expr, target.var] : [Expression.lift(target), nil]
      var = Expression.lift(var || Solve.variable(expr, nil))
      order = target.is_a?(Derivative) ? target.order : 1
      out = []
      result = expr
      order.times do |i|
        line(out, 0, "the derivative number #{i + 1}:", result) if order > 1
        result = differentiate(result.simplify, var, 0, out)
      end
      Derivation.new(Derivative.new(expr, var, order), out, result)
    end

    # The rule that applies at the top, then the pieces it asks for.
    def differentiate(expr, var, depth, out)
      value = Differentiate.diff(expr, var).simplify
      case expr
      when Num, Const
        line(out, depth, "#{expr} is a constant, so its derivative is 0")
      when Var
        line(out, depth, expr == var ? "d/d#{var} #{var} = 1" : "#{expr} does not depend on #{var}: its derivative is 0")
      when Neg
        line(out, depth, "a minus sign comes along:")
        differentiate(expr.arg, var, depth + 1, out)
      when Add, Sub
        line(out, depth, "sum rule: differentiate each term of #{expr}")
        [expr.left, expr.right].each { |part| differentiate(part, var, depth + 1, out) unless constant?(part, var) }
      when Mul
        product_rule(expr, var, depth, out)
      when Div
        quotient_rule(expr, var, depth, out)
      when Pow
        power_rule(expr, var, depth, out)
      when Fn
        chain_rule(expr, var, depth, out)
      else
        line(out, depth, "the derivative of #{expr}:")
      end
      line(out, depth, "d/d#{var} (#{expr}) = #{value}", value) if depth.positive? && !atom?(expr)
      value
    end

    def atom?(expr) = expr.is_a?(Var) || expr.is_a?(Num) || expr.is_a?(Const)

    def product_rule(expr, var, depth, out)
      u, v = expr.left, expr.right
      if constant?(u, var) || constant?(v, var)
        constant, rest = constant?(u, var) ? [u, v] : [v, u]
        line(out, depth, "#{constant} is a constant factor, so it stays where it is:")
        return differentiate(rest, var, depth + 1, out)
      end
      line(out, depth, "product rule (u*v)' = u'*v + u*v', with u = #{u} and v = #{v}")
      differentiate(u, var, depth + 1, out)
      differentiate(v, var, depth + 1, out)
    end

    def quotient_rule(expr, var, depth, out)
      u, v = expr.left, expr.right
      if constant?(v, var)
        line(out, depth, "dividing by the constant #{v} does not change the rule:")
        return differentiate(u, var, depth + 1, out)
      end
      line(out, depth, "quotient rule (u/v)' = (u'*v - u*v')/v**2, with u = #{u} and v = #{v}")
      differentiate(u, var, depth + 1, out) unless constant?(u, var)
      differentiate(v, var, depth + 1, out)
    end

    def power_rule(expr, var, depth, out)
      base, exponent = expr.base, expr.exponent
      if constant?(exponent, var)
        line(out, depth, "power rule (u**n)' = n*u**(n - 1)*u', with u = #{base} and n = #{exponent}")
        differentiate(base, var, depth + 1, out) unless base == var
      elsif constant?(base, var)
        line(out, depth, "an exponential: (a**u)' = a**u*log(a)*u', with a = #{base}")
        differentiate(exponent, var, depth + 1, out) unless exponent == var
      else
        line(out, depth, "both base and exponent depend on #{var}, so write #{expr} as exp(#{exponent}*log(#{base}))")
      end
    end

    # The derivatives a table lists, and the chain rule around them.
    TABLE = {
      sin: "cos(u)", cos: "-sin(u)", tan: "1 + tan(u)**2", exp: "exp(u)", log: "1/u",
      atan: "1/(1 + u**2)", asin: "1/sqrt(1 - u**2)", acos: "-1/sqrt(1 - u**2)",
      sinh: "cosh(u)", cosh: "sinh(u)", abs: "sign(u)", erf: "2*exp(-u**2)/sqrt(pi)",
      Si: "sin(u)/u", Ci: "cos(u)/u", Ei: "exp(u)/u", li: "1/log(u)"
    }.freeze

    def chain_rule(expr, var, depth, out)
      u = expr.args.first
      rule = TABLE[expr.name]
      known = rule ? "d/du #{expr.name}(u) = #{rule}" : "the derivative of #{expr.name}"
      if u == var
        line(out, depth, "#{known}, from the table")
      else
        line(out, depth, "chain rule: #{known} with u = #{u}, times u'")
        differentiate(u, var, depth + 1, out)
      end
    end

    # ---- antiderivatives -----------------------------------------------------

    def antiderivative(target)
      unless target.is_a?(Integral)
        raise ArgumentError, "steps: integrate(...) inside a block, or an integral node"
      end
      var = target.var
      out = []
      result = integrate_part(target.integrand.simplify, var, 0, out)
      result = definite(target, var, result, out) if target.definite?
      Derivation.new(target, out, result.simplify)
    end

    def definite(target, var, antiderivative, out)
      line(out, 0, "put in the two ends of #{target.from} .. #{target.to}:", antiderivative)
      value = Integrate.definite(target.integrand, var, target.from, target.to)
      line(out, 0, "F(#{target.to}) - F(#{target.from})")
      value
    end

    # The integrals a table lists, for a linear argument.
    INTEGRALS = {
      sin: "-cos(u)", cos: "sin(u)", exp: "exp(u)", sinh: "cosh(u)", cosh: "sinh(u)",
      tan: "-log(cos(u))"
    }.freeze

    def integrate_part(expr, var, depth, out)
      value = Integrate.integrate(expr, var)
      if expr.is_a?(Add) || expr.is_a?(Sub)
        line(out, depth, "integrate term by term:")
        [expr.left, expr.right].each { |part| integrate_part(part, var, depth + 1, out) }
        return value
      end
      coefficient, rest = Integrate.split_constant(expr, var)
      unless Scalar.one?(coefficient)
        line(out, depth, "the constant factor #{coefficient} comes out of the integral:")
        integrate_part(rest, var, depth + 1, out)
        line(out, depth, "integral(#{expr}, #{var}) = #{value}", value) if depth.positive?
        return value
      end
      power_integral(expr, var, depth, out) || table_integral(expr, var, depth, out) ||
        substitution(expr, var, depth, out) || by_parts(expr, var, depth, out) ||
        line(out, depth, "rcas integrates #{expr} directly (no textbook rule is being followed here)")
      line(out, depth, "integral(#{expr}, #{var}) = #{value}", value) if depth.positive?
      value
    end

    # x**n, and 1/x with its logarithm. The factor table is what says which
    # power this is: 1/x is a Div, sqrt(x) a Pow with a rational exponent.
    def power_integral(expr, var, depth, out)
      coefficient, factors = Simplify.factorize(expr)
      return nil unless coefficient == 1 && factors.size == 1
      base, exponent = factors.first
      return nil unless base == var && exponent.is_a?(Numeric) && exponent.real?
      if exponent == -1
        line(out, depth, "integral(1/#{var}) = log(#{var}), the one power the rule below misses")
      else
        line(out, depth, "power rule: integral(u**n) = u**(n + 1)/(n + 1) with n = #{Simplify.normalize_number(exponent)}")
      end
      true
    end

    # sin(a*x + b) and friends: the table entry, divided by a.
    def table_integral(expr, var, depth, out)
      name, u = expr.is_a?(Fn) && expr.args.size == 1 ? [expr.name, expr.args.first] : [nil, nil]
      name = :exp if expr.is_a?(Pow) && expr.base == Simplify.exp_base
      u = Expression.lift(expr.exponent) if name == :exp && expr.is_a?(Pow)
      entry = INTEGRALS[name]
      return nil if entry.nil?
      a, = Integrate.linear(u, var)
      return nil if a.nil?
      if Scalar.one?(a)
        line(out, depth, "from the table: integral(#{name}(u)) = #{entry}")
      else
        line(out, depth, "from the table: integral(#{name}(u)) = #{entry}, and u = #{u} is linear, so divide by #{a}")
      end
      true
    end

    # g(u)*u': the substitution that turns the integral into one in u.
    def substitution(expr, var, depth, out)
      candidates(expr, var).each do |u|
        derivative = begin
          u.diff(var).simplify
        rescue StandardError => rescued
          RCAS.guard!(rescued)
          next
        end
        next if Scalar.zero?(derivative)
        # Substitute before cancelling: cancelling first can dissolve the
        # very subexpression that is about to become u (x/(1 + x**2)
        # becomes x/(2*x + 2*x**3) and u is no longer there to be seen).
        t = Var.new(:_u)
        replaced = begin
          Div.new(expr, derivative).subs(u => t).cancel.simplify
        rescue StandardError => rescued
          RCAS.guard!(rescued)
          next
        end
        next if replaced.variables.include?(var.name) || !replaced.variables.include?(t.name)
        line(out, depth, "substitute u = #{u}, so du = #{derivative} d#{var}")
        line(out, depth, "the integral becomes integral(#{replaced.subs(t => Var.new(:u))}, u)")
        return true
      end
      nil
    end

    # What is worth trying as a substitution: first the inside of a
    # function or a power (u = x**2 in exp(x**2)), then the function itself
    # (u = sin(x) in sin(x)*cos(x)).
    def candidates(expr, var)
      inner = expr.each_node.filter_map do |node|
        argument = node.is_a?(Fn) ? node.args.first : (node.is_a?(Pow) ? node.base : nil)
        next if argument.nil? || atom?(argument) || !argument.variables.include?(var.name)
        argument
      end
      whole = expr.each_node.select { |node| node.is_a?(Fn) && node.args.size == 1 && !constant?(node, var) }
      (inner + whole).uniq
    end

    # A polynomial times exp/sin/cos, or a lone log/atan/asin.
    BY_PARTS = %i[log atan asin acos].freeze

    def by_parts(expr, var, depth, out)
      if expr.is_a?(Fn) && BY_PARTS.include?(expr.name) && expr.args.first == var
        line(out, depth, "by parts with u = #{expr} and dv = d#{var}, so v = #{var}")
        line(out, depth, "u*v - integral(v*du) = #{var}*#{expr} - integral(#{var}*#{expr.diff(var).simplify}, #{var})")
        return true
      end
      coefficient, factors = Simplify.factorize(expr)
      polynomial = factors.find { |base, exp| base == var && exp.is_a?(Integer) && exp.positive? }
      return nil if polynomial.nil? || factors.size != 2
      other = Simplify.rebuild_product(1, factors.reject { |base, _| base == polynomial.first })
      u = Simplify.rebuild_product(coefficient, { polynomial.first => polynomial.last })
      v = Integrate.integrate(other, var)
      return nil unless Integrate.complete?(v)
      line(out, depth, "by parts with u = #{u} and dv = #{other} d#{var}")
      line(out, depth, "du = #{u.diff(var).simplify} d#{var} and v = #{v}")
      line(out, depth, "u*v - integral(v*du) leaves integral(#{(v * u.diff(var)).simplify}, #{var})")
      true
    end

    # ---- solving -------------------------------------------------------------

    def solution(target, var = nil)
      equation = target.is_a?(Equation) ? target : Equation.new(Expression.lift(target), Num.new(0))
      f = (equation.lhs - equation.rhs).simplify
      var = Expression.lift(var || Solve.variable(f, nil))
      out = []
      line(out, 0, "everything on one side: #{f} = 0", f) unless Scalar.zero?(equation.rhs)
      coefficients = Solve.polynomial_coefficients(f, var)
      if coefficients.nil?
        line(out, 0, "#{f} is not a polynomial in #{var}, so rcas solves it its own way")
      else
        polynomial(coefficients, var, out)
      end
      Derivation.new(Equation.new(equation.lhs, equation.rhs), out, Solve.solve(equation, var.name, principal: true))
    end

    def polynomial(coefficients, var, out)
      degree = coefficients.size - 1
      case degree
      when 0 then line(out, 0, "there is no #{var} left: #{coefficients.first} = 0 has no solution unless it is 0")
      when 1 then linear(coefficients, var, out)
      when 2 then quadratic(coefficients, var, out)
      else higher(coefficients, degree, var, out)
      end
    end

    def linear(coefficients, var, out)
      b, a = coefficients
      line(out, 0, "a linear equation #{a}*#{var} + #{b} = 0, so #{var} = -#{b}/#{a} = #{(-b / a).simplify}")
    end

    def quadratic(coefficients, var, out)
      c, b, a = coefficients
      line(out, 0, "a quadratic a*#{var}**2 + b*#{var} + c = 0 with a = #{a}, b = #{b}, c = #{c}")
      discriminant = (b**2 - 4 * a * c).simplify
      line(out, 0, "the discriminant b**2 - 4*a*c = #{discriminant}", discriminant)
      if Scalar.zero?(discriminant)
        line(out, 0, "it is zero, so the two roots fall together at -b/(2*a)")
      elsif discriminant.variables.empty? && discriminant.evalf.negative?
        line(out, 0, "it is negative, so the two roots are complex conjugates")
      else
        root = Pow.new(discriminant, Num.new(Rational(1, 2))).simplify
        line(out, 0, "#{var} = (-b +- sqrt(b**2 - 4*a*c))/(2*a) = (#{(-b).simplify} +- #{root})/#{(2 * a).simplify}")
      end
    end

    def higher(coefficients, degree, var, out)
      line(out, 0, "a polynomial of degree #{degree}: look for factors first")
      expression = coefficients.each_with_index.map { |c, k| c * var**k }.reduce(:+).simplify
      factored = expression.factor
      if factored.to_s == expression.to_s
        line(out, 0, "it does not factor over the rationals, so the roots are algebraic numbers (RootOf)")
      else
        line(out, 0, "#{expression} = #{factored}, and a product is zero when one of its factors is", factored)
      end
    end

    # ---- partial fractions ---------------------------------------------------

    def fractions(target, var = nil)
      f = Expression.lift(target).cancel
      var = Expression.lift(var || Solve.variable(f, nil))
      out = []
      numerator = RationalFunction.numer(f)
      denominator = RationalFunction.denom(f)
      line(out, 0, "numerator #{numerator} over denominator #{denominator}")
      factored = denominator.factor
      line(out, 0, "factor the denominator: #{denominator} = #{factored}", factored)
      ansatz(numerator, denominator, var, out)
      Derivation.new(Fn.new(:apart, [f]), out, RationalFunction.apart(f, var))
    end

    # One term per factor and per power of it, with an unknown numerator of
    # one degree less; multiplying up and comparing coefficients in x gives
    # a linear system for the unknowns. This is the lesson, so it is worked
    # out rather than asserted.
    def ansatz(numerator, denominator, var, out)
      pieces = []
      unknowns = []
      names = ("A".."Z").to_a
      denominator.to_poly.factor.factors.each do |factor, multiplicity|
        base = factor.to_expr
        degree = Coefficients.degree(base, var)
        (1..multiplicity).each do |power|
          top = (0...degree).map do |k|
            name = Var.new(names[unknowns.size].to_sym)
            unknowns << name
            name * var**k
          end.reduce(:+).simplify
          pieces << Div.new(top, Simplify.power_node(base, power))
        end
      end
      return line(out, 0, "one term per factor, with an unknown on top") if pieces.empty? || unknowns.size > names.size
      line(out, 0, "the ansatz: (#{numerator})/(#{denominator}) = #{pieces.map(&:to_s).join(' + ')}")
      identity = pieces.map { |piece| (piece * denominator).cancel.expand }.reduce(:+)
      equations = Coefficients.coeffs((identity - numerator).expand, var)
      solution = begin
        Solve.linear_system(equations.map(&:simplify), unknowns).first
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        nil
      end
      if solution
        line(out, 0, "comparing the coefficients of #{var}: #{unknowns.map { |u| "#{u} = #{solution[u] || 0}" }.join(', ')}")
      else
        line(out, 0, "comparing the coefficients of #{var} gives a linear system for #{unknowns.join(', ')}")
      end
    end

    # ---- Gaussian elimination ------------------------------------------------

    def elimination(matrix)
      rows = matrix.to_a
      out = []
      pivot_row = 0
      (0...matrix.cols).each do |column|
        break if pivot_row >= matrix.rows
        pivot = (pivot_row...matrix.rows).find { |i| !Scalar.zero?(rows[i][column]) }
        next if pivot.nil?
        if pivot != pivot_row
          rows[pivot_row], rows[pivot] = rows[pivot], rows[pivot_row]
          show(out, rows, matrix, "swap R#{pivot_row + 1} and R#{pivot + 1}")
        end
        unless Scalar.one?(rows[pivot_row][column])
          divisor = rows[pivot_row][column]
          rows[pivot_row] = rows[pivot_row].map { |e| Scalar.div(e, divisor).simplify }
          show(out, rows, matrix, "R#{pivot_row + 1} := R#{pivot_row + 1}/(#{divisor})")
        end
        (0...matrix.rows).each do |i|
          next if i == pivot_row || Scalar.zero?(rows[i][column])
          factor = rows[i][column]
          rows[i] = rows[i].each_with_index.map { |e, j| Scalar.sub(e, Scalar.mul(factor, rows[pivot_row][j])).simplify }
          show(out, rows, matrix, "R#{i + 1} := R#{i + 1} - (#{factor})*R#{pivot_row + 1}")
        end
        pivot_row += 1
      end
      Derivation.new(matrix, out, matrix.rref)
    end

    def show(out, rows, matrix, text)
      space = MatrixSpace.new(matrix.base.fraction_field, matrix.rows, matrix.cols)
      line(out, 0, "#{text}\n#{space.unchecked(rows.map(&:dup))}")
    end

    # ---- Euclid --------------------------------------------------------------

    def euclid(a, b)
      raise ArgumentError, "steps: gcd needs two arguments" if b.nil?
      out = []
      integers = a.is_a?(Integer) && b.is_a?(Integer)
      integers ? integer_euclid(a, b, out) : polynomial_euclid(a, b, out)
      result = integers ? a.gcd(b) : RationalFunction.gcd(a, b)
      Derivation.new(Fn.new(:gcd, [Expression.lift(a), Expression.lift(b)]), out, result)
    end

    def integer_euclid(a, b, out)
      a, b = a.abs, b.abs
      a, b = b, a if b > a
      while b.positive?
        quotient, remainder = a.divmod(b)
        line(out, 0, "#{a} = #{quotient}*#{b} + #{remainder}")
        a, b = b, remainder
      end
      line(out, 0, "the last remainder that is not zero is the gcd")
    end

    def polynomial_euclid(a, b, out)
      a = Expression.lift(a)
      b = Expression.lift(b)
      var = Solve.variable(a + b, nil)
      while !Scalar.zero?(b.simplify)
        quotient = RationalFunction.quo(a, b, var)
        remainder = RationalFunction.rem(a, b, var).simplify
        line(out, 0, "#{a} = (#{quotient})*(#{b}) + (#{remainder})")
        a, b = b, remainder
        break if Coefficients.degree(b, var).zero?
      end
      line(out, 0, "the last remainder that is not zero is the gcd, up to a constant factor")
    end

    # ---- factorization -------------------------------------------------------

    def factorization(target, var = nil)
      value = target.is_a?(Num) ? target.value : target
      return integer_factors(value) if value.is_a?(Integer)
      polynomial_factors(Expression.lift(value), var)
    end

    TRIAL_LIMIT = 10_000

    # Trial division by the primes, one at a time, which is how it is first
    # taught and what rcas itself does until the numbers get large.
    def integer_factors(n)
      out = []
      rest = n.abs
      line(out, 0, "a minus sign comes out in front") if n.negative?
      if rest < 2
        line(out, 0, "#{n} has no prime factorization of its own")
        return Derivation.new(Fn.new(:factor, [Num.new(n)]), out, NumberTheory.factor(n))
      end
      prime = 2
      while rest > 1 && prime <= TRIAL_LIMIT && prime * prime <= rest
        break if NumberTheory.prime?(rest)
        if (rest % prime).zero?
          line(out, 0, "#{rest} = #{prime}*#{rest / prime}")
          rest /= prime
        else
          prime = NumberTheory.nextprime(prime)
        end
      end
      if rest > 1 && NumberTheory.prime?(rest)
        line(out, 0, "#{rest} is prime, and the trial division stops there")
      elsif rest > 1
        line(out, 0, "#{rest} is left, too big to divide through by hand; rcas finishes it with Pollard's rho")
      end
      Derivation.new(Fn.new(:factor, [Num.new(n)]), out, NumberTheory.factor(n))
    end

    def polynomial_factors(f, var)
      out = []
      result = f.factor
      var = Expression.lift(var) if var
      var ||= f.variables.size == 1 ? Var.new(f.variables.first) : nil
      coefficients = var && Solve.polynomial_coefficients(f.expand, var)
      if coefficients.nil?
        line(out, 0, "several variables, so rcas factors this its own way: squarefree decomposition, " \
                     "factoring modulo a prime, Hensel lifting and recombination")
        return Derivation.new(Fn.new(:factor, [f]), out, result)
      end
      rest = common_factor(coefficients, var, out)
      roots(rest, var, out)
      Derivation.new(Fn.new(:factor, [f]), out, result)
    end

    # The content and the lowest power of the variable.
    def common_factor(coefficients, var, out)
      numbers = coefficients.map { |c| c.is_a?(Num) ? c.value : nil }
      content = numbers.all? { |c| c.is_a?(Integer) } ? numbers.reduce(0) { |a, b| a.gcd(b) } : 1
      low = coefficients.index { |c| !Scalar.zero?(c) }
      polynomial = rebuild(coefficients, var)
      if content > 1 || low.positive?
        factor = Simplify.rebuild_product(content, low.positive? ? { var => low } : {})
        polynomial = rebuild(coefficients.drop(low).map { |c| (c / content).simplify }, var)
        line(out, 0, "every term has #{factor} in it, so it comes out: #{Mul.new(factor, polynomial)}")
      end
      polynomial
    end

    def rebuild(coefficients, var)
      coefficients.each_with_index.map { |c, k| c * var**k }.reduce(:+).simplify
    end

    # The rational root theorem, then division, until a quadratic is left.
    def roots(f, var, out, depth = 0)
      coefficients = Solve.polynomial_coefficients(f.expand, var)
      degree = coefficients ? coefficients.size - 1 : 0
      return line(out, depth, "#{f} is linear, so there is nothing left to do") if degree <= 1
      return difference_of_squares(coefficients, var, out, depth) if squares?(coefficients)
      return quadratic_factor(coefficients, f, var, out, depth) if degree == 2

      root = rational_root(coefficients, var, out, depth)
      unless root
        line(out, depth, "no rational root, so #{f} needs the modular algorithm rcas uses for the general case")
        return
      end
      quotient = RationalFunction.quo(f, var - root, var).simplify
      line(out, depth, "#{f} = (#{(var - root).simplify})*(#{quotient})")
      roots(quotient, var, out, depth)
    end

    # p/q with p dividing the constant term and q the leading coefficient.
    def rational_root(coefficients, var, out, depth)
      constant = coefficients.first
      leading = coefficients.last
      return nil unless constant.is_a?(Num) && leading.is_a?(Num) &&
                        constant.value.is_a?(Integer) && leading.value.is_a?(Integer) && !constant.value.zero?
      tops = NumberTheory.divisors(constant.value)
      bottoms = NumberTheory.divisors(leading.value)
      candidates = tops.product(bottoms).flat_map { |a, b| [Rational(a, b), Rational(-a, b)] }.uniq.sort
      line(out, depth, "a rational root p/q has p dividing #{constant} and q dividing #{leading}: " \
                       "try #{candidates.first(8).map { |c| Num.new(Simplify.normalize_number(c)) }.join(', ')}#{' and so on' if candidates.size > 8}")
      f = rebuild(coefficients, var)
      found = candidates.find { |c| Scalar.zero?(f.subs(var => Num.new(Simplify.normalize_number(c))).simplify) }
      return nil if found.nil?
      value = Num.new(Simplify.normalize_number(found))
      line(out, depth, "f(#{value}) = 0, so #{(var - value).simplify} divides it")
      value
    end

    def quadratic_factor(coefficients, f, var, out, depth)
      c, b, a = coefficients
      discriminant = (b**2 - 4 * a * c).simplify
      line(out, depth, "the quadratic #{f}: its discriminant is #{discriminant}", discriminant)
      if Scalar.zero?(discriminant)
        line(out, depth, "zero, so it is a square: (#{(var + b / (2 * a)).simplify})**2 times #{a}")
      elsif square_number?(discriminant)
        root = Pow.new(discriminant, Num.new(Rational(1, 2))).simplify
        line(out, depth, "#{root}**2, a square, so the roots (#{(-b).simplify} +- #{root})/#{(2 * a).simplify} are rational and it factors")
      else
        line(out, depth, "not a square, so it does not factor over the rationals")
      end
    end

    # a*x**2 - c with both a and c square numbers.
    def squares?(coefficients)
      return false unless coefficients.size == 3 && Scalar.zero?(coefficients[1])
      a = coefficients[2]
      c = coefficients[0]
      square_number?(a) && a.is_a?(Num) && c.is_a?(Num) && c.value.negative? && square_number?(Num.new(-c.value))
    end

    def difference_of_squares(coefficients, var, out, depth)
      a = Pow.new(coefficients[2], Num.new(Rational(1, 2))).simplify
      b = Pow.new(Num.new(-coefficients[0].value), Num.new(Rational(1, 2))).simplify
      line(out, depth, "a difference of squares: u**2 - v**2 = (u - v)*(u + v) with u = #{(a * var).simplify} and v = #{b}")
    end

    def square_number?(value)
      value.is_a?(Num) && value.value.is_a?(Integer) && !value.value.negative? &&
        Integer.sqrt(value.value)**2 == value.value
    end
  end
end
