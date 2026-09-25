# rcas design notes

This document is for readers who know computer algebra and want to know
how rcas is built and why: what its objects mean, which rules the code
keeps, how it decides questions that cannot always be decided, and where
it stands next to Sage, SymPy, MuPAD and Maxima. The user manual is
[MANUAL.md](MANUAL.md); the list of what is not implemented is at the end
of [its reference section](MANUAL.md#2-reference), and the sources of the
algorithms are in [MANUAL.md, section 4](MANUAL.md#4-sources). Keys such
as `[Zei91]` below refer to that bibliography.

Contents

1. [rcas at a glance](#1-rcas-at-a-glance)
2. [Vocabulary](#2-vocabulary)
3. [Invariants](#3-invariants)
4. [Decision policies](#4-decision-policies)
5. [Algorithms and rule chains](#5-algorithms-and-rule-chains)
6. [Implementation notes and traps](#6-implementation-notes-and-traps)
7. [Contributing a feature](#7-contributing-a-feature)
8. [Layout](#8-layout)

## 1. rcas at a glance

rcas is a computer algebra system written in Ruby (3.3 and later,
standard library only). It extends Ruby rather than defining a language:
Ruby symbols are the indeterminates, Ruby operators build expression
trees, and irb is the read-eval-print loop. There is no parser and no
evaluator of its own. The intended audience is school, high school and
undergraduate mathematics, and two things follow from that throughout:
answers are exact wherever possible (Integer, Rational, algebraic
numbers), and an answer rcas cannot justify is returned as an
unevaluated node or refused, never replaced by a plausible guess.

### What `==` means

`==` is structural: two expressions are equal when they are the same
tree, and `eql?`/`hash` agree with it, so expressions work as Hash keys
and as `subs` patterns.

```
rcas> x + 1 == 1 + x
=> false
rcas> (x + 1).simplify == (1 + x).simplify
=> true
```

Mathematical equality is a question, not an operator: compare canonical
forms, or ask `Scalar.zero?(a - b)`, which may answer "undecided" (see
below). Inside `hold { }` the operator changes role: `==` builds an
`Equation`, `!=` an `Inequality` and `in?` a `Membership` - statements
about expressions, which are not themselves expressions. Outside `hold`,
equations are written `a.eq(b)` or passed to `solve` as expressions equal
to zero. This keeps `==` usable as Ruby expects (in `Array#include?`,
`Hash`, tests) at the price of one extra spelling for equations; Sage and
SymPy made the opposite choice (Sage) or the same one (SymPy, with `Eq`).

### When rcas rewrites

Construction never rewrites. `(x + 1)*(1 - x)` is stored and printed as
written; rewriting happens only when asked, through `simplify`, `expand`,
`factor`, `cancel`, `diff` and the other operations.

```
rcas> e = (x + 1)*(1 - x)
=> (x + 1)*(1 - x)
rcas> e.simplify
=> (1 + x)*(1 - x)
rcas> expand(e)
=> 1 - x**2
```

There is one exception: a *function applied to a constant argument* folds
when it is built, so `sin(PI/6)` is `1/2` and `sqrt(-4)` is `2*i`. The
reason is that Ruby folds `1 + 2` before rcas sees it, and a student
expects `sin(pi/6)` to behave like a number in the same way. Operator
expressions on constants (`I**2`) still wait for `simplify`.

Ruby's own folding is the one real trap of the design: `/` between two
Integers is integer division (the quotient rounded down, as `//` in
Python), so `1/2` is the Integer 0, and `2**(1/3r)` is a Float, before
any rcas code runs; `x + 1/3` is `x + 0`. Redefining `Integer#/` would
change it for every library in the process, and rcas has no preparser
(Sage's answer), so the literal has to say what it means. Output keeps
the mathematical spelling `x**(1/3)` for the stored Rational exponent,
which reads well but does not paste back: typed at the prompt it is
`x**0`, and the input warning is what catches it. The exact spellings are `1/3r`, `Rational(1, 3)`,
`root(2, 3)` and `cbrt`, and `hold { }` keeps the literal structure of a
block by reading its syntax tree instead of running it. Since the value
cannot be recovered afterwards, the front ends read each input line's
syntax tree before running it and warn about a division of two integer
literals that is not whole (`RCAS::Lint`).

### The canonical form

`simplify` produces one canonical form. Sums are ordered by ascending
degree with the constant first (`1 + 2*x + x**2`, as Mathematica prints
them), ties broken graded-lexicographically; factors are ordered number,
constant, indeterminate, function, sum, with `i` first. Radicals of
positive integers keep an exponent in (0, 1) and move the integer part
into the coefficient (`1/sqrt(2)` is `2**(1/2)/2`), which is what lets
exact tables such as `atan`'s match. Internally the normal form is a term
table `{ {base => exponent} => coefficient }`; every module that needs
coefficients, atoms, numerators or denominators reads it rather than
walking trees. `simplify` does not expand products and does not apply
branch-dependent rules (`log(exp(x))` stays unless `x` is known to be
real; see [branch cuts](#branch-cuts)).

### Domains

Domains are values: `NN ZZ QQ RR CC` (also `ℕ ℤ ℚ ℝ ℂ`), polynomial rings
`ZZ[x]`, fraction fields, `GF(p**n)`, algebraic fields `QQ(alpha)`,
vector spaces `QQ**3` and matrix spaces `QQ**[2, 3]`. A *value* answers
`domain` with the smallest domain rcas knows it to lie in; a *structure*
answers `base` with the domain its entries come from (`ZZ[x].base` is
`ZZ`). For an expression the domain is inferred (`Infer.domain`) and is
`nil` when unknown. Assumptions (`assume(x: ZZ)`, `assume(x > 0)`, the
block form `assume(...) { }` that restores both tables afterwards) record
a number set and a sign per indeterminate, and are used by `simplify`,
`Infer`, `solve` and a few rewriting rules.

A matrix or vector whose entries are in undeclared indeterminates lives
over the polynomial ring they generate, the way integer entries put it
over `ZZ`: `matrix([[a, b], [c, d]])` is in `ZZ[a, b, c, d]**[2, 2]`,
and `inverse` and `rref` pass to the fraction field when they need it.
A declared name is a scalar of its own domain instead. Entries that are
not rational functions (a radical, as in a generic eigenvalue, or
`sin(a)`) read the undeclared names as complex numbers, which is what an
undeclared name is to `Infer` anyway, and the matrix is over `CC`; the
constructor runs under that same temporary reading, so its membership
check agrees with the inference.

Membership is exact where possible and one-sided otherwise:
`Infer.excluded?(value, domain)` answers true only when the value is
*demonstrably* outside - exactly for a number, by the minimal polynomial
for an algebraic constant, by transcendence for a rational multiple of
`pi` or `e`. `log(2)` survives a declared `QQ` because rcas cannot prove
it irrational. A wrong answer kept is preferred to a right answer dropped.

### Undecidable questions

Zero-equivalence of constants is undecidable in general, and rcas does
not pretend otherwise. There is one numeric decision procedure,
`Decide.sign`/`Decide.zero?`, and every part of the system that needs a
sign or a zero test goes through it. Its rule: **numerics prove "not
zero", never "zero".** A value is non-zero when an evaluation stands
clear of its error bound (a Float with a running error bound first, then
30, 60 and 120 digits measured against the largest magnitude met in the
walk). A zero is proved only by a root separation bound for an algebraic
constant or by a normal form (simplification, expansion, cancellation,
the Pythagorean identity, logarithms of rationals over their primes).
Anything else is `nil`, undecided, and callers must treat it as such:
matrix elimination takes an undecided pivot as the generic non-zero case
and documents that; certified `evalf` refuses.

```
rcas> evalf(atan(1/2r) + atan(1/3r) - PI/4, 30)
NoConvergence: evalf: atan(1/2) + atan(1/3) - pi/4 could not be certified
to 30 digits; ... (it is 0 to 660 digits, and rcas cannot prove it is
exactly 0)
```

The same attitude shapes the answers of the symbolic algorithms. An
integral without an antiderivative rcas can find stays `integral(...)`;
a sum, limit or product likewise; a polynomial root without radicals is a
`RootOf`. A question rcas cannot settle raises `RCAS::Unsupported` naming
what is missing - "cannot" is never reported as "none".

### Comparison with other systems

rcas is small next to all of these, and its closest relatives are clear.
Structurally it is closest to Sage: a host-language variable holds an
algebraic object, and domains are parents with elements (`ZZ[x]`,
`QQ**[2, 3]` follow Sage's `ZZ['x']`, `MatrixSpace`). Unlike Sage it has
no preparser, which is why Ruby's integer division is visible. From MuPAD
it takes `hold`/`eval`, domains as first-class values, the image-set
notation `{pi*k | k in ZZ}` for infinite solution sets, and `assume`.
From Maple and Mathematica it takes `surd` (Maple's name; Mathematica's
`Surd`), `RootOf`, and the scoped assumptions of `assuming`/`Assuming`.

| | rcas | Sage | SymPy | MuPAD | Maxima |
|---|---|---|---|---|---|
| language | Ruby, no parser of its own | Python with a preparser | Python library | own language | own language (Lisp underneath) |
| indeterminates | Ruby symbols `:x` (bare names in the REPL) | `var('x')` | `Symbol('x')` | identifiers | atoms |
| `==` on expressions | structural | builds a relation | structural (`Eq` builds one) | `=` builds an equation | `=` builds an equation |
| at construction | stored as written | automatic simplification | automatic canonicalization (`evaluate=False` to prevent it) | evaluation to full depth, `hold` to prevent it | general simplifier on, quote `'` to prevent evaluation |
| exact rationals from literals | `1/3r` (Ruby's `1/3` is 0) | yes, via the preparser | `Rational(1, 3)` (Python's `1/3` is a float) | yes | yes |
| domains | values; parents and elements | parents and elements | ring objects in `polys`, assumptions on symbols | `Dom::...` domains | `declare`, `assume` |
| `sin(x) = 0` | `{pi*k \| k in ZZ}` | one solution by default | `solveset` gives an image set | image set | one solution, with a warning |
| undecided zero | `nil`; refuse or generic case | heuristic | heuristic (`equals` may return `None`) | heuristic | may ask the user |

These entries describe default behaviour as far as it is documented;
details differ between versions of each system.

Where rcas is weaker, it is weaker by a lot. Its scope is an
undergraduate curriculum, not research: no complete Risch algorithm
(rational functions exactly, then heuristics), special functions only up
to `erf`, `Ei`, `Si`, `Ci` and `li`, limits by leading terms rather than
Gruntz's algorithm, Gröbner bases by Buchberger's algorithm without F4,
number fields with at most two generators, no ODEs with variable
coefficients beyond first order, inequalities only polynomial, rational
and with absolute values. The complete list is at the end of
[the reference section](MANUAL.md#2-reference). It is also slow in the
way interpreted exact arithmetic is slow: the manual's
[performance notes](MANUAL.md#115-performance-notes) give measured
numbers, and multivariate factorization by Kronecker substitution has
cliffs a system with Hensel lifting in several variables does not.

Where rcas takes a different position, it does so deliberately:

- **Exactness first.** A Float appears only when one was put in or
  asked for (`evalf`, `nsolve`, `nintegrate`), and such answers are
  labelled as numeric.
- **Decisions are proofs.** A sign on an interval, an inflection, the
  real part of a family, a zero pivot: each is proved or left undecided,
  never read off a few samples (see [section 4](#4-decision-policies)).
- **Complete answers by default.** `solve` returns every solution over
  `CC`, families included; `principal: true` asks for one period and
  `domain: RR` for the real ones.
- **Principal branches everywhere, with the real alternative named.**
  `x**(1/3)` is the principal root, `surd(x, 3)` the real one.
- **No rewriting at construction**, which costs a `simplify` call and
  buys expressions that print the way they were typed - useful when the
  point is to watch a derivation.

## 2. Vocabulary

The code and the manual use these words consistently.

- **Symbol**: the Ruby object `:x`. Any Ruby identifier qualifies,
  Unicode included (`α`, `β₁`); `RCAS::IDENTIFIER` is the shared pattern.
  `π` and `∞` are aliases of `pi` and `oo`.
- **Indeterminate**: the role a symbol plays inside an expression or a
  ring (`x**2 - 1`, `ZZ[x]`). This is the word for the mathematics; not
  "variable". The API method that returns them is still called
  `Expression#variables`, following CAS convention.
- **Variable**: a Ruby binding (`e = (x + 1)*(1 - x)`). In `bin/rcas` a
  bare undefined name evaluates to its symbol and is stored in a variable
  of the same name.
- **Unknown function**: `u(n + 1)`, `f(x)`: a function node whose name is
  not a built-in function. An undefined name applied to expressions or
  numbers builds one, which is how `rsolve` reads recurrences.
- **Parameter**: an indeterminate that is not the one being solved,
  integrated or summed for (`a` in `solve(x**2 - a >= 0, x)`).
- **Image set**: `{pi/6 + 2*pi*k | k in ZZ}`, the answer to an equation
  with infinitely many solutions. It is a statement about expressions,
  like `Equation`, `Inequality` and `Membership`, not an expression; it
  carries the domain of its index, so that `sin` of a member folds to
  `1/2` without any declaration.
- **domain and base**: a value's `domain` is the smallest domain it is
  known to lie in (its ring, space or field; for an expression the
  inferred number set, or `nil`). A structure's `base` is the domain of
  its entries or coefficients. `space`, `ring` and `field` are the
  precise accessors.
- **Double-struck sets**: `ℕ ℤ ℚ ℝ ℂ` are constants (Ruby reads them as
  capitals), aliases of `NN ZZ QQ RR CC`. `RCAS.unicode = true` prints
  them and `π`, `∞` in output; the default is ASCII.

## 3. Invariants

These are the rules the code keeps; a change that breaks one breaks a
large part of the system.

1. **Construction never rewrites.** Only the operations rewrite. The
   exception is a function of a constant argument, which folds
   (`Functions#sin` and friends do it; `Fn.new` does not).
2. **`==`, `eql?` and `hash` are structural.** The hash is computed once
   in the constructor, before the node is frozen, and combined by hand
   and masked with `Expression::FIXNUM`: an unmasked `31*h1 + h2` grows
   about five bits per level, and the hash of a 20000-term sum became a
   bignum of 99000 bits.
3. **One canonical form**, described [above](#the-canonical-form). Sums
   longer than `Simplify::CHAIN` (32) are balanced trees of chains, and
   `termize`/`factorize` are iterative with explicit stacks, so the
   recursion depth stays logarithmic: a 20000-term sum simplifies in well
   under a second, and the performance tests keep it so.
4. **Term tables are the shared internal normal form.**
   `Expand.table(e)` returns `[constant, { {base => exponent} => coeff }]`
   and `Simplify.factorize` returns `[coeff, factors]`. Unknown leaf
   classes (constants, integrals, `RootOf`) are atoms.
5. **Everything numeric lives in `Num`**: Integer, Rational, Float,
   Complex, finite-field elements (`Mod`, `GFElement`) and the
   arbitrary-precision `Decimal`. A new numeric type is a `Numeric` with
   a `printer_precedence` hook; `Simplify.normalize_number` and
   `pow_number` must stay safe for all of them. `exp(u)` is stored in
   factor tables as a power of one base, so exponentials merge.
6. **Domains are values, and membership is exact where possible.**
   `NumberSet#===` is membership, so `case domain when ZZ` is wrong -
   compare with `==`. Matrix and vector spaces are domains: square
   matrices over a ring form a ring, a vector space is neither, and a
   space is not a scalar domain, so a polynomial ring over a matrix space
   is refused.
7. **Infinity is a value with arithmetic.** `oo` is a constant and an
   atom in the term tables, so `rebuild_sum` and `rebuild_product` catch
   it: `oo - oo`, `oo/oo` and `0*oo` are `undefined`; `2*oo`, `oo**2` and
   `oo - 2` are `oo`; `1/oo` is 0; `1**oo` and `oo**0` are 1, as IEEE
   `pow` has them. A symbolic coefficient is never absorbed (`x*oo`
   stays), because `0*oo` is undefined.
8. **Formal nodes** - `Integral`, `Sum`, `Product`, `Limit`,
   `Derivative`, `RootOf`, `Piecewise` - are expressions and atoms to
   everything else; `evaluate` (`doit`) computes them. A binder keeps the
   shape body, bound variable, bounds (`children[0]`, `children[1]`,
   rest); `variables`, `constant?` and `replace_with` skip bound
   occurrences, and a substitution that would be captured renames the
   bound variable. `Piecewise` carries conditions that are inequalities,
   not expressions, and overrides `variables` and `replace_with` for them.
9. **Zero of a matrix entry is decided, not assumed.** `Scalar.zero?` is
   exact for numbers, then asks `Decide`; a non-constant entry is zero
   when it is identically zero (one exact rational point first, then
   expansion, cancellation, `trigsimp`). Symbolic pivots not shown to be
   zero are the generic case, and a symbolic matrix of full rank at one
   rational point has full rank.
10. **Ruby folds before rcas sees anything**, so no code may assume a
    literal arrived unevaluated.
11. **Bare names are precious.** No bare `e` or `i` (they are common
    names); the constants are `E`, `I`, `PI`, `OO` with bare `pi` and
    `oo`. In the REPL Kernel's `p`, `pp`, `j`, `jj` are undefined so they
    can be indeterminates. Symbol-to-symbol comparison keeps Ruby's
    meaning; comparing a symbol with a number or an expression builds an
    inequality.

## 4. Decision policies

### Settled design decisions

Each of these is what most comparable systems do, and MuPAD's choice
where they differ.

1. **`**` is the principal root; `surd(x, n)` is the real one.**
   `x**(1/n)` and `root(x, n)` are principal on every path, including
   arbitrary precision; `surd(x, n)` is `-|x|**(1/n)` below 0 for odd n
   and `undefined` there for even n; `cbrt` is `surd(x, 3)`. Hence
   `real_domain(x**(1/3))` is `[0, oo)`, and `discuss` and `plot` of such
   a power point at `surd`.
2. **`real_domain` requires every subexpression to be real**, as
   Mathematica's `FunctionDomain` does. A decided non-real constant
   subexpression leaves the empty set. Whether the *value* is real is a
   different question, `solve(im(f) == 0, x)`. Scattered domains are
   answers (intervals plus or minus affine families: `x**x`, `(-2)**x`,
   `gamma` of a linear argument).
3. **`solve` is complete over `CC`.** `exp(u) = v` is
   `log(v) + 2*pi*i*k`, and several exponentials go through a common
   measure. `domain: RR` keeps the real members of a family whose step is
   not real. Every internal caller that means the real line passes
   `domain: RR`; callers that want one period pass `principal: true`.
4. **Karr's convention** [Kar81] for reversed sums and products:
   `sum(f, k, a, b)` is `-sum(f, k, b + 1, a - 1)` for `b < a - 1`, so
   `sum(k, k, 5, 1)` is -9, and the telescoping identities hold for all
   bounds.
5. **Coordinates are named.** Vector calculus uses the given list, or the
   free names when they are among `x, y, z`, or - for a field in names of
   its own - as many names as components; anything else is an error
   naming the extra symbol.
6. **An antiderivative lists its special parameter values.** The public
   `integrate` returns a `Piecewise` over the values where a denominator
   free of x vanishes, each integrated again:
   `integrate(cos(a*x), x)` is `piecewise(a.eq(0) => x, :else =>
   sin(a*x)/a)`. `generic: true` gives the short form; internal callers
   use the generic `Integrate.integrate`.
7. **Log rules need proved positivity.** `expand_log` and `logcombine`
   split or join only factors proved positive and take `force: true` for
   the textbook manipulation. Callers whose results are verified
   afterwards (the logarithmic equations in `solve`) pass it.
8. **No domain claim where there is no value.** `1/x` for real x has no
   inferred domain until `x != 0` is known (`Infer.nonzero?`); matrix and
   vector constructors ask the weaker question, real where defined
   (`Infer.where_defined { }`).

Printing and normal forms follow two smaller rules: an affine family over
`ZZ` is written with a positive step and, when possible, a base in
`[0, step)` (`Solve.normal_family`), so equal solution sets print alike;
and a negative number on the right of a sum prints with the other sign
(`x + 7/10` rather than `x - (-7/10)`), which changes printing only.

### Proofs, not samples

The common failure of a CAS built from heuristics is an exact rewriting
justified by a few numeric samples. rcas's rule is that an exact
statement needs a proof; samples may *veto* a claim, never establish it.

- **`Decide` is the only numeric decision procedure.** No module keeps a
  private tolerance. `nil` means undecided and must be handled as such.
- **The Float route carries an error bound** (`Decide.float_bound`):
  exact inputs half an ulp, sums add absolute errors, products relative
  ones, a function its slope over the interval times the argument's
  error. Near a pole or jump of an evaluated function (`Decide::SINGULAR`)
  there is no bound, and within the error nothing is concluded. A
  constant whose Float evaluation cancelled is taken again in arbitrary
  precision.
- **Certified digits.** `Precision.evalf` reports the digits two working
  precisions agree on, raising the guard digits (`Precision::GUARDS`)
  until that is what was asked for; a value that looks like 0 must be
  proved 0 by `Decide`, or the call ends in `NoConvergence` saying how far
  it got. An expression with a Float leaf has no exact value to prove,
  and there 0 is an honest answer.
- **A sign on an interval** (`Analysis.sign_on_interval`) is proved: a
  continuous function keeps its sign on an interval in which it has no
  zero, so `solve` names all zeros (complete, families counted out), and
  there must be no pole, jump or edge of the real domain inside. On a box
  of several variables the sign comes from an interval enclosure
  (`Analysis.enclosure`), or factor by factor. Radii of solids of
  revolution, length elements and `abs` removal depend on this.
- **Inflections and extrema by order of vanishing**: derivatives are
  taken until one is decided non-zero; odd order at an inflection
  candidate means a sign change. An undecided case raises, and `discuss`
  prints it as "not determined".
- **"Cannot" is never "none".** An equation that cannot be inverted
  raises instead of returning `[]`; `nintegrate` never counts an
  undefined sample as 0; a truncated search raises rather than reporting
  what it found as complete. rcas's refusals are `RCAS::Unsupported`
  (a `StandardError`); a broad rescue must not turn one into an empty
  answer.
- **Poles are read off the equation as written**, before simplification:
  `solve((x**2 - 1)/(x - 1), x)` does not return 1. Families and identity
  sets are cut the same way.
- **Complete, not principal, where the answer is used as all of them**:
  the poles inside a definite integral, the kinks of `abs`, the
  breakpoints of a piecewise function, the rows of `discuss` for a
  non-periodic function. A periodic function is discussed over one
  period of *its own* period, computed from complete solutions.
- **Periodicity and conservativity are identities**, `f(x + T) = f(x)`
  proved and a potential that is its own proof, not agreement at a few
  points.

### Branch cuts

Two rules that look like algebra are statements about branches and are
applied only where they hold:

- `exp(u)**v = exp(u*v)` for integer `v`, or real `u`. Otherwise
  `sqrt(exp(2*pi*i))` would be `exp(pi*i) = -1` instead of 1.
- `log(exp(u)) = u` only on the principal strip `-pi < im(u) <= pi`.
  A rational multiple of `pi` is compared as a rational; any other
  imaginary part is admitted only when `|im(u)| <= 31/10`, which proves
  it inside because `31/10 < pi`.

Both ask whether `u` is real by `Infer.domain(u) <= RR`, so an undeclared
indeterminate is *not* real and `assume(x: RR)` turns the rules on:

```
rcas> log(exp(x)).simplify
=> log(exp(x))
rcas> assume(x: RR) { log(exp(x)).simplify }
=> x
```

The real branches of `asin` and `acos` past `[-1, 1]` are values
(`acos(2.0)` is `-i*acosh(2)`, about `-1.317*i`), not errors, and
`cos(acos(u))` simplifies to `u` for every u while `acos(cos(u))`, which
is `u` only on `[0, pi]`, stays as it is.

## 5. Algorithms and rule chains

Every non-trivial algorithm names its source in its module comment, with
the key used in [MANUAL.md, section 4](MANUAL.md#4-sources).

### Indefinite integration

`Integrate.attempt` splits a sum into terms and pulls out constant
factors, then tries the rules in a fixed order, and the order carries
meaning:

```
table -> trig_product -> IntegralFunctions.antiderivative -> piecewise
  -> rational -> substitution -> by_parts -> Substitutions.radical
  -> Substitutions.gaussian -> heurisch -> Substitutions.root_of_linear
  -> Substitutions.root_of_ratio -> Substitutions.exponential
  -> Substitutions.trigonometric -> shift
```

- The named integrals (`Ei`, `Si`, `Ci`, `li`) come right after the
  table, because `exp(u)/u` and friends have no elementary antiderivative
  and the later rules would only find longer ways to fail.
- `piecewise` runs before `rational`, because an integrand with `abs` or
  `sign` is not a rational function. It returns `sign(u)*(F - F(x0))`
  with `x0` the root of the linear `u`; the constant `F(x0)` makes the
  antiderivative continuous, and without it definite integrals across
  `x0` would be wrong.
- `rational` is exact: Hermite reduction [Her72], [Mac75], then the
  logarithmic part by Lazard-Rioboo-Trager [LR90], [Bro05], and as a
  fallback the real quadratic factors of a biquadratic denominator.
- `by_parts` must not trade down: a `v` carrying `erf` is rejected when
  `dv` carries none, or `x**2*exp(-x**2)` would recurse to the depth
  limit instead of reaching the Gaussian moment rule.
- `heurisch` is the Risch-Norman parallel heuristic [NM77], [GS89].
- An integrand rcas cannot differentiate (`floor`, an unknown function)
  stays formal; a rule that differentiates a subexpression must keep that
  promise. A definite integral inside the integrand that depends on x
  also leaves the integral formal, because every differentiating rule
  would add a layer for ever.

### Definite integrals

`Integrate.definite` is not `F(b) - F(a)`. The range is split at every
pole strictly inside (the denominators and their factors, the zeros of
`cos(u)` under a `tan`) and at every jump of the antiderivative (the
Weierstrass substitution puts `tan(x/2)` into it, which breaks where the
integrand is smooth). Each piece is evaluated with one-sided limits at
its interior ends, and `+oo` plus `-oo` is `undefined`. Families of
breakpoints are counted out between the bounds; when they cannot be
(more than `Integrate::MAX_BREAKS` = 128 for the whole range, a second
parameter, an unmeasurable step), the answer is "unknown", not "no
breaks". A pole whose zeros cannot be named but whose denominator changes
sign keeps the integral formal. When a piece comes out non-real, as
`log(cos(x))` past `pi/2` does, the pieces are taken again with
`log|u|` - but only where the integrand is proved real on the range.

### Hypergeometric summation

The chain follows Koepf's book [Koe14] and [PWZ96]: **Gosper** [Gos78]
decides indefinite summation; **Zeilberger** [Zei91] runs Gosper on a
pencil `sum_j sigma_j F(n + j, k)` and gets a recurrence for a definite
sum; **Petkovsek** [Pet92] solves the recurrence in hypergeometric
terms; polynomial solutions with Abramov's degree bound are the common
subroutine. Each has a q-twin with `x = q**k` in place of `k` [Koo93],
[GR04].

- The sigmas stay linear. The pencil's term ratio has the shape
  `r(k)*D(k)/D(k+1) * N(k+1)/N(k)` with `N` linear in the sigmas, so the
  Gosper-Petkovsek normal form is sigma-free, and Gosper's equation is
  linear in the unknown polynomial's coefficients and the sigmas
  together: one null space gives both.
- That null space is computed by evaluation and interpolation
  (`PolyMatrix.kernel`), because elimination over rational functions of
  n swells beyond use. Row reduction over rational functions also needs
  cancellation at every step: `Scalar.zero?` on an uncancelled
  `q + q*(q - 1)/(1 - q)` does not see zero.
- The certificate is assembled in the polynomial ring with one gcd, not
  as an expression to be cancelled (milliseconds against minutes).
- Creative telescoping proves an identity under the summation sign; the
  natural boundaries are not automatic. `sumrecursion` checks the
  recurrence against the sum for the first few n and refuses when the
  residue is demonstrably non-zero.
- `sum` calls Zeilberger with order 1 only: a hypergeometric closed form
  satisfies a first-order recurrence. `sumrecursion` goes to order 4.
- Petkovsek's terms start past the singularities of the ratio, so
  `u(n + 1) = n*u(n)` gives `(n - 1)!`.

**Formal power series** follow Koepf [Koe92]: holonomic differential
equation by undetermined coefficients, the coefficient recurrence, the
two-term (hypergeometric) case, assembly. The ansatz splits each
derivative by monomials in the transcendental atoms and asks each to
cancel on its own, which is sufficient and never spurious. Denominators
are cleared by one lcm in the polynomial ring, null spaces go through
`PolyMatrix.kernel`, and the coefficient is offered as factorials, as
binomial coefficients and as a product, the first form that reproduces
the Taylor coefficients being kept. `fps` refuses series whose
coefficients are not hypergeometric (`tan`) rather than guess.

### Polynomial factorization

Over `ZZ`: squarefree decomposition [Yun76], factorization modulo a
prime by Cantor-Zassenhaus [CZ81], Hensel lifting of the non-monic
polynomial (the monic transformation produced coefficients of hundreds
of digits), and recombination. Recombination is by subsets [Zas69] while
the number of subsets of the next size stays within
`VanHoeij::SUBSET_BUDGET` (50000), and then by lattice reduction on the
traces of `f*g'/g` [vHo02], [HvHN11], bounded through Fujiwara's root
bound [Fuj16], with the lifted factors handed over rather than lifted
again. A threshold on the *number* of local factors was measured and
rejected: products of small factors are faster by subsets at every size
tried, because the true factors appear among pairs and triples; what
makes subsets explode is the size of the subsets the true factors need,
as for products of translated Swinnerton-Dyer polynomials. Multivariate
polynomials go through Kronecker substitution [Knu98, §4.6.2], which does
not preserve squarefreeness, so the image is factored completely and
recombined by index. Over `QQ(alpha)` factoring is Trager's norm method
[Tra76].

### Exact linear algebra

- **Products** of Integer or Rational matrices run on the bare numbers
  after scaling rows and columns by their denominators (fifteen times
  faster than entry-by-entry arithmetic on nodes). Strassen's algorithm
  in Winograd's form [Str69], [Win71] is used from n = 192 for
  machine-word entries (leaves of 48) and from n = 64 past 62 bits
  (leaves of 16), never for symbolic entries, whose products expand.
- **Determinant, inverse and square systems** of Integer and Rational
  matrices are computed modulo primes below `2**31` and recombined by
  the Chinese remainder theorem, with the number of primes from
  Hadamard's bound [Had93], so the answer is a proof. Solve and inverse
  may stop early after rational reconstruction, accepted only if
  `A*N = d*B` holds exactly - without the check a too-small modulus
  reconstructs a wrong fraction. The determinant always takes the bound.
- **One square system** from n = 32 goes through Dixon's p-adic lifting
  [Dix82]: the inverse modulo one prime, then lifting digit by digit,
  reconstruction tried at steps 4, 8, 16, ...
- **Symbolic matrices** use evaluation and interpolation for
  determinants and kernels (`PolyMatrix`), falling back to elimination.
- **LLL** is exact, in Cohen's formulation [Coh93, §2.6], [LLL82], with
  the Gram-Schmidt data updated rather than recomputed.

### Other parts worth knowing

- **Limits** go through Puiseux series with log terms, a squeeze rule
  for bounded factors, and rewriting through `exp` and `log`; they are
  the textbook strategy, not Gruntz's algorithm [Gru96].
- **Linear programs** are solved by the two-phase simplex method
  [Dan63] with Bland's rule [Bla77] in exact rationals, integer programs
  by branch and bound [LD60].
- **Float polynomial roots** of degree above 2 use Durand-Kerner
  [Ker66], with clusters of nearby roots merged into one multiple root.
  This is the one place thresholds are heuristic, because the input is a
  Float and there is no exact answer to decide against; exact
  coefficients never come here.
- **OpenMath** [OM19] is an object model with XML and POPCORN [HR09] as
  two encodings of it; one phrasebook table maps both directions, and a
  symbol with no row survives the round trip as a held function.

## 6. Implementation notes and traps

These are mistakes that have been made in this code base and are easy to
make again.

**Ruby semantics**

- `1/2` is 0 and `2**(1/3r)` is a Float before rcas runs. Use `1/2r`,
  `root`, `cbrt`, or `hold { }`.
- `NotImplementedError` is a `ScriptError`, not a `StandardError`; a
  bare `rescue` does not catch it. rcas's refusals are
  `RCAS::Unsupported < StandardError`. Inside `module Precision` a bare
  `Unsupported` is `Precision::Unsupported`; write `RCAS::Unsupported`.
- `Math.log(-1.0)` and `Math.asin(2.0)` raise `Math::DomainError`; the
  function layer computes the complex value instead.
- `Math.respond_to?(name)` is not a guard: including `RCAS::Functions`
  into Object gives the `Math` module a `floor`, and folding recursed.
  Compare against `Functions::MATH_NAMES`.
- `Hash#inspect` changed in Ruby 3.4 (`{x => 1, a: 2}`). Tests compare
  hash output through `TestSupport.hash_style` on both sides.
- `filter_map` drops `false` as well as `nil`; a block that returns a
  boolean sign loses the negative ones. Map to symbols.
- `return x if (x = ...)` is a NameError (the body is parsed first);
  `@x ||=` fails on frozen objects; `a, b = f or return` is a syntax
  error.
- `Integer#to_f` past `2**1024` is Infinity with a warning; check
  `bit_length` first.
- A Rational accumulated term by term is slow where bignum gcds are
  slow (`ChiSquare(10**4).cdf(10**4)` took a minute under one Ruby);
  sum Integers over one common denominator.
- `RubyVM::AbstractSyntaxTree.of` does not work on a Prism-compiled
  block (Ruby 3.4+ default). `hold` cuts the block's source out by the
  instruction sequence's code location and re-parses it; a block without
  readable source is refused, never run.

**Numerics**

- A sign test is never a product: `a*b > 0` underflows to 0 for two
  values near `1e-165`. Compare signs (`Numerics.same_sign?`).
- Never write a private tolerance for a decision; ask `Decide`.
- `nintegrate` compares its bounds exactly: `10**20` and `10**20 + 1`
  are the same Float, and a width of `10**-400` underflows.
- The tanh-sinh abscissa is measured from the near end, or the digits an
  endpoint singularity needs cancel away; every `exp` in the doubly
  exponential maps is guarded, because BigMath grinds for ever on
  arguments like `10**160`.

**Data structures**

- Hash writes that should merge: on a factor table that may already hold
  a base use `Simplify.add_factor`, never `factors[b] = e` (`i*i**(1/2)`
  lost a factor that way).
- `Expand.table` returns a pair; destructure it.
- A module method named `hash` replaces `Module#hash` and breaks every
  Hash keyed by the module (`LaTeX.table`, not `LaTeX.hash`).
- A solution keyed by indeterminates is an `Assignment`, so that
  `sol[:x]` and `sol[x]` both work; a plain Hash keyed by nodes answers a
  Symbol key with nil.
- `Polynomial#content` is positive; `.abs` on a Complex is a magnitude,
  never a sign fix.
- A polynomial over `Frac(QQ[a])[x]` times a parameter expression must
  not make `a` a new ring variable (`Polynomial#scalar_in_base`).

**Algorithms**

- `Polynomial#coeff(k)` takes an exponent vector. In a ring of several
  variables the coefficient of a power of one of them is
  `coefficient_in(var, k)`; reading `coeff(k)` there left a
  characteristic polynomial in `QQ[x, _l]` with no eigenvalues.
- `cancel` treats a radical as an atom, so a zero that depends on
  `B**(1/q)` for a non-constant `B` is invisible to it.
  `Scalar.radical_zero?` replaces each radical by a new indeterminate `t`
  and reduces the numerator modulo `t**q - B`; a zero remainder is a
  proof, since every branch of the radical satisfies that equation.
- Hensel lifting needs a prime not dividing the leading coefficient.
- The primitive PRS loses resultant factors where a gcd degree jumps; the
  Rothstein-Trager resultant is the Sylvester determinant.
- `Array#-` removes all duplicates; recombination works by index.
- `acos` is neither odd nor even (`acos(-u) = pi - acos(u)`).
- Folding a number back into a coefficient must skip the imaginary unit,
  or `i` disappears into a Complex coefficient.
- `evalf` can come back symbolic when folding restores an exact constant
  after floatification (`exp(-1.0)` is `1/e` again); it makes one more
  pass and keeps it only if that ends in a number.
- `[from, *nil, to]` is `[from, to]`: a function that says "unknown" with
  `nil` must be tested before its result is splatted.

**Tests**

- Minitest collects public methods only: a test appended after `private`
  never runs. Check the run count when adding to a file with helpers at
  the bottom.
- Never `include RCAS::Functions` in a test class: `Functions#diff`
  overrides `Minitest::Assertions#diff`, and the first failing assertion
  dies while formatting its message. Write `RCAS.sin(x)`.
- Tests that call `assume` must `forget` in a teardown, or use the block
  form, which cannot leak.
- `assert_in_delta`'s third argument is the tolerance, not the message.
- The suite must run from a path containing a space, under a tty as well
  as piped, and without warnings under `-w`.

## 7. Contributing a feature

1. The algorithm goes in its own module under `lib/rcas/`, in
   `module_function` style, required from `lib/rcas.rb` after its
   dependencies.
2. The top-level function goes in `functions.rb` with a one-line doc
   comment; `doc(name)` and the chat's `/help` show it, and the docs test
   fails without it. Keyword forms follow the existing ones:
   `f(expr, x: 0..1)`, `x: 0`, `n: 6`, an endless range for infinity.
3. A new expression node class needs cases in the printer, `latex.rb`,
   `Differentiate`, `Infer.domain`, `evalf`, `evaluate`, `Hold::FORMAL`
   if it should stay formal inside `hold`, and a row in
   `openmath/phrasebook.rb` - the OpenMath test enumerates every
   expression class and fails without one.
4. A new numeric type inside `Num` needs `Simplify.normalize_number`,
   `pow_number`, the printer's precedence hook, `Scalar` and `Infer`.
5. Tests: exact strings for representative outputs, plus a property check
   wherever there is one - integrals are differentiated and compared
   numerically, ODE solutions substituted, sums evaluated at small n, the
   theorems of vector calculus checked against the integrals they relate.
6. A manual section with transcripts, a row in the reference table, and
   an entry in the "not implemented" list where the feature stops short.
7. The source of the algorithm, cited in the module comment with a key
   and listed in [MANUAL.md, section 4](MANUAL.md#4-sources).

A broad `rescue StandardError` in mathematical code calls
`RCAS.guard!(e)` first: under `RCAS_STRICT=1` (set by the Rake task) it
re-raises `NoMethodError` and `NameError`, so a bug cannot be mistaken for
"no answer", and it always passes on `RCAS::Unsupported`, so a refusal is
not turned into an empty result.

**Running the tests.** `ruby -S rake` runs the whole suite;
`ruby -Ilib -Itest test/solve_test.rb` runs one file;
`ruby -S rake TESTOPTS="--seed=1"` fixes the order. **MANUAL.md is
executable**: `test/manual_test.rb` runs every `rcas> ` line of it in a
session that behaves like `bin/rcas` and compares the `inspect` output
with the `=> ` lines (continuation lines indented three spaces). When an
output format changes, the code or the manual is changed deliberately;
the comparison is never loosened. Locals persist across all code blocks
of the manual, so new transcripts use fresh names, and transcripts that
use random objects seed at the top of their own block.
`ruby -S rake toc` regenerates the manual's table of contents.

## 8. Layout

| file | contents |
|---|---|
| `expression.rb` | the tree: `Var Num Const Neg Add Sub Mul Div Pow Fn`; lift, subs, evalf, evaluate |
| `printer.rb`, `latex.rb` | text with minimal parentheses (valid Ruby apart from bare names); LaTeX |
| `simplify.rb`, `expand.rb` | canonical form and term tables; distribution with like-term merging |
| `decide.rb`, `scalar.rb` | the numeric decision procedure; entry arithmetic and zero tests |
| `precision.rb` | arbitrary-precision evaluation over BigDecimal, certified digits, tanh-sinh quadrature |
| `domains.rb` | number sets, assumptions, `Infer`, polynomial rings, fraction fields |
| `polynomial.rb`, `gcd.rb`, `factor.rb`, `van_hoeij.rb` | ring elements, gcd by PRS, factorization and recombination |
| `fraction.rb`, `rational_function.rb` | rational normal form, partial fractions |
| `algebraic.rb`, `finite_field.rb`, `number_theory.rb` | algebraic numbers and fields, `GF(p**n)`, integers |
| `groebner.rb`, `lattice.rb` | Buchberger's algorithm; LLL |
| `differentiate.rb`, `integrate.rb`, `integrate_substitutions.rb`, `integral_functions.rb` | derivatives; the integration rule chain; `Ei Si Ci li` |
| `series.rb`, `fps.rb`, `fourier.rb` | Puiseux series and limits; formal power series; Fourier series |
| `summation.rb`, `zeilberger.rb`, `petkovsek.rb`, `poly_recurrence.rb`, `product.rb` | sums, creative telescoping, recurrences, products |
| `q_functions.rb`, `q_summation.rb`, `q_zeilberger.rb`, `q_difference.rb` | the q-analogues |
| `solve.rb`, `inequalities.rb`, `piecewise.rb` | equations and systems, inequalities and real sets, piecewise functions |
| `analysis.rb`, `discussion.rb`, `vector_calculus.rb` | real analysis, curve sketching, line and surface integrals |
| `ode.rb`, `recurrence.rb`, `laplace.rb` | differential equations, recurrences, the Laplace transform |
| `matrix.rb`, `vector.rb`, `matrix_multiply.rb`, `multimodular.rb`, `dixon.rb`, `poly_matrix.rb`, `decompositions.rb`, `linear_algebra.rb` | linear algebra |
| `linear_program.rb`, `geometry.rb`, `statistics.rb`, `distributions.rb`, `hypothesis.rb` | optimization, plane geometry, statistics |
| `hold.rb`, `steps.rb`, `docs.rb`, `background.rb` | `hold`, worked solutions, documentation and its background texts |
| `plot.rb`, `plot3d.rb`, `render.rb` | text and picture plots, typesetting |
| `openmath.rb`, `openmath/` | OpenMath objects, XML, POPCORN, the phrasebook |
| `functions.rb`, `core_ext.rb`, `constants.rb` | the top-level functions, operators on Symbol and Numeric, constants |
| `irb.rb`, `results.rb`, `chat.rb`, `chat/`, `app.rb`, `app/` | the three front ends: irb, the terminal chat, the window |

All paths are under `lib/rcas/`.
