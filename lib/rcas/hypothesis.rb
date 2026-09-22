# frozen_string_literal: true

module RCAS
  # Hypothesis tests and confidence intervals.
  #
  #   ttest([5.1, 4.9, 5.6, 5.2, 5.0], mu: 5)      # one-sample t test
  #   ttest(xs, ys)                                 # Welch's two-sample t test
  #   ttest(xs, ys, paired: true)
  #   ztest(data, sigma: 2, mu: 100)
  #   chisquare_test([18, 22, 20, 25, 15])          # goodness of fit
  #   chisquare_test([[30, 20], [15, 35]])          # independence
  #   ftest(xs, ys)                                 # ratio of variances
  #   binomial_test(9, 10)                          # exact, p stays a rational
  #   confidence_interval(data)                     # t interval for the mean
  #   confidence_interval(data, parameter: :variance)
  #   proportion_interval(41, 100)
  #
  # A test returns a TestResult: statistic, degrees of freedom, p value,
  # `reject?(alpha)`. The p values come from the t, chi-square, F and normal
  # CDFs and are Floats, labelled as numeric; the binomial test is exact.
  # `alternative:` is :two_sided (the default), :less or :greater.
  #
  # Sources (keys: MANUAL.md, Sources): [Ros14, ch. 8-9]; Welch's degrees of
  # freedom [Wel47]; the exact binomial p value is the sum of the outcomes no
  # more probable than the observed one [Ros14, §9.7]; Wilson's score interval
  # for a proportion [Wil27].
  module Hypothesis
    ALTERNATIVES = %i[two_sided less greater].freeze

    # The outcome of a test: printable, and usable as a value.
    class TestResult
      attr_reader :name, :statistic_name, :statistic, :pvalue, :distribution, :alternative, :estimate, :parameters

      def initialize(name:, statistic:, pvalue:, distribution:, alternative:, statistic_name: "statistic", estimate: nil, parameters: {})
        @name = name
        @statistic_name = statistic_name
        @statistic = Expression.lift(statistic)
        @pvalue = Expression.lift(pvalue)
        @distribution = distribution
        @alternative = alternative
        @estimate = estimate
        @parameters = parameters
        freeze
      end

      # Is the null hypothesis rejected at this level?
      def reject?(alpha = 0.05)
        p = pvalue.evalf
        raise ArgumentError, "reject?: the p value #{pvalue} is not numeric" unless p.is_a?(Numeric) && !p.is_a?(Complex)
        p <= alpha
      end

      # Exact values print exactly, unless the fraction is unwieldy (the exact
      # binomial p value for n = 100, say); the value itself stays exact.
      def self.number(value)
        v = Expression.lift(value)
        if v.is_a?(Num) && (v.value.is_a?(Integer) || (v.value.is_a?(Rational) && v.value.denominator <= 10**6))
          return v.to_s
        end
        f = v.evalf
        f.is_a?(Numeric) ? format("%.6g", f) : v.to_s
      end

      def parameter_text = parameters.map { |k, v| "#{k} = #{self.class.number(v)}" }

      def to_s
        parts = ["#{statistic_name} = #{self.class.number(statistic)}"] + parameter_text
        parts << "p = #{self.class.number(pvalue)}"
        "#{name}: #{parts.join(', ')} (#{alternative.to_s.tr('_', '-')})"
      end

      def inspect = to_s

      def to_latex(wrap: nil)
        parts = ["#{LaTeX.escape(statistic_name)} = #{self.class.number(statistic)}"] +
                parameters.map { |k, v| "#{LaTeX.escape(k.to_s)} = #{self.class.number(v)}" } +
                ["p = #{self.class.number(pvalue)}"]
        "\\text{#{LaTeX.escape(name)}}: #{parts.join(',\; ')}"
      end
    end

    module_function

    def check_alternative(alternative)
      raise ArgumentError, "alternative: use #{ALTERNATIVES.join(', ')}" unless ALTERNATIVES.include?(alternative)
      alternative
    end

    def float(value, name)
      v = Expression.lift(value).evalf
      raise ArgumentError, "#{name}: a real number is needed, got #{value}" unless v.is_a?(Numeric) && !v.is_a?(Complex)
      v.to_f
    end

    # P(|T| >= |t|), P(T <= t) or P(T >= t) for a symmetric or one-sided statistic.
    # The upper tail is the distribution's survival function, not 1 - cdf:
    # z = 10 has p = 1.5e-23, and 1 - cdf said 0 (third review, P-11).
    def tail(distribution, statistic, alternative, symmetric: true)
      t = float(statistic, "p value")
      case alternative
      when :less then float(distribution.cdf(t), "p value")
      when :greater then float(distribution.survival(t), "p value")
      else
        if symmetric
          [2.0 * float(distribution.survival(t.abs), "p value"), 1.0].min
        else
          lower = float(distribution.cdf(t), "p value")
          upper = float(distribution.survival(t), "p value")
          [2.0 * [lower, upper].min, 1.0].min
        end
      end
    end

    # ---- t tests ---------------------------------------------------------------------

    def ttest(data, other = nil, mu: 0, alternative: :two_sided, paired: false, equal_variance: false)
      check_alternative(alternative)
      return one_sample_t(data, mu, alternative) if other.nil?
      if paired
        xs = Statistics.data(data, "ttest")
        ys = Statistics.data(other, "ttest")
        raise ArgumentError, "ttest: paired samples must have the same length" unless xs.size == ys.size
        return one_sample_t(xs.zip(ys).map { |x, y| (x - y).simplify }, mu, alternative, name: "paired t test")
      end
      two_sample_t(data, other, mu, alternative, equal_variance)
    end

    def one_sample_t(data, mu, alternative, name: "one-sample t test")
      values = Statistics.data(data, "ttest")
      n = values.size
      raise ArgumentError, "ttest: at least two values are needed" if n < 2
      mean = Statistics.mean(values)
      error = (Statistics.stdev(values) / RCAS.sqrt(Num.new(n))).simplify
      raise ArgumentError, "ttest: the sample has no spread" if Scalar.zero?(error)
      t = ((mean - Expression.lift(mu)) / error).simplify
      df = n - 1
      TestResult.new(name: name, statistic_name: "t", statistic: t, distribution: Distributions::StudentT.new(df),
                     pvalue: Num.new(tail(Distributions::StudentT.new(df), t, alternative)),
                     alternative: alternative, estimate: mean, parameters: { df: df })
    end

    # Welch by default (unequal variances), the pooled test with equal_variance: true.
    def two_sample_t(xs, ys, mu, alternative, equal_variance)
      xs = Statistics.data(xs, "ttest")
      ys = Statistics.data(ys, "ttest")
      raise ArgumentError, "ttest: at least two values per sample are needed" if xs.size < 2 || ys.size < 2
      n = xs.size
      m = ys.size
      vx = float(Statistics.variance(xs), "ttest")
      vy = float(Statistics.variance(ys), "ttest")
      difference = float(Statistics.mean(xs), "ttest") - float(Statistics.mean(ys), "ttest") - float(mu, "ttest")
      if equal_variance
        pooled = ((n - 1) * vx + (m - 1) * vy) / (n + m - 2.0)
        error = Math.sqrt(pooled * (1.0 / n + 1.0 / m))
        df = n + m - 2
        name = "two-sample t test"
      else
        error = Math.sqrt(vx / n + vy / m)
        df = (vx / n + vy / m)**2 / ((vx / n)**2 / (n - 1) + (vy / m)**2 / (m - 1))
        name = "Welch t test"
      end
      raise ArgumentError, "ttest: the samples have no spread" if error.zero?
      t = difference / error
      distribution = Distributions::StudentT.new(df)
      TestResult.new(name: name, statistic_name: "t", statistic: Num.new(t), distribution: distribution,
                     pvalue: Num.new(tail(distribution, t, alternative)), alternative: alternative,
                     estimate: Num.new(difference), parameters: { df: Num.new(df) })
    end

    # ---- z test ----------------------------------------------------------------------

    def ztest(data, sigma:, mu: 0, alternative: :two_sided)
      check_alternative(alternative)
      values = Statistics.data(data, "ztest")
      n = values.size
      mean = Statistics.mean(values)
      z = ((mean - Expression.lift(mu)) / (Expression.lift(sigma) / RCAS.sqrt(Num.new(n)))).simplify
      normal = Distributions::Normal.new(0, 1)
      TestResult.new(name: "z test", statistic_name: "z", statistic: z, distribution: normal,
                     pvalue: Num.new(tail(normal, z, alternative)), alternative: alternative,
                     estimate: mean, parameters: { n: n })
    end

    # ---- chi-square ------------------------------------------------------------------

    # A flat list is a goodness-of-fit test against +expected+ (counts or
    # probabilities, uniform by default); a list of rows is a test of
    # independence. +df:+ lowers the degrees of freedom for estimated parameters.
    def chisquare_test(observed, expected: nil, df: nil, alternative: :greater)
      check_alternative(alternative)
      rows = observed.is_a?(Matrix) ? observed.to_a : observed
      return independence_test(rows) if rows.is_a?(Array) && rows.first.is_a?(Array)
      goodness_of_fit(rows, expected, df, alternative)
    end

    def goodness_of_fit(observed, expected, df, alternative)
      counts = Statistics.data(observed, "chisquare_test")
      total = counts.reduce(:+).simplify
      expected = if expected.nil?
                   Array.new(counts.size) { (total / counts.size).simplify }
                 else
                   e = Statistics.data(expected, "chisquare_test")
                   raise ArgumentError, "chisquare_test: #{e.size} expected values for #{counts.size} observed ones" unless e.size == counts.size
                   sum = e.reduce(:+).simplify
                   # probabilities sum to 1 and counts to the number observed;
                   # anything else is an input error, as R has it (P-16)
                   if Scalar.zero?((sum - 1).simplify) || close?(sum, 1)
                     e.map { |v| (v * total).simplify }
                   elsif Scalar.zero?((sum - total).simplify) || close?(sum, total)
                     e
                   elsif e.all? { |v| float(v, "chisquare_test") <= 1 }
                     raise ArgumentError, "chisquare_test: the expected probabilities sum to #{sum}, not 1"
                   else
                     raise ArgumentError, "chisquare_test: the expected counts sum to #{sum}, not to the #{total} observed"
                   end
                 end
      expected.each { |v| raise ArgumentError, "chisquare_test: expected counts must be positive" if float(v, "chisquare_test") <= 0 }
      statistic = counts.zip(expected).map { |o, e| ((o - e)**2 / e).expand }.reduce(:+).simplify
      degrees = df || counts.size - 1
      distribution = Distributions::ChiSquare.new(degrees)
      TestResult.new(name: "chi-square goodness of fit", statistic_name: "X^2", statistic: statistic,
                     distribution: distribution, pvalue: Num.new(tail(distribution, statistic, alternative, symmetric: false)),
                     alternative: alternative, parameters: { df: degrees })
    end

    def close?(a, b)
      x = float(a, "chisquare_test")
      y = float(b, "chisquare_test")
      (x - y).abs <= 1e-9 * [1.0, y.abs].max
    end

    def independence_test(rows)
      table = rows.map { |row| Statistics.data(row, "chisquare_test") }
      width = table.first.size
      raise ArgumentError, "chisquare_test: the rows must have the same length" unless table.all? { |r| r.size == width }
      raise ArgumentError, "chisquare_test: a table of at least 2 by 2 is needed" if table.size < 2 || width < 2
      total = table.flatten.reduce(:+).simplify
      row_sums = table.map { |r| r.reduce(:+).simplify }
      column_sums = (0...width).map { |j| table.map { |r| r[j] }.reduce(:+).simplify }
      statistic = table.each_with_index.map do |row, i|
        row.each_with_index.map do |observed, j|
          expected = (row_sums[i] * column_sums[j] / total).simplify
          raise ArgumentError, "chisquare_test: a row or column sums to zero" if Scalar.zero?(expected)
          ((observed - expected)**2 / expected).expand
        end.reduce(:+)
      end.reduce(:+).simplify
      degrees = (table.size - 1) * (width - 1)
      distribution = Distributions::ChiSquare.new(degrees)
      TestResult.new(name: "chi-square test of independence", statistic_name: "X^2", statistic: statistic,
                     distribution: distribution, pvalue: Num.new(tail(distribution, statistic, :greater, symmetric: false)),
                     alternative: :greater, parameters: { df: degrees })
    end

    # ---- F test ----------------------------------------------------------------------

    def ftest(xs, ys, alternative: :two_sided)
      check_alternative(alternative)
      xs = Statistics.data(xs, "ftest")
      ys = Statistics.data(ys, "ftest")
      raise ArgumentError, "ftest: at least two values per sample are needed" if xs.size < 2 || ys.size < 2
      vx = Statistics.variance(xs)
      vy = Statistics.variance(ys)
      raise ArgumentError, "ftest: the second sample has no spread" if Scalar.zero?(vy)
      f = (vx / vy).simplify
      distribution = Distributions::FRatio.new(xs.size - 1, ys.size - 1)
      TestResult.new(name: "F test of two variances", statistic_name: "F", statistic: f, distribution: distribution,
                     pvalue: Num.new(tail(distribution, f, alternative, symmetric: false)), alternative: alternative,
                     estimate: f, parameters: { df1: xs.size - 1, df2: ys.size - 1 })
    end

    # ---- exact binomial test ------------------------------------------------------------

    # Two-sided: the sum of the probabilities of all outcomes no more probable
    # than the observed one. Exact, so the p value stays a rational.
    def binomial_test(successes, trials, p: Rational(1, 2), alternative: :two_sided)
      check_alternative(alternative)
      k = successes.is_a?(Num) ? successes.value : successes
      n = trials.is_a?(Num) ? trials.value : trials
      raise ArgumentError, "binomial_test: 0 <= successes <= trials is needed" unless k.is_a?(Integer) && n.is_a?(Integer) && k >= 0 && k <= n
      distribution = Distributions::Binomial.new(n, p)
      probabilities = exact_binomial_pmf(n, p) || (0..n).map { |j| distribution.pdf(j) }
      pvalue =
        case alternative
        when :less then probabilities[0..k].reduce(:+)
        when :greater then probabilities[k..].reduce(:+)
        else
          # "no more probable than the observed one", compared exactly when
          # the probabilities are exact: as Floats, 2**-1100 underflowed and
          # every outcome was as improbable as k = 0 (third review, P-12)
          observed = probabilities[k]
          exact = probabilities.all? { |q| q.is_a?(Rational) || q.is_a?(Integer) }
          if exact
            probabilities.select { |q| q <= observed }.sum
          else
            reference = float(observed, "binomial_test")
            probabilities.select { |q| float(q, "binomial_test") <= reference * (1 + 1e-9) }.reduce(:+)
          end
        end
      TestResult.new(name: "exact binomial test", statistic_name: "k", statistic: Num.new(k), distribution: distribution,
                     pvalue: Expression.lift(pvalue).simplify, alternative: alternative,
                     estimate: Num.new(Simplify.normalize_number(Rational(k, n))), parameters: { n: n })
    end

    # The pmf of Binomial(n, p) for a rational p as Rationals, the
    # binomial coefficients built up one from the next; nil otherwise.
    def exact_binomial_pmf(n, p)
      q = p.is_a?(Num) ? p.value : p
      return nil unless q.is_a?(Rational) || q.is_a?(Integer)
      q = Rational(q)
      coefficient = 1
      (0..n).map do |j|
        coefficient = coefficient * (n - j + 1) / j unless j.zero?
        coefficient * q**j * (1 - q)**(n - j)
      end
    end

    # ---- confidence intervals -------------------------------------------------------------

    # For the mean (Student t, or normal when sigma is known), the variance or
    # the standard deviation of a sample. Returns an Interval.
    def confidence_interval(data, level: 0.95, sigma: nil, parameter: :mean)
      values = Statistics.data(data, "confidence_interval")
      n = values.size
      raise ArgumentError, "confidence_interval: at least two values are needed" if n < 2
      alpha = 1.0 - float(level, "confidence_interval")
      raise ArgumentError, "confidence_interval: level must be in (0, 1)" unless alpha.positive? && alpha < 1
      case parameter
      when :mean
        mean = float(Statistics.mean(values), "confidence_interval")
        if sigma
          error = float(sigma, "confidence_interval") / Math.sqrt(n)
          critical = float(Distributions::Normal.new(0, 1).quantile(1 - alpha / 2), "confidence_interval")
        else
          error = float(Statistics.stdev(values), "confidence_interval") / Math.sqrt(n)
          critical = float(Distributions::StudentT.new(n - 1).quantile(1 - alpha / 2), "confidence_interval")
        end
        Interval.closed(Num.new(mean - critical * error), Num.new(mean + critical * error))
      when :variance, :stdev
        scaled = (n - 1) * float(Statistics.variance(values), "confidence_interval")
        chi = Distributions::ChiSquare.new(n - 1)
        upper = scaled / float(chi.quantile(alpha / 2), "confidence_interval")
        lower = scaled / float(chi.quantile(1 - alpha / 2), "confidence_interval")
        lower, upper = [Math.sqrt(lower), Math.sqrt(upper)] if parameter == :stdev
        Interval.closed(Num.new(lower), Num.new(upper))
      else raise ArgumentError, "confidence_interval: parameter must be :mean, :variance or :stdev"
      end
    end

    # Wilson's score interval for a proportion.
    def proportion_interval(successes, trials, level: 0.95)
      k = float(successes, "proportion_interval")
      n = float(trials, "proportion_interval")
      raise ArgumentError, "proportion_interval: 0 <= successes <= trials is needed" unless k >= 0 && k <= n && n.positive?
      alpha = 1.0 - float(level, "proportion_interval")
      z = float(Distributions::Normal.new(0, 1).quantile(1 - alpha / 2), "proportion_interval")
      phat = k / n
      centre = (phat + z * z / (2 * n)) / (1 + z * z / n)
      spread = z * Math.sqrt(phat * (1 - phat) / n + z * z / (4 * n * n)) / (1 + z * z / n)
      low = k.zero? ? 0.0 : [centre - spread, 0.0].max
      high = k == n ? 1.0 : [centre + spread, 1.0].min
      Interval.closed(Num.new(low), Num.new(high))
    end
  end
end
