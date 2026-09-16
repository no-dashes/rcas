# frozen_string_literal: true

module RCAS
  # The named families of polynomials, in a namespace of their own: they are
  # many, and bare names are precious (`legendre` is already the Legendre
  # symbol of number theory, `bernoulli` the Bernoulli number).
  #
  #   Poly.chebyshev_t(5, x)   # => 5*x - 20*x**3 + 16*x**5
  #   Poly.legendre(4, x)      # => 3/8 - 15*x**2/4 + 35*x**4/8
  #   Poly.cyclotomic(12, x)   # => 1 - x**2 + x**4
  #
  # Each family is computed from its three-term recurrence (Jacobi: from its
  # explicit sum) on lists of exact coefficients and handed back expanded, so
  # the second argument may be any expression - `Poly.legendre(2, cos(t))` is
  # the Legendre polynomial in cos(t), `Poly.hermite(3, 2)` a number. The
  # parameters `alpha:` and `beta:` of the classical families may stay
  # symbolic; they default to the indeterminates of the same name.
  #
  # Sources (keys: MANUAL.md, Sources): [AS64, ch. 22, ch. 23]; [Sze75];
  # [GKP94, ch. 5, ch. 6]; [vzGG13, ch. 14].
  module Poly
    extend self

    # Poly.chebyshev_t(5, x): the Chebyshev polynomial T_n of the first kind, T_n(cos(u)) = cos(n*u)
    def chebyshev_t(n, x = :x)
      build(three_term(degree(n, "chebyshev_t"), [num(1)], [num(0), num(1)]) { [num(2), num(0), num(-1)] }, x)
    end

    # Poly.chebyshev_u(4, x): the Chebyshev polynomial U_n of the second kind, U_n(cos(u)) = sin((n + 1)*u)/sin(u)
    def chebyshev_u(n, x = :x)
      build(three_term(degree(n, "chebyshev_u"), [num(1)], [num(0), num(2)]) { [num(2), num(0), num(-1)] }, x)
    end

    # Poly.legendre(4, x): the Legendre polynomial P_n, orthogonal on [-1, 1] with weight 1
    def legendre(n, x = :x)
      coeffs = three_term(degree(n, "legendre"), [num(1)], [num(0), num(1)]) do |k|
        [num(Rational(2 * k - 1, k)), num(0), num(Rational(1 - k, k))]
      end
      build(coeffs, x)
    end

    # Poly.hermite(3, x): the physicists' Hermite polynomial H_n, weight exp(-x**2)
    def hermite(n, x = :x)
      coeffs = three_term(degree(n, "hermite"), [num(1)], [num(0), num(2)]) { |k| [num(2), num(0), num(2 - 2 * k)] }
      build(coeffs, x)
    end

    # Poly.hermite_prob(3, x): the probabilists' Hermite polynomial He_n, weight exp(-x**2/2)
    def hermite_prob(n, x = :x)
      coeffs = three_term(degree(n, "hermite_prob"), [num(1)], [num(0), num(1)]) { |k| [num(1), num(0), num(1 - k)] }
      build(coeffs, x)
    end

    # Poly.laguerre(3, x) or Poly.laguerre(3, x, alpha: 1): the (generalized) Laguerre polynomial L_n, weight x**alpha*exp(-x)
    def laguerre(n, x = :x, alpha: 0)
      a = Expression.lift(alpha)
      coeffs = three_term(degree(n, "laguerre"), [num(1)], [Scalar.add(num(1), a), num(-1)]) do |k|
        [num(Rational(-1, k)),                                       # -x/k
         scale(Scalar.add(a, num(2 * k - 1)), Rational(1, k)),       # (2k - 1 + alpha)/k
         scale(Scalar.add(a, num(k - 1)), Rational(-1, k))]          # -(k - 1 + alpha)/k
      end
      build(coeffs, x)
    end

    # Poly.gegenbauer(3, x, alpha: 2): the Gegenbauer (ultraspherical) polynomial C_n, weight (1 - x**2)**(alpha - 1/2)
    def gegenbauer(n, x = :x, alpha: :alpha)
      a = Expression.lift(alpha)
      coeffs = three_term(degree(n, "gegenbauer"), [num(1)], [num(0), Scalar.mul(num(2), a)]) do |k|
        [scale(Scalar.add(a, num(k - 1)), Rational(2, k)), num(0),   # 2(k - 1 + alpha)*x/k
         scale(Scalar.add(Scalar.mul(num(2), a), num(k - 2)), Rational(-1, k))] # -(k - 2 + 2*alpha)/k
      end
      build(coeffs, x)
    end

    # Poly.jacobi(2, x, alpha: 1, beta: 2): the Jacobi polynomial P_n, weight (1 - x)**alpha*(1 + x)**beta
    def jacobi(n, x = :x, alpha: :alpha, beta: :beta)
      n = degree(n, "jacobi")
      a = Expression.lift(alpha)
      b = Expression.lift(beta)
      left = [num(Rational(-1, 2)), num(Rational(1, 2))]  # (x - 1)/2
      right = [num(Rational(1, 2)), num(Rational(1, 2))]  # (x + 1)/2
      coeffs = (0..n).reduce([num(0)]) do |sum, s|
        c = Scalar.mul(binomial_polynomial(Scalar.add(a, num(n)), n - s), binomial_polynomial(Scalar.add(b, num(n)), s))
        padd(sum, pscale(pmul(ppow(left, s), ppow(right, n - s)), c))
      end
      build(coeffs, x)
    end

    # Poly.bernoulli(4, x): the Bernoulli polynomial B_n, with B_n(0) the Bernoulli number
    def bernoulli(n, x = :x) = build(bernoulli_coeffs(degree(n, "bernoulli")), x)

    # Poly.euler(3, x): the Euler polynomial E_n, from B_(n+1) by E_n(x) = 2/(n + 1)*(B_(n+1)(x) - 2**(n+1)*B_(n+1)(x/2))
    def euler(n, x = :x)
      n = degree(n, "euler")
      coeffs = bernoulli_coeffs(n + 1).each_with_index.map do |c, k|
        scale(c, Rational(2, n + 1) * (1 - 2**(n + 1 - k)))
      end
      build(coeffs, x)
    end

    # Poly.cyclotomic(12, x): the cyclotomic polynomial Phi_n, the minimal polynomial of a primitive n-th root of unity
    def cyclotomic(n, x = :x)
      n = degree(n, "cyclotomic")
      raise ArgumentError, "cyclotomic: n must be positive" if n.zero?
      build(cyclotomic_coeffs(n).map { |c| num(c) }, x)
    end

    # Poly.swinnerton_dyer(2, x): the minimal polynomial of sqrt(2) + sqrt(3) + ... over the first n primes, of degree 2**n
    def swinnerton_dyer(n, x = :x)
      n = degree(n, "swinnerton_dyer")
      coeffs = primes(n).reduce([0, 1]) { |f, p| conjugate_product(f, p) }
      build(coeffs.map { |c| num(c) }, x)
    end

    # Poly.abel(3, x) or Poly.abel(3, x, a: 2): the Abel polynomial A_n(x; a) = x*(x - a*n)**(n - 1)
    def abel(n, x = :x, a: 1)
      n = degree(n, "abel")
      return build([num(1)], x) if n.zero?
      root = Scalar.mul(Expression.lift(a), num(-n))
      coeffs = ppow([root, num(1)], n - 1)
      build(pshift(coeffs), x)
    end

    # Poly.fibonacci(6, x): the Fibonacci polynomial F_n, F_n(1) the Fibonacci number
    def fibonacci(n, x = :x)
      build(three_term(degree(n, "fibonacci"), [num(0)], [num(1)]) { [num(1), num(0), num(1)] }, x)
    end

    # Poly.lucas(5, x): the Lucas polynomial L_n, L_n(1) the Lucas number
    def lucas(n, x = :x)
      build(three_term(degree(n, "lucas"), [num(2)], [num(0), num(1)]) { [num(1), num(0), num(1)] }, x)
    end

    # Poly.bell(4, x): the Bell (Touchard) polynomial, the Stirling numbers of the second kind as coefficients; bell(n, 1) is the Bell number
    def bell(n, x = :x)
      build(stirling2_row(degree(n, "bell")).map { |c| num(c) }, x)
    end

    # ---- the machinery ------------------------------------------------------
    #
    # Polynomials are lists of coefficients, lowest degree first; every entry
    # is an Expression, so a symbolic parameter is no different from a number.

    private

    def num(value) = Num.new(value)

    # p_k = (a*x + b)*p_(k-1) + c*p_(k-2), from the two given lists.
    def three_term(n, first, second)
      return first if n.zero?
      prev, cur = first, second
      (2..n).each do |k|
        a, b, c = yield(k)
        prev, cur = cur, padd(padd(pscale(pshift(cur), a), pscale(cur, b)), pscale(prev, c))
      end
      cur
    end

    def padd(f, g) = Array.new([f.size, g.size].max) { |i| Scalar.add(f[i] || num(0), g[i] || num(0)) }
    def pscale(f, c) = f.map { |a| Scalar.mul(a, c) }
    def pshift(f, k = 1) = Array.new(k, num(0)) + f
    def scale(a, r) = Scalar.mul(a, num(r))

    def pmul(f, g)
      out = Array.new(f.size + g.size - 1) { num(0) }
      f.each_with_index do |a, i|
        next if a.is_a?(Num) && a.value.zero?
        g.each_with_index { |b, j| out[i + j] = Scalar.add(out[i + j], Scalar.mul(a, b)) }
      end
      out
    end

    def ppow(f, k) = k.zero? ? [num(1)] : (2..k).reduce(f) { |acc, _| pmul(acc, f) }

    # The coefficient list as an expanded expression in x.
    def build(coeffs, x)
      v = Expression.lift(x)
      terms = coeffs.each_with_index.reject { |c, _| c.is_a?(Num) && c.value.zero? }
      return num(0) if terms.empty?
      sum = terms.map { |c, i| i.zero? ? c : c * v**i }.reduce(:+)
      sum.variables.empty? ? sum.simplify : sum.expand
    end

    def degree(n, name)
      n = n.value if n.is_a?(Num)
      raise ArgumentError, "#{name}: the degree must be a non-negative integer, got #{n}" unless n.is_a?(Integer) && !n.negative?
      n
    end

    # binomial(u, k) with an integer k as the polynomial u(u-1)...(u-k+1)/k!,
    # so that a symbolic alpha survives into the coefficients.
    def binomial_polynomial(u, k) = Combinatorics.expand_binomial(u, num(k))

    # B_n(x) = sum(binomial(n, k)*B_(n-k)*x**k), with the Bernoulli numbers of summation.rb.
    def bernoulli_coeffs(n)
      (0..n).map { |k| num(Summation.bernoulli(n - k) * binomial_integer(n, k)) }
    end

    def binomial_integer(n, k) = (0...k).reduce(1) { |acc, i| acc * (n - i) } / (1..k).reduce(1, :*)

    # Stirling numbers of the second kind, S(n, k) for k = 0..n, by the
    # recurrence S(n, k) = k*S(n-1, k) + S(n-1, k-1).
    def stirling2_row(n)
      (1..n).reduce([1]) do |row, _|
        Array.new(row.size + 1) { |k| (k * (row[k] || 0)) + (k.positive? ? row[k - 1] : 0) }
      end
    end

    # ---- cyclotomic and Swinnerton-Dyer, over the integers -------------------

    @cyclotomic = {}

    # x**n - 1 = product(Phi_d(x), d | n), so Phi_n is one exact division away.
    def cyclotomic_coeffs(n)
      @cyclotomic[n] ||= begin
        numerator = Array.new(n + 1, 0)
        numerator[0] = -1
        numerator[n] = 1
        divisors = (1...n).select { |d| (n % d).zero? }
        divisors.reduce(numerator) { |acc, d| divide_exactly(acc, cyclotomic_coeffs(d)) }
      end
    end

    # Division of integer coefficient lists, the divisor monic (it always is here).
    def divide_exactly(f, g)
      f = f.dup
      quotient = Array.new(f.size - g.size + 1, 0)
      (quotient.size - 1).downto(0) do |i|
        c = f[i + g.size - 1]
        quotient[i] = c
        next if c.zero?
        g.each_with_index { |b, j| f[i + j] -= c * b }
      end
      quotient
    end

    def primes(n)
      found = []
      candidate = 2
      while found.size < n
        found << candidate
        candidate = NumberTheory.nextprime(candidate)
      end
      found
    end

    # f(x - sqrt(p))*f(x + sqrt(p)): writing f(x + s) = u(x) + s*v(x) with
    # s**2 = p, the product is u**2 - p*v**2 and the radical is gone.
    def conjugate_product(f, p)
      u = Array.new(f.size, 0)
      v = Array.new(f.size, 0)
      f.each_with_index do |a, m|
        next if a.zero?
        (0..m).each do |j|
          c = a * binomial_integer(m, j)
          if j.even? then u[m - j] += c * p**(j / 2)
          else v[m - j] += c * p**((j - 1) / 2)
          end
        end
      end
      square = multiply_integers(u, u)
      correction = multiply_integers(v, v).map { |c| c * p }
      Array.new(square.size) { |i| square[i] - (correction[i] || 0) }
    end

    def multiply_integers(f, g)
      out = Array.new(f.size + g.size - 1, 0)
      f.each_with_index { |a, i| g.each_with_index { |b, j| out[i + j] += a * b } unless a.zero? }
      out
    end
  end

  Constants.const_set(:Poly, Poly)
end
