<p align="center">
  <img src="assets/rcas-logo.jpeg" alt="rcas - Ruby Computer Algebra System" width="360"><br>
</p>

# rcas manual

rcas is a computer algebra system that lives inside Ruby. Symbols are
indeterminates, the ordinary operators build expression trees, and irb is the
REPL. This manual walks through everything that is finished. Every
transcript in it is checked by `test/manual_test.rb`, so the outputs are
exactly what the current code prints.

Start a session with

```
$ bin/rcas
```

or use the library from Ruby with `require "rcas"`. In plain Ruby, write
variables as symbols (`:x`) and call functions on the module (`RCAS.sin`,
`RCAS.solve`), or `include RCAS::Functions`, `RCAS::Sets` and
`RCAS::Constants` to get the bare names used below.

<!-- toc -->
- [Sessions and setup](#sessions-and-setup)
- [1. Mathematics](#1-mathematics)
  - [1.1 Expressions](#11-expressions)
    - [Variables and operators](#variables-and-operators)
    - [simplify, expand, factor](#simplify-expand-factor)
    - [Substitution and evaluation](#substitution-and-evaluation)
    - [Equality](#equality)
  - [1.2 Numbers and constants](#12-numbers-and-constants)
    - [Integers and primes](#integers-and-primes)
  - [1.3 Calculus](#13-calculus)
    - [Derivatives](#derivatives)
    - [Antiderivatives](#antiderivatives)
    - [Definite integrals](#definite-integrals)
    - [Series](#series)
    - [Limits](#limits)
    - [Sums](#sums)
    - [hold and evaluate](#hold-and-evaluate)
    - [Factorials, binomials, gamma](#factorials-binomials-gamma)
    - [Trigonometric and logarithmic rewriting](#trigonometric-and-logarithmic-rewriting)
  - [1.4 Equations and solving](#14-equations-and-solving)
    - [Inequalities](#inequalities)
  - [1.5 Domains and assumptions](#15-domains-and-assumptions)
  - [1.6 Polynomial rings](#16-polynomial-rings)
    - [gcd and division of expressions](#gcd-and-division-of-expressions)
    - [Degree and coefficients](#degree-and-coefficients)
    - [Algebraic numbers](#algebraic-numbers)
    - [Finite fields](#finite-fields)
  - [1.7 Linear algebra](#17-linear-algebra)
  - [1.8 Differential equations](#18-differential-equations)
  - [1.9 Performance notes](#19-performance-notes)
- [2. Reference](#2-reference)
- [3. Files](#3-files)
- [4. License](#4-license)
- [Appendix A. Typeset output](#appendix-a-typeset-output)
  - [Pictures](#pictures)
- [Appendix B. rcas-chat](#appendix-b-rcas-chat)
  - [Input](#input)
  - [Claude](#claude)
  - [Output modes](#output-modes)
  - [Errors](#errors)
  - [Sessions](#sessions)
  - [Commands](#commands)
  - [Options and environment](#options-and-environment)
  - [Files](#files)
<!-- /toc -->

## Sessions and setup

`bin/rcas` starts irb with `RCAS::IRB.setup` applied to the top-level
object:

- A bare identifier that is not yet defined (`x`, `foo_bar`) evaluates to
  the symbol of the same name and is assigned to a local variable, so after
  `e = x + 1` the variable `x` holds `:x`. Only zero-argument, block-less
  lowercase names are intercepted; `foo(1)` still raises `NoMethodError`,
  and `respond_to?` is untouched so Ruby's implicit conversions are
  unaffected.
- The functions of the reference section, the constants `PI E I oo`, the
  number sets `NN ZZ QQ RR CC` and `GF` are in scope, and `hold { ... }`
  can read the source of blocks typed at the prompt.
- Any name Ruby accepts as an identifier works, Unicode included: `α`,
  `β₁`, `φ`, `δt`. A name starting with an uppercase letter (`X`, `Δt`) is
  a constant to Ruby and therefore not available. `π` and `∞` are the
  constants `pi` and `oo`; results still print as `pi` and `oo` so that
  they can be pasted back.
- Names Ruby already uses cannot become indeterminates this way. Of the
  one- and two-letter names only `p`, `pp` and (with the JSON library)
  `j`, `jj` are affected. rcas' own `eq`, `pi` and `oo` are reserved too;
  everything else short is free.

**Caveat: the one thing rcas takes away from irb.** Everything above only
*adds* to irb. The single exception is that Kernel's printers `p`, `pp`,
`j` and `jj` are undefined on the session object so that `p` can be an
indeterminate (a prime, say). `p(expr)` therefore raises `NoMethodError` in
`bin/rcas` and `bin/rcas-chat`; use `puts expr`, `print`, or
`Kernel.p(expr)`. Plain `irb` with `require "rcas"` is unaffected.
- Results print as text. `show(obj)` typesets a value (Appendix A);
  `bin/rcas-chat` (Appendix B) shows pictures inline and answers questions
  in plain language.

Without the launcher, `require "rcas"` and use `:x`, `RCAS::ZZ` or
`include RCAS::Sets`, and `RCAS.sin(:x)` / `RCAS.assume(x: RCAS::ZZ)`.
Blocks passed to `hold` work in files and in irb; code assembled with
`eval` is covered too because loading rcas turns on
`RubyVM.keep_script_lines`.

## 1. Mathematics

### 1.1 Expressions

#### Variables and operators

Inside `bin/rcas` a bare name that is not yet defined becomes an
indeterminate: the session evaluates `x` to the symbol `:x` and remembers
it as a local variable holding that symbol. Arithmetic on symbols builds
expressions and nothing is rewritten until you ask for it.

A word on terms. A Ruby *variable* such as `e` holds a value. A symbol such
as `:x` inside an expression is an *indeterminate*: it stands for nothing
in particular, and `x**2 - 1` is a formal expression, not a computation
waiting for a value. Giving an indeterminate a value is what `subs` and
`call` do; `x.in(ZZ)` restricts what it may stand for without fixing it.
For historical reasons the method that lists the indeterminates of an
expression is called `variables`, as in most computer algebra systems.

```
rcas> x + 1
=> x + 1
rcas> e = (x + 1) * (1 - x)
=> (x + 1)*(1 - x)
rcas> e.to_sexp
=> [:mul, [:add, :x, 1], [:sub, 1, :x]]
rcas> 1 - x
=> 1 - x
rcas> 2 * x**2 / 3
=> 2*x**2/3
```

The tree is printed with the minimum of parentheses that preserves it.
Output is valid Ruby apart from the variable names, so it can be pasted back.

```
rcas> x - (y - 1)
=> x - (y - 1)
rcas> x / (y * z)
=> x/(y*z)
rcas> (x**2)**3
=> (x**2)**3
rcas> -(x + 1)
=> -(x + 1)
```

#### simplify, expand, factor

`simplify` brings an expression into a canonical form: numbers are folded
exactly, like terms and like factors are merged, sums are ordered by
degree. It never distributes products over sums; `expand` does that;
`factor` goes the other way.

```
rcas> (x + x + 3 * x**2 - x**2).simplify
=> 2*x + 2*x**2
rcas> (x * x**2 / x).simplify
=> x**2
rcas> e.expand
=> 1 - x**2
rcas> ((x + y)**3).expand
=> x**3 + 3*x**2*y + 3*x*y**2 + y**3
rcas> (x**4 - 1).factor
=> (-1 + x)*(1 + x)*(1 + x**2)
rcas> (x**2 - y**2).factor
=> (x + y)*(x - y)
rcas> (6*x**2 - x - 2).factor
=> (-2 + 3*x)*(1 + 2*x)
```

Rational expressions: `cancel` puts everything over one denominator with the
polynomial gcd removed, `rationalize` clears square roots from denominators.
`numer` and `denom` return the two halves of that normal form, with integer
coefficients and a positive leading coefficient in the denominator.

```
rcas> ((x**2 - 1) / (x - 1)).cancel
=> 1 + x
rcas> (1 / (a**2 * (-1 - 1/a)) + 1/a).cancel
=> 1/(1 + a)
rcas> (1 / (1 + sqrt(2))).rationalize
=> -1 + 2**(1/2)
rcas> [numer(1/x + 1/(x + 1)), denom(1/x + 1/(x + 1))]
=> [1 + 2*x, x + x**2]
rcas> [numer(x/2), denom(x/2), numer(3/4r), denom(sin(x)/x**2)]
=> [x, 2, 3, x**2]
```

`apart` is the partial fraction decomposition over QQ: a polynomial part,
then one term per power of each irreducible factor of the denominator.
Other indeterminates are parameters; name the one to decompose in when
there are several.

```
rcas> apart(1/(x**2 - 1))
=> 1/(2*(-1 + x)) - 1/(2*(1 + x))
rcas> apart((x + 1)/(x**2*(x - 1)))
=> 2/(-1 + x) - 2/x - 1/x**2
rcas> apart(x**3/(x**2 + 1))
=> x - x/(1 + x**2)
rcas> apart((x**2 + x + 1)/((x - 1)**2*(x**2 + 1)))
=> 3/(2*(-1 + x)**2) - 1/(2*(1 + x**2))
rcas> apart(1/(x**2 - a**2), x)
=> -1/(2*a*(a + x)) - 1/(2*a*(a - x))
rcas> apart(1/(x**2 - 2))
=> 1/(-2 + x**2)
```

The last denominator is irreducible over QQ, so nothing splits; `apart`
does not introduce algebraic numbers. The rewriting methods also exist as
functions, MuPAD and Maple style: `simplify(f)`, `expand(f)`, `cancel(f)`,
`rationalize(f)`.

#### Substitution and evaluation

```
rcas> f = x**2 + y
=> x**2 + y
rcas> f.subs(x: 3)
=> 3**2 + y
rcas> f.subs(x: 3).simplify
=> 9 + y
rcas> f.subs(x**2 => z)
=> z + y
rcas> f.call(x: 3, y: 1)
=> 10
rcas> (x**2 + 1).(9)
=> 82
rcas> (x + y).(1, 2)
=> 3
rcas> [1, 2, 3].map(&(x**2))
=> [1, 4, 9]
rcas> f.variables
=> [:x, :y]
```

`call` (and the `.()` shorthand) returns a plain Ruby number when every
variable is bound. Positional arguments bind the variables in sorted order.
`evalf` evaluates numerically, turning every exact number into a float;
`to_f` does the same for a constant expression.

```
rcas> (sqrt(2) * x).evalf(x: 3)
=> 4.242640687119286
rcas> (PI**2 / 6).to_f
=> 1.6449340668482262
```

#### Equality

`==` is structural: two expressions are equal when they are the same tree.
Compare canonical forms when you mean mathematical equality.

```
rcas> x + 1 == 1 + x
=> false
rcas> (x + 1).simplify == (1 + x).simplify
=> true
rcas> (x - x).simplify == 0
=> true
```

### 1.2 Numbers and constants

Integers and rationals stay exact, floats stay floats. `1/2` in Ruby is
integer division, so write `1/2r` (or `Rational(1, 2)`) for one half.

```
rcas> (x / 2 + x / 3).simplify
=> 5*x/6
rcas> (x * 1/2r).simplify
=> x/2
rcas> (2**100).to_s.size
=> 31
rcas> sqrt(32)
=> 4*2**(1/2)
rcas> sqrt(-4)
=> 2*i
rcas> log(8)
=> 3*log(2)
```

`PI`, `E` and `I` are the exact constants (`pi` and `π` work as bare
names too); `oo` and `∞` are infinity, used as a limit point and a
summation bound. A function
applied to a constant folds right away, the way Ruby folds `1 + 2`; an
operator expression such as `I**2` is kept as written until `simplify`.

```
rcas> [sin(PI/6), cos(PI/4), tan(PI/4), sin(PI)]
=> [1/2, 2**(1/2)/2, 1, 0]
rcas> [sin(π/6), limit(1/x, x: ∞)]
=> [1/2, 0]
rcas> [exp(I*PI), (I**2).simplify, ((1 + 2*I)*(1 - 2*I)).expand]
=> [-1, -1, 5]
rcas> [(E**x).simplify, log(E), (E**2 * E).simplify]
=> [exp(x), 1, exp(3)]
rcas> [asin(1/2r), acos(0), atan(1)]
=> [pi/6, pi/2, pi/4]
rcas> sin(PI/5)
=> sin(pi/5)
rcas> sin(x)
=> sin(x)
```

The functions are `sin cos tan asin acos atan exp log sinh cosh sqrt zeta`.
`sqrt(x)` is `x**(1/2)`, and `exp(a)*exp(b)` merges into `exp(a + b)`.

```
rcas> (exp(x) * exp(2*x)).simplify
=> exp(3*x)
rcas> (exp(x)**2).simplify
=> exp(2*x)
rcas> sin(-x).simplify
=> -sin(x)
rcas> zeta(2)
=> pi**2/6
```

#### Integers and primes

`factor` on an integer or rational gives its prime factorization, an
object with `unit`, `factors` (prime and exponent pairs), `primes`,
`expand` and `prime?`; `ifactor` is the same function under Maple's name.
Trial division by small primes is followed by Pollard's rho method, which
handles factors of a dozen digits or so; `isprime` is a Miller-Rabin test
that is exact below 3.3e24 and a strong probable-prime test beyond.

```
rcas> factor(360)
=> 2**3*3**2*5
rcas> [factor(360).factors, factor(360).unit, factor(4/9r), factor(-12)]
=> [[[2, 3], [3, 2], [5, 1]], 1, 2**2/3**2, -(2**2*3)]
rcas> factor(2**67 - 1)
=> 193707721*761838257287
rcas> [isprime(97), isprime(2**61 - 1), isprime(2**64 + 1)]
=> [true, true, false]
rcas> [nextprime(100), prevprime(100), divisors(12), totient(12)]
=> [101, 97, [1, 2, 3, 4, 6, 12], 4]
rcas> [invmod(3, 7), chrem([2, 3], [3, 5]), 3.pow(100, 7), 12.gcd(18)]
=> [5, 8, 4, 6]
```

`chrem(residues, moduli)` solves the simultaneous congruences (the moduli
need not be coprime; an inconsistent system raises). Modular powers, gcd
and lcm of integers are Ruby's own `pow(e, m)`, `gcd` and `lcm`.

### 1.3 Calculus

#### Derivatives

```
rcas> (x**3 + sin(x)).diff(x)
=> cos(x) + 3*x**2
rcas> (x**x).diff(x)
=> x**x*(1 + log(x))
rcas> exp(x**2).diff(x)
=> 2*x*exp(x**2)
rcas> (x**3).diff(x, 2)
=> 6*x
rcas> atan(x).diff(x)
=> 1/(1 + x**2)
```

#### Antiderivatives

`integrate(f, x)` (or `f.integrate(x)`) returns an antiderivative without
the constant. Whatever cannot be integrated stays as an `integral(...)`
node, so partial results remain usable and `diff` undoes `integrate`.
Three layers are tried in order for every term:

1. **Rules.** Linearity and constant factors, a table for `u**n`, `1/u`,
   `c**u` and `exp sin cos tan log atan sinh cosh` of a linear argument,
   derivative-divides substitution (`x*exp(x**2)`, `sin(x)*cos(x)**3`,
   `log(x)/x`), and integration by parts for a polynomial times an
   exponential or trigonometric factor and for `log` / `atan` factors.
2. **Rational functions, exactly.** Hermite reduction strips repeated
   denominator factors; the logarithmic part comes from the
   Rothstein-Trager resultant, whose rational roots give `log` terms and
   whose quadratic irreducible factors give `log` plus `atan` with square
   roots. Roots of degree three or more are left as an `integral(...)`.
3. **Risch-Norman heuristic.** The integrand is written as a Laurent
   polynomial in `x` and its transcendental atoms (`exp(u)`, `log(u)`,
   `sin(u)`/`cos(u)`, `sinh`/`cosh`, `atan`, `c**u`, roots such as
   `x**(1/2)`, polynomial denominators). An ansatz of the same shape plus
   `log` terms is differentiated symbolically, `sin**2 + cos**2 = 1` is
   reduced away, and the undetermined coefficients are found as an exact
   linear system over QQ. A final linear substitution (`v = x + 1`)
   rescues integrands like `x*exp(x)/(x + 1)**2`.

The test suite checks every antiderivative by differentiating it and
comparing numerically with the integrand at a few points.

```
rcas> integrate(x**2 * exp(x), x)
=> 2*exp(x) - 2*x*exp(x) + x**2*exp(x)
rcas> integrate(x * log(x), x)
=> -x**2/4 + x**2*log(x)/2
rcas> integrate(1 / (x**2 + 1), x)
=> atan(x)
rcas> integrate(1 / (x**3 + 1), x)
=> log(1 + x)/3 - log(1 - x + x**2)/6 + 3**(1/2)*atan((-1 + 2*x)/3**(1/2))/3
rcas> integrate((x**3 + 1) / (x**2 * (x + 1)**2), x)
=> -1/x + 3*log(1 + x) - 2*log(x)
rcas> integrate(exp(x) * sin(x), x)
=> -(cos(x)*exp(x))/2 + exp(x)*sin(x)/2
rcas> integrate(sin(x)**2, x)
=> x/2 - cos(x)*sin(x)/2
rcas> integrate(exp(x) / (1 + exp(x)), x)
=> log(1 + exp(x))
rcas> integrate(exp(sqrt(x)) / sqrt(x), x)
=> 2*exp(x**(1/2))
rcas> integrate(exp(-x**2) + x, x)
=> integral(exp(-x**2), x) + x**2/2
```

#### Definite integrals

Give the bounds positionally or as a range on the variable; an endless
range means infinity. Improper integrals go through limits.

```
rcas> integrate(x**2, x, 0, 1)
=> 1/3
rcas> integrate(sin(x), x: 0..PI)
=> 2
rcas> integrate(exp(-x), x: 0..)
=> 1
rcas> integrate(1 / (1 + x**2), x: -oo..oo)
=> pi
rcas> integrate(log(x), x: 0..1)
=> -1
rcas> integrate(exp(-x**2), x: 0..1)
=> integral(exp(-x**2), x, 0, 1)
```

#### Series

`series(f, x, a, n)` expands around `a` to order `n` with an `O(...)` term;
`taylor` omits the `O`. Laurent and Puiseux series (negative and fractional
powers) and expansions at infinity work.

```
rcas> series(sin(x), x, 0, 8)
=> x - x**3/6 + x**5/120 - x**7/5040 + O(x**8)
rcas> taylor(exp(x), x)
=> 1 + x + x**2/2 + x**3/6 + x**4/24 + x**5/120
rcas> series(log(1 + x), x: 0, n: 4)
=> x - x**2/2 + x**3/3 + O(x**4)
rcas> series(1 / sin(x), x, 0, 4)
=> 1/x + x/6 + 7*x**3/360 + O(x**4)
rcas> series(sqrt(1 + x), x, 0, 4)
=> 1 + x/2 - x**2/8 + x**3/16 + O(x**4)
rcas> series(x / (x + 1), x, oo, 3)
=> 1/x**2 - 1/x + 1 + O(1/x**3)
rcas> taylor((1 + x)**a, x, 0, 3)
=> 1 + a*x + a*x**2*(-1 + a)/2
```

#### Limits

Limits read the leading term of the series. `oo` and `-oo` are valid
points; `dir: :right` or `:left` gives one-sided limits, and a two-sided
limit whose sides disagree stays unevaluated.

```
rcas> limit(sin(x) / x, x, 0)
=> 1
rcas> limit((1 - cos(x)) / x**2, x: 0)
=> 1/2
rcas> limit((1 + 1/x)**x, x, oo)
=> e
rcas> limit((3*x**2 + 1) / (2*x**2 - x), x, oo)
=> 3/2
rcas> limit(x * log(x), x: 0, dir: :right)
=> 0
rcas> limit(x**3 * exp(-x), x, oo)
=> 0
rcas> limit(sqrt(x**2 + x) - x, x, oo)
=> 1/2
rcas> [limit(1/x, x: 0, dir: :right), limit(1/x, x: 0, dir: :left), limit(1/x, x, 0)]
=> [oo, -oo, limit(1/x, x, 0)]
rcas> limit(sin(x) / x, x, oo)
=> limit(sin(x)/x, x, oo)
```

#### Sums

`sum(f, k, a, b)` or `sum(f, k: a..b)`; `k: a..` sums to infinity and
`a...b` excludes `b`. Polynomials in `k` get closed forms, hypergeometric
terms go through Gosper's algorithm, `1/n**s` to infinity uses the zeta
function, and finite sums with integer bounds are added up exactly when
nothing else applies.

```
rcas> sum(k, k: 1..n)
=> n/2 + n**2/2
rcas> sum(k**2, k, 1, n)
=> n/6 + n**2/2 + n**3/3
rcas> sum(2**k, k: 0..n)
=> -1 + 2*2**n
rcas> sum(k * 2**k, k: 1..n)
=> 2 + 2*2**n*(-1 + n)
rcas> sum(1 / (k*(k + 1)), k: 1..n)
=> n/(1 + n)
rcas> sum(1 / (k*(k + 1)), k: 1..)
=> 1
rcas> sum(k / 2**k, k: 1..)
=> 2
rcas> sum(1/n**2, n: 1..)
=> pi**2/6
rcas> sum(1/n**4, n: 1..)
=> pi**4/90
rcas> sum(1/n**3, n: 1..)
=> zeta(3)
rcas> sum(1/n**2, n: 1..10)
=> 1968329/1270080
rcas> sum(1/k, k: 1..n)
=> sum(1/k, k, 1, n)
```

#### hold and evaluate

Ruby folds `1 + 2` before rcas sees it. `hold { ... }` reads the block's
source instead and keeps it as written. Inside the block `integrate`,
`diff`, `sum` and `limit` stay formal; `evaluate` (aliases `unhold`,
`doit`) computes them, like MuPAD's `eval`. Everything else works on held
expressions as usual.

```
rcas> hold { 1 + 2 }
=> 1 + 2
rcas> hold { 1 + 2 }.simplify
=> 3
rcas> hold { 1/2 }
=> 1/2
rcas> f = hold { (sin(x)**2).integrate(x) }
=> integral(sin(x)**2, x)
rcas> f.evaluate
=> x/2 - cos(x)*sin(x)/2
rcas> hold { sum(1/n**2, n: 1..) }
=> sum(1/n**2, n, 1, oo)
rcas> evaluate(hold { sum(1/n**2, n: 1..) })
=> pi**2/6
rcas> hold { diff(x**3, x, 2) }
=> D(x**3, x, 2)
rcas> hold { (x + 1)**2 }.expand
=> 1 + 2*x + x**2
rcas> hold { x**2 - 3 == 0 }
=> x**2 - 3 = 0
rcas> hold { x**2 - 3 == 0 }.solve
=> [-3**(1/2), 3**(1/2)]
```

Inside `hold`, `==` builds an equation and `!=` a "not equal" relation
(outside `hold` both compare structure); `<`, `<=`, `>`, `>=` build
inequalities as they do everywhere.

```
rcas> hold { x**2 - 3 != 0 }.solve
=> (-oo, -3**(1/2)) ∪ (-3**(1/2), 3**(1/2)) ∪ (3**(1/2), oo)
```

#### Factorials, binomials, gamma

`factorial(n)` prints as `n!`. Values fold exactly, including half-integers
through the gamma function; `(k + 2)!/k!` cancels to a polynomial, which is
what lets `sum` handle terms with factorials and binomials.

```
rcas> [factorial(5), factorial(1/2r), gamma(5/2r), gamma(0.5)]
=> [120, pi**(1/2)/2, 3*pi**(1/2)/4, 1.772453850905516]
rcas> [binomial(5, 2), binomial(n, 2), binomial(n, 1), binomial(5, 7)]
=> [10, binomial(n, 2), n, 0]
rcas> factorial(n + 1)
=> (n + 1)!
rcas> (factorial(k + 2) / factorial(k)).simplify
=> (1 + k)*(2 + k)
rcas> sum(x**k / factorial(k), k: 0..)
=> exp(x)
rcas> [sum(1 / factorial(k), k: 0..), sum(1 / factorial(k), k: 2..)]
=> [e, -2 + e]
rcas> sum((-1)**k * x**(2*k) / factorial(2*k), k: 0..)
=> cos(x)
rcas> sum((-1)**(k + 1) * x**k / k, k: 1..)
=> log(1 + x)
rcas> sum((-1)**k / (2*k + 1), k: 0..)
=> pi/4
rcas> [sum(binomial(n, k) * x**k, k: 0..n), sum(binomial(n, k), k: 0..n)]
=> [(1 + x)**n, 2**n]
rcas> sum(k * factorial(k), k: 1..n)
=> -1 + (1 + n)!
rcas> sum(k / factorial(k + 1), k: 1..)
=> 1
```

The infinite sums come from the classical power series (`exp`, `sin`,
`cos`, `sinh`, `cosh`, `log(1 + x)`, `atan`, the binomial theorem),
recognised from the ratio of consecutive terms; the finite ones from
Gosper's algorithm.

#### Trigonometric and logarithmic rewriting

`simplify` is a canonical form and leaves `sin(x)**2 + cos(x)**2` alone.
`trigsimp` tries the rewritings with `sin**2 + cos**2 = 1` (with `tan`
written as `sin/cos`, with and without `expand_trig`) and returns the
shortest result; `expand_trig` writes out sums and multiples of angles.

```
rcas> expand_trig(sin(x + y))
=> cos(x)*sin(y) + cos(y)*sin(x)
rcas> expand_trig(cos(2*x))
=> cos(x)**2 - sin(x)**2
rcas> expand_trig(sin(3*x))
=> 3*cos(x)**2*sin(x) - sin(x)**3
rcas> trigsimp(sin(x)**2 + cos(x)**2)
=> 1
rcas> trigsimp(sin(x)**4 - cos(x)**4)
=> 1 - 2*cos(x)**2
rcas> trigsimp((1 - cos(x)**2) / sin(x))
=> sin(x)
rcas> trigsimp(tan(x) * cos(x))
=> sin(x)
rcas> trigsimp(2*sin(x)*cos(x) - sin(2*x))
=> 0
rcas> trigsimp(1 / cos(x)**2 - tan(x)**2)
=> 1
rcas> expand_log(log(x**2 * y / 3))
=> -log(3) + 2*log(x) + log(y)
rcas> logcombine(2*log(x) - log(y) + 1)
=> 1 + log(x**2/y)
```

`expand_log` and `logcombine` assume positive arguments.

### 1.4 Equations and solving

`eq(lhs, rhs)` (or `lhs.eq(rhs)`) builds an equation. `solve` takes an
equation or an expression that is meant to be zero, and a variable; it
returns an array of solutions.

```
rcas> solve(x**2 - 3*x + 2, x)
=> [1, 2]
rcas> solve(eq(x**2, -1), x)
=> [-i, i]
rcas> solve(x**2 - 2, x)
=> [-2**(1/2), 2**(1/2)]
rcas> solve(x**3 - 8, x)
=> [2, -1 - i*3**(1/2), -1 + i*3**(1/2)]
rcas> solve(a*x**2 + b*x + c, x)
=> [(-(-4*a*c + b**2)**(1/2) - b)/(2*a), ((-4*a*c + b**2)**(1/2) - b)/(2*a)]
rcas> solve(x**3 - x - 1, x).first
=> RootOf(-1 - x + x**3, 0)
rcas> solve(x**3 - x - 1, x).first.evalf
=> 1.324717957245
rcas> solve(1/(x - 1) - 1/(x + 1) - 1, x)
=> [-3**(1/2), 3**(1/2)]
rcas> solve(x + sqrt(x) - 6, x)
=> [4]
```

Polynomials are solved exactly by factoring over the rationals, the
quadratic formula, k-th roots for binomials and the symbolic quadratic
formula; an irreducible factor of degree three or more with numeric
coefficients gets floating-point roots. Transcendental equations are
reduced to a polynomial in one atom and inverted; trigonometric inverses
give the principal solutions of one period.

```
rcas> solve(exp(x) - 5, x)
=> [log(5)]
rcas> solve(exp(2*x) - 3*exp(x) + 2, x)
=> [0, log(2)]
rcas> solve(2**x - 8, x)
=> [3]
rcas> solve(log(x) - 2, x)
=> [exp(2)]
rcas> solve(sin(x) - 1/2r, x)
=> [pi/6, 5*pi/6]
rcas> solve(cos(x), x)
=> [pi/2, -pi/2]
```

Systems take an array of equations and an array of unknowns and return an
array of hashes. Linear systems are solved for the pivot unknowns in terms
of the free ones; two polynomial equations in two unknowns go through a
resultant.

```
rcas> solve([eq(x + y, 3), eq(x - y, 1)], [x, y])
=> [{x=>2, y=>1}]
rcas> solve([x + y + z - 1, x - y], [x, y, z])
=> [{x=>1/2 - z/2, y=>1/2 - z/2}]
rcas> solve([x + y - 1, x + y - 2], [x, y])
=> []
rcas> solve([x**2 + y**2 - 25, x + y - 7], [x, y])
=> [{x=>4, y=>3}, {x=>3, y=>4}]
```

Roots of irreducible polynomials of degree three or more are exact
`RootOf` objects; `evalf` gives the number, and arithmetic with them is
exact (see algebraic numbers below).

```
rcas> solve(x**3 - x - 1, x)
=> [RootOf(-1 - x + x**3, 0), RootOf(-1 - x + x**3, 1), RootOf(-1 - x + x**3, 2)]
```

Equation objects support sidewise arithmetic, `subs`, `swap`, `holds?`,
`lhs`, `rhs` and `solve`.

```
rcas> q = eq(x + 1, 3)
=> x + 1 = 3
rcas> (q - 1).simplify
=> x = 2
rcas> q.solve
=> [2]
rcas> q.holds?(x: 2)
=> true
```

#### Inequalities

`<`, `<=`, `>`, `>=` between an expression (or bare symbol) and a number or
expression build an inequality; `solve` returns the solution set as a
union of intervals. Polynomial and rational inequalities go through a sign
chart on the real roots, absolute values by splitting the line at the zeros
of their arguments; a list of inequalities is intersected.

```
rcas> solve(x**2 < 4, x)
=> (-2, 2)
rcas> solve(x**2 >= 4, x)
=> (-oo, -2] ∪ [2, oo)
rcas> solve(x**2 - 2 < 0, x)
=> (-2**(1/2), 2**(1/2))
rcas> solve((x - 1) / (x + 1) >= 0, x)
=> (-oo, -1) ∪ [1, oo)
rcas> solve(abs(x - 1) <= 2, x)
=> [-1, 3]
rcas> solve(abs(2*x + 1) < abs(x), x)
=> (-1, -1/3)
rcas> solve([x > 1, x < 3], x)
=> (1, 3)
rcas> [solve(x**2 + 1 < 0, x), solve(x**2 <= 0, x), solve(x**2 + 1 > 0, x)]
=> [{}, {0}, (-oo, oo)]
rcas> solve(x**2 < 4, x).include?(1)
=> true
rcas> (x**2 < 4).holds?(x: 3)
=> false
```

With one parameter in the inequality the answer depends on it, and
`solve` returns the cases: the parameter line is split where roots become
real, coincide or the degree drops, each piece is solved exactly, and pieces
with the same solution are merged. `at(value)` picks the case for a
concrete parameter.

```
rcas> solve(x**2 - a >= 0, x)
=> a <= 0: (-oo, oo)
   a > 0:  (-oo, -a**(1/2)] ∪ [a**(1/2), oo)
rcas> solve((x - a) * (x - 1) < 0, x)
=> a < 1: (a, 1)
   a = 1: {}
   a > 1: (1, a)
rcas> solve(a*x - 1 > 0, x)
=> a < 0: (-oo, 1/a)
   a = 0: {}
   a > 0: (1/a, oo)
rcas> solve(x**2 - a >= 0, x).at(4)
=> (-oo, -a**(1/2)] ∪ [a**(1/2), oo)
```

`abs` and `sign` are functions (`abs(-x)` simplifies to `abs(x)`, the
derivative of `abs(x)` is `sign(x)`). Comparing two bare symbols keeps
Ruby's meaning; write `x.to_expr < y` or `lt`-style code with an
expression on the left for that case.

### 1.5 Domains and assumptions

`NN ZZ QQ RR CC` are the number sets (NN includes 0). They answer
`include?` (`===` too) for numbers and expressions, compare as sets, and
know which are rings and fields. Membership of a number is by value for
exact types (`4/2r` is an integer) and by type for floats (floats are reals).

```
rcas> [NN.include?(3), NN.include?(-3), ZZ.include?(-3), QQ === 1/2r, RR.include?(2.0)]
=> [true, false, true, true, true]
rcas> NN < ZZ && ZZ < QQ && QQ < RR && RR < CC
=> true
rcas> [ZZ.ring?, ZZ.field?, QQ.field?]
=> [true, false, true]
```

A variable becomes a member of a set with `x.in(ZZ)` or `assume(x: ZZ)`.
Expressions then infer the smallest set that must contain their value.

```
rcas> x.in(ZZ); n.in(NN); assume(y: QQ)
=> true
rcas> [x.domain, (x + 1).domain, (x / 2).domain, (n - 1).domain, sqrt(n).domain, sqrt(x).domain]
=> [ZZ, ZZ, QQ, ZZ, RR, CC]
rcas> [ZZ.include?(x**2 + 1), ZZ.include?(x / 2), (x / 2).in?(QQ)]
=> [true, false, true]
rcas> (t + 1).domain
=> nil
rcas> assumptions
=> {:x=>ZZ, :n=>NN, :y=>QQ}
rcas> forget
=> true
```

### 1.6 Polynomial rings

`ZZ[x]`, `QQ[x, y]`, `RR[t]` are polynomial rings. `R.(expr)` converts an
expression into a ring element, an `RCAS::Polynomial` stored as a map from
exponents to coefficients. Rings are sets as well.

```
rcas> R = ZZ[x]
=> ZZ[x]
rcas> [R.include?(x**2 + 1), R.include?(x / 2), QQ[x].include?(x / 2), R.include?(1 / x)]
=> [true, false, true, false]
rcas> ZZ[x] < QQ[x] && QQ[x] < QQ[x, y]
=> true
rcas> R.fraction_field
=> Frac(ZZ[x])
rcas> f = R.(x**2 - 1)
=> -1 + x**2
rcas> [f.degree, f.coefficients, f.leading_coefficient, f.derivative]
=> [2, [-1, 0, 1], 1, 2*x]
```

Arithmetic mixes freely with expressions and numbers. Coefficients widen as
needed, new variables extend the ring, and a non-polynomial partner falls
back to a plain expression.

```
rcas> [f + 1, 2 * f, x * f, f**2]
=> [x**2, -2 + 2*x**2, -x + x**3, 1 - 2*x**2 + x**4]
rcas> (f + 1/2r).ring
=> QQ[x]
rcas> (f + y).ring
=> ZZ[x, y]
rcas> f + sin(x)
=> -1 + x**2 + sin(x)
```

Division, gcd and factorization:

```
rcas> f / (x - 1)
=> 1 + x
rcas> (f**2).divmod(R.(x - 1))
=> [-1 - x + x**2 + x**3, 0]
rcas> f.gcd(x**2 + 2*x + 1)
=> 1 + x
rcas> R.(2*x + 2).gcd(4*x**2 - 4)
=> 2 + 2*x
rcas> QQ[x].(x**2 + 1).xgcd(x)
=> [1, 1, -x]
rcas> f.lcm(x**2 + 2*x + 1)
=> -1 - x + x**2 + x**3
rcas> R.(x**2 + x + 1).discriminant
=> -3
rcas> ZZ[x, a, b, c].(a*x**2 + b*x + c).discriminant(x)
=> -4*a*c + b**2
rcas> R.(x**6 - 1).factor
=> (-1 + x)*(1 + x)*(1 + x + x**2)*(1 - x + x**2)
rcas> QQ[x].(x**2 - 1/4r).factor
=> (1/4)*(-1 + 2*x)*(1 + 2*x)
rcas> ZZ[x, y].(x**4 - y**4).factor
=> (x + y)*(x - y)*(x**2 + y**2)
rcas> R.(x**3 - x).roots
=> [-1, 0, 1]
rcas> R.((x + 1)**2 * (x - 1)**3 * x).squarefree_decomposition
=> [[x, 1], [1 + x, 2], [-1 + x, 3]]
```

`factor` returns a factorization object with `unit`, `factors` (pairs of
polynomial and multiplicity), `expand` and `to_expr`. Factorization is
exact over ZZ and QQ (squarefree decomposition, Cantor-Zassenhaus, Hensel
lifting, recombination; Kronecker substitution for several variables). gcd
over ZZ and QQ works in any number of variables.

```
rcas> fact = R.(2*x**2 + 4*x + 2).factor
=> 2*(1 + x)**2
rcas> [fact.unit, fact.factors.size, fact.expand]
=> [2, 1, 2 + 4*x + 2*x**2]
rcas> ZZ[x, y].(x**2 * y - y).gcd(x * y**2 - y**2)
=> -y + x*y
```

#### gcd and division of expressions

`gcd`, `lcm`, `quo`, `rem` and `divmod` work on plain expressions as well
as on ring elements and integers. Division is over QQ; with several
indeterminates, name the one to divide by and the others become
parameters.

```
rcas> [gcd(12, 18), gcd(2*x + 2, 4*x**2 - 4), lcm(x**2 - 1, x**2 + 2*x + 1)]
=> [6, 2 + 2*x, -1 - x + x**2 + x**3]
rcas> [quo(x**3 - 1, x - 1), rem(x**3 + 1, x - 1), divmod(x**2 + 1, 2*x)]
=> [1 + x + x**2, 2, [x/2, 1]]
rcas> divmod(a*x**2 + x - a, x - 1, x)
=> [1 + a + a*x, 1]
```

#### Degree and coefficients

`degree`, `ldegree`, `lcoeff`, `tcoeff`, `coeff`, `coeffs` and `collect`
read the polynomial structure of a plain expression, without building a
ring first. They expand internally, so the input need not be expanded, and
coefficients come back in canonical form. All of them are also methods on
expressions (`f.degree(x)`, `f.coeff(x, 2)`).

```
rcas> f = a*x**2 + b*x + c
=> a*x**2 + b*x + c
rcas> [degree(f, x), lcoeff(f, x), tcoeff(f, x), coeff(f, x, 1), coeff(f, x**2)]
=> [2, a, c, b, a]
rcas> coeffs(f, x)
=> [c, b, a]
rcas> [degree((x + 1)**3, x), coeffs((x + 1)**4, x), ldegree(x**3 - 2*x, x)]
=> [3, [1, 4, 6, 4, 1], 1]
rcas> collect((x + y)**2 + a*x, x)
=> y**2 + (a + 2*y)*x + x**2
rcas> collect(a*x**2 - x**2 + b*x - 3*x + 1, x)
=> 1 + (-3 + b)*x + (-1 + a)*x**2
```

Without an indeterminate the whole expression is examined: `degree` is the
total degree, `coeffs` lists the coefficients of the canonical sum in
printed order, and `lcoeff`/`tcoeff` belong to its last and first term.
The zero polynomial has degree -1, as in `ZZ[x]`, and no coefficients.

```
rcas> [degree(x**2*y + x*y**3), coeffs((x + y)**2), degree(x**2 + 1, y)]
=> [4, [1, 2, 1], 0]
rcas> [degree(0), coeffs(0, x), degree(pi*x**2 + sqrt(2), x)]
=> [-1, [], 2]
```

An expression that is not a polynomial in the indeterminate (`sin(x)`,
`1/x`, `x**n`, `sqrt(x)`) raises a `DomainError` instead of guessing;
`degree(x*sin(y), x)` is fine because `sin(y)` is a constant with respect
to `x`. `coeff(f, x, k)` needs an integer `k`; rational exponents are not
polynomial terms.

#### Algebraic numbers

Constant expressions built from rationals, `i`, radicals (`sqrt(2)`,
`cbrt(2)`, `root(5, 4)`) and `RootOf` are recognised as elements of a
number field `QQ(alpha)`, where arithmetic is exact. This is what makes
zero tests on such constants exact, clears denominators in general, gives
minimal polynomials, exact eigenvectors, and factorization over an
extension field.

```
rcas> K = QQ.adjoin(sqrt(2))
=> QQ(2**(1/2))
rcas> [K.degree, K.include?(1 + sqrt(2)), K.include?(sqrt(3)), K < RR]
=> [2, true, false, true]
rcas> (1 / (1 + sqrt(2))).rationalize
=> -1 + 2**(1/2)
rcas> (1 / (1/2r + sqrt(5)/2)).rationalize
=> -1/2 + 5**(1/2)/2
rcas> ((1 + sqrt(2))**3).rationalize
=> 7 + 5*2**(1/2)
rcas> minpoly(sqrt(2) + sqrt(3))
=> 1 - 10*x**2 + x**4
rcas> minpoly(cbrt(2))
=> -2 + x**3
rcas> minpoly(-1/2r + I*sqrt(3)/2)
=> 1 + x + x**2
rcas> factor(x**2 - 2, extension: sqrt(2))
=> (-2**(1/2) + x)*(2**(1/2) + x)
rcas> factor(x**4 + 1, extension: sqrt(2))
=> (1 + 2**(1/2)*x + x**2)*(1 - 2**(1/2)*x + x**2)
rcas> factor(x**2 + 1, extension: I)
=> (-i + x)*(i + x)
rcas> QQ[x].(x**3 - 2).factor(extension: cbrt(2))
=> (-2**(1/3) + x)*(2**(2/3) + 2**(1/3)*x + x**2)
rcas> r = solve(x**3 - x - 1, x).first
=> RootOf(-1 - x + x**3, 0)
rcas> (1 / r).rationalize
=> -1 + RootOf(-1 - x + x**3, 0)**2
rcas> QQ.matrix([[1, 1], [1, 0]]).eigenvectors.map { |l, m, vs| vs.first }
=> [(1/2 - 5**(1/2)/2, 1), (1/2 + 5**(1/2)/2, 1)]
```

Fields with one generator (any radical or `RootOf`) and fields generated
by two square roots are supported; other combinations fall back to
numeric zero tests.

#### Finite fields

`GF(p)` and `GF(p**n)` are fields; `GF(9, :b)` names the generator. Elements
are plain values that print as residues (or as polynomials in the
generator) and promote into expressions when they meet a symbol, so
polynomial rings, vectors and matrices over them work like everywhere else.

```
rcas> F = GF(7)
=> GF(7)
rcas> [F.(10), F.(1/2r), F.(3) * F.(5), F.(3)**-1, 1 / F.(3)]
=> [3, 4, 1, 5, 5]
rcas> [F.primitive_element, F.log(6), F.(3).order]
=> [3, 3, 6]
rcas> R = F[x]
=> GF(7)[x]
rcas> R.(x**2 + 10*x + 1)
=> 1 + 3*x + x**2
rcas> R.(x**7 - x).factor
=> (1 + x)*(2 + x)*(3 + x)*(4 + x)*(5 + x)*(6 + x)*x
rcas> [R.(x**2 + 1).irreducible?, R.(x**2 - 2).roots, F.solve(x**2 + x + 1, x)]
=> [true, [3, 4], [2, 4]]
rcas> GF(2)[x].(x**8 + x).factor
=> (1 + x)*x*(1 + x + x**3)*(1 + x**2 + x**3)
rcas> GF(3)[x].(x**6 + 1).factor
=> (1 + x**2)**3
rcas> m = (F**[2, 2])[[1, 2], [3, 4]]
=> [1 2]
   [3 4]
rcas> [m.det, m.rank, m.solve([1, 0])]
=> [5, 2, (5, 5)]
rcas> m.inverse
=> [5 1]
   [5 3]
rcas> m.charpoly
=> 5 + 2*x + x**2
```

Extension fields use the lexicographically smallest monic irreducible
polynomial of the right degree (`modulus` lists its coefficients from the
constant term up):

```
rcas> K = GF(8)
=> GF(8)
rcas> K.modulus
=> [1, 1, 0, 1]
rcas> a = K.gen
=> a
rcas> [a**3, a**7, a**-1, (a + 1) * (a**2 + a)]
=> [1 + a, 1, 1 + a**2, 1]
rcas> [K.primitive_element, K.log(a**5), a.order, K.frobenius(a)]
=> [a, 5, 7, a**2]
rcas> K.minpoly(a**3)
=> 1 + x**2 + x**3
rcas> K[x].(x**3 + x + 1).factor
=> ((a + a**2) + x)*(a + x)*(a**2 + x)
rcas> GF(9, :b)[x].(x**2 + 1).factor
=> (2*b + x)*(b + x)
rcas> GF(25).primitive_element
=> 1 + a
```

Factorization over any finite field is squarefree decomposition in
characteristic `p` followed by Cantor-Zassenhaus; `GF(6)` and other
non-prime-powers are rejected.

### 1.7 Linear algebra

`QQ**3` is a vector space, `QQ**[2, 3]` a space of 2x3 matrices (over ZZ
they are free modules with the same API). Indexing a space builds an
element and checks every entry belongs to the domain.

```
rcas> V = QQ**3
=> QQ**3
rcas> v = V[1, 2, 3]
=> (1, 2, 3)
rcas> w = V[1/2r, 0, -1]
=> (1/2, 0, -1)
rcas> [v + w, 2 * v, v / 2, v * w, v.cross(w), v.norm]
=> [(3/2, 2, 2), (2, 4, 6), (1/2, 1, 3/2), -5/2, (-2, 5/2, -1), 14**(1/2)]
rcas> (v / 2).space
=> QQ**3
rcas> V.basis
=> [(1, 0, 0), (0, 1, 0), (0, 0, 1)]
```

`v * w` is the dot product. Result spaces follow the scalars: dividing an
integer vector by 2 lands in `QQ**3`. Entries outside the domain are
rejected, and an undeclared symbolic entry tells you what to declare.

```
rcas> (ZZ**3)[1, 2, 3].space
=> ZZ**3
rcas> ((ZZ**3)[1, 2, 3] / 2).space
=> QQ**3
```

Matrices:

```
rcas> A = QQ**[2, 2]
=> QQ**[2, 2]
rcas> a = A[[1, 2], [3, 4]]
=> [1 2]
   [3 4]
rcas> [a.det, a.trace, a.rank]
=> [-2, 5, 2]
rcas> a.inverse
=> [ -2    1]
   [3/2 -1/2]
rcas> a * a.inverse == A.identity
=> true
rcas> a**3
=> [37  54]
   [81 118]
rcas> a.transpose
=> [1 3]
   [2 4]
rcas> a * (QQ**2)[1, 1]
=> (3, 7)
rcas> a.solve([5, 6])
=> (-4, 9/2)
rcas> a.charpoly
=> -2 - 5*x + x**2
rcas> b = (QQ**[2, 3])[[1, 2, 3], [2, 4, 6]]
=> [1 2 3]
   [2 4 6]
rcas> [b.rank, b.kernel]
=> [1, [(-2, 1, 0), (-3, 0, 1)]]
rcas> b.rref
=> [1 2 3]
   [0 0 0]
rcas> matrix([[1, 2], [3, 4]]).space
=> ZZ**[2, 2]
rcas> ZZ.matrix([[2, 0], [0, 2]]).inverse.space
=> QQ**[2, 2]
```

Eigenvalues are the roots of the characteristic polynomial, exact whenever
`solve` is; `eigenvectors` lists `[eigenvalue, multiplicity, basis]`.

```
rcas> m = QQ.matrix([[2, 1], [1, 2]])
=> [2 1]
   [1 2]
rcas> m.eigenvalues
=> [1, 3]
rcas> m.eigenvectors
=> [[1, 1, [(-1, 1)]], [3, 1, [(1, 1)]]]
rcas> m.diagonalizable?
=> true
rcas> QQ.matrix([[1, 1], [1, 0]]).eigenvalues
=> [1/2 - 5**(1/2)/2, 1/2 + 5**(1/2)/2]
rcas> QQ.matrix([[1, 1], [0, 1]]).diagonalizable?
=> false
```

Symbolic entries are allowed once their variables are declared. When every
entry is a polynomial or rational function in one indeterminate with
rational coefficients, `det`, `inverse`, `solve` and `kernel` work by
evaluation and interpolation: a degree bound for the result, exact
elimination at that many rational points, Newton interpolation back
(Horn, *Faktorisierung in Schief-Polynomringen*, Kassel 2008, chapter 6).
An 8x8 matrix of cubics takes a few hundredths of a second where cofactor
expansion would not finish. Anything else falls back to cofactor expansion
and row reduction over expressions, so keep those small.

```
rcas> m = QQ[x].matrix([[1, x**2], [x**2 + 1, x - 2]])
=> [       1  x**2]
   [x**2 + 1 x - 2]
rcas> m.det
=> -2 + x - x**2 - x**4
rcas> m.solve([x - 1, x + 1])
=> ((-2 + 3*x + x**3)/(2 - x + x**2 + x**4), (-2 - x**2 + x**3)/(2 - x + x**2 + x**4))
rcas> m.inverse
=> [   (2 - x)/(2 - x + x**2 + x**4) x**2/(2 - x + x**2 + x**4)]
   [(1 + x**2)/(2 - x + x**2 + x**4)   -1/(2 - x + x**2 + x**4)]
```

```
rcas> x.in(RR)
=> x
rcas> s = RR.matrix([[x, 1], [1, x]])
=> [x 1]
   [1 x]
rcas> s.det
=> -1 + x**2
rcas> s.inverse
=> [ x/(-1 + x**2) -1/(-1 + x**2)]
   [-1/(-1 + x**2)  x/(-1 + x**2)]
rcas> s.charpoly(l)
=> -1 + l**2 - 2*l*x + x**2
rcas> forget
=> true
```

### 1.8 Differential equations

`D(y, x, n)` is the n-th derivative of an unknown function `y`. `dsolve`
handles separable and linear first-order equations and homogeneous
second-order equations with constant coefficients, returning equations
`y = ...` with constants `C1`, `C2`.

```
rcas> dsolve(eq(D(y, x), 2*x*y), y, x)
=> [y = exp(C1 + x**2)]
rcas> dsolve(D(y, x) - x/y, y, x)
=> [y = -(2*C1 + x**2)**(1/2), y = (2*C1 + x**2)**(1/2)]
rcas> dsolve(eq(D(y, x) + 2*y, exp(x)), y, x)
=> [y = exp(-2*x)*(C1 + exp(3*x)/3)]
rcas> dsolve(D(y, x, 2) - 3*D(y, x) + 2*y, y, x)
=> [y = C1*exp(x) + C2*exp(2*x)]
rcas> dsolve(D(y, x, 2) + y, y, x)
=> [y = C1*cos(x) + C2*sin(x)]
rcas> dsolve(D(y, x, 2) + 2*D(y, x) + 5*y, y, x)
=> [y = exp(-x)*(C1*cos(2*x) + C2*sin(2*x))]
```

### 1.9 Performance notes

`expand` and polynomial conversion combine like terms while multiplying,
so a product of many sums never materialises more terms than the result
has; expanding a product of ten sums with a dozen terms each takes
milliseconds. `simplify` flattens sums and products in a single pass, and
canonical results with more than 32 terms are built as balanced trees of
short chains, which keeps every recursive algorithm (printing, equality,
substitution, differentiation) at logarithmic depth. A 20000-term sum
simplifies, prints and converts to a polynomial in well under a second.

Expressions you build yourself are stored exactly as written, so a
20000-term sum typed as one long chain is 20000 levels deep. `simplify`,
`expand`, `to_s`, `variables` and `to_poly` cope with that; `==`, `subs`,
`diff` and `hash` on such a raw chain still recurse per term, so simplify
first.

Polynomial factorization over ZZ is fast up to degrees in the dozens; the
recombination step is exponential in the number of modular factors, so a
product of twenty random factors of degree up to twenty takes about a
minute. Multivariate factorization goes through Kronecker substitution and
is meant for small examples. Symbolic determinants and inverses use
cofactor expansion; keep symbolic matrices small.

## 2. Reference

Top-level functions (bare in `bin/rcas`, `RCAS.name` elsewhere):

| purpose | functions |
|---|---|
| elementary functions | `sin cos tan asin acos atan exp log sinh cosh sqrt cbrt root zeta abs sign` |
| combinatorics | `factorial binomial gamma` |
| rewriting | `simplify expand cancel rationalize trigsimp expand_trig expand_log logcombine minpoly` |
| rational functions | `numer denom apart gcd lcm quo rem divmod` |
| integers | `factor ifactor isprime nextprime prevprime divisors totient invmod chrem` |
| polynomial structure | `degree ldegree lcoeff tcoeff coeff coeffs collect` |
| constants | `PI E I oo` (bare `pi`, `π`, `oo`, `∞`) |
| calculus | `integrate diff series taylor limit sum` |
| algebra | `solve eq factor` |
| differential equations | `D dsolve` |
| domains | `NN ZZ QQ RR CC GF assume forget assumptions` |
| linear algebra | `vector matrix` |
| holding | `hold evaluate` |

Methods on expressions: `simplify expand factor cancel rationalize collect
numer denom apart gcd lcm quo rem divmod subs call evalf to_f diff integrate
series taylor limit solve eq variables degree ldegree lcoeff tcoeff coeff
coeffs domain in in? to_poly to_sexp hold-related evaluate`.

Not implemented: the complete Risch algorithm and special functions
(`erf`, `Ei`), non-homogeneous second-order differential equations, limits
of bounded oscillation (`sin(x)/x` at infinity), inequalities beyond
polynomial, rational and absolute-value ones, number fields with more than
two generators, and Zeilberger's algorithm for definite hypergeometric sums.

## 3. Files

```
lib/rcas.rb                 entry point
lib/rcas/expression.rb      Expression tree: Var Num Const Neg Add Sub Mul Div Pow Fn
lib/rcas/printer.rb         precedence-aware to_s
lib/rcas/simplify.rb        canonical sums/products, exact number folding
lib/rcas/expand.rb          distribution with like-term merging
lib/rcas/differentiate.rb   derivative rules
lib/rcas/integrate.rb       rules, rational functions, Risch-Norman heuristic
lib/rcas/series.rb          Puiseux series, limits
lib/rcas/summation.rb       Faulhaber, Gosper, zeta
lib/rcas/solve.rb           equations, solve, systems
lib/rcas/ode.rb             D, dsolve
lib/rcas/constants.rb       pi, e, i and exact values
lib/rcas/domains.rb         NN ZZ QQ RR CC, assumptions, PolynomialRing, FractionField
lib/rcas/polynomial.rb      ring elements
lib/rcas/gcd.rb             polynomial gcd
lib/rcas/factor.rb          polynomial factorization
lib/rcas/fraction.rb        cancel, rationalize
lib/rcas/rational_function.rb  numer, denom, apart, gcd/lcm/quo/rem on expressions
lib/rcas/number_theory.rb   integer factorization, primes, divisors, totient, invmod, chrem
lib/rcas/poly_matrix.rb     det/solve/inverse/kernel of polynomial matrices by evaluation and interpolation
lib/rcas/vector.rb          VectorSpace, Vector
lib/rcas/matrix.rb          MatrixSpace, Matrix, elimination
lib/rcas/hold.rb            hold
lib/rcas/functions.rb       the top-level functions
lib/rcas/core_ext.rb        Symbol / Numeric extensions
lib/rcas/irb.rb             irb setup
lib/rcas/latex.rb           to_latex, line breaking (Appendix A)
lib/rcas/render.rb          pictures from LaTeX, inline images (Appendix A)
lib/rcas/chat.rb            rcas-chat front end (Appendix B)
lib/rcas/chat/*.rb
assets/rcas-logo.jpeg       the logo (960 px, used in the documents)
assets/rcas-logo-full.jpeg  the logo at full resolution
bin/rcas                    irb launcher
bin/rcas-chat               rcas-chat launcher
package.json                KaTeX for the typesetting
```

Run the tests with `ruby -S rake`.

## 4. License

rcas is released under the MIT License; see `LICENSE`.

## Appendix A. Typeset output

Everything rcas produces has a `to_latex` method: expressions, polynomials,
factorizations, the number sets and rings, spaces, vectors and matrices,
equations and derivatives, and also symbols, numbers, arrays and hashes.
The LaTeX follows the tree exactly as `to_s` does and adds only what a
typesetter expects: `\frac` for division, implicit multiplication, `\sqrt`
for the exponent 1/2, `\sin^{2} x`, `e^{x}`, `\ln`, `\pi`, `\mathbb{Q}[x]`,
`pmatrix` for matrices. Strings are shown here as Ruby `inspect`s them, so
every backslash is doubled.

```
rcas> ((x + 1) / (x - 1)).to_latex
=> "\\frac{x + 1}{x - 1}"
rcas> sin(x**2).diff(x).to_latex
=> "2 x \\cos\\left(x^{2}\\right)"
rcas> (sin(x)**2 + cos(x)**2).to_latex
=> "\\sin^{2} x + \\cos^{2} x"
rcas> (x * exp(x)).integrate(x).to_latex
=> "-e^{x} + x e^{x}"
rcas> ZZ[x].(x**6 - 1).factor.to_latex
=> "\\left(-1 + x\\right) \\left(1 + x\\right) \\left(1 + x + x^{2}\\right) \\left(1 - x + x^{2}\\right)"
rcas> QQ[x, y].to_latex
=> "\\mathbb{Q}[x, y]"
rcas> matrix([[1, 2], [3, 4]]).inverse.to_latex
=> "\\begin{pmatrix} -2 & 1 \\\\ \\displaystyle \\frac{3}{2} & \\displaystyle -\\frac{1}{2} \\end{pmatrix}"
rcas> (2 * PI * x).to_latex
=> "2 \\pi x"
rcas> eq(D(y, x), 2 * x * y).to_latex
=> "\\frac{d y}{dx} = 2 x y"
rcas> [1, x, QQ].to_latex
=> "\\left[1,\\; x,\\; \\mathbb{Q}\\right]"
```

Long results can be broken into lines. `to_latex(wrap: n)` splits the
top-level sum or product (or a long array, one element per line) into an
`aligned` block whose lines are about `n` typeset characters wide, with
continuation lines indented and led by the operator. Nothing changes when
the result fits.

```
rcas> (x + 1).to_latex(wrap: 40)
=> "x + 1"
rcas> ((x + 1)**8).expand.to_latex(wrap: 40)
=> "\\begin{aligned} & 1 + 8 x + 28 x^{2} + 56 x^{3} + 70 x^{4} + 56 x^{5} \\\\ &\\quad {} + 28 x^{6} + 8 x^{7} + x^{8} \\end{aligned}"
```

### Pictures

`show(obj)` (or `obj.show`) typesets a value. In iTerm2 it appears as an
inline picture right in the terminal; anywhere else the LaTeX source is
printed. `obj.to_png("f.png")` writes the picture to a file. `bin/rcas`
itself is unchanged: it prints text as before and typesets only when you
ask with `show`.

Two rendering backends are supported and tried in this order:

* **KaTeX** ([katex.org](https://katex.org)). Run `npm install` once in the
  project directory to fetch the `katex` package listed in `package.json`.
  node typesets the formula to HTML and a local Google Chrome (or Chromium,
  Brave, Edge, Arc) rasterizes it. `RCAS_NODE` and `RCAS_CHROME` point to
  other binaries.
* **LaTeX**. A TeX installation with `latex` and `dvipng` (or `pdflatex`
  and ImageMagick).

Pick one with `RCAS::Render.backend = :latex` or `RCAS_TEX_BACKEND=latex`.
Pictures are kept in `/tmp/rcas` (`RCAS_CACHE_DIR`) while a session runs and the ones it created are deleted when it ends, so a formula
is rendered once. Settings, each also available as an environment variable:

| setting | environment | meaning |
|---|---|---|
| `RCAS::Render.scale = 1.5` | `RCAS_TEX_SCALE` | zoom factor, 1 is natural size |
| `RCAS::Render.theme = "light"` | `RCAS_TEX_THEME` | colour of the text; detected from iTerm2's background or `COLORFGBG` when unset |
| `RCAS::Render.device_scale = 1` | `RCAS_TEX_DEVICE_SCALE` | picture pixels per point, 2 for Retina displays |
| | `RCAS_TEX_WRAP` | line width for wrapping, otherwise derived from the terminal width |
| `RCAS::Render.inline = false` | `RCAS_TEX_INLINE=0` | never print inline pictures |

## Appendix B. rcas-chat

`bin/rcas-chat` is a second front end, in the style of Claude Code. You
type Ruby and get the result as text plus, in iTerm2, the typeset picture.
You type a question in plain language and Claude answers it by running rcas
code in your session, showing every call and its result as it goes. The
Ruby side works without any credentials; questions need the `anthropic` gem
and an API key.

```
$ bin/rcas-chat
╭─────────────────────────────────────────────────────────────╮
│ ✻ rcas 0.1.0 - symbols are indeterminates; type Ruby or ...  │
│   model    claude-opus-5                                    │
│   output   both via katex                                   │
│   session  20260912-143012-a1b2                             │
╰─────────────────────────────────────────────────────────────╯
──────────────────────────────────────────────────────────────
❯ e = (x + 1) * (1 - x)
=> (x + 1)*(1 - x)
   [picture]
──────────────────────────────────────────────────────────────
❯ factor x**6 - 1 over the integers
⏺ rcas_eval(ZZ[x].(x**6 - 1).factor)
  ⎿  => (-1 + x)*(1 + x)*(1 + x + x**2)*(1 - x + x**2)
   [picture]
⏺ Four irreducible factors over ZZ; over QQ the factorization is the same.
```

### Input

Each input sits between two rules while you type; the upper one stays in
the scrollback as the separator between turns. What you type is sorted by
its first character and then by whether it is Ruby:

* `/word` is a command (see the table below), `!cmd` runs a shell command.
* `? question` goes to Claude.
* Anything that parses and runs as Ruby is evaluated, with the same rules
  as `bin/rcas`: bare names are variables, the functions and sets are in
  scope, `_` is the last result. Unfinished Ruby (an open `def`, bracket or
  string) continues on the next line.
* Anything else is a question for Claude. A line that parses as Ruby but
  fails with an unknown name and reads like a sentence ("what is x
  squared") is treated as a question too.

Tab completes command names, variables and common method names; the input
history is kept in `~/.rcas/history`. A spinner turns while Ruby computes,
while Claude thinks and while one of its calls runs; a result that took
longer than a second or two is followed by its time.

### Claude

Questions are answered by `claude-opus-5` (change it with `/model`,
`--model` or `RCAS_MODEL`). Claude has one tool, `rcas_eval`, which
evaluates Ruby in your session: it sees your variables and assumptions, and
what it defines stays defined, so after asking for a factorization you can
carry on with `_` or the variables it made. Each call is shown as
`⏺ rcas_eval(code)` with its result underneath, and results Claude chooses
to display are typeset like your own. The reply itself is kept short.

Credentials come from the SDK: `ANTHROPIC_API_KEY`, or a profile from
`ant auth login`. When Claude declines a request the API falls back
server-side to `claude-opus-4-8`; `/fallbacks off` or `RCAS_FALLBACKS=0`
turns that off. `/cost` shows the tokens used in the session with a rough
price, `/compact` forgets the conversation but keeps your variables.

### Output modes

`/output` chooses how results are shown, for your own Ruby and for Claude's
calls alike:

| mode | shows |
|---|---|
| `text` | the plain rcas text only (the default outside iTerm2) |
| `tex` | the typeset picture only, text when a value has no LaTeX form |
| `both` | text, then the picture (the default in iTerm2) |
| `latex` | text, then the LaTeX source |

`/backend katex|latex`, `/scale N` and `/theme dark|light` are the settings
of Appendix A; `/settings` shows them, `/settings save` writes them to
`~/.rcas/settings.json` as defaults for later sessions, and `/settings reset`
removes that file. `/latex EXPR` prints the LaTeX of an expression, `/show
EXPR` typesets one regardless of the mode, `/png EXPR FILE` writes a file.

### Errors

An error is shown in one line. An `ArgumentError` from an rcas function
comes with a usage hint taken from the function's own documentation
comment: the signature and the example it gives.

```
❯ sum(x)
  ArgumentError: sum: which variable?
  usage: sum(f, k = nil, from = nil, to = nil, **range)
  sum(k**2, k, 1, n) or sum(k**2, k: 1..n); an endless range means infinity
```

Claude gets the same hint when one of its calls fails, so it can correct
itself. Domain errors (`DomainError`) describe the mathematics rather than
the call and come without a hint.

### Sessions

Every input is saved to `~/.rcas/sessions/<id>.json` (`RCAS_SESSION_DIR`):
the transcript, the conversation with Claude and the settings. Variables
are not stored; they are rebuilt by replaying the session's Ruby, including
Claude's calls, when the session is resumed.

* `/rename NAME` names the current session. Unnamed sessions go by their
  first input.
* `/resume` opens a picker over the other saved sessions: arrow keys or
  Ctrl-N/Ctrl-P move, typing filters by name, first input or id, Enter
  resumes, Esc cancels. Each row shows when the session was last used, how
  many inputs it has, its name and its first prompt. Resuming shows the
  session's recent history and then continues it.
* `/resume NAME` switches directly; an id, a unique prefix of either, or a
  number from `/sessions` work as well.
* `rcas-chat --continue` reopens the most recent session, `rcas-chat
  --resume` opens the picker and `rcas-chat --resume NAME` resumes by name.
* `/save [FILE]` writes a Markdown transcript with the LaTeX of every
  result; `/reset` starts a fresh session.

### Commands

```
/help                             this list
/output [text|tex|both|latex]     how results are shown
/backend [katex|latex]            typesetting backend
/scale N                          zoom factor for pictures
/theme dark|light                 colour of the pictures
/latex EXPR   /show EXPR   /png EXPR FILE
/ask TEXT                         ask Claude (also: ? TEXT)
/vars                             the session's variables
/assumptions   /forget [x ...]    variable domains
/model [ID]   /fallbacks [on|off]   /cost   /compact
/sessions   /resume [NAME|ID|N]   /rename NAME   /reset   /save [FILE]
/clear   /exit                    (Ctrl-D also leaves)
!CMD                              run a shell command
```

### Options and environment

```
rcas-chat [-c|--continue] [-r|--resume [NAME|ID]] [--model ID]
          [--output=MODE] [--tex|--no-tex] [--backend=katex|latex] [--no-color]
```

| variable | meaning |
|---|---|
| `ANTHROPIC_API_KEY` | credentials for Claude (or a profile from `ant auth login`) |
| `RCAS_MODEL` | default model |
| `RCAS_FALLBACKS=0` | no server-side fallback on refusals |
| `RCAS_SESSION_DIR` | where sessions are saved |
| `RCAS_TEX_*`, `RCAS_CACHE_DIR`, `RCAS_NODE`, `RCAS_CHROME` | typesetting, see Appendix A |
| `NO_COLOR` | plain output |

### Files

```
lib/rcas/chat.rb              entry point, requires the parts below
lib/rcas/chat/workspace.rb    the evaluation session (bare names, locals, Ruby detection)
lib/rcas/chat/ui.rb           results, banner, spinner, Claude's streamed text and calls
lib/rcas/chat/assistant.rb    the conversation with Claude and the rcas_eval tool
lib/rcas/chat/session.rb      saved sessions, replay, lookup by name
lib/rcas/chat/picker.rb       the /resume picker
lib/rcas/chat/usage.rb        usage hints from documentation comments
lib/rcas/chat/repl.rb         the loop, commands, options
lib/rcas/chat/style.rb        colours
bin/rcas-chat                 launcher
test/chat_test.rb             tests, with a fake Claude
```
