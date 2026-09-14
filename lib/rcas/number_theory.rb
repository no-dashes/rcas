# frozen_string_literal: true

require "prime"

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

    SMALL_PRIMES = Prime.first(168).freeze # primes below 1000

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

    # [[prime, multiplicity], ...] in ascending order; [] for 1.
    def prime_division(n)
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
