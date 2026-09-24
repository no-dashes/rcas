# frozen_string_literal: true

module RCAS
  # Dixon's p-adic solution of one square system A*x = b with Integer and
  # Rational entries [Dix82].
  #
  # The primes of Multimodular pay a whole elimination per prime. Dixon
  # pays for one: C = A**-1 modulo a single prime p, and then computes the
  # solution one p-adic digit at a time, as long division does in base 10:
  #
  #   x_i = C*r mod p,   r <- (r - A*x_i)/p      (r starts as b)
  #
  # Each step is two products of a matrix and a vector, and the division
  # by p is exact because A*x_i = r modulo p. After k steps
  # x_0 + x_1*p + ... + x_(k-1)*p**(k-1) is the solution modulo p**k, and
  # rational reconstruction reads it back as fractions over one common
  # denominator [vzGG13, §5.10]. So an elimination is paid once, and every
  # further digit costs n**2 instead of n**3.
  #
  # The reconstruction is tried after 4, 8, 16, ... steps and believed only
  # when A*x = b holds exactly, which is a proof: A is invertible (it is
  # modulo p), so the solution is unique. Hadamard's bound says when the
  # reconstruction must succeed - numerators and denominator are then below
  # the square root of p**k/2 - so the loop ends.
  module Dixon
    module_function

    # The solution as Integers and Rationals, or nil when A is singular.
    def solve(rows, b)
      a, scales = Multimodular.integral(Multimodular.values(rows))
      column = b.map { |e| e.is_a?(Num) ? e.value : e }.each_with_index.map { |v, i| v * scales[i] }
      common = column.map(&:denominator).reduce(1, :lcm)
      d, x = lift(a, column.map { |v| (v * common).to_i })
      return nil if d.zero?
      x.map { |v| Rational(v, d * common) }.map { |v| v.denominator == 1 ? v.numerator : v }
    end

    # [d, N] with A*N = d*b for an Integer matrix A and an Integer vector b,
    # or [0, nil] when A is singular.
    def lift(a, b)
      n = a.size
      found = inverse_modulo_a_prime(a) or return [0, nil]
      p, c = found
      certain = 2 * [Multimodular.cramer_bound(a, b.map { |v| [v] }), Multimodular.hadamard(a)].max**2
      r = b.dup
      x = Array.new(n, 0)
      power = 1
      attempt = 4
      (1..).each do |step|
        digit = c.map do |row|
          s = 0
          j = 0
          while j < n
            s += row[j] * r[j]
            j += 1
          end
          s % p
        end
        x = x.each_with_index.map { |v, i| v + power * digit[i] }
        power *= p
        r = a.each_with_index.map do |row, i|
          s = r[i]
          j = 0
          while j < n
            s -= row[j] * digit[j]
            j += 1
          end
          s / p
        end
        next unless step == attempt || power > certain
        attempt *= 2
        found = Multimodular.verified(a, b.map { |v| [v] }, x.map { |v| [v] }, power)
        return [found.first, found.last.map(&:first)] if found
        raise "Dixon: no solution past the bound, which cannot happen" if power > certain
      end
    end

    # [p, A**-1 mod p] for the first prime that does not divide det A, or
    # nil when the primes tried multiply past twice Hadamard's bound: then
    # det A is 0 modulo all of them, and so is 0.
    def inverse_modulo_a_prime(a)
      n = a.size
      identity = Array.new(n) { |i| Array.new(n) { |j| i == j ? 1 : 0 } }
      bound = 2 * Multimodular.hadamard(a)
      modulus = 1
      (0..).each do |i|
        return nil if modulus > bound
        p = Multimodular.prime(i)
        d, inverse = Multimodular.eliminate(a, identity, p)
        return [p, inverse] unless d.zero?
        modulus *= p
      end
    end
  end
end
