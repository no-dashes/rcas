# frozen_string_literal: true


module RCAS
  # Integer arithmetic beyond what Ruby ships with: prime factorization,
  # primality, divisors, Euler's totient, modular inverses and the Chinese
  # remainder theorem.
  #
  #   factor(360)          # => 2**3*3**2*5
  #   isprime(2**61 - 1)   # => true
  #   divisors(12)         # => [1, 2, 3, 4, 6, 12]
  #   chrem([2, 3], [3, 5]) # => 8
  #
  # Ruby's Integer already provides gcd, lcm, pow(e, m), Integer.sqrt and
  # bit_length, and Integer#prime? for numbers below about 3e24. Above that
  # its prime? falls back to trial division, so primality here is a
  # Miller-Rabin test (deterministic below 3.3e24, probabilistic with 24
  # bases beyond) and factoring uses trial division by small primes
  # followed by Pollard-Brent rho.
  #
  # Sources (keys refer to MANUAL.md, section Sources): Miller-Rabin
  # [Mil76], [Rab80b], [Knu98, §4.5.4, Algorithm P]; the 13-base bound
  # 3.3e24 [SW17]; Pollard rho [Pol75] with Brent's cycle finding [Bre80],
  # [Knu98, §4.5.4, Algorithm B]; Chinese remainder theorem and modular
  # inverse [Coh93, §1.3], [Knu98, §4.3.2, §4.5.2]; totient [HW08, §5.5].
  module NumberTheory
    module_function

    # The primes below 1000, by sieve: enough to divide out the small
    # factors before Miller-Rabin and rho take over. (`require "prime"` is
    # trial division all the way up and cost 27 ms of the load.)
    SMALL_PRIMES = begin
      sieve = Array.new(1000, true)
      sieve[0] = sieve[1] = false
      (2..31).each { |i| (i * i).step(999, i) { |j| sieve[j] = false } if sieve[i] }
      sieve.each_index.select { |i| sieve[i] }.freeze
    end

    # Above this many bits a composite cofactor is left alone when the
    # caller did not ask for a factorization in the first place.
    EASY_BITS = 64

    # Bases that make Miller-Rabin deterministic below 3 317 044 064 679 887 385 961 981.
    DETERMINISTIC_BASES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41].freeze
    DETERMINISTIC_LIMIT = 3_317_044_064_679_887_385_961_981

    # ---- factorization ----------------------------------------------------

    # Prime factorization of an integer or rational as an IntegerFactorization.
    def factor(n)
      n = integer_or_rational(n, "factor")
      raise ArgumentError, "factor: 0 has no prime factorization" if n.zero?
      unit = n.negative? ? -1 : 1
      if n.is_a?(Rational)
        num = prime_division(n.numerator.abs)
        den = prime_division(n.denominator).map { |p, e| [p, -e] }
        IntegerFactorization.new(unit, (num + den).sort)
      else
        IntegerFactorization.new(unit, prime_division(n.abs))
      end
    end

    # The primes in ascending order, without end: what `Prime.each` was.
    def each_prime
      SMALL_PRIMES.each { |p| yield p }
      p = SMALL_PRIMES.last
      loop { yield(p = nextprime(p)) }
    end

    # [[prime, multiplicity], ...] in ascending order; [] for 1.
    # With hard: false a large composite cofactor is not pursued and the
    # answer is nil instead: that is for callers that are only tidying a
    # number they were handed - sqrt(n), log(n) - and must not disappear
    # into a factorization nobody asked for.
    def prime_division(n, hard: true)
      raise ArgumentError, "prime_division: expected a positive integer, got #{n.inspect}" unless n.is_a?(Integer) && n.positive?
      counts = Hash.new(0)
      SMALL_PRIMES.each do |p|
        break if p * p > n
        while (n % p).zero?
          counts[p] += 1
          n /= p
        end
      end
      if n > 1
        if n < SMALL_PRIMES.last**2 || prime?(n)
          counts[n] += 1
        else
          return nil if !hard && n.bit_length > EASY_BITS
          split_composite(n, counts)
        end
      end
      counts.sort
    end

    def split_composite(n, counts)
      stack = [n]
      until stack.empty?
        m = stack.pop
        if prime?(m)
          counts[m] += 1
        elsif (r = Integer.sqrt(m)) && r * r == m
          stack.push(r, r)
        else
          d = rho(m)
          stack.push(d, m / d)
        end
      end
    end

    # Pollard-Brent rho: a nontrivial factor of a composite n.
    def rho(n)
      return 2 if n.even?
      c = 1
      loop do
        y = 2
        m = 128
        g = r = q = 1
        x = ys = y
        while g == 1
          x = y
          r.times { y = (y * y + c) % n }
          k = 0
          while k < r && g == 1
            ys = y
            [m, r - k].min.times do
              y = (y * y + c) % n
              q = q * (x - y).abs % n
            end
            g = q.gcd(n)
            k += m
          end
          r *= 2
        end
        if g == n
          loop do
            ys = (ys * ys + c) % n
            g = (x - ys).abs.gcd(n)
            break if g > 1
          end
        end
        return g if g != n
        c += 1
      end
    end

    # ---- primes -----------------------------------------------------------

    # Miller-Rabin; exact below DETERMINISTIC_LIMIT, a strong probable-prime
    # test with 24 bases above it.
    def prime?(n)
      n = integer_or_rational(n, "isprime")
      return false unless n.is_a?(Integer) && n >= 2
      SMALL_PRIMES.each do |p|
        return n == p if (n % p).zero?
      end
      return true if n < SMALL_PRIMES.last**2
      bases = n < DETERMINISTIC_LIMIT ? DETERMINISTIC_BASES : SMALL_PRIMES.first(24)
      d = n - 1
      s = 0
      while d.even?
        d >>= 1
        s += 1
      end
      bases.all? { |a| strong_probable_prime?(n, a, d, s) }
    end

    def strong_probable_prime?(n, a, d, s)
      x = a.pow(d, n)
      return true if x == 1 || x == n - 1
      (s - 1).times do
        x = x.pow(2, n)
        return true if x == n - 1
      end
      false
    end

    # The smallest prime greater than n.
    def nextprime(n)
      n = integer_or_rational(n, "nextprime").floor
      return 2 if n < 2
      candidate = n.even? ? n + 1 : n + 2
      candidate += 2 until prime?(candidate)
      candidate
    end

    # The largest prime smaller than n.
    def prevprime(n)
      n = integer_or_rational(n, "prevprime").ceil
      raise ArgumentError, "prevprime: there is no prime below #{n}" if n <= 2
      return 2 if n == 3
      candidate = n.even? ? n - 1 : n - 2
      candidate -= 2 until prime?(candidate)
      candidate
    end

    # ---- divisors and multiplicative functions ----------------------------

    # All positive divisors of n in ascending order.
    def divisors(n)
      n = integer_or_rational(n, "divisors")
      raise ArgumentError, "divisors: expected a nonzero integer, got #{n.inspect}" unless n.is_a?(Integer) && !n.zero?
      prime_division(n.abs).reduce([1]) do |list, (p, e)|
        list.flat_map { |d| (0..e).map { |k| d * p**k } }
      end.sort
    end

    # Euler's totient: the number of integers in 1..n coprime to n.
    def totient(n)
      n = integer_or_rational(n, "totient")
      raise ArgumentError, "totient: expected a positive integer, got #{n.inspect}" unless n.is_a?(Integer) && n.positive?
      prime_division(n).reduce(1) { |acc, (p, e)| acc * p**(e - 1) * (p - 1) }
    end

    # ---- modular arithmetic -----------------------------------------------

    # The inverse of a modulo m, in 0...m.
    def invmod(a, m)
      raise ArgumentError, "invmod: the modulus must be a positive integer" unless m.is_a?(Integer) && m.positive?
      a = a % m
      g, x, = extended_gcd(a, m)
      raise ZeroDivisionError, "#{a} has no inverse modulo #{m} (gcd #{g})" unless g == 1
      x % m
    end

    # [g, s, t] with s*a + t*b = g = gcd(a, b).
    def extended_gcd(a, b)
      s0, s1, t0, t1 = 1, 0, 0, 1
      until b.zero?
        q, r = a.divmod(b)
        a, b = b, r
        s0, s1 = s1, s0 - q * s1
        t0, t1 = t1, t0 - q * t1
      end
      a.negative? ? [-a, -s0, -t0] : [a, s0, t0]
    end

    # Chinese remainder theorem: the smallest x >= 0 with x = r_i (mod m_i)
    # for every i. Moduli need not be coprime; an inconsistent system raises.
    # Solutions of f(x) = 0 mod m, as the residues in 0...m. A linear
    # congruence goes through the extended Euclidean algorithm, anything else
    # is tested residue by residue, which is what a first course does.
    def congruence(f, x, m)
      m = integer_or_rational(m, "congruence").to_i
      raise ArgumentError, "congruence: the modulus must be positive" unless m.positive?
      x = Expression.lift(x)
      coefficients = Solve.polynomial_coefficients(Solve.to_zero(f).simplify, x)
      raise ArgumentError, "congruence: #{f} is not a polynomial in #{x}" if coefficients.nil?
      values = coefficients.map { |c| integer_or_rational(c, "congruence").to_i }
      return linear_congruence(values, m) if values.size == 2
      raise ArgumentError, "congruence: the modulus #{m} is too large to search" if m > 100_000
      (0...m).select { |r| horner(values, r, m).zero? }
    end

    def horner(coefficients, r, m) = coefficients.reverse.reduce(0) { |acc, c| (acc * r + c) % m }

    # a*x + b = 0 mod m has gcd(a, m) solutions when that gcd divides b.
    def linear_congruence(coefficients, m)
      b, a = coefficients
      g = a.gcd(m)
      return [] unless (-b % m % g).zero?
      step = m / g
      first = (invmod(a / g, step) * (-b / g)) % step
      (0...g).map { |i| (first + i * step) % m }
    end

    # The Legendre symbol (a/p): 0, 1 when a is a square modulo the odd prime
    # p, and -1 when it is not (Euler's criterion).
    def legendre(a, p)
      a = integer_or_rational(a, "legendre").to_i
      p = integer_or_rational(p, "legendre").to_i
      raise ArgumentError, "legendre: p must be an odd prime" unless p > 2 && prime?(p)
      value = a.pow((p - 1) / 2, p)
      value > 1 ? value - p : value
    end

    # The Jacobi symbol, the Legendre symbol extended to odd composite n.
    def jacobi(a, n)
      a = integer_or_rational(a, "jacobi").to_i
      n = integer_or_rational(n, "jacobi").to_i
      raise ArgumentError, "jacobi: n must be positive and odd" unless n.positive? && n.odd?
      a %= n
      result = 1
      while a != 0
        while a.even?
          a /= 2
          result = -result if [3, 5].include?(n % 8)
        end
        a, n = n, a
        result = -result if a % 4 == 3 && n % 4 == 3
        a %= n
      end
      n == 1 ? result : 0
    end

    # The multiplicative order of a modulo m: the least k > 0 with a**k = 1.
    def order(a, m)
      a = integer_or_rational(a, "order").to_i
      m = integer_or_rational(m, "order").to_i
      raise ArgumentError, "order: a and m must be coprime" unless a.gcd(m) == 1
      phi = totient(m)
      divisors(phi).find { |d| a.pow(d, m) == 1 }
    end

    # A generator of the multiplicative group modulo m, when one exists.
    def primitive_root(m)
      m = integer_or_rational(m, "primitive_root").to_i
      phi = totient(m)
      candidate = (2...m).find { |a| a.gcd(m) == 1 && order(a, m) == phi }
      raise ArgumentError, "primitive_root: there is none modulo #{m}" if candidate.nil? && m > 1
      m == 1 ? 0 : candidate
    end

    # The continued fraction [a0; a1, a2, ...] of a rational or a real number.
    def continued_fraction(value, terms = 10)
      x = value.is_a?(Expression) ? value.evalf : value
      x = Rational(x) if x.is_a?(Integer)
      out = []
      terms.times do
        whole = x.floor
        out << whole
        rest = x - whole
        break if rest.zero? || (rest.is_a?(Float) && rest.abs < 1e-12)
        x = 1 / rest
      end
      out
    end

    # The fractions [a0], [a0; a1], ... of a continued fraction, the best
    # rational approximations of the number.
    def convergents(value, terms = 10)
      coefficients = value.is_a?(Array) ? value : continued_fraction(value, terms)
      previous = [1, 0]   # numerator, denominator of the fraction before
      current = [coefficients.first, 1]
      out = [Rational(current[0], current[1])]
      coefficients.drop(1).each do |a|
        nxt = [a * current[0] + previous[0], a * current[1] + previous[1]]
        previous = current
        current = nxt
        out << Rational(current[0], current[1])
      end
      out
    end

    def chrem(residues, moduli)
      raise ArgumentError, "chrem: give as many residues as moduli" unless residues.size == moduli.size && !moduli.empty?
      x = 0
      m = 1
      residues.zip(moduli).each do |r, mod|
        raise ArgumentError, "chrem: the moduli must be positive integers" unless mod.is_a?(Integer) && mod.positive?
        g, s, = extended_gcd(m, mod)
        diff = r - x
        raise ArgumentError, "chrem: no solution, #{x} mod #{m} and #{r} mod #{mod} are incompatible" unless (diff % g).zero?
        lcm = m / g * mod
        x = (x + m * ((diff / g) * s % (mod / g))) % lcm
        m = lcm
      end
      x
    end

    def integer_or_rational(n, name)
      n = n.value if n.is_a?(Num)
      return n if n.is_a?(Integer) || n.is_a?(Rational)
      raise ArgumentError, "#{name}: expected an integer, got #{n.inspect}"
    end
  end

  # The result of factoring an integer or rational: a unit (1 or -1) and
  # [prime, exponent] pairs; rationals carry negative exponents.
  class IntegerFactorization
    include Enumerable

    attr_reader :unit, :factors

    def initialize(unit, factors)
      @unit = unit
      @factors = factors.freeze
      freeze
    end

    def each(&block) = factors.each(&block)
    def size = factors.size
    def [](i) = factors[i]
    def prime? = factors.size == 1 && factors.first.last == 1 && unit == 1
    def primes = factors.map(&:first)

    # Multiply back out: the Integer or Rational.
    def expand
      factors.reduce(unit) { |acc, (p, e)| acc * Rational(p)**e }.then { |v| v.is_a?(Rational) && v.denominator == 1 ? v.numerator : v }
    end

    def to_expr
      up = factors.select { |_, e| e.positive? }.map { |p, e| Simplify.power_node(Num.new(p), e) }
      down = factors.select { |_, e| e.negative? }.map { |p, e| Simplify.power_node(Num.new(p), -e) }
      body = up.empty? ? Num.new(1) : Simplify.product_node(up)
      body = Div.new(body, Simplify.product_node(down)) unless down.empty?
      unit == -1 ? Neg.new(body) : body
    end

    def to_s = to_expr.to_s
    alias inspect to_s

    def to_latex(wrap: nil) = LaTeX.of(to_expr, wrap: wrap)

    def ==(other) = other.is_a?(IntegerFactorization) && other.unit == unit && other.factors == factors
  end
end
