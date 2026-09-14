# frozen_string_literal: true

module RCAS
  # Descriptive statistics and least squares on lists of data, exact.
  #
  #   mean([1, 2, 3, 4])                 # => 5/2
  #   variance([2, 4, 4, 4, 5, 5, 7, 9]) # => 32/7   (sample variance, n - 1)
  #   quantile([1, 2, 3, 4], 1/4r)       # => 7/4
  #   mean([a, b, c])                    # => a/3 + b/3 + c/3
  #   linreg([1, 2, 3], [2, 4, 7], x)    # => -2/3 + 5*x/2
  #
  # Conventions follow Maple, Mathematica and MuPAD: variance, standard
  # deviation and covariance divide by n - 1 unless sample: false; skewness
  # and kurtosis are the standardized third and fourth central moments
  # (kurtosis 3 for a normal sample, not the excess); quantiles interpolate
  # linearly between order statistics (definition 7 of [HF96], the default of
  # R and Excel). Data may be symbolic wherever no ordering is needed.
  #
  # Sources (keys: MANUAL.md, Sources): [HF96]; least squares and the moment
  # statistics are textbook [Ros14, ch. 7].
  module Statistics
    module_function

    def data(list, name)
      list = list.to_a if list.is_a?(Range)
      raise ArgumentError, "#{name}: a non-empty list of values is needed, got #{list.inspect}" unless list.is_a?(Array) && !list.empty?
      list.map { |v| Expression.lift(v) }
    end

    # Sorted ascending by numeric value; symbolic data has no order.
    def sorted(list, name)
      values = data(list, name)
      keyed = values.map do |v|
        f = v.evalf
        raise ArgumentError, "#{name}: #{v} is not a real number" unless f.is_a?(Numeric) && !f.is_a?(Complex)
        [f, v]
      end
      keyed.sort_by(&:first).map(&:last)
    end

    def size(list) = Num.new(list.size)

    def mean(list)
      values = data(list, "mean")
      (values.reduce(:+) / size(values)).simplify
    end

    def median(list)
      values = sorted(list, "median")
      n = values.size
      return values[n / 2] if n.odd?
      ((values[n / 2 - 1] + values[n / 2]) / 2).simplify
    end

    # The most frequent value; a list when several tie.
    def mode(list)
      counts = frequencies(list)
      top = counts.values.max
      modes = counts.select { |_, c| c == top }.keys
      modes.size == 1 ? modes.first : modes
    end

    # { value => count }, ordered by value where the data is numeric.
    def frequencies(list)
      values = data(list, "frequencies").map(&:simplify)
      counts = {}
      values.each { |v| counts[v] = (counts[v] || 0) + 1 }
      numeric = counts.keys.all? { |v| (f = v.evalf).is_a?(Numeric) && !f.is_a?(Complex) }
      numeric ? counts.sort_by { |v, _| v.evalf }.to_h : counts
    end

    def variance(list, sample: true)
      values = data(list, "variance")
      raise ArgumentError, "variance: at least two values are needed for a sample variance" if sample && values.size < 2
      m = mean(values)
      squares = values.map { |v| ((v - m)**2).expand }.reduce(:+)
      (squares / Num.new(sample ? values.size - 1 : values.size)).simplify
    end

    def stdev(list, sample: true) = RCAS.sqrt(variance(list, sample: sample)).simplify

    # k-th central (or raw) moment, divided by n.
    def moment(list, k, central: true)
      values = data(list, "moment")
      shift = central ? mean(values) : Num.new(0)
      (values.map { |v| ((v - shift)**k).expand }.reduce(:+) / size(values)).simplify
    end

    def skewness(list)
      m2 = moment(list, 2)
      (moment(list, 3) / m2**Rational(3, 2)).simplify
    end

    def kurtosis(list)
      m2 = moment(list, 2)
      (moment(list, 4) / m2**2).simplify
    end

    # Definition 7 of [HF96]: h = (n - 1) p, linear interpolation between the
    # order statistics x[floor h] and x[floor h + 1].
    def quantile(list, p)
      values = sorted(list, "quantile")
      p = Expression.lift(p)
      raise ArgumentError, "quantile: p must be a number in [0, 1], got #{p}" unless p.is_a?(Num) && p.value.real? && p.value.between?(0, 1)
      h = (values.size - 1) * p.value
      i = h.floor
      return values[i] if i == h || i + 1 >= values.size
      (values[i] + (values[i + 1] - values[i]) * Num.new(Simplify.normalize_number(h - i))).simplify
    end

    def quartiles(list) = [quantile(list, Rational(1, 4)), median(list), quantile(list, Rational(3, 4))]
    def iqr(list) = (quantile(list, Rational(3, 4)) - quantile(list, Rational(1, 4))).simplify

    def geometric_mean(list)
      values = data(list, "geometric_mean")
      (values.reduce(:*)**Rational(1, values.size)).simplify
    end

    def harmonic_mean(list)
      values = data(list, "harmonic_mean")
      (size(values) / values.map { |v| 1 / v }.reduce(:+)).simplify
    end

    # ---- two variables ----------------------------------------------------------

    def pairs(xs, ys, name)
      xs = data(xs, name)
      ys = data(ys, name)
      raise ArgumentError, "#{name}: the lists must have the same length (#{xs.size} and #{ys.size})" unless xs.size == ys.size
      raise ArgumentError, "#{name}: at least two pairs are needed" if xs.size < 2
      [xs, ys]
    end

    def covariance(xs, ys, sample: true)
      xs, ys = pairs(xs, ys, "covariance")
      mx = mean(xs)
      my = mean(ys)
      total = xs.zip(ys).map { |x, y| ((x - mx) * (y - my)).expand }.reduce(:+)
      (total / Num.new(sample ? xs.size - 1 : xs.size)).simplify
    end

    def correlation(xs, ys)
      xs, ys = pairs(xs, ys, "correlation")
      (covariance(xs, ys) / (stdev(xs) * stdev(ys))).simplify
    end

    # Least squares line as an expression in var: a + b*var.
    def linreg(xs, ys, var = :x)
      xs, ys = pairs(xs, ys, "linreg")
      x = Expression.lift(var)
      raise ArgumentError, "linreg: the third argument names the indeterminate, got #{x}" unless x.is_a?(Var)
      vx = variance(xs)
      raise ArgumentError, "linreg: all x values are equal" if Scalar.zero?(vx)
      b = (covariance(xs, ys) / vx).simplify
      a = (mean(ys) - b * mean(xs)).simplify
      (a + b * x).simplify
    end
  end
end
