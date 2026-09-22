# frozen_string_literal: true

module RCAS
  # lhs = rhs. Build with eq(a, b) or a.eq(b); solve with solve(equation, x).
  class Equation
    attr_reader :lhs, :rhs

    def initialize(lhs, rhs)
      @lhs = Expression.lift(lhs)
      @rhs = Expression.lift(rhs)
      freeze
    end

    def to_expr = Sub.new(lhs, rhs)
    def simplify = Equation.new(lhs.simplify, rhs.simplify)
    def expand = Equation.new(lhs.expand, rhs.expand)
    def subs(*args) = Equation.new(lhs.subs(*args), rhs.subs(*args))
    def swap = Equation.new(rhs, lhs)
    def variables = (lhs.variables | rhs.variables).sort
    def solve(var = nil) = Solve.solve(self, var)

    # Does the equation hold for these values?
    def holds?(**bindings)
      value = Expression.lift((lhs - rhs).call(**bindings)).simplify
      value.is_a?(Num) && (value.value.is_a?(Float) ? value.value.abs < 1e-9 : value.zero?)
    end

    %i[+ - * /].each do |op|
      define_method(op) do |other|
        other.is_a?(Equation) ? Equation.new(lhs.public_send(op, other.lhs), rhs.public_send(op, other.rhs)) : Equation.new(lhs.public_send(op, other), rhs.public_send(op, other))
      end
    end
    def -@ = Equation.new(-lhs, -rhs)

    # hold { integral(x**2, x) == x }.doit is x**3/3 = x: both sides
    # evaluated, the statement kept (third review, C9)
    def evaluate = Equation.new(lhs.evaluate, rhs.evaluate)
    alias doit evaluate
    alias unhold evaluate

    def ==(other) = other.is_a?(Equation) && other.lhs == lhs && other.rhs == rhs
    alias eql? ==
    def hash = [Equation, lhs, rhs].hash

    def to_s = "#{lhs} = #{rhs}"
    alias inspect to_s

    # to_latex: latex.rb's (the one with wrap:), which replaced this one
  end

  # {2*pi*k | k in ZZ}: a solution that is a family rather than a number.
  # An equation with infinitely many solutions has no honest answer as a
  # list of numbers - sin(x) = 0 is solved by every multiple of pi, not by
  # 0 and pi - and this is the object MuPAD answers such an equation with.
  # The parameter carries its domain with it, so the answer says what k is
  # instead of leaving the reader (and `simplify`) to guess.
  class ImageSet
    attr_reader :expr, :parameters, :domain

    def initialize(expr, parameters, domain = ZZ)
      @expr = Expression.lift(expr)
      @parameters = Array(parameters).map { |p| p.is_a?(Var) ? p : Var.new(p) }
      @domain = domain
      freeze
    end

    # The member at k = i, with one value per parameter: at(0), at(1), ...
    def at(*values)
      bindings = parameters.each_with_index.to_h { |p, i| [p.name, Expression.lift(values[i])] }
      expr.subs(bindings).simplify
    end

    # No member on the real line: the step is real and a member is not, so
    # every member has the same non-zero imaginary part ({pi - acos(2) +
    # 2*pi*k}, the zeros of 2 + cos(x)).
    def nonreal?
      return false unless parameters.size == 1
      step = (at(1) - at(0)).simplify
      Inequalities.real?(step) && !Inequalities.real?(at(0))
    rescue NotImplementedError, StandardError
      false
    end

    # The members between two numbers, when they can be counted out; [] for
    # a family that never meets the real line.
    def between(lo, hi, limit: 1024)
      return nil unless parameters.size == 1
      return [] if nonreal?
      base = numeric(at(0))
      step = base && numeric(at(1))
      return nil if base.nil? || step.nil? || (step - base).abs < 1e-12
      first, last = [((lo - base) / (step - base)).floor, ((hi - base) / (step - base)).ceil].minmax
      return nil if last - first > limit
      (first..last).map { |i| at(i) }.select { |m| (v = numeric(m)) && v >= lo && v <= hi }
    end

    def variables = expr.variables - parameters.map(&:name)
    def to_expr = expr

    # The image of the set under a function of its member: the parameter
    # keeps its domain while the block runs, and the result is simplified
    # there too, so cos of {2*pi*k | k in ZZ} folds to 1 without anyone
    # declaring k first - that fold needs the integer. A result that no
    # longer mentions the parameter is not a family any more and comes back
    # as the value itself.
    def map
      inside = RCAS.assume(**parameters.to_h { |p| [p.name, domain] }) do
        found = yield(expr)
        found.is_a?(Expression) ? found.simplify : found
      end
      lifted = Expression.lift(inside)
      (lifted.variables & parameters.map(&:name)).empty? ? lifted : ImageSet.new(lifted, parameters, domain)
    end

    def ==(other)
      other.is_a?(ImageSet) && other.expr == expr && other.parameters == parameters && other.domain == domain
    end
    alias eql? ==
    def hash = [ImageSet, expr, parameters, domain].hash

    def to_s = "{#{expr} | #{parameters.join(', ')} in #{domain}}"
    alias inspect to_s

    def to_latex(wrap: nil)
      inside = parameters.map { |p| LaTeX.of(p) }.join(', ')
      "\\left\\{ #{LaTeX.of(expr)} \\mid #{inside} \\in #{LaTeX.of(domain)} \\right\\}"
    end

    private

    def numeric(value) = RCAS.real_float(value, finite: false)
  end

  # Equation solving.
  #
  #   solve(x**2 - 3*x + 2, x)          # => [1, 2]
  #   solve(eq(x**2, -1), x)            # => [-i, i]
  #   solve(exp(2*x) - 3*exp(x) + 2, x) # => [0, log(2)]
  #   solve([eq(x + y, 3), eq(x - y, 1)], [x, y])   # => [{x => 2, y => 1}]
  #
  #   solve(abs(x) - 1, x)              # => [1, -1]
  #
  # Polynomials are solved exactly through factorization over QQ, the
  # quadratic formula, k-th roots for binomials and the quadratic formula
  # with symbolic coefficients; irreducible factors of degree >= 3 with
  # numeric coefficients get numeric roots. Transcendental equations are
  # reduced to polynomials in one atom (exp(x), sin(x), sqrt(x), ...) and
  # inverted. An equation with abs or sign is split into its cases and each
  # candidate substituted back. Systems: linear in the unknowns, or two
  # polynomial equations in two unknowns through resultants.
  #
  # Sources (keys: MANUAL.md, Sources): elimination by resultants [GCL92,
  # ch. 9], [CLO15, §3.6]; numeric roots by the Durand-Kerner (Weierstrass)
  # simultaneous iteration [Ker66], started at powers of 0.4 + 0.9i.
  module Solve
    MAX_DEPTH = 6
    # abs and sign split the line into cases; 2**n branches, so a small n.
    CASES = %i[abs sign].freeze
    MAX_CASES = 3

    module_function

    # Every solution, which for a trigonometric equation means a family per
    # period: the answer is an ImageSet, {2*pi*k | k in ZZ}, rather than a
    # selection from it. `principal: true` (or the older `all: false`) asks
    # for the solutions in one period instead, which is what the analysis
    # inside rcas wants and what a table of exact values shows.
    # The unknown's declared domain (assume(x: ZZ), or domain: here) keeps
    # out the solutions that demonstrably do not lie in it.
    def solve(target, vars = nil, all: true, principal: false, domain: nil)
      principal ||= !all
      if target.equal?(true) || target.equal?(false)
        raise ArgumentError, "solve: `==` compares structurally in Ruby and this one is already #{target}; " \
                             "write solve(eq(lhs, rhs), x) or solve(hold { lhs == rhs }, x)"
      end
      return Inequalities.solve(target, vars) if target.is_a?(Inequality) || (target.is_a?(Array) && target.any? { |t| t.is_a?(Inequality) })
      return system(target, vars, domain: domain) if target.is_a?(Array)
      return piecewise(target, vars) if piecewise?(target)
      original = to_zero(target)
      f = original.simplify
      x = variable(f, vars)
      # The poles are read off the equation as it was written: simplify
      # cancels (x - 1)/(x - 1) to 1, and x = 1 is still no solution of
      # (x - 1)/(x - 1) = 1, where the left side has no value.
      poles = Analysis.denominators(original, x)
      # 0 = 0 holds for every value of x. That is an answer, and a set is
      # what says it; raising made a true statement look like a failure.
      # Every value *of x*: with x declared an integer, sin(pi*x) vanishes
      # on ZZ and nowhere else, so the reals would be an overstatement.
      return everywhere(x, domain, poles) if Scalar.zero?(f) || rational_identity?(f, x)
      found =
        begin
          univariate(f, x, 0, all: !principal)
        rescue Whole => e
          # squaring gave an identity, and the answer is a set (S18)
          return e.set
        rescue NotImplementedError
          constant = trig_constant(f)
          raise if constant.nil?
          return Scalar.zero?(constant) ? everywhere(x, domain, poles) : []
        end
      roots = dedupe(found).map { |root| family(root, x, f) }
      ordered(restrict(off_poles(merge_families(roots), poles, x), x, domain))
    end

    # x/(x + 1) + 1/(x + 1) - 1 is zero as a rational function, which the
    # normal form of simplify does not show: its cleared numerator is the
    # zero polynomial, and the root finder answered that with [].
    def rational_identity?(f, x)
      return false unless f.each_node.any? { |n| n.is_a?(Div) || (n.is_a?(Pow) && n.exponent.is_a?(Num) && Simplify.negative?(n.exponent.value)) }
      Scalar.zero?(f.cancel)
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    # Every value of x is a solution: the declared domain when there is one,
    # the reals otherwise - less the poles of the equation as written, so
    # (x**2 - 1)/(x - 1) = x + 1 holds everywhere but at 1. Poles that come
    # in a family cannot be taken out of a finite union of intervals, and
    # the reals would claim them: that is refused.
    def everywhere(x, domain, poles = [])
      declared = domain || RCAS.assumption(x.name)
      return declared if declared
      points = poles.flat_map do |d|
        found = Solve.solve(d, x)
        raise NotImplementedError, "every #{x} where #{d} != 0 is a solution; that set is not a finite union of intervals" unless found.is_a?(Array)
        found
      end
      if points.any? { |p| p.is_a?(ImageSet) }
        raise NotImplementedError, "every #{x} off the zeros of #{poles.join(', ')} is a solution; that set is not a finite union of intervals"
      end
      real = points.select { |p| Analysis.numeric(p) }
      return RealSet.reals if real.empty?
      RealSet.reals - RealSet.new(real.map { |p| Interval.point(p) })
    end

    # Roots and families of the simplified equation that are poles of the
    # equation as written. A point is dropped when a denominator is shown
    # to vanish there. A family is checked member by member through its
    # index: the members where a denominator vanishes form a sub-progression
    # (or a single index, or nothing), and what is left is written as
    # families again - sin(2*x)/sin(x) keeps {pi/2 + pi*k} and loses
    # {pi*k}, sin(x)/x keeps {pi*k} for k >= 1 and k <= -1.
    def off_poles(roots, poles, x)
      return roots if poles.empty?
      roots.flat_map do |root|
        if root.is_a?(ImageSet)
          family_off_poles(root, poles, x)
        elsif root.is_a?(Expression) && root.variables.empty?
          pole_at?(poles, x, root) ? [] : [root]
        else
          [root]
        end
      end
    end

    def pole_at?(poles, x, point)
      poles.any? do |d|
        value = begin
          d.subs(x => point).simplify
        rescue ZeroDivisionError
          next true
        end
        Decide.zero?(value) == true
      end
    end

    # [a + b*k | k in ZZ] minus its poles, as a list of families.
    def family_off_poles(set, poles, x)
      return [set] unless set.parameters.size == 1 && set.domain == ZZ
      k = set.parameters.first
      step = begin
        Coefficients.coeff(set.expr, k, 1)
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        return [set]
      end
      offset = (set.expr - step * k).simplify
      return [set] if offset.variables.include?(k.name) || Scalar.zero?(step)
      # indices to drop: residues r mod n (from a family of poles) and
      # single indices (from isolated poles)
      progressions = []
      singles = []
      poles.each do |d|
        zeros = begin
          Solve.solve(d, x)
        rescue NotImplementedError, ArgumentError
          next
        end
        next unless zeros.is_a?(Array)
        zeros.each do |z|
          if z.is_a?(ImageSet)
            progressions.concat(progression_hit(z, offset, step))
          elsif z.is_a?(Expression) && z.variables.empty?
            index = ((z - offset) / step).simplify
            singles << index.value if index.is_a?(Num) && index.value.is_a?(Integer)
          end
        end
      end
      return [set] if progressions.empty? && singles.empty?
      modulus = progressions.map(&:last).reduce(1, :lcm)
      kept = (0...modulus).reject { |r| progressions.any? { |res, n| r % n == res } }
      return [] if kept.empty?
      j = Var.new(k.name)
      families = kept.map do |r|
        ImageSet.new((offset + step * (r + modulus * j)).simplify, [j], ZZ)
      end
      singles = singles.uniq.select { |i| kept.include?(i % modulus) }
      singles.reduce(families) { |list, i| split_at(list, i, offset, step, modulus, j) }
    end

    # The residues r mod n of the indices k at which a + b*k is a member of
    # the family z, as [[r, n], ...], when that is decidable: the steps and
    # the offsets have a rational ratio. k gives the member of z with index
    # m = (a - c + b*k)/e, which is an integer or not with period q in k,
    # q the denominator of b/e - so trying k = 0...q finds every residue.
    def progression_hit(z, offset, step)
      return [] unless z.parameters.size == 1 && z.domain == ZZ
      m = z.parameters.first
      zstep = begin
        Coefficients.coeff(z.expr, m, 1)
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        return []
      end
      zoffset = (z.expr - zstep * m).simplify
      return [] if zoffset.variables.include?(m.name)
      ratio = (step / zstep).simplify
      shift = ((offset - zoffset) / zstep).simplify
      rational = ->(v) { v.is_a?(Num) && (v.value.is_a?(Integer) || v.value.is_a?(Rational)) }
      return [] unless rational.call(ratio) && rational.call(shift)
      ratio = Rational(ratio.value)
      shift = Rational(shift.value)
      q = ratio.denominator
      (0...q).select { |k| (shift + ratio * k).denominator == 1 }.map { |r| [r, q] }
    end

    # A family minus one member at index i (of the original a + b*k): the
    # family containing it becomes two half-families running away from it.
    def split_at(families, i, offset, step, modulus, j)
      r = i % modulus
      families.flat_map do |fam|
        next [fam] unless fam.expr == (offset + step * (r + modulus * j)).simplify
        up = (offset + step * (i + modulus + modulus * j)).simplify
        down = (offset + step * (i - modulus - modulus * j)).simplify
        [ImageSet.new(down, [j], NN), ImageSet.new(up, [j], NN)]
      end
    end

    # An identity is an identity however it is written, and no rule in the
    # chain sees the Pythagorean one: sin(x)**2 + cos(x)**2 - 1 is zero, and
    # `Scalar.zero?` cannot say so because the identity only shows after
    # trigsimp. The other side of the same reading is just as much an
    # answer - a trigonometric expression that reduces to a constant which
    # is not zero has no solutions at all, so sin(x)**2 + cos(x)**2 + 1 = 0
    # is [] rather than "can't solve" (20 Sept 2026, the ninth pass of the
    # review). It is asked only once every rule has failed, because trigsimp
    # costs milliseconds and `discuss` calls solve for every row it fills.
    def trig_constant(f)
      return nil unless f.each_node.any? { |n| n.is_a?(Fn) && Trigonometry::SQUARES.key?(n.name) }
      reduced = Trigonometry.trigsimp(f).simplify
      reduced.variables.empty? ? reduced : nil
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      nil
    end

    # Families of one period that say the same thing twice, or that together
    # make a finer one: sin(x)**2 = 1 is solved at pi/2, -pi/2 and 3*pi/2
    # over a period of 2*pi, of which the last two are the same set and all
    # three together are {pi/2 + pi*k | k in ZZ} - which is what a student
    # writes. The offsets are compared as fractions of the step, so it works
    # the same for {2*k} and {1 + 2*k}, whose union is the integers.
    def merge_families(roots)
      entries = roots.map { |root| family_shape(root) || [:plain, root] }
      groups = entries.select { |e| e.first == :family }.group_by { |e| e[1] }
      done = {}
      entries.flat_map do |entry|
        next [entry.last] if entry.first == :plain
        next [] if done[entry[1]]
        done[entry[1]] = true
        merged_family(groups[entry[1]], entry[1])
      end
    end

    # [:family, step, offset as a fraction of the step, the set], or nil for
    # anything this cannot measure - a set whose offset is not a rational
    # multiple of its step has no residue to compare.
    def family_shape(root)
      return nil unless root.is_a?(ImageSet) && root.parameters.size == 1
      k = root.parameters.first
      step = begin
        Coefficients.coeff(root.expr, k, 1)
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        nil
      end
      return nil if step.nil? || Scalar.zero?(step)
      offset = (root.expr - step * k).simplify
      return nil if offset.variables.include?(k.name)
      residue = (offset / step).simplify
      return nil unless residue.is_a?(Num) && (residue.value.is_a?(Integer) || residue.value.is_a?(Rational))
      [:family, step, Rational(residue.value) % 1, root]
    end

    def merged_family(group, step)
      residues = group.map { |e| e[2] }.uniq.sort
      set = group.first.last
      count = residues.size
      if count > 1 && residues.each_cons(2).all? { |a, b| b - a == Rational(1, count) }
        [rebuilt_family(set, residues.first * step, step / count)]
      else
        residues.map { |residue| rebuilt_family(set, residue * step, step) }
      end
    end

    # {k | k in ZZ} is the domain itself, and says so.
    def rebuilt_family(set, offset, step)
      k = set.parameters.first
      expr = (Expression.lift(offset) + step * k).simplify
      expr == k ? set.domain : ImageSet.new(expr, [k], set.domain)
    end

    # A root carrying a parameter the equation did not have is one period's
    # worth of solutions repeated for ever: say so as a set, and name the
    # parameter's domain, so that `simplify` can check the answer and the
    # reader does not have to assume what k is.
    def family(root, x, f)
      return root unless root.is_a?(Expression)
      parameters = root.variables - f.variables - [x.name]
      parameters.empty? ? root : ImageSet.new(root, parameters.sort.map { |name| Var.new(name) })
    end

    # Real roots ascending, then the rest in the order they were found. The
    # order a method happens to produce is not an answer about the roots.
    def ordered(roots)
      keys = roots.each_with_index.to_h do |root, i|
        value = begin
          root.is_a?(Expression) ? root.evalf : nil # a family or a set has no value
        rescue StandardError => rescued
          RCAS.guard!(rescued)
          nil
        end
        value = value.value if value.is_a?(Num)
        [root, value.is_a?(Numeric) && value.real? ? [0, value.to_f, i] : [1, 0.0, i]]
      end
      roots.sort_by { |root| keys[root] }
    end

    # Drop the solutions that contradict what the unknown was declared to
    # be - a number set, a sign, or both. What cannot be decided stays
    # (Infer.excluded?), so an answer is never lost to a guess.
    def restrict(roots, x, domain)
      wanted = domain || RCAS.assumption(x.name)
      sign = RCAS.signs[x.name]
      return roots if wanted.nil? && sign.nil?
      roots.flat_map do |root|
        # {k | k in ZZ} came back as ZZ itself: the smaller of the two sets
        # (third review, S17)
        next [wanted && !root.subset?(wanted) ? wanted : root] if root.is_a?(NumberSet)
        next restrict_family(root, wanted, sign) if root.is_a?(ImageSet)
        (wanted && Infer.excluded?(root, wanted)) || (sign && wrong_sign?(root, sign)) ? [] : [root]
      end
    end

    # Which members of a family lie in a declared domain. For the families
    # trigonometry produces this is decidable rather than guessed: a + b*k
    # with a and b rational multiples of pi is rational only where the pi
    # part cancels, because pi is transcendental, and that happens for at
    # most one k. So {2*pi*k | k in ZZ} meets ZZ in 0 alone, and
    # {pi + 2*pi*k | k in ZZ} not at all. A family of any other shape stays
    # whole: "some member might qualify" is the honest answer there.
    def restrict_family(set, wanted, sign)
      # a family off the real line has no member in RR: asin(2) + 2*pi*k
      # under domain: RR (third review, S19)
      return [] if wanted && wanted <= RR && set.nonreal?
      return [set] unless wanted && wanted <= QQ && set.parameters.size == 1
      k = set.parameters.first
      slope = begin
        Coefficients.coeff(set.expr, k, 1)
      rescue StandardError => rescued
        RCAS.guard!(rescued)
        nil
      end
      return [set] if slope.nil?
      rest = (set.expr - slope * k).simplify
      return [set] if rest.variables.include?(k.name)
      step = Trig.pi_multiple(slope)
      offset = Scalar.zero?(rest) ? Rational(0) : Trig.pi_multiple(rest)
      return [set] if step.nil? || offset.nil? || step.zero?
      turns = -offset / step
      return [] unless turns.denominator == 1 && set.domain.include?(turns.numerator)
      member = set.at(turns.numerator)
      (wanted && Infer.excluded?(member, wanted)) || (sign && wrong_sign?(member, sign)) ? [] : [member]
    end

    # What each declared sign allows a root to be.
    ALLOWED_SIGNS = { positive: %i[positive], nonnegative: %i[positive zero],
                      negative: %i[negative], nonpositive: %i[negative zero] }.freeze

    def wrong_sign?(root, sign)
      found = root_sign(root)
      !found.nil? && !ALLOWED_SIGNS.fetch(sign, %i[positive negative zero]).include?(found)
    end

    # The sign of a constant root, or nil when it is not decided: a root
    # with a parameter in it, or one that is not real.
    def root_sign(root)
      return nil unless root.variables.empty?
      return :zero if Scalar.zero?(root)
      value = Analysis.numeric(root)
      return nil if value.nil?
      value.positive? ? :positive : :negative
    end

    # An integer parameter for the periodic solutions, avoiding the names in use.
    def period_parameter(f, x)
      taken = f.variables | [x.name]
      name = %i[k n m j].find { |candidate| !taken.include?(candidate) }
      name ||= (1..).lazy.map { |i| :"k#{i}" }.find { |candidate| !taken.include?(candidate) }
      Var.new(name)
    end

    def to_zero(target) = target.is_a?(Equation) ? Sub.new(target.lhs, target.rhs) : Expression.lift(target)

    def piecewise?(target)
      return true if target.is_a?(Expression) && target.each_node.any? { |n| n.is_a?(Piecewise) }
      target.is_a?(Equation) && (target.lhs.each_node.any? { |n| n.is_a?(Piecewise) } || target.rhs.each_node.any? { |n| n.is_a?(Piecewise) })
    end

    # Every branch is solved on its own piece (piecewise.rb).
    def piecewise(target, vars)
      return Piecewises.solve(Piecewises.hoist(target), Num.new(0), vars) unless target.is_a?(Equation)
      pw = Piecewises.hoist(Sub.new(target.lhs, target.rhs).simplify)
      return Piecewises.solve(pw, Num.new(0), vars) if pw.is_a?(Piecewise)
      Solve.solve(pw, vars)
    end

    def variable(f, vars)
      return Expression.lift(vars) if vars
      free = f.variables
      raise ArgumentError, "solve: which variable? #{f} has #{free.size} variables" unless free.size == 1
      Var.new(free.first)
    end

    def depends?(e, x) = e.variables.include?(x.name)

    def dedupe(list)
      out = []
      list.each { |s| out << s unless out.any? { |o| o == s } }
      out
    end

    # ---- one equation, one unknown ----------------------------------------------

    def univariate(f, x, depth, all: false)
      return [] if depth > MAX_DEPTH
      f = f.simplify
      raise ArgumentError, "every value of #{x} is a solution" if Scalar.zero?(f)
      return [] unless depends?(f, x)

      cases = case_nodes(f, x)
      return case_split(f, x, cases, depth, all: all) unless cases.empty?

      num, den = numerator_denominator(f, x)
      coeffs = polynomial_coefficients(num, x)
      # a zero numerator is an identity off the poles, not "no roots"
      raise ArgumentError, "every value of #{x} is a solution" if coeffs&.all? { |c| Scalar.zero?(c) }
      roots = coeffs ? polynomial_roots(coeffs) : transcendental(num, x, depth, all: all)
      roots = roots.map(&:simplify).reject { |r| Scalar.zero?(den.subs(x => r).simplify) }
      verify(f, x, roots)
    end

    # The distinct abs(u) and sign(u) in f whose u depends on x: the places
    # where f is one expression to the left of a point and another to the right.
    def case_nodes(f, x)
      f.each_node.select { |n| n.is_a?(Fn) && CASES.include?(n.name) && n.args.size == 1 && depends?(n.args.first, x) }.uniq
    end

    # |u| is u where u >= 0 and -u where u <= 0, and sign(u) is 1, -1 and 0
    # in the same three places, so an equation with n of them is 2**n
    # equations without any, together with the points where a sign vanishes.
    # Every candidate goes back through verify, which drops the roots of a
    # branch that do not lie in it, so the answer is the case split a
    # student writes - and |x| - 1 = 0 no longer comes back empty.
    def case_split(f, x, nodes, depth, all: false)
      raise NotImplementedError, "can't solve #{f} = 0 for #{x}: too many cases" if nodes.size > MAX_CASES
      roots = [1, -1].repeated_permutation(nodes.size).flat_map { |signs| branch_roots(f, x, nodes, signs, depth, all: all) }
      roots += nodes.select { |n| n.name == :sign }.flat_map { |n| univariate(n.args.first, x, depth + 1, all: all) }
      verify(f, x, dedupe(roots.map(&:simplify)))
    end

    def branch_roots(f, x, nodes, signs, depth, all: false)
      branch = nodes.zip(signs).map { |node, sign| [node, branch_value(node, sign)] }.to_h
      univariate(f.subs(branch), x, depth + 1, all: all)
    rescue ArgumentError => e
      raise unless e.message.start_with?("every value")
      # A whole branch vanishes: |x| - x is zero on all of x >= 0, which is
      # a set, and solve answers with points. Name the branch instead.
      raise ArgumentError, "every #{x} with #{branch_conditions(nodes, signs).join(' and ')} solves #{f} = 0"
    end

    def branch_value(node, sign)
      return Num.new(sign) if node.name == :sign
      sign.positive? ? node.args.first : Neg.new(node.args.first)
    end

    def branch_conditions(nodes, signs)
      nodes.zip(signs).map do |node, sign|
        strict = node.name == :sign
        op = if sign.positive? then strict ? :> : :>=
             else strict ? :< : :<=
             end
        Inequality.new(node.args.first, op, 0)
      end
    end

    # f = num / den with den the product of the x-dependent denominators.
    def numerator_denominator(f, x)
      _, table = Expand.table(f)
      den_factors = {}
      table.each_key do |factors|
        factors.each do |base, exp|
          next unless exp.is_a?(Integer) && exp.negative? && depends?(base, x)
          den_factors[base] = [den_factors[base] || 0, -exp].max
        end
      end
      return [f, Num.new(1)] if den_factors.empty?
      constant, table = Expand.table(f)
      cleared = {}
      cleared[den_factors.dup] = constant unless constant.zero?
      table.each do |factors, coeff|
        merged = factors.dup
        den_factors.each do |base, k|
          e = Simplify.add_exponents(merged[base] || 0, k)
          e.is_a?(Numeric) && e.zero? ? merged.delete(base) : merged[base] = e
        end
        cleared[merged] = (cleared[merged] || 0) + coeff
      end
      [Simplify.rebuild_sum(0, cleared).expand, Simplify.rebuild_product(1, den_factors)]
    end

    # Coefficients of f as a polynomial in x (index = degree), or nil.
    def polynomial_coefficients(f, x)
      constant, table = Expand.table(f)
      coeffs = Hash.new { Num.new(0) }
      coeffs[0] = Num.new(constant)
      table.each do |factors, coeff|
        degree = 0
        c = Num.new(coeff)
        factors.each do |base, exp|
          if base == x
            return nil unless exp.is_a?(Integer) && exp >= 0
            degree += exp
          elsif depends?(base, x) || (exp.is_a?(Expression) && depends?(exp, x))
            return nil
          else
            c *= Simplify.power_node(base, exp)
          end
        end
        coeffs[degree] = coeffs[degree] + c
      end
      list = (0..coeffs.keys.max).map { |k| coeffs[k].simplify }
      list.pop while list.size > 1 && Scalar.zero?(list.last)
      list
    end

    # Roots (with multiplicity) of the polynomial with these coefficients.
    def polynomial_roots(coeffs)
      coeffs = coeffs.dup
      coeffs.pop while coeffs.size > 1 && Scalar.zero?(coeffs.last)
      n = coeffs.size - 1
      return [] if n < 1
      return exact_roots(coeffs) if coeffs.all? { |c| c.is_a?(Num) && (c.value.is_a?(Integer) || c.value.is_a?(Rational)) }

      factored = symbolic_roots_by_factoring(coeffs)
      return factored if factored

      case n
      when 1 then [(-coeffs[0] / coeffs[1]).cancel]
      when 2 then quadratic(coeffs[2], coeffs[1], coeffs[0])
      else raise NotImplementedError, "can't solve a degree #{n} polynomial with symbolic coefficients exactly"
      end
    end

    # (x - a)*(x - 1) = 0 has the roots a and 1: factor over QQ[x, params]
    # first and read linear factors off; quadratic factors use the formula.
    def symbolic_roots_by_factoring(coeffs)
      x = Var.new(:_x)
      expr = coeffs.each_with_index.reduce(Num.new(0)) { |acc, (c, k)| acc + c * x**k }
      vars = expr.variables
      return nil unless vars.include?(:_x)
      return nil if coeffs.size > 3 && irreducible_image?(coeffs)
      poly = Polynomial.from_expr(QQ[*vars], expr)
      factors = poly.factor.factors.map(&:first).reject { |g| g.degree(:_x).zero? }
      return nil if factors.size <= 1 && factors.first&.degree(:_x).to_i >= 2
      factors.flat_map do |g|
        cs = (0..g.degree(:_x)).map { |k| g.coefficient_in(:_x, k).to_expr }
        case cs.size - 1
        when 1 then [(-cs[0] / cs[1]).cancel]
        when 2 then quadratic(cs[2], cs[1], cs[0])
        else raise NotImplementedError, "can't solve a degree #{cs.size - 1} factor with symbolic coefficients exactly"
        end
      end
    rescue DomainError
      nil
    end

    # A factor of f in x, of any degree, survives setting the parameters to
    # integers where the leading coefficient does not vanish, so an
    # irreducible image of the full degree proves f has no factor to find:
    # a quartic with three parameters sat in Kronecker's substitution for
    # half a minute before the same refusal (third review, section 5).
    def irreducible_image?(coeffs)
      params = coeffs.flat_map(&:variables).uniq
      return false if params.empty?
      random = Random.new(20260923)
      2.times do
        point = params.to_h { |v| [Var.new(v), Num.new(random.rand(2..97))] }
        values = coeffs.map { |c| c.subs(point).simplify }
        next unless values.all? { |v| v.is_a?(Num) && (v.value.is_a?(Integer) || v.value.is_a?(Rational)) }
        next if values.last.value.zero?
        image = Polynomial.new(QQ[:_x], values.each_with_index.reject { |v, _| v.value.zero? }.to_h { |v, k| [[k], v] })
        found = image.factor.factors
        return true if found.size == 1 && found.first.last == 1 && found.first.first.degree == coeffs.size - 1
      end
      false
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    def quadratic(a, b, c)
      disc = (b**2 - 4 * a * c).expand
      return [(-b / (2 * a)).simplify] * 2 if Scalar.zero?(disc)
      root = square_root(disc)
      [((-b - root) / (2 * a)).simplify, ((-b + root) / (2 * a)).simplify]
    end

    # sqrt(d) with perfect squares taken out: sqrt((a - 1)**2) => a - 1 (a sign is
    # immaterial for +- roots), sqrt(4*a) => 2*sqrt(a).
    def square_root(d)
      return RCAS.sqrt(d) if d.variables.empty?
      fact = d.to_poly.factor
      unit = fact.unit.value
      return RCAS.sqrt(d) unless fact.factors.all? { |_, m| m.even? } && unit.positive?
      root = fact.factors.reduce(RCAS.sqrt(Num.new(unit))) { |acc, (g, m)| acc * g.to_expr**(m / 2) }
      root.simplify
    rescue DomainError, NotImplementedError
      RCAS.sqrt(d)
    end

    def exact_roots(coeffs)
      ring = QQ[:_x]
      poly = Polynomial.new(ring, coeffs.each_with_index.to_h { |c, k| [[k], c] })
      poly.factor.factors.flat_map do |g, m|
        roots =
          if g.degree == 1
            [Num.new(Simplify.normalize_number(Rational(-g.coeff(0).value, g.coeff(1).value)))]
          elsif g.degree == 2
            quadratic(g.coeff(2), g.coeff(1), g.coeff(0))
          elsif g.terms.size == 2 && g.coeff(0) != 0
            binomial_roots(g)
          elsif g.degree == 4 && g.terms.keys.all? { |e| e[0].even? }
            biquadratic_roots(g)
          else
            (0...g.degree).map { |i| RootOf.new(g.primitive_part, i) }
          end
        roots * m
      end
    end

    # a x^4 + b x^2 + c = 0: x = +-sqrt(r) for the two roots r of a r^2 + b r + c
    def biquadratic_roots(g)
      quadratic(g.coeff(4), g.coeff(2), g.coeff(0)).flat_map do |r|
        root = RCAS.sqrt(r)
        [Simplify.negate(root).simplify, root]
      end
    end

    # a x^k + b = 0  =>  |b/a|^(1/k) times the k-th roots of +-1
    def binomial_roots(g)
      k = g.degree
      c = Rational(-g.coeff(0).value, g.coeff(k).value)
      radius = Pow.new(Num.new(c.abs), Num.new(Rational(1, k)))
      (0...k).map do |j|
        angle = c.positive? ? Rational(2 * j, k) : Rational(2 * j + 1, k)
        (radius * Fn.new(:exp, [I * PI * angle])).simplify
      end
    end

    # Durand-Kerner iteration for an irreducible numeric polynomial.
    def numeric_roots(g)
      n = g.degree
      lc = g.coeff(n).value.to_f
      a = (0..n).map { |k| g.coeff(k).value.to_f / lc }
      roots = (0...n).map { |k| Complex(0.4, 0.9)**k }
      value = ->(z) { a.each_with_index.reduce(0) { |acc, (c, k)| acc + c * z**k } }
      500.times do
        moved = 0.0
        roots = roots.each_with_index.map do |z, i|
          denom = roots.each_with_index.reduce(1) { |acc, (w, j)| i == j ? acc : acc * (z - w) }
          nz = z - value.call(z) / denom
          moved += (nz - z).abs
          nz
        end
        break if moved < 1e-14
      end
      roots.map do |z|
        z = z.real if z.imaginary.abs < 1e-9
        Num.new(z.is_a?(Complex) ? Complex(z.real.round(12), z.imaginary.round(12)) : z.round(12))
      end.sort_by { |r| r.value.is_a?(Complex) ? [r.value.real, r.value.imaginary] : [r.value, 0] }
    end

    # ---- transcendental equations -------------------------------------------------

    def transcendental(f, x, depth, all: false)
      atoms = f.each_node.select { |n| depends?(n, x) && transcendental_atom?(n) }.uniq
      atoms = atoms.sort_by { |n| -n.each_node.count }
      t = Var.new(:"_s#{depth}")

      atoms.each do |u|
        g = replace_atom(f, u, x, t)
        next if g.nil? || depends?(g, x)
        inverted = begin
          univariate(g, t, depth + 1).flat_map { |v| invert(u, v, x, depth, all: all) }
        rescue NotImplementedError, ArgumentError
          next # another atom, or one of the rules below, may do better
        end
        return inverted
      end

      # x**(p/q): substitute t = x**(1/q)
      q = root_denominator(f, x)
      if q > 1 && !depends?(g = replace_root(f, x, q, t), x)
        # only when t = x**(1/q) replaces every x: sqrt(x)*log(x) keeps an
        # x inside the log, and "solving for t" there treated it as a
        # constant (and sqrt(x) = sqrt(2 - x) answered 2 - x)
        values = univariate(g, t, depth + 1)
        return values.map { |v| (v**q).simplify }
      end

      product = product_equation(f, x, depth, all: all)
      return product if product

      homogeneous = homogeneous_trig(f, x, depth, all: all)
      return homogeneous if homogeneous

      radicals = radical_equation(f, x, depth)
      return radicals if radicals

      logs = logarithmic_equation(f, x, depth)
      return logs if logs

      raise NotImplementedError, "can't solve #{f} = 0 for #{x}; nsolve(#{f}, #{x}: a..b) finds a root numerically"
    end

    # A product vanishes where one of its factors does, so a product no
    # rule can take whole is still three easy equations when it is written
    # as one: (x + 1)*(x - 2)*sin(x). Every factor has to be solvable, or
    # the answer would be missing roots without saying so; a factor in the
    # denominator is not one of them (`numerator_denominator` has already
    # taken those away, and its zeros are poles rather than roots).
    def product_equation(f, x, depth, all: false)
      _, factors = Simplify.factorize(f)
      pieces = factors.filter_map do |base, exponent|
        next nil if exponent.is_a?(Numeric) && Simplify.negative?(exponent)
        # a positive power vanishes exactly where its base does, and a
        # symbolic exponent is the factor itself: exp(u) is stored as
        # EXP**u, whose base knows nothing about x
        piece = exponent.is_a?(Numeric) && exponent.positive? ? base : Simplify.power_node(base, exponent)
        depends?(piece, x) ? piece : nil
      end
      if pieces.size < 2
        # a product the normal form has already multiplied out:
        # (x - 2)*log(x)/x arrives as -2*log(x) + x*log(x)
        common, rest = Simplify.common_factor(f)
        pieces = [common, rest].compact.select { |piece| depends?(piece, x) }
        return nil if pieces.size < 2
      end
      # A root of one factor is a root of the product only where the rest of
      # the product is defined: log(x)*(x**2 - 4) does not vanish at -2.
      defined_roots(f, x, pieces.flat_map { |piece| univariate(piece, x, depth + 1, all: all) })
    rescue NotImplementedError
      nil # one factor rcas cannot solve: the product is no easier
    end

    # An equation in which every term has the same total degree in sin(u)
    # and cos(u) is a polynomial in tan(u): divide through by cos(u)**n.
    # sin(x) + cos(x) = 0 is tan(x) = -1, which rcas solves, and there was
    # no rule that saw it. Where the division loses the zeros of cos(u) -
    # which it does only when no term is a pure power of sin(u) - they are
    # put back, and a term short of the top degree is raised to it by
    # `homogenize` first.
    def homogeneous_trig(f, x, depth, all: false)
      arguments = f.each_node.filter_map do |node|
        node.args.first if node.is_a?(Fn) && %i[sin cos].include?(node.name) && depends?(node, x)
      end.uniq
      return nil unless arguments.size == 1
      u = arguments.first
      sine = Fn.new(:sin, [u])
      cosine = Fn.new(:cos, [u])
      f = homogenize(f, sine, cosine)
      return nil if f.nil?
      constant, table = Expand.table(f)
      return nil unless constant.zero? && table.size > 1

      t = Var.new(:"_t#{depth}")
      degrees = []
      polynomial = Num.new(0)
      table.each do |factors, coefficient|
        sines = factors[sine] || 0
        cosines = factors[cosine] || 0
        rest = factors.reject { |base, _| base == sine || base == cosine }
        return nil unless [sines, cosines].all? { |e| e.is_a?(Integer) && !e.negative? }
        return nil if rest.keys.any? { |base| depends?(base, x) }
        degrees << sines + cosines
        polynomial += Simplify.rebuild_product(coefficient, rest) * t**sines
      end
      return nil unless degrees.uniq.size == 1 && degrees.first.positive?

      roots = univariate(polynomial.simplify, t, depth + 1)
      answers = roots.flat_map { |value| invert(Fn.new(:tan, [u]), value, x, depth, all: all) }
      # cos(u) = 0 solves it too when there is no pure sin(u)**n term
      answers += univariate(cosine, x, depth + 1, all: all) if Coefficients.coeff(polynomial.simplify, t, degrees.first).nil? ||
                                                               Scalar.zero?(Coefficients.coeff(polynomial.simplify, t, degrees.first))
      answers
    rescue NotImplementedError
      nil
    end

    # sin(x)*cos(x) = 1/2 is not homogeneous as written and becomes so when
    # the 1/2 is read as (sin(x)**2 + cos(x)**2)/2 - the classical trick,
    # and the reason the identity is taught before the equation is set. A
    # term short of the top degree by an even number is raised to it that
    # way; an odd gap (sin(x) = 1/2) has no such reading and the rule
    # declines, which leaves the equation to the atom substitution that
    # already answers it.
    def homogenize(f, sine, cosine)
      constant, table = Expand.table(f)
      entries = table.map do |factors, coefficient|
        powers = [factors[sine] || 0, factors[cosine] || 0]
        return nil unless powers.all? { |e| e.is_a?(Integer) && !e.negative? }
        [powers.sum, Simplify.rebuild_product(coefficient, factors)]
      end
      entries << [0, Expression.lift(constant)] unless constant.zero?
      return nil if entries.empty?
      top = entries.map(&:first).max
      return f if entries.all? { |degree, _| degree == top }
      return nil unless top.positive? && entries.all? { |degree, _| ((top - degree) % 2).zero? }
      pythagoras = Simplify.power_node(sine, 2) + Simplify.power_node(cosine, 2)
      raised = entries.map { |degree, term| term * pythagoras**((top - degree) / 2) }
      Expand.expand(raised.inject(:+)).simplify
    end

    # sqrt(u) = v: the radical on one side, both sides to the q-th power,
    # and the answers kept only where the original equation is defined.
    # Raising to a power invents roots, and `verify` drops those.
    #
    # Two radicals go one to each side, sqrt(x) = sqrt(2 - x), and the
    # squared equation has one radical fewer; what is left is squared again
    # one level down.
    # The answer of an equation that is a whole set rather than points.
    class Whole < StandardError
      attr_reader :set

      def initialize(set)
        @set = set
        super("the solutions form the set #{set}")
      end
    end

    def radical_equation(f, x, depth)
      constant, terms = Simplify.termize(f)
      with, without = terms.partition { |factors, _| root_index(factors, x) }
      return nil unless [1, 2].include?(with.size)
      q = with.map { |factors, _| root_index(factors, x) }.max
      return nil if q.nil? || q > 3
      side = Simplify.rebuild_sum(0, with.first(1).to_h)
      others = with.drop(1) + without
      rest = Simplify.rebuild_sum(-constant, others.to_h.transform_values { |c| -c })
      g = (Expand.expand(Simplify.power_node(side, q)) - Expand.expand(Simplify.power_node(rest, q))).simplify
      if Scalar.zero?(g)
        # sqrt(x**2) = -x squares to x**2 = x**2, which says nothing: an even
        # root is the non-negative one, so the equation holds exactly where
        # the other side is not negative - that set, or a refusal below the
        # top (an "every value" verdict about the square was wrong: S18)
        raise NotImplementedError, "squaring #{f} = 0 gives an identity" unless q.even? && depth.zero? && with.size == 1 && side_is_root?(side, x)
        raise Whole, Inequalities.solve(Inequality.new(rest, :>=, 0), x)
      end
      if root_denominator(g, x) > 1 || g.each_node.any? { |n| root_index_of(n, x) }
        # still a radical: fine if there are fewer radical terms than before
        remaining = Simplify.termize(g).last.count { |factors, _| root_index(factors, x) }
        return nil unless remaining < with.size
      end
      defined_roots(f, x, verify(f, x, univariate(g, x, depth + 1)))
    rescue NotImplementedError
      nil
    end

    # log(u) + log(v) = c: one logarithm instead of two, which the atom
    # substitution can then invert.
    def logarithmic_equation(f, x, depth)
      logs = f.each_node.count { |n| n.is_a?(Fn) && n.name == :log && depends?(n, x) }
      return nil unless logs > 1
      combined = Trigonometry.logcombine(f).simplify
      return nil if combined == f
      defined_roots(f, x, univariate(combined, x, depth + 1))
    rescue NotImplementedError
      nil
    end

    # A single radical with coefficient 1: sqrt(u) itself, so that
    # sqrt(u) = rest holds exactly where rest >= 0 once the squares agree.
    def side_is_root?(side, x)
      coeff, factors = Simplify.factorize(side)
      coeff == 1 && factors.size == 1 && root_index_of(Simplify.power_node(*factors.first), x)
    end

    # The denominator of a fractional exponent on a base that involves x.
    def root_index(factors, x)
      factors.filter_map { |base, exp| root_index_of(Simplify.power_node(base, exp), x) }.max
    end

    def root_index_of(node, x)
      return nil unless node.is_a?(Pow) && node.exponent.is_a?(Num)
      value = node.exponent.value
      return nil unless value.is_a?(Rational) && value.denominator > 1 && depends?(node.base, x)
      value.denominator
    end

    # A root of the squared equation is a root of this one only where this
    # one is defined: a logarithm needs a positive argument and an even root
    # a non-negative one. That is the check a student is told to make.
    def defined_roots(f, x, roots)
      conditions = Analysis.domain_conditions(f, x)
      return roots if conditions.empty?
      roots.select do |root|
        # The sign of the condition at the root is decided, not measured
        # against 1e-9: the root 10**-12 of log(x)*(x - 10**-12) is inside
        # the domain of log, and a tolerance said it was on the edge.
        # Undecided keeps the root.
        next true unless root.is_a?(Expression) && root.variables.empty?
        conditions.all? do |condition|
          sign = begin
            Decide.sign(Expression.lift(condition.lhs - condition.rhs).subs(x => root))
          rescue StandardError => rescued
            RCAS.guard!(rescued)
            nil
          end
          next true if sign.nil?
          case condition.op
          when :> then sign == :positive
          when :>= then sign != :negative
          when :< then sign == :negative
          when :<= then sign != :positive
          when :!= then sign != :zero
          else true
          end
        end
      end
    end

    def transcendental_atom?(n)
      (n.is_a?(Fn)) || (n.is_a?(Pow) && !n.base.is_a?(Var) && !(n.exponent.is_a?(Num) && n.exponent.integer?)) ||
        (n.is_a?(Pow) && !n.exponent.is_a?(Num))
    end

    # Replace the atom u by t. exp(k*v) becomes t**k for every rational k.
    def replace_atom(f, u, x, t)
      if u.is_a?(Fn) && u.name == :exp
        v = u.args.first
        constant, table = Expand.table(f)
        rebuilt = {}
        table.each do |factors, coeff|
          new_factors = {}
          factors.each do |base, exp|
            if base == Simplify.exp_base && exp.is_a?(Expression) && depends?(exp, x)
              ratio = (exp / v).simplify
              return nil unless ratio.is_a?(Num)
              new_factors[t] = (new_factors[t] || 0) + ratio.value
            else
              new_factors[base] = exp
            end
          end
          rebuilt[new_factors] = (rebuilt[new_factors] || 0) + coeff
        end
        Simplify.rebuild_sum(constant, rebuilt)
      else
        f.subs(u => t)
      end
    end

    def root_denominator(f, x)
      _, table = Expand.table(f)
      table.each_key.flat_map { |factors| factors.select { |b, e| b == x && e.is_a?(Rational) }.map { |_, e| e.denominator } }.reduce(1, :lcm)
    end

    def replace_root(f, x, q, t)
      constant, table = Expand.table(f)
      rebuilt = {}
      table.each do |factors, coeff|
        new_factors = factors.to_h do |base, exp|
          base == x ? [t, Simplify.normalize_number(Rational(exp) * q)] : [base, exp]
        end
        rebuilt[new_factors] = (rebuilt[new_factors] || 0) + coeff
      end
      Simplify.rebuild_sum(constant, rebuilt)
    end

    # A target the function never takes is not an equation with complex
    # solutions, it is an equation with none. rcas can name one such gap:
    # tan(z) = (exp(2*i*z) - 1)/(i*(exp(2*i*z) + 1)) is i only where
    # exp(2*i*z) + 1 vanishes in the denominator, so the tangent omits
    # exactly +i and -i from the complex plane - which is also why atan(i)
    # does not evaluate. Without this, sin(x)**2 + cos(x)**2 = 0 came back
    # as two families built on atan(-i) and atan(i) (20 Sept 2026, the ninth
    # pass of the review). cos(u) = 2 is not of this kind and keeps its
    # answers: the cosine does reach 2, at i*log(2 + 3**(1/2)).
    def tangent_gap?(v)
      value = Expression.lift(v)
      return false unless value.is_a?(Num)
      number = Complex(value.value)
      number.real.zero? && number.imaginary.abs == 1
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      false
    end

    # Solutions of u = v for x, where u is a single atom containing x. With
    # all: true the period of sin, cos and tan is added, with an integer
    # parameter, so that every solution is covered and not just one period.
    def invert(u, v, x, depth, all: false)
      case u
      when Fn
        arg = u.args.first
        period = all ? period_parameter(arg - v, x) : nil
        turn = ->(multiple) { period ? multiple * PI * period : Num.new(0) }
        targets =
          case u.name
          when :exp  then [Fn.new(:log, [v])]
          when :log  then [Fn.new(:exp, [v])]
          when :sin  then [Fn.new(:asin, [v]) + turn.call(2), PI - Fn.new(:asin, [v]) + turn.call(2)]
          when :cos  then [Fn.new(:acos, [v]) + turn.call(2), -Fn.new(:acos, [v]) + turn.call(2)]
          when :tan  then tangent_gap?(v) ? [] : [Fn.new(:atan, [v]) + turn.call(1)]
          when :atan then [Fn.new(:tan, [v])]
          when :asin then [Fn.new(:sin, [v])]
          when :acos then [Fn.new(:cos, [v])]
          when :sinh then [Fn.new(:log, [v + RCAS.sqrt(v**2 + 1)])]
          when :cosh then [Fn.new(:log, [v + RCAS.sqrt(v**2 - 1)]), -Fn.new(:log, [v + RCAS.sqrt(v**2 - 1)])]
          else cannot_invert!(u, v)
          end
        # all: goes down with the equation: exp(sin(x)) = 1 is sin(x) = 0,
        # and that has a family, not two points
        targets.flat_map { |w| univariate((arg - w).simplify, x, depth + 1, all: all) }
      when Pow
        if depends?(u.base, x) && !depends?(u.exponent, x)
          univariate((u.base - v**(1 / u.exponent)).simplify, x, depth + 1, all: all)
        elsif !depends?(u.base, x)
          roots_of_unity(u, v, x, depth, all: all) ||
            univariate((u.exponent - Fn.new(:log, [v]) / Fn.new(:log, [u.base])).simplify, x, depth + 1, all: all)
        else
          cannot_invert!(u, v)
        end
      else
        cannot_invert!(u, v)
      end
    end

    # No inverse is known for u (x**x, erf, gamma, floor, an unknown
    # function): that is "can't", never "no solution" - x**x = 4 has the
    # root 2.
    def cannot_invert!(u, v)
      raise NotImplementedError, "can't solve #{u} = #{v}: rcas knows no inverse of #{u.is_a?(Fn) ? u.name : u}"
    end

    # Largest order of a root of unity we look for: (-1)**x is the one that
    # turns up, from cos(pi*x) with x an integer.
    MAX_ORDER = 12

    # b**u = v where b is a root of unity: the logarithm is no use, because
    # the solutions repeat. (-1)**x = 1 holds for every even x and
    # (-1)**x = -1 for every odd one, and answering with one of them - which
    # is what log gave - drops all the rest. nil when b is not one, so that
    # 2**x = 4 keeps the ordinary route.
    def roots_of_unity(u, v, x, depth, all: false)
      base = u.base
      return nil unless base.is_a?(Num) && v.is_a?(Num)
      order = (2..MAX_ORDER).find { |n| unity?(Simplify.pow_number(base.value, n), 1) }
      return nil if order.nil?
      turn = all ? period_parameter(u.exponent - v, x) : nil
      (0...order).filter_map do |j|
        next nil unless unity?(Simplify.pow_number(base.value, j), v.value)
        target = Num.new(j)
        target = (target + Num.new(order) * turn).simplify if turn
        univariate((u.exponent - target).simplify, x, depth + 1)
      end.flatten
    end

    def unity?(value, target) = Scalar.zero?(Expression.lift(Simplify.normalize_number(value - target)))

    # Drop the candidates that demonstrably fail the equation: the roots a
    # squaring or a case split invented. The residual f(r) is decided by
    # Decide, so a root is dropped only when the residual is shown to be
    # non-zero - a residual of 4e-5 at exp(x) = 10**10 is rounding, and
    # an unknown x is not always called x (the old check substituted the
    # literal keyword x: and was a no-op for every other name). A root with
    # a parameter in it cannot be checked by a number and stays.
    def verify(f, x, roots)
      roots.select do |r|
        next true unless r.is_a?(Expression)
        next false unless Integrate.defined_value?(r) # log(0) is no number, let alone a root
        next true unless r.variables.empty?
        residual = begin
          f.subs(x => r).simplify
        rescue ZeroDivisionError
          next false
        rescue StandardError => rescued
          RCAS.guard!(rescued)
          next true
        end
        Integrate.defined_value?(residual) && Decide.zero?(residual) != false
      end
    end

    # ---- systems ---------------------------------------------------------------------

    def system(targets, vars, domain: nil)
      fs = targets.map { |t| to_zero(t).simplify }
      unknowns = Array(vars).map { |v| Expression.lift(v) }
      raise ArgumentError, "solve: list the unknowns, e.g. solve([...], [x, y])" if unknowns.empty?

      solutions =
        if fs.all? { |f| linear_in?(f, unknowns) }
          linear_system(fs, unknowns)
        elsif (found = polynomial_system(fs, unknowns))
          found
        elsif fs.size == 2 && unknowns.size == 2
          polynomial_pair(fs, unknowns)
        else
          raise NotImplementedError, "only linear systems and polynomial systems with rational coefficients are supported"
        end
      restrict_system(solutions, unknowns, domain)
    end

    # A solution of a system survives when every unknown in it does.
    def restrict_system(solutions, unknowns, domain)
      wanted = unknowns.to_h { |x| [x, domain || RCAS.assumption(x.name)] }.compact
      return solutions if wanted.empty?
      solutions.reject do |solution|
        next false unless solution.is_a?(Hash)
        solution.any? { |x, value| wanted[x] && Infer.excluded?(value, wanted[x]) }
      end
    end

    # Polynomial systems over QQ by a lex Gröbner basis [CLO15, ch. 2 §8, ch. 3 §1]:
    # the basis is triangular, so the last unknown has a univariate polynomial;
    # its roots are substituted into the rest. nil when a coefficient is not
    # rational (parameters), so that the resultant route can try.
    def polynomial_system(fs, unknowns)
      ring = QQ[*unknowns.map(&:name)]
      polys = fs.map do |f|
        ring.call(f)
      rescue DomainError
        return nil
      end
      basis = Groebner.basis(polys, :lex)
      return [] if basis.size == 1 && basis.first.constant?
      unless Groebner.zero_dimensional?(basis, :lex)
        raise NotImplementedError, "the system has infinitely many solutions; its Gröbner basis is #{basis.map(&:to_s).join(', ')}"
      end
      triangular(basis.map(&:to_expr), unknowns, {}).map { |sol| unknowns.to_h { |u| [u, sol[u]] } }
    end

    def triangular(basis, unknowns, known)
      return [known] if unknowns.empty?
      x = unknowns.last
      rest = unknowns[0...-1].map(&:name)
      substituted = basis.map { |g| g.subs(known).simplify }.reject { |g| Scalar.zero?(g) }
      univariate = substituted.select { |g| (g.variables & rest).empty? }
      return [] if univariate.any? { |g| g.variables.empty? } # a non-zero constant: no solution on this branch
      raise NotImplementedError, "no univariate polynomial in #{x} after substituting #{known}" if univariate.empty?
      pivot = univariate.min_by { |g| polynomial_coefficients(g, x)&.size || Float::INFINITY }
      coeffs = polynomial_coefficients(pivot, x) or raise NotImplementedError, "#{pivot} is not a polynomial in #{x}"
      roots = dedupe(polynomial_roots(coeffs).map(&:simplify))
      roots = roots.select { |r| univariate.all? { |g| Scalar.zero?(g.subs(x => r).simplify) } }
      roots.flat_map { |r| triangular(basis, unknowns[0...-1], known.merge(x => r)) }
    end

    def linear_in?(f, unknowns)
      names = unknowns.map(&:name)
      _, table = Expand.table(f)
      table.each_key.all? do |factors|
        degree = 0
        factors.each do |base, exp|
          if base.is_a?(Var) && names.include?(base.name)
            return false unless exp.is_a?(Integer) && exp >= 0
            degree += exp
          elsif (base.variables & names).any? || (exp.is_a?(Expression) && (exp.variables & names).any?)
            return false
          end
        end
        degree <= 1
      end
    end

    def linear_system(fs, unknowns)
      n = unknowns.size
      rows = fs.map do |f|
        constant, table = Expand.table(f)
        row = Array.new(n) { Num.new(0) }
        rhs = Num.new(-constant)
        table.each do |factors, coeff|
          c = Num.new(coeff)
          index = nil
          factors.each do |base, exp|
            if base.is_a?(Var) && (i = unknowns.index(base))
              index = i
            else
              c *= Simplify.power_node(base, exp)
            end
          end
          index ? row[index] = Scalar.add(row[index], c.simplify) : rhs = Scalar.sub(rhs, c.simplify)
        end
        row + [rhs]
      end
      reduced, pivots = Elimination.rref(rows)
      return [] if pivots.include?(n)
      solution = {}
      pivots.each_with_index do |p, i|
        value = reduced[i][n]
        (0...n).each do |j|
          next if j == p || Scalar.zero?(reduced[i][j])
          value = Scalar.sub(value, Scalar.mul(reduced[i][j], unknowns[j]))
        end
        solution[unknowns[p]] = value.cancel
      end
      [solution]
    end

    def polynomial_pair(fs, unknowns)
      x, y = unknowns
      ring = QQ[x.name, y.name]
      f, g = fs.map do |e|
        ring.call(e)
      rescue DomainError
        raise NotImplementedError, "polynomial systems need rational coefficients: #{e}"
      end
      res = f.resultant(g, x.name)
      raise NotImplementedError, "the equations share a common factor" if res.zero?
      ys = polynomial_roots((0..res.degree(y.name)).map { |k| ring_constant(res.coefficient_in(y.name, k)) })
      dedupe(ys).flat_map do |y0|
        xs = univariate(fs[0].subs(y => y0), x, 1)
        xs.select { |x0| Equation.new(fs[1], 0).holds?(x.name => x0, y.name => y0) }.map { |x0| { x => x0, y => y0 } }
      end
    end

    def ring_constant(poly) = poly.constant_term
  end
end
