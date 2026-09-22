# frozen_string_literal: true

module RCAS
  # A curve discussion: the questions a course asks about a graph, in the
  # order it asks them. Continental schools give the ritual a name - the
  # German "Kurvendiskussion", the French "etude de fonction", the Italian
  # "studio di funzione"; in English it is curve sketching.
  #
  #   discuss(x**3 - 3*x, x)           the answers, one row each
  #   steps(x**3 - 3*x, x, :discuss)   the same questions, worked through
  #
  # Every answer is asked of the function that owns it - real_domain, solve,
  # limit, extrema, inflections, asymptotes - so a discussion cannot
  # disagree with them, and a question rcas cannot answer says so instead of
  # being dropped. The monotonicity and the curvature come from a sign
  # chart: the line is cut at the zeros of f' (of f'') and at the gaps of
  # the domain, and the sign of each piece is read off sample points, which
  # is the table a student draws. Three samples per piece, so a piece whose
  # sign is not constant - a zero the solver missed - is reported as
  # undecided rather than guessed. For a periodic f the chart covers one
  # period and says so.
  #
  # Sources (keys: MANUAL.md, Sources): the questions, the second-derivative
  # test and the sign table are the textbook ones [Spi08, ch. 11].
  module Discussion
    # What a discussion found, one row per question. The expressions stay
    # expressions, so the rows typeset as well as they print.
    class Report
      LABEL = 13

      SYMMETRY = {
        even: "even: f(-%<x>s) = f(%<x>s), symmetric about the vertical axis",
        odd: "odd: f(-%<x>s) = -f(%<x>s), symmetric about the origin",
        none: "none"
      }.freeze

      attr_reader :f, :var, :domain, :symmetry, :period, :zeros, :intercept, :gaps,
                  :limits, :asymptotes, :derivatives, :extrema, :monotonicity,
                  :inflections, :curvature

      def initialize(**parts)
        parts.each { |name, value| instance_variable_set("@#{name}", value) }
        freeze
      end

      # [label, items, separator, suffix]; an item is a list of strings and
      # expressions, so to_s and to_latex render the same rows.
      def rows
        out = []
        out << ["domain", [[domain || "not determined"]]]
        out << ["symmetry", [[symmetry_text]]]
        out << ["period", [[period]]] if period
        out << ["zeros", items(zeros) { |z| [z] }, nil, repeats(zeros)]
        out << ["y intercept", [["f(0) = ", intercept]]] if intercept
        out << ["gaps", gaps.map { |point, kind, _left, _right| [point, " (#{kind})"] }] unless gaps.empty?
        out << ["at infinity", limits.map { |point, value| limit_item(point, value) }, "; "]
        lines = asymptote_items
        out << ["asymptotes", lines.empty? ? [["none"]] : lines]
        out << ["extrema", items(extrema) { |p, v, kind| ["#{kind} at (", p, ", ", v, ")"] }, "; ", repeats(extrema)]
        out << ["monotonic", items(monotonicity) { |i, kind| ["#{kind} on ", i] }, nil, repeats(monotonicity)]
        out << ["inflections", items(inflections) { |p, v| ["(", p, ", ", v, ")"] }, nil, repeats(inflections)]
        out << ["curvature", items(curvature) { |i, kind| ["#{kind} on ", i] }, nil, repeats(curvature)]
        out
      end

      def symmetry_text
        template = SYMMETRY[symmetry]
        template.include?("%") ? format(template, x: var) : template
      end

      # "none" and "not determined" are answers too, and different ones.
      def items(values, &block)
        return [["not determined"]] if values.nil?
        return [["none"]] if values.empty?
        values.map(&block)
      end

      # A periodic function repeats what a row says, one period on.
      def repeats(values)
        period && values && !values.empty? ? ["(+ k*", period, ", k an integer)"] : nil
      end

      def limit_item(point, value)
        return ["f -> ", value, " as #{var} -> ", point] if value
        ["#{period ? 'no limit' : 'not determined'} as #{var} -> ", point]
      end

      def asymptote_items
        vertical = (asymptotes[:vertical] || []).map { |p| ["#{var} = ", p] }
        vertical + ((asymptotes[:horizontal] || []) + (asymptotes[:oblique] || [])).map { |l| ["y = ", l] }
      end

      def self.render(item) = item.map(&:to_s).join

      def self.render_latex(item)
        item.map { |part| part.is_a?(String) ? "\\text{#{LaTeX.escape(part)}}" : LaTeX.of(part) }.join
      end

      def to_s
        body = rows.map do |label, list, separator, suffix|
          values = list.map { |item| Report.render(item) }.join(separator || ", ")
          values += " #{Report.render(suffix)}" if suffix
          "  #{label.ljust(LABEL)}#{values}"
        end
        (["f(#{var}) = #{f}"] + body).join("\n")
      end
      alias inspect to_s

      def to_latex(wrap: nil)
        body = rows.map do |label, list, _separator, suffix|
          values = list.map { |item| Report.render_latex(item) }.join(',\; ')
          values += " #{Report.render_latex(suffix)}" if suffix
          "\\text{#{LaTeX.escape(label)}} &: #{values}"
        end
        "\\begin{aligned} f(#{LaTeX.of(var)}) &= #{LaTeX.of(f)} \\\\ #{body.join(' \\\\ ')} \\end{aligned}"
      end
    end

    module_function

    # The whole discussion of f as a function of one indeterminate.
    def discuss(f, var = nil)
      f = Expression.lift(f)
      x = Analysis.variable(f, var)
      domain = domain_of(f, x)
      inside = domain || RealSet.reals
      cycle = period(f, x)
      # zeros are counted in full unless f is periodic, when one period is
      # the chart and the answer: sin(x)/x has zeros at every k*pi, k != 0,
      # and "pi" alone was a truncation (third review, S14)
      @principal = !cycle.nil?
      first = derivative(f, x)
      second = first && derivative(first, x)
      holes = gaps(f, x)
      cuts = holes.map(&:first)
      Report.new(
        f: f, var: x, domain: domain, symmetry: symmetry(f, x), period: cycle,
        zeros: zeros(f, x, inside), intercept: intercept(f, x, inside),
        gaps: holes, limits: limits_at_infinity(f, x, inside), asymptotes: asymptotes(f, x, inside),
        derivatives: [first, second, second && derivative(second, x)],
        extrema: extrema(f, x, first),
        monotonicity: label(sign_chart(first, x, inside, cuts, cycle), :increasing, :decreasing),
        inflections: inflections(f, x, second),
        curvature: label(sign_chart(second, x, inside, cuts, cycle), :convex, :concave)
      )
    end

    # nil when rcas cannot differentiate (an unknown function, floor): the
    # whole second half of the discussion then says it is undecided rather
    # than raising in the middle of the report.
    def derivative(e, x)
      tidy(e.diff(x))
    rescue ArgumentError, NotImplementedError
      nil
    end

    # "Undecided" is an answer here: nil means the row could not be
    # determined and prints as "not determined". These are the ways the
    # library says so. A bare `rescue StandardError` said it for a typo or a
    # genuine bug too, and the tests still passed.
    UNDECIDED = [ArgumentError, DomainError, ZeroDivisionError, NotImplementedError, SeriesError].freeze

    # A derivative reads better cancelled: the second derivative of
    # (x**2 + 1)/x is 2/x**3, not a quotient of quartics.
    def tidy(e)
      Fraction.cancel(e)
    rescue *UNDECIDED
      e.simplify
    end

    # ---- the single questions --------------------------------------------------

    def domain_of(f, x)
      Analysis.real_domain(f, x)
    rescue NotImplementedError, ArgumentError, DomainError
      nil
    end

    def reflect(f, x) = f.subs(x => Neg.new(x).simplify).simplify

    # f(-x) against f(x) and -f(x).
    def symmetry(f, x)
      reflected = reflect(f, x)
      return :even if same?(reflected, f)
      return :odd if same?(reflected, Neg.new(f).simplify)
      :none
    end

    def same?(a, b)
      difference = a - b
      return true if Scalar.zero?(difference.simplify)
      Scalar.zero?(Fraction.cancel(difference))
    rescue *UNDECIDED
      false
    end

    # The real solutions of f = 0 that lie in the domain.
    def zeros(f, x, domain)
      points = solutions(f, x) or return nil
      Analysis.sort_points(points.select { |p| in_domain?(domain, p) })
    end

    def in_domain?(domain, point)
      value = Analysis.numeric(point)
      value.nil? || domain.include?(value)
    end

    def intercept(f, x, domain)
      return nil unless domain.include?(0)
      value = f.subs(x => Num.new(0)).simplify
      Limits.infinite?(value) ? nil : value
    rescue *UNDECIDED
      nil
    end

    # Where a denominator vanishes, and whether the graph runs away there:
    # [[point, :pole | :removable | :gap, limit from the left, from the right], ...]
    def gaps(f, x)
      points = Analysis.denominators(f, x).flat_map { |d| solutions(d, x) || [] }.uniq
      Analysis.sort_points(points).map do |point|
        probe = point.is_a?(ImageSet) ? point.at(0) : point # a family stands for its members
        left = one_sided(f, x, probe, :left)
        right = one_sided(f, x, probe, :right)
        kind = if left.nil? || right.nil? then :gap
               elsif Limits.infinite?(left) || Limits.infinite?(right) then :pole
               else :removable
               end
        [point, kind, left, right]
      end
    end

    def one_sided(f, x, point, side)
      value = Limits.limit(f, x, point, side)
      value.is_a?(Limit) ? nil : value
    rescue *UNDECIDED
      nil
    end

    # [[-oo, value], [oo, value]]; a limit rcas cannot find is nil, and an
    # end the domain does not reach is not asked about at all.
    def limits_at_infinity(f, x, domain)
      ends(domain).map do |point|
        value = begin
          found = Limits.limit(f, x, point)
          found.is_a?(Limit) ? nil : found.simplify
        rescue *UNDECIDED
          nil
        end
        [point, value]
      end
    end

    # A line the graph approaches. A line that *is* the graph - the oblique
    # asymptote of 2*x + 1 is 2*x + 1 - is not worth saying. A vertical one
    # is a place rather than a line, and may be a whole family of them
    # ({pi/2 + pi*k | k in ZZ} for the tangent), so that question is not
    # asked of it.
    def asymptotes(f, x, domain)
      found = Analysis.asymptotes(f, x, at: ends(domain))
      found.to_h do |kind, lines|
        [kind, kind == :vertical ? lines : lines.reject { |line| same?(line, f) }]
      end
    rescue *UNDECIDED
      { vertical: [], horizontal: [], oblique: [] }
    end

    # The infinite ends the domain reaches: log(x) has no minus infinity to
    # ask about, and an answer there would be an answer about nothing.
    def ends(domain)
      minus, plus = Neg.new(OO).simplify, OO
      reached = []
      reached << minus if domain.intervals.first&.low == minus
      reached << plus if domain.intervals.last&.high == plus
      reached
    end

    # The extrema, but nil rather than [] when the critical points are out of
    # reach: "none" and "I could not tell" are different answers.
    def extrema(f, x, first)
      points = first && solutions(first, x) or return nil
      return nil if points.any? { |p| p.is_a?(ImageSet) } # infinitely many, not charted
      Analysis.extrema(f, x, points: Analysis.sort_points(points))
    rescue *UNDECIDED
      nil
    end

    def inflections(f, x, second)
      points = second && solutions(second, x) or return nil
      return nil if points.any? { |p| p.is_a?(ImageSet) }
      Analysis.inflections(f, x, points: points).map { |point| [point, f.subs(x => point).simplify] }
    rescue *UNDECIDED
      nil # a curvature rcas cannot decide is "not determined", not "none"
    end

    # The real zeros of g, or nil when rcas cannot solve g = 0. One period
    # of them for a periodic f, all of them (families included) otherwise.
    def solutions(g, x)
      g = Expression.lift(g)
      return [] unless g.variables.include?(x.name)
      begin
        found = Solve.solve(g, x, principal: @principal != false)
        return nil unless found.is_a?(Array)
        found.select { |root| root.is_a?(ImageSet) ? !root.nonreal? : real?(root) }
      rescue NotImplementedError, ArgumentError, DomainError
        factor_solutions(g, x)
      end
    end

    # A product vanishes where one of its factors does, so a product solve
    # will not touch can still be solvable factor by factor: the derivative
    # of exp(-x**2) is -2*x*exp(-x**2), and the exponential is never zero.
    # Every root found this way is checked against g before it is believed.
    def factor_solutions(g, x)
      roots = pieces(g, x).flat_map { |piece| Solve.solve(piece, x, principal: true).select { |root| real?(root) } }
      roots.uniq.select { |root| vanishes?(g, x, root) }
    rescue *UNDECIDED
      nil
    end

    MAX_SPLIT = 3

    # The parts of g that can vanish: its factors, and, for a sum whose terms
    # share a factor, that factor and what the sum leaves when it is divided
    # out. The second derivative of exp(-x**2) is a sum, not a product, until
    # the exponential is taken out of it.
    def pieces(g, x, depth = 0)
      _coefficient, factors = Simplify.factorize(g, simplify: true)
      factors.flat_map do |base, exponent|
        next [] if exponent.is_a?(Numeric) && exponent.negative?
        next [] unless base.variables.include?(x.name)
        parts = depth < MAX_SPLIT ? split_common(base) : nil
        parts ? parts.flat_map { |part| pieces(part, x, depth + 1) } : [base]
      end.uniq
    end

    # [what every term of the sum has in common, what is left], or nil.
    def split_common(g)
      Simplify.common_factor(g)
    rescue *UNDECIDED
      nil
    end

    def vanishes?(g, x, root)
      Decide.zero?(g.subs(x => root).simplify) != false
    rescue *UNDECIDED
      true
    end

    # Decided, not measured: 1 + 10**-13*i is not a real zero of
    # (x - 1)**2 + 10**-26, and an |Im| < 1e-12 test said it was (Q1). A
    # point whose realness cannot be told is kept.
    def real?(value)
      Inequalities.real?(value)
    rescue NotImplementedError
      true
    rescue *UNDECIDED
      false
    end

    # ---- the sign chart --------------------------------------------------------

    # The sign of g piece by piece: [[Interval, :positive | :negative], ...],
    # or nil when the zeros, the samples or the signs are out of reach. The
    # line is cut at the zeros of g, at the gaps handed in, and at the ends
    # of the domain; pieces that the domain leaves out are dropped, and two
    # pieces meeting at a point of the domain are merged.
    def sign_chart(g, x, domain, extra = [], cycle = nil)
      return nil if g.nil?
      return [] if constant_zero?(g)
      cuts = chart_cuts(g, x, domain, extra, cycle) or return nil
      pieces = []
      cuts.each_cons(2) do |(low_value, low), (high_value, high)|
        sign = piece_sign(g, x, low_value, high_value, domain)
        next if sign == :outside
        return nil if sign.nil?
        piece = Interval.new(low, high, left_open: true, right_open: true)
        last = pieces.last
        # never across a gap: tan is increasing on (0, pi/2) and on
        # (pi/2, pi), and not on (0, pi) (S13)
        across_gap = extra.any? { |e| (v = Analysis.numeric(e)) && (v - low_value).abs <= 1e-12 * [1.0, v.abs].max }
        if last && last[1] == sign && last[0].high == low && domain.include?(low_value) && !across_gap
          pieces[-1] = [Interval.open(last[0].low, high), sign]
        else
          pieces << [piece, sign]
        end
      end
      pieces.empty? ? nil : pieces
    end

    # [[value, expression], ...] in order, the ends included.
    def chart_cuts(g, x, domain, extra, cycle)
      points = solutions(g, x) or return nil
      return nil if (points + extra).any? { |p| p.is_a?(ImageSet) } # infinitely many pieces
      cuts = (points + extra).map { |p| [Analysis.numeric(p), p] }
      return nil if cuts.any? { |value, _| value.nil? }
      cuts = window(cuts, cycle) or return nil if cycle
      bounds = domain.intervals.flat_map { |i| [[i.low_value, i.low], [i.high_value, i.high]] }
      cuts += bounds.select { |value, _| value.is_a?(Float) && value.finite? } unless cycle
      cuts = cuts.uniq { |value, _| value }.sort_by(&:first)
      return cuts if cycle
      [[-Float::INFINITY, Neg.new(OO).simplify]] + cuts + [[Float::INFINITY, OO]]
    end

    # One period, from 0: every cut moved into [0, p] by whole periods.
    def window(cuts, cycle)
      length = Analysis.numeric(cycle) or return nil
      moved = cuts.map do |value, point|
        shift = (value / length).floor
        shift.zero? ? [value, point] : [value - shift * length, (point - shift * cycle).simplify]
      end
      ([[0.0, Num.new(0)]] + moved + [[length, cycle]]).uniq { |value, _| value.round(9) }
    end

    # g is the zero function: a straight graph has no curvature to report,
    # and a constant one no monotonicity.
    def constant_zero?(g)
      Scalar.zero?(g.simplify) || Scalar.zero?(Fraction.cancel(g))
    rescue *UNDECIDED
      false
    end

    # :positive, :negative, :outside (no sample is in the domain), or nil
    # when the samples disagree or none of them says anything. A sample too
    # close to zero to read - exp(-x**2) far out - is skipped, not believed.
    def piece_sign(g, x, low, high, domain)
      points = sample_points(low, high).select { |s| domain.include?(s) }
      return :outside if points.empty?
      signs = points.filter_map do |sample|
        value = Analysis.numeric(g.subs(x => Num.new(sample)))
        next nil if value.nil? || value.abs < 1e-12
        value.positive? ? :positive : :negative
      end.uniq
      signs.size == 1 ? signs.first : nil
    end

    # Three points a piece, so that a piece hiding a zero is noticed.
    SAMPLES = 3
    OFFSETS = [0.5, 1.5, 4.0].freeze

    def sample_points(low, high)
      return OFFSETS.map { |o| o - 1.0 } if low.infinite? && high.infinite?
      return OFFSETS.map { |o| high - o } if low.infinite?
      return OFFSETS.map { |o| low + o } if high.infinite?
      (1..SAMPLES).map { |i| low + (high - low) * i / (SAMPLES + 1) }
    end

    def label(chart, positive, negative)
      chart&.map { |piece, sign| [piece, sign == :positive ? positive : negative] }
    end

    # ---- periodicity -----------------------------------------------------------

    # 2*pi/|a| for sin(a*x + b), pi/|a| for tan.
    PERIODS = { sin: 2, cos: 2, sec: 2, csc: 2, tan: 1, cot: 1 }.freeze

    # A period of f: the least common multiple of the periods of its
    # trigonometric parts, once a sample of points confirms it (nil
    # otherwise - rcas never guesses one). The smallest period, unless the
    # expression hides a shorter one, as cos(x)**2 = (1 + cos(2*x))/2 does.
    def period(f, x)
      bases = period_bases(f, x) or return nil
      return nil if bases.empty?
      first = Analysis.numeric(bases.first) or return nil
      multiple = Rational(1)
      bases.each do |base|
        value = Analysis.numeric(base) or return nil
        ratio = Rational(value / first).rationalize(Rational(1, 10**6))
        return nil if ratio.denominator > 100
        multiple = Rational(multiple.numerator.lcm(ratio.numerator), multiple.denominator.gcd(ratio.denominator))
      end
      candidate = (bases.first * Num.new(multiple)).simplify
      periodic?(f, x, candidate) ? candidate : nil
    end

    def period_bases(f, x)
      bases = []
      f.each_node do |node|
        next unless node.is_a?(Fn) && PERIODS.key?(node.name)
        argument = node.args.first
        return nil unless argument.variables.include?(x.name)
        slope = linear_slope(argument, x) or return nil
        bases << (Num.new(PERIODS[node.name]) * PI / slope).simplify
      end
      bases.uniq
    end

    # The a of a*x + b, positive, or nil when the argument is not linear.
    def linear_slope(argument, x)
      return nil unless Coefficients.degree(argument, x) == 1
      slope = Coefficients.coeff(argument, x, 1)
      value = Analysis.numeric(slope) or return nil
      value.negative? ? Neg.new(slope).simplify : slope
    rescue DomainError, NotImplementedError, ArgumentError
      nil
    end

    def periodic?(f, x, candidate)
      shifted = f.subs(x => (x + candidate).simplify)
      [0.3, 1.1, 2.4, -0.7].all? do |point|
        here = Analysis.numeric(f.subs(x => Num.new(point)))
        there = Analysis.numeric(shifted.subs(x => Num.new(point)))
        here && there && (here - there).abs < 1e-9 * [1.0, here.abs].max
      end
    end
  end
end
