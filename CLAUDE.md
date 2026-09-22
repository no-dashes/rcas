# CLAUDE.md - working notes for Claude sessions on rcas

rcas is a computer algebra system written in plain Ruby (3.3, standard
library only) that uses irb as its REPL. This file records what a session
needs to know that is not obvious from the code: vocabulary, design
invariants, workflow, and the traps we have already fallen into. Keep it
current when you change any of these. It is gitignored for now.

## What the user wants

> "I want rcas to be the CAS I wished I had, when I was an undergraduate."
> (the user, Sept 2026)

That is the test for every feature: would it have helped a student who is
learning the mathematics, not just someone who wants the answer? Hence the
honest unevaluated nodes, the exact arithmetic, the `maths:`/`method:`
background in `doc`/`/help`, and the manual full of worked transcripts.


- A CAS that *extends Ruby* rather than inventing a language: Ruby symbols
  are the indeterminates, Ruby operators build expression trees, irb (and
  `bin/rcas-chat`) is the front end. No new parser, no new REPL.
- MuPAD is the main inspiration (`hold`/`eval`, domains), then Maple,
  Mathematica, Sage and a little Axiom. When a design question comes up,
  the user appreciates a serious comparison with those systems, not
  flattery. Structurally rcas is closest to Sage (host-language variable
  holds the algebraic object).
- Audience: school, high school and undergraduate mathematics. Exactness
  first (Integer/Rational, algebraic numbers), numerics as a fallback that
  is labelled as such.
- Outputs must be honest: unevaluated nodes (`integral(...)`, `sum(...)`,
  `limit(...)`, `RootOf`) rather than wrong or silently numeric answers.

## Vocabulary (settled with the user; use it consistently)

- **Double-struck sets**: `ℕ ℤ ℚ ℝ ℂ` are *constants* (Ruby reads them as
  uppercase letters, so a method would never be called), defined in
  domains.rb next to NN..CC and in `Sets`. `RCAS.unicode = true` (chat:
  `/unicode on`, env `RCAS_UNICODE=1`) makes `Domain#to_s` and `Const`
  print ℤ/π/∞; default off, so the manual and the tests stay ASCII.
  `LaTeX` reads `dom.name`, not `to_s`, so typesetting is unaffected.
- **Symbol**: the Ruby object `:x`. Any Ruby identifier qualifies,
  Unicode included (`α`, `β₁`, `∞`); the shared pattern is
  `RCAS::IDENTIFIER` (used by irb, the chat workspace and `hold`). `π`/`∞`
  are bare aliases of `pi`/`oo`; printing stays ASCII.
- **Indeterminate**: the role a symbol plays inside an expression or ring
  (`x**2 - 1`, `ZZ[x]`). This is the word for the mathematics. Not
  "variable", not MuPAD's "identifier".
- **Variable**: a Ruby binding (`e = (x + 1) * (1 - x)`). In `bin/rcas` a
  bare undefined name evaluates to its symbol and is stored in a Ruby
  variable of the same name (`RCAS::IRB::AutoSymbol`).
- **Unknown function**: `u(n + 1)`, `f(x)`: a `Fn` whose name is not a
  built-in function. In both front ends an undefined name applied to
  expressions or numbers builds one (`RCAS.unknown_function`); `rsolve`
  reads recurrences written this way. `dsolve` still uses `D(y, x)`.
- **Parameter**: an indeterminate that is not the one being solved,
  integrated or summed for (`a` in `solve(x**2 - a >= 0, x)`).
- **Image set**: `{pi/6 + 2*pi*k | k in ZZ}`, the answer `solve` gives an
  equation with infinitely many solutions (20 Sept 2026, the user's call
  after the review asked what `solve(sin(x))` should be). `ImageSet` is not
  an Expression - like `Equation`, `Inequality` and `Membership` it is a
  statement about them - and it carries the parameter's domain, which is
  what lets `set.map { }` fold `sin` of a member to 1/2 without the reader
  declaring anything. `solve` is complete by default now; `principal: true`
  (or the older `all: false`) asks for one period, which is what every
  caller inside rcas wants - `discuss`, `Analysis`, `Piecewises`, `steps`
  and the sign charts all pass it. `restrict` can decide a family against a
  declared domain where the members are rational multiples of pi, since pi
  is transcendental: `{2*pi*k | k in ZZ}` meets ZZ in 0 alone and
  `{pi + 2*pi*k | k in ZZ}` not at all. `merge_families` then folds the
  families of one period together - it compares each offset as a fraction
  of the step, so `{pi/2 + 2*pi*k}` and `{3*pi/2 + 2*pi*k}` become
  `{pi/2 + pi*k}`, and `{2*k}` with `{1 + 2*k}` becomes `ZZ` - and
  `roots_of_unity` gives `(-1)**x = 1` the even integers rather than 0
  alone (all three: 20 Sept 2026, the seventh pass of the review).
  `homogeneous_trig` divides an equation whose terms all have the same
  degree in `sin(u)` and `cos(u)` by `cos(u)**n`, which makes it a
  polynomial in `tan(u)`: that is `sin(x) + cos(x) = 0`, and the zeros of
  `cos(u)` go back in when no term is a pure power of `sin(u)`.
  Three more pieces came out of the ninth pass of the review (20 Sept
  2026). `homogenize` raises a term short of the top degree by an *even*
  number to it with `sin**2 + cos**2 = 1`, which is `sin(x)*cos(x) = 1/2`
  read as `tan(x) = 1` - the trick the identity is taught for; an odd gap
  (`sin(x) = 1/2`) has no such reading and the rule declines, leaving the
  equation to the atom substitution that already answers it. `invert`
  refuses `tan(u) = i` and `tan(u) = -i` (`unreachable?`): those are the
  two values the tangent omits from the whole complex plane, which is also
  why `atan(i)` has no value, and without the guard
  `solve(sin(x)**2 + cos(x)**2, x)` answered an equation with no solutions
  by two families built on `atan(+-i)`. It is a *range* test, not a
  complex-root test: `cos(x) = 2` keeps its families, because the cosine
  does reach 2. And when every rule has failed, `trig_constant` asks
  `trigsimp` whether the equation was an identity after all
  (`sin(x)**2 + cos(x)**2 - 1` is every x, and `Scalar.zero?` at the
  funnel cannot see it) or a contradiction (`... + 1` is `[]`); it runs
  only on the failure path, because trigsimp costs milliseconds and
  `discuss` calls `solve` for every row it fills.
- The API method `Expression#variables` returns the indeterminates; the
  name follows CAS convention and stays. The manual notes this once.
- **domain and base** (settled 17 Sept 2026, after "`(ZZ**[2,2]).random.domain`
  answers ZZ. Shouldn't it be ZZ**[2,2]?"): a *value* answers `domain` with
  the smallest domain rcas knows it to lie in - its ring, space or field,
  and for an expression the inferred number set (nil when unknown, the one
  soft case, because a tree has no parent object). A *structure* answers
  `base` with the domain its entries come from: `ZZ[x].base`,
  `(ZZ**[2, 2]).base`. `space`, `ring` and `field` stay as the precise
  accessors, and `Matrix#base`/`Vector#base`/`Polynomial#base` are the
  shorthand for `domain.base`. Before this, `Matrix#domain` meant the
  entries' domain and a Polynomial had no `domain` at all.

## Layout

```
lib/rcas.rb                 requires everything (order matters: see below)
lib/rcas/expression.rb      Expression tree: Var Num Const Neg Add Sub Mul Div Pow Fn; lift, subs, call, evalf, doit/evaluate
lib/rcas/printer.rb         to_s with minimal parentheses (output is valid Ruby apart from bare indeterminates)
lib/rcas/simplify.rb        canonical form: termize/factorize tables, rebuild_sum/rebuild_product, number folding
lib/rcas/expand.rb          distribution on term tables with like-term merging (Expand.table is used everywhere)
lib/rcas/differentiate.rb   derivative rules
lib/rcas/integrate.rb       rules (table, abs/sign, parts) -> exact rational (Hermite, LRT, then real quadratic factors of a biquadratic denominator) -> Risch-Norman heuristic; Integral node
lib/rcas/integrate_substitutions.rb  Integrate::Substitutions: R(x, sqrt(quadratic)) reduction, roots of linear forms and of ratios of them (Moebius), exp, tan(x/2); hooked into Integrate.attempt
lib/rcas/series.rb          Puiseux series with log terms, limits (squeeze rule for a bounded factor, `dominant` for a sum whose other terms are bounded, of strictly smaller order, or vanish in the quotient), Limit node, OO
lib/rcas/fourier.rb         Fourier.series: partial sums and the general coefficient (the index is assumed integer while the coefficient integrals run), half-range :sine/:cosine
lib/rcas/integral_functions.rb  Ei Si Ci li: Fn nodes, exact values, derivatives, the integration rule, Floats by series/continued fraction
lib/rcas/fps.rb             FPS: Koepf's formal power series. Holonomic differential equation by undetermined coefficients, coefficient recurrence, the two-term (m-fold symmetric hypergeometric) case; behind fps() and series(formal: true)
lib/rcas/summation.rb       Faulhaber, Gosper, zeta, classical series; Sum node; sum 1/k => harmonic(n); Summation.normal_form is the Gosper-Petkovsek form Zeilberger reuses
lib/rcas/poly_recurrence.rb PolyRecurrence: polynomial solutions of sum_j q_j(n) c(n + j) = rhs, Abramov's degree bound through the Delta basis
lib/rcas/petkovsek.rb       Petkovsek: hypergeometric solutions (ratios and closed forms) of a recurrence with polynomial coefficients; rsolve falls back to it
lib/rcas/zeilberger.rb      Zeilberger: creative telescoping, Certificate struct, sumrecursion/sumcertificate, closed_form (hooked into Summation.sum)
lib/rcas/q_functions.rb     QFunctions: qpochhammer/qbracket/qfactorial/qbinomial as Fn nodes, folding, to_pochhammer/align/merge_pochhammers for the algorithms
lib/rcas/q_summation.rb     QSummation: term ratios as rational functions of X = q**k, q-Gosper (qgosper/qsum), q-dispersion, and linear_solve (a cancelling rref)
lib/rcas/q_zeilberger.rb    QZeilberger: creative telescoping with X = q**k and Y = q**n; qsumrecursion/qsumcertificate
lib/rcas/q_difference.rb    QDifference: linear q-difference equations, q-Petkovsek; qsolve reports at x = q**n, qhyper gives the ratios
lib/rcas/product.rb         Products: factorial/gamma ratios for linear factors, a**sum(u), direct products; Product node
lib/rcas/recurrence.rb      Recurrence.rsolve: u(n + k) as Fn(:u), characteristic roots, undetermined coefficients, init: values
lib/rcas/complex_parts.rb   ComplexParts: re/im/conj/arg by expansion; variables are real only when assumed so
lib/rcas/statistics.rb      Statistics: mean/median/mode/variance(sample: n-1)/quantile (HF96 type 7)/moments/covariance/correlation/linreg, exact and symbolic
lib/rcas/distributions.rb   Distributions::{Normal Uniform Exponential Bernoulli Binomial Poisson Geometric DiscreteUniform StudentT ChiSquare FRatio}: pdf cdf quantile moments probability expectation sample; not Expressions (to_latex hook)
lib/rcas/random.rb          Randoms + a `random` method on NumberSet/PolynomialRing/FractionField/VectorSpace/MatrixSpace/FiniteField/AlgebraicField (reopened there, as decompositions.rb reopens Matrix); `RCAS.random` is the session's source and `RCAS.random = 42` pins it (Distributions#sample defaults to it too)
lib/rcas/special.rb         Special.gamma_p/gamma_q/beta_i: incomplete gamma and beta, Floats only (series + Lentz continued fractions)
lib/rcas/precision.rb       Decimal (a Numeric that carries its digit count) and Precision.evalf(expr, digits): the tree walked in BigDecimal/BigMath with GUARD=10 guard digits. Also erf/Si/Ci/Ei/li by series (with adaptive guard digits for the cancellation, MAX_CANCELLATION), zeta by Euler-Maclaurin over Summation.bernoulli, euler_gamma by Brent-McMillan, quadrature by tanh-sinh (three maps: finite, exp_sinh, sinh_sinh) and refine for roots. nsolve/nintegrate take digits: and come here; Unsupported names whatever is left
lib/rcas/background.rb      (titles verified against the Wikipedia API 2026-09-14; re-check with
                            ruby -Ilib -rrcas -rnet/http -rjson -e 'RCAS::Background::READING.values.flatten.uniq.each_slice(40) { |b| u = URI("https://en.wikipedia.org/w/api.php"); u.query = URI.encode_www_form(action: "query", format: "json", redirects: 1, titles: b.join("|")); puts JSON.parse(Net::HTTP.get(u))["query"]["pages"].values.select { |p| p.key?("missing") }.map { |p| p["title"] } }')
lib/rcas/background.rb      Background::ENTRIES: { maths:, method: } per name (or a Symbol alias) and READING: Wikipedia article titles (ASCII, spaces not underscores; Docs expands the [Key00] citations from MANUAL's bibliography itself); test/docs_test.rb checks the names exist and the [Key00] sources are in MANUAL's bibliography
lib/rcas/docs.rb            Docs.doc(name) -> Documentation: signature + comment block read from the source, `Docs::NAMESPACES` resolves `Poly.legendre` (and the bare `chebyshev_t` when no top-level function has the name; Background keys them as `"Poly.legendre"`), plus the MANUAL.md headings that mention the name; the chat's /help NAME and the top-level doc() use it. test/docs_test.rb asserts every top-level function has a comment
lib/rcas/plot.rb            Plot (braille canvas, SVG, PNG via Render.which/run + Chrome) and Plotting.plot/parametric/polar/scatter/histogram/boxplot/barchart (Curve markers: line, :dot, :stem, :bar, :box; ylabels/xlabels name the rows and columns); Plot has no to_latex on purpose, so the chat shows the art. `Plot.style` (:text/:image, RCAS_PLOT_STYLE) is the hook the chat's /plotstyle writes; `picture?`/`picture` draw the inline image
lib/rcas/plot3d.rb          Plot3D (a Plot) + Plotting.plot3d: surfaces in space, the graph z = f(x, y) and the parametrized kind. A mesh, a parallel projection (azimuth/elevation), and the faces painted back to front, each erasing its own area before drawing its edges - the depth sort [NNS72], no z buffer. Three decisions are load-bearing: the *terminal* picture is built from a coarser mesh (`terminal_step`), because braille faces two or three dots wide rub out each other's shared edges and the picture comes out speckled; the erase walks the face outline as well as filling it, since a thin face's scanlines round away to nothing; and each axis is scaled to the box on its own for a graph, while a *parametric* surface gets one scale for all three (`equal:`), so a sphere is round
lib/rcas/numerics.rb        Numerics.nsolve (bisection + Newton, and `pole?` on the answer: a sign change across a pole is not a root), nintegrate (bounded adaptive Simpson first, its answer cross-checked against composite Gauss-Legendre - `resonant?`, because Simpson refines by halving and an integrand whose period divides the interval samples the same phase at every level, so sin(x)**2 over 0..100*pi came back as 0; the Gauss panels escalate until the second opinion settles, so a genuinely oscillating integrand is still believed - then Precision.quadrature at 17 digits; `caller_for` refloats a folded exact constant, or the integrand has a hole wherever exp(-1.0) folds back to 1/e), resolve (evalf on a definite Integral)
lib/rcas/analysis.rb        Analysis: critical_points/extrema/inflections/asymptotes/tangent/normal/real_domain, gradient/hessian/jacobian/divergence/curl/laplacian/lagrange, arclength/revolution_volume/revolution_surface. `domain_conditions` is the list real_domain intersects: one per denominator, even root and logarithm, and *two* per `asin`/`acos` (`BOUNDED_INVERSES`, 20 Sept 2026), which is the first condition with an upper bound - `Solve.defined_roots` needed `:<`/`:<=` cases for it
lib/rcas/vector_calculus.rb VectorCalculus: line_integral/surface_integral/flux over a parametrization, enclosed_area, green/stokes/divergence_theorem (each computes the side over the region, the integrals compute the other), conservative?/potential; `norm` takes perfect squares out of the length element with the sign they have on the parameter range
lib/rcas/discussion.rb      Discussion.discuss -> Report: the whole Kurvendiskussion in one object (domain, symmetry/period, zeros, gaps, limits+asymptotes, extrema, monotonicity, inflections, curvature). Every row comes from the function that owns it; nil means undecided and prints as "not determined", [] means none. Monotonicity/curvature by sign chart (three samples a piece); a periodic f is charted over one period. steps(f, x, :discuss) narrates the same report, and `hold`/`steps { discuss(f, x) }` keep the call as `Fn(:discuss, [f, x])` (in `Hold::FORMAL`; `doit` answers it with the Report, which is not an Expression)
lib/rcas/geometry.rb        Geometry::{Point Line Circle} (a line is a*x + b*y + c = 0, normalized) and the constructions; exact coordinates
lib/rcas/linear_algebra.rb  LinearAlgebra: gram_schmidt/project/least_squares, exact
lib/rcas/decompositions.rb  Decompositions + Matrix#lu/qr/cholesky/diagonalize/jordan; the Jordan form from chains of generalized eigenvectors
lib/rcas/laplace.rb         Laplace.transform (table + first shift + multiplication by t) and .inverse (partial fractions)
lib/rcas/hypothesis.rb      Hypothesis: ttest/ztest/chisquare_test/ftest/binomial_test (exact), confidence_interval, proportion_interval; TestResult prints one line
lib/rcas/combinatorics.rb   factorial/binomial/gamma values, factorial cancellation, known power series
lib/rcas/solve.rb           Equation, Solve (polynomial, transcendental, abs/sign by case split + verify, products factor by factor - `product_equation`, whose roots go through `defined_roots` because a factor's root solves the product only where the rest of it is defined, falling back to `Simplify.common_factor` for a product the normal form has multiplied out - systems: linear, lex Gröbner + triangular, resultants for parameters), polynomial_roots (binomial, biquadratic, RootOf); `restrict` drops the answers that contradict the unknown's declared domain or sign (`Infer.excluded?`, `domain:` for one call)
lib/rcas/groebner.rb        Groebner: Buchberger (product criterion), reduce, interreduce, zero_dimensional?; orders :lex :grlex :grevlex
lib/rcas/named_polynomials.rb  Poly: the named families (chebyshev_t/u, legendre, hermite/hermite_prob, laguerre, gegenbauer, jacobi, bernoulli, euler, cyclotomic, swinnerton_dyer, abel, fibonacci, lucas, bell) as coefficient lists, handed back expanded; a namespace, registered in `Constants` (so all three front ends see `Poly`), never bare names - `legendre`/`bernoulli`/`fibonacci` are taken
lib/rcas/interpolate.rb     Interpolate.newton (divided differences over Scalar arithmetic; PolyMatrix keeps its own Rational-only copy)
lib/rcas/inequalities.rb    Inequality, Interval, RealSet (complement/-), Cases, sign charts, Parametric (one-parameter case split)
lib/rcas/piecewise.rb       Piecewise node + Piecewises: first-match branch selection, diff/integrate (continuity constant)/limit/solve per branch, discontinuities/kinks
lib/rcas/ode.rb             Derivative node, dsolve (separable, linear 1st order, const-coeff any order: char. roots, undetermined coefficients, variation of parameters) and systems: dsolve([eqs], [y1, y2], t) via eigenvectors + Jordan chains
lib/rcas/constants.rb       Const (pi, oo, undefined), E = exp(1), I = Num(Complex(0,1)), exact trig values
lib/rcas/domains.rb         NN ZZ QQ RR CC, assumptions, Infer (domain inference, `excluded?`), Membership ("x in ZZ": the statement `hold { x.in?(ZZ) }` keeps, and what `assumptions` lists), PolynomialRing, FractionField
lib/rcas/polynomial.rb      ring elements: {exponent vector => coefficient}
lib/rcas/coefficients.rb    degree/ldegree/lcoeff/tcoeff/coeff/coeffs/collect on expressions (via Expand.table)
lib/rcas/gcd.rb             primitive PRS gcd (multivariate over ZZ/QQ), xgcd, lcm
lib/rcas/factor.rb          Zassenhaus over ZZ (Dense integer arrays), Kronecker for multivariate, Factorization
lib/rcas/fraction.rb        cancel (rational normal form), rationalize
lib/rcas/rational_function.rb  numer/denom (integral normal form), apart (xgcd splitting + p-adic expansion over QQ or Frac(QQ[params])[x]), gcd/lcm/quo/rem/divmod on expressions
lib/rcas/number_theory.rb   integer factor (trial division, Miller-Rabin, Pollard-Brent rho), isprime, next/prevprime, divisors, totient, invmod, chrem; IntegerFactorization
lib/rcas/algebraic.rb       RootOf, AlgebraicField QQ(alpha), AlgebraicNumber, minpoly, Trager factoring
lib/rcas/finite_field.rb    Mod, GFElement, FiniteField GF(p)/GF(p^n), field-generic Cantor-Zassenhaus
lib/rcas/trig.rb            expand_trig, trigsimp (SQUARES: sin/cos and sinh/cosh), expand_log, logcombine
lib/rcas/vector.rb          VectorSpace (QQ**3), Vector
lib/rcas/matrix.rb          MatrixSpace (QQ**[2,3]), Matrix, Elimination (rref, det, cofactor), eigen*
lib/rcas/poly_matrix.rb     PolyDet/RatDet/PolyLinearSolve/nullspace (Horn 2008 ch. 6): degree bound, rational evaluation, Newton interpolation; Matrix falls back to Elimination when it returns nil
lib/rcas/scalar.rb          entry arithmetic with Num fast paths; zero? (exact via Algebraic, then numeric)
lib/rcas/hold.rb            hold { } via RubyVM::AbstractSyntaxTree; sets RubyVM.keep_script_lines = true; a qualified RCAS.integrate(...) call inside the block is treated like the bare one
lib/rcas/steps.rb           Step/Derivation and Steps: worked solutions (diff, integrate, solve, factor, apart, rref, gcd, discuss). Each narrator names the rule and asks the library for the piece, so the working cannot disagree with the answer; the fallback line says no textbook rule applies
lib/rcas/functions.rb       the top-level functions (bare in irb, RCAS.x elsewhere); Functions.fold
lib/rcas/core_ext.rb        Symbol/Numeric operators, Symbol#in/eq/< ...
lib/rcas/irb.rb             bin/rcas setup (AutoSymbol, includes, prompt, In/Out hooks)
lib/rcas/results.rb         In/Out: every input line and its result, numbered (RCAS.numbered puts the number in the prompt)
lib/rcas/openmath.rb        OpenMath: the entry points openmath/from_openmath, Expression#to_openmath
lib/rcas/openmath/objects.rb the thirteen object classes of the standard. An OpenMath object is *not* XML; XML is one encoding of it. Four of the standard's names would shadow a Ruby class in the namespace (Integer Float String Object) and two more are taken (Binding, and Symbol means the indeterminate here), so those are Int Double Text Root Bind ContentSymbol. OpenMath::Error is a node (OME), not an exception
lib/rcas/openmath/xml.rb     the XML encoding, written and read; the reader is hand-rolled over StringScanner because REXML is a bundled gem, not the stdlib
lib/rcas/openmath/popcorn.rb the POPCORN notation [HR09], written and read: the third encoding of the same objects and the one a person types. `Node#to_s` is POPCORN with every symbol written out (arith1.plus($x, 1)), `to_popcorn` the sugared spelling ($x + 1); both parse. Variables carry `$` so a bare name can be short for a symbol - that is the whole trick. Watch the operators that are not ordinary notation: // is nums1.rational, | is complex1.complex_cartesian, .. is interval1.interval, ~ is relation2.approx (not relation1), `!(` builds an OME, and a minus in front of a literal belongs to the literal (-17 is Int(-17), never unary_minus(17)). The precedence *levels* are the published grammar's, but the bracketing follows the operators' association, because the reference implementation's own numbers (plus 70, minus 75) write plus($a, minus($b, $c)) as "$a + $b - $c", which reads back as a different tree
lib/rcas/openmath/phrasebook.rb  the one table, both directions. No expression class carries a to_openmath of its own: one declaration list builds a decode index keyed by [cd, name] and an encode index keyed by node class / Fn name. Symbol names and argument orders were checked against the official CDs (piece1.piece is (value, condition), transc1.log is (base, x), limit1.limit is (point, direction, lambda)). A symbol with no row decodes to a held Fn named "cd.name", and such an Fn encodes back to the symbol, so an unknown document survives the round trip
lib/rcas/latex.rb, render.rb, chat.rb, chat/*   typesetting and the chat front end (see below)
lib/rcas/app.rb             rcas-app: the window front end. A stdlib TCPServer on 127.0.0.1 serves one page and a few JSON routes; App::Window opens a Chromium-family browser with `--app=URL` (borrowed engine, not a bundled one), so closing the window ends the program
lib/rcas/app/worksheet.rb   the session behind the window: Chat::Workspace + Results, every answer a plain Hash cell { n:, input:, kind:, text:, latex:, svg:, stdout:, hint: }; it borrows Chat::UI#text_of/#typesettable? and Chat::Usage.hint rather than restating those rules
lib/rcas/app/server.rb      the HTTP server: loopback only, a per-run token in the X-RCAS-Token header, and a Host check against DNS rebinding. Static assets are free, every added route needs the token
lib/rcas/app/window.rb      finding the browser (Render::KaTeX::CHROME_CANDIDATES plus the Windows paths) and the --app/--user-data-dir flags
lib/rcas/app/launcher.rb    --install/--uninstall: .app bundle (macOS), .desktop (Linux), Start-menu shortcut (Windows)
lib/rcas/app/public/        index.html, app.css, app.js: the worksheet
bin/rcas, bin/rcas-chat, bin/rcas-app
test/*_test.rb              minitest; test/manual_test.rb runs every `rcas>` transcript in MANUAL.md
test/app_test.rb            the window front end: worksheet cells, the server (including the token, Host and traversal guards), the browser flags, the desktop entries
MANUAL.md                   the user manual (usage); README.md (setup only); assets/ (logo)
```

## Core design invariants (do not break these)

1. **Construction never rewrites.** `(:x + 1) * (1 - :x)` is stored and
   printed exactly as written. Rewriting happens only on request:
   `simplify`, `expand`, `factor`, `cancel`, `diff`, ... The one exception:
   a *function applied to a constant argument* folds at construction
   (`sin(PI/6)` is `1/2`, `sqrt(-4)` is `2*i`), because Ruby itself folds
   `1 + 2`; operator expressions on constants (`I**2`) still wait for
   `simplify`. `Functions#sin` etc. implement this; `Fn.new` does not fold.
2. **`==` is structural**, `eql?`/`hash` too (hash keys, `subs` patterns
   rely on it). The hash is computed in the constructor before the node is
   frozen and combined by hand, no array: a node is built far more often
   than it is hashed, and recomputing walked the whole subtree every time.
   A new node class that sets no `@hash` falls back to that walk. **Mask
   the combination with `Expression::FIXNUM`**: `left.hash * 31 +
   right.hash` grows about five bits per level, and without the mask the
   hash of a 20000-term sum was a 99000-bit integer and the sum 390 MB
   (found by the second pass of the review, 19 Sept 2026;
   `performance_test` asserts `hash.bit_length <= 64` now, because the
   regression showed up in neither the clock nor the object count - a
   bignum is one object).
   Mathematical equality = compare canonical forms, or
   `Scalar.zero?(a - b)`. Inside `hold { }`, `==` builds an `Equation`,
   `!=` an `Inequality` and `in?` a `Membership` - three
   statements that are not Expressions and each need their own row in
   latex.rb and the OpenMath phrasebook (relation1.eq, relation1.lt...,
   set1.in).
3. **Canonical form** (`Simplify`): sums ordered by ascending degree,
   constant first (Mathematica style: `1 + 2*x + x**2`), then graded
   lexicographic; factors ordered Num, Const, Var, Fn, sums; `i` first.
   Sums longer than `Simplify::CHAIN` (32) are built as *balanced trees* of
   chains so recursion depth stays logarithmic. `termize`/`factorize` are
   iterative (explicit stacks) and take `simplify: true` to canonicalise
   leaves in one pass. Never reintroduce per-level recursion here: a
   20000-term sum must simplify in well under a second (performance_test
   times it now, generously, so a hundredfold regression fails the suite).
   `rebuild_sum` reads a term's ordering key off its factor map
   (`term_key`, 19 Sept 2026) rather than building `rebuild_product(1,
   factors)` to ask it, and the text that breaks a tie is a `LazyText`
   built only if the comparison gets that far: that was a quarter of the
   20000-term simplify. `keyable?` says when reading the map is the same as
   re-factorizing the node - a numeric base, a power, a quotient and an
   `exp` Fn are not, and take the long way round.
   Radicals of positive integers keep a fractional exponent in (0, 1) and
   move the integer part into the coefficient (`rebuild_product`):
   `1/sqrt(2)` is `2**(1/2)/2`, `2**(3/2)` is `2*2**(1/2)`. This is what
   makes `atan`'s exact table and `arg` match.
4. **Term tables** `{ {base => exponent} => coefficient }` (Expand.table,
   Simplify.termize/factorize) are the shared internal normal form; use
   them instead of walking trees when you need coefficients, atoms or
   numerators/denominators. `Expand.table` treats unknown leaf classes
   (Const, Integral, RootOf, ...) as atoms.
5. **Everything numeric lives in `Num`**, including finite-field elements
   (`Mod`, `GFElement`), Complex and `Decimal` (precision.rb; it needed no
   case anywhere, because it is a `Numeric` with the `printer_precedence`
   hook Printer looks for, and `NumberSet#include?` routes every Numeric
   to RR - that is the template for a new value type). `Simplify.normalize_number`,
   `pow_number`, `negative?`/`sign_negative?` must stay safe for Rational,
   Float, Complex, Mod, GFElement. `exp(u)` is stored in factor tables as
   `Simplify.exp_base ** u` so exponentials merge; `power_node` turns it
   back into `Fn(:exp)` and folds.
6. **Domains are values, membership is exact where possible.**
   `NumberSet#===` is membership (so never `case domain when ZZ`; use
   `==`). `Domain#join` must handle PolynomialRing/FractionField explicitly
   (mutual `other.join(self)` recursion has bitten twice). `MatrixSpace`
   and `VectorSpace` are `Domain`s too (since 17 Sept 2026): they compare
   with `subset?`, join with a space of the same shape or with a domain of
   scalars (which is what scaling gives), and answer `ring?`/`field?`
   honestly - square matrices over a ring are a ring, a vector space is
   neither. Their `[]` is the element constructor and shadows
   `Domain#[]`, so `(QQ**3)[1, 2, 3]` still builds a vector rather than a
   polynomial ring. Nothing is lost by that: a space answers `scalar?` with
   false (19 Sept 2026, the user pointed at the collision), so a polynomial
   ring over it is refused anyway - `Polynomial`'s coefficients are
   Expressions, and `MatrixSpace#[]` answers a symbol with that message and
   the direction that works, `(QQ[x])**[2, 2]`. Every value answers `in?(domain)` through the
   `Algebraic` mixin; `Mod` and `GFElement` carry their own one-liner,
   because that mixin's `rop` refuses the arithmetic they accept.
6a. **Infinity is a value with arithmetic** (19 Sept 2026, from a review):
   `OO` is an ordinary `Const` and therefore an atom in the term tables, so
   `Simplify.rebuild_sum`/`rebuild_product` are where it has to be caught -
   `undefined_term?` answers `oo - oo`, `oo/oo` and `0*oo` with `UNDEFINED`
   (a `Const` of its own, bare name `undefined`, nums1.NaN in OpenMath),
   and `absorb_infinity` collapses `2*oo`, `oo**2` and `oo - 2` to `oo`
   and `1/oo` to 0. `Expand.add_term`/`multiply_factors` keep a cancelling
   infinity in the table for the same reason. A symbolic coefficient is
   never absorbed (`x*oo` stays, because `0*oo` is undefined).
   `1**oo` and `oo**0` are **1** (22 Sept 2026, the user's call after the
   third review suggested undefined: an exact 1 or an exact zeroth power
   is 1 whatever the other side is, as IEEE `pow` has it). `oo**0` has to
   be caught in `factorize` *before* the table merges it (`infinity?`),
   because `oo/oo` also lands as `{oo => 0}` there and must stay undefined.

7. **Formal nodes**: `Integral`, `Sum`, `Product`, `Limit`, `Derivative`,
   `RootOf` and `Piecewise` are Expressions and atoms to everything else;
   `evaluate` (aliases `doit`, `unhold`) computes them. Printer, LaTeX,
   Differentiate, Infer, evalf need a case for every new node class.
   `Piecewise` is the one whose children are not the whole node: its
   conditions are Inequalities, not Expressions, so it overrides
   `variables` and `replace_with` to carry them along, and
   `Piecewises.hoist` pulls a piecewise out of a surrounding expression
   (2*pw is piecewise(c => 2*v)) before integration and limits.
8. **`Scalar.zero?`** decides zero for matrix entries: exact for Num, exact
   via `Algebraic.exact` for constants in one radical/RootOf or two square
   roots, otherwise numeric (1e-12) *confirmed at two precisions*
   (`vanishes?`, 19 Sept 2026): a true zero is cancellation and shrinks as
   the digits rise, `exp(-100)` sits at 3.7e-44 and is not zero. A complex
   value has no arbitrary-precision route here, so there the float
   tolerance still decides. Symbolic pivots that are not
   identically zero are assumed non-zero (generic case) and this is
   documented.
9. **Ruby folds before rcas sees anything**: `1/2` is 0, `2**(1/3r)` is a
   Float. Hence `1/2r`, `root(2, 3)`, `cbrt`, and `hold { }` for keeping
   input structure. Never assume a literal reached us unevaluated.
10. **Bare names are precious.** Do not define bare `e` or `i` (common
    variable names; the chat tests rely on `e` being a symbol); constants
    are `E`, `I`, `PI`, `OO` (`pi`, `oo` are bare); `In`/`Out` are
    constants for the same reason as the double-struck sets, so they cost
    no indeterminate names. Kernel's `p`, `pp`,
    `j`, `jj` are *undefined* on both session objects
    (`RCAS.undefine_kernel_printers`) so they can be indeterminates; print
    with `puts`/`Kernel.p`. Symbol comparison operators build inequalities
    only against Numeric/Expression; symbol vs symbol keeps Ruby semantics.

## Workflow

- Run everything: `ruby -S rake` (plain `rake` may hit a shell alias).
  Seeds: `ruby -S rake TESTOPTS="--seed=1"`. Individual file:
  `ruby -Ilib -Itest test/solve_test.rb`.
- **MANUAL.md is executable documentation.** `test/manual_test.rb` runs
  every `rcas> ` line in a session that mimics `bin/rcas` (bare names
  become symbols, locals persist within a code block) and compares
  `inspect` output with the `=> ` lines (multi-line results: continuation
  lines indented three spaces). When output format changes, fix the code
  or the manual deliberately; never loosen the test. Prose-only claims in
  README/MANUAL should be things you verified in this session.
- Regenerate the manual TOC after adding sections: `ruby -S rake toc`
  (markers `<!-- toc -->` / `<!-- /toc -->`). Numbering: `## 1.
  Mathematics` with `### 1.n ...` and `#### ...` beneath; then Reference,
  Files, License, Appendix A (typeset output), Appendix B (rcas-chat),
  Appendix C (rcas-app).
- README is *setup only* (requirements, running, library use, files and
  settings, tests, pointers). Usage goes in MANUAL. Logo at the top of
  both with the "This logo was AI generated" hint; `assets/rcas-logo.jpeg`
  is the 960px copy used in documents.
- **The tour is a poster linking to YouTube**, at the top of MANUAL.md and as
  a link in README.md (21-22 Sept 2026, after two wrong turns). What is worth
  knowing, because it cost a round trip: **`gh api /markdown` is not the
  sanitizer github.com uses for a file**, and trusting it produced an embed
  that rendered as an empty `<details>` on the blob page. The API keeps
  `<video>`; the blob view *strips* it unless the `src` is GitHub-hosted
  media (a `github.com/user-attachments/assets/<uuid>` URL from dragging a
  file into a comment box, which GitHub then rewrites to a signed
  `private-user-images.githubusercontent.com` URL and wraps in its own
  collapsible player - `zai-org/GLM-4`'s README is a live example). It also
  *escapes* `<iframe>`, so a YouTube embed renders as literal text and the
  thumbnail-link is the only route. To check any of this, fetch the real
  `github.com/<repo>/blob/...` page and look at the rendered richText, not
  the API and not the raw source that sits in the same payload. A release
  asset is served `application/octet-stream` with `Content-Disposition:
  attachment`, so a link to one downloads - media elements ignore both
  headers and would have played it, but only if the tag survived.
- Smoke-test interactively with piped input:
  `printf 'x + 1\n' | ruby bin/rcas` (no `=> ` prefix without a tty) or
  `printf '/settings\n' | RCAS_HOME=/tmp/h ruby bin/rcas-chat`.
- The window front end is smoke-tested without a window:
  `ruby bin/rcas-app --no-window` prints the address, and a headless
  screenshot of that URL (the `--screenshot` flag of the same Chrome
  render.rb uses) shows the page as it really renders. `--install` writes
  to the real desktop, so test `Launcher.install_bundle` into a tmpdir
  instead.
- Scratch files go in the session scratchpad directory, not the repo.

## Adding a feature: checklist

1. Algorithm in its own module under `lib/rcas/`, `module_function`
   style, required from `lib/rcas.rb` (after its dependencies; constants
   like `OO` are defined in series.rb and registered into
   `RCAS::Constants` afterwards).
2. Top-level function in `functions.rb` (with a one-line doc comment: the
   chat shows it as a usage hint on ArgumentError and as `/help name`, and
   `test/docs_test.rb` fails without it) and, where natural, an
   `Expression` method. Keyword forms follow the existing convention:
   `f(expr, x: 0..1)`, `x: 0`, `n: 6`, endless range = infinity
   (`Functions.range_arguments`, `point_arguments`).
3. New node class? Add cases to Printer, `latex.rb` (theirs; small
   additive edits are fine, see below), Differentiate, `Infer.domain`,
   `Expression#evalf`, `Expression#evaluate`, and `Hold::FORMAL` if it
   should stay formal inside `hold`. Also a row in
   `openmath/phrasebook.rb`: `test/openmath_test.rb` enumerates every
   `Expression` subclass and fails when one has none (the audit
   `LaTeX.print` went a year without). A new *OpenMath* node class needs a
   case in `XML.parts`, `XML.build`, `Popcorn.emit_bare` and the parser.
4. New value type inside `Num`? Check `Simplify.normalize_number`,
   `pow_number`, Printer.number/number_precedence (`printer_precedence`
   hook), `Scalar`, `NumberSet.of` / `Infer` (see `Num#finite_field?`).
5. Tests: exact strings for representative outputs, plus a property check
   where possible (integrals are verified by differentiating and
   `evalf`-comparing at a few points; ODE solutions by substitution; sums
   by `call` at small n).
6. Manual section with transcripts (they become tests), reference table
   row, "not implemented" list if applicable; `ruby -S rake toc`.
7. **Cite the source.** Every non-trivial algorithm names its origin in the
   module header comment with a key like `[GCL92, ch. 8]`, and the key is
   listed in MANUAL.md "4. Sources" (table row + bibliography entry). The
   user asked for this explicitly; a named algorithm without a reference is
   not finished.

## The typesetting and chat layer

`lib/rcas/latex.rb`, `render.rb`, `chat.rb`, `chat/*`, `bin/rcas-chat`,
`test/latex_test.rb`, `render_test.rb`, `chat_test.rb` and Appendices A/B
of the manual are the typesetting and chat front end. (Until Sept 2026
they were written in a second, parallel session; there is only one session
now, so they are just as editable as the rest - the habits below are worth
keeping anyway, because they are what makes new node classes cheap.)

- Prefer hooks over edits there: `LaTeX.of` falls back to `obj.to_latex`
  for non-Expression objects, so give new classes a `to_latex(wrap: nil)`;
  the chat UI typesets anything responding to `to_latex`. A new
  *Expression* class does need a case in `LaTeX.print` - keep it to the
  dispatch line plus a helper, and let the helper delegate the details
  back to the module that owns the node (`Piecewises.condition_latex`).
- The output mode `:tex` was renamed `:typeset` (Sept 2026, the user's
  ask) and is now the *default* in both the window and the chat (the chat
  only where inline pictures work; elsewhere `:text` as before).
  `Chat::UI::MODES` is the list, `Chat::UI.mode_for` is the only way to
  turn a name into a mode: it keeps the old spelling `tex` working, which
  a `~/.rcas/settings.json` and a saved session written before the rename
  still contain. Never test a mode name against `MODES` directly - that
  was the bug the rename introduced in `REPL#resume`.
- `chat/workspace.rb` mirrors `RCAS.unknown_function` (`undefined_calls?`),
  `chat/repl.rb` routes prose with undefined calls to Claude before
  evaluating and hides `/ask /model /fallbacks /cost /compact`, the `?`
  prefix and every Claude string unless `Assistant.configured?`; the
  banner, `/settings` and errors say nothing about Claude offline. Keep
  that: the user wants non-AI users to see a plain CAS.
- The numbered session runs through the chat too: `chat/ui.rb` records the
  result in `UI#result` and takes the prefix from `Results.mark`,
  `chat/repl.rb` records the input in `#evaluate` and builds its prompt
  with `Results.prompt(PROMPT)` (so `read_line` compares against
  `CONTINUE`, not `PROMPT`), and `/numbered` and the `numbered` settings
  key switch it off.
- `test/latex_test.rb` has a teardown that forgets assumptions (a leaked
  `x: ZZ` broke other tests under some seeds); clock-dependent chat tests
  have failed at midnight before.

## Settings, files, environment (chat front end)

`~/.rcas` (`RCAS_HOME`): `settings.json` (defaults: output, backend,
scale, theme, wrap, plotstyle, unicode, numbered, model, fallbacks;
`/settings save|reset`), `history`,
`sessions/*.json`. Pictures go to `/tmp/rcas` (`RCAS_CACHE_DIR`) and the
ones a process created are deleted at exit (`Render.cleanup!`).
Precedence: settings.json < env vars < flags < `/commands`. `bin/rcas`
and the library keep no state apart from the session's results and
`RCAS.random`, the source of randomness a seed pins. Claude is used for exactly one thing: plain
language questions in `rcas-chat` (`ANTHROPIC_API_KEY`); without it the
chat shows no trace of it: no model line, no `/ask` in `/help`, no
mention in errors (the user wants non-AI users to see a plain CAS).

## In and Out: the numbered session

The session is numbered by *line*, Mathematica style: line n has the input
`In[n]` and the result `Out[n]`. `RCAS::Results.record_input(source,
binding)` opens line n (the REPL calls it with the line it is about to
evaluate) and `Results.record(value)` stores the result of the line it
opened; a line whose value is not echoed (an error, a trailing `;`) keeps
its number and simply has no `Out[n]`. A negative index counts back from
the last *finished* line, and the line being read is in neither table, so
`In[7]` on line 7 is nil instead of an infinite regress (`Results.holding`
guards the rest: a line that reads itself comes back as its text).

`In` and `Out` are `RCAS::Results::Store`s (Hash) and are constants in
`RCAS` *and* in `RCAS::Constants`, which is how all three front ends see
them: bin/rcas includes Constants into Object, the chat's workspace has
`RCAS` in its lexical nesting, test/manual_test.rb includes Constants.
`Store#number` also accepts a `Num` key, because a held line hands its
numbers over as nodes.

`Out[n]` is the value as it was; `In[n]` is `Hold.source(text, binding)` -
the line rebuilt with `hold`, so it holds exactly as much as `hold { }`
does and everything else (an assignment, `factor(...)`, a sentence) is
evaluated or, when that fails, handed back as the text typed. The tables
themselves are not recorded as results (`@bare`, and `return_format` then
drops the `=>`).

`RCAS.numbered` puts the number of the line to come into the *prompt*
(`rcas[3]> `, `[3]❯ `) via `Results.prompt(plain)`; results always keep
`=> `. It is **on by default** (the user asked for that in Sept 2026);
`RCAS.numbered = false`, `RCAS_NUMBERED=0`, `/numbered off` or the settings
key `numbered` switch it off. The transcripts in MANUAL.md still show the
plain `rcas> ` prompt, and the manual says so once in "Sessions and
setup" - keep that note if you touch the prompt again.
test/manual_test.rb prints no prompt at all, so it is unaffected either
way. irb is hooked in `RCAS::IRB.record_session`: prepended `output_value`
(result) and `IRB::Context#evaluate` (input, `Statement::Expression` only,
so irb commands and empty lines are not lines of the session), plus
singleton `return_format` and `prompt_i` on the context, so irb's own
paging and non-tty format stay. The chat records the input in `REPL#evaluate`
and the result in `UI#result`, and its prompt goes through `Results.prompt`
too. test/manual_test.rb records both, so manual transcripts may use
`In`/`Out` - but only with *negative* indices, since one workspace runs all
code blocks in sequence, and never the bare tables (they would print the
whole manual).

## Hypergeometric summation (Koepf's book)

The chain is: **Gosper** (already there, summation.rb) decides the
indefinite question; **Zeilberger** runs Gosper on a pencil
`sum_j sigma_j F(n + j, k)` and gets a recurrence for a definite sum;
**Petkovsek** solves such a recurrence in hypergeometric terms;
**PolyRecurrence** is the polynomial-solution subroutine both need. Each has
a q-twin with `x = q**k` in place of `k` (and `y = q**n` for q-Zeilberger),
which is the whole of the second half of the book.

Load-bearing details, most of them found the hard way:

- **The sigmas stay linear.** Zeilberger works because the pencil's term
  ratio is `r(k)*D(k)/D(k+1) * N(k+1)/N(k)` with `N` linear in the sigmas,
  and `N(k+1)/N(k)` is exactly of the shape `c(k+1)/c(k)`: so the
  Gosper-Petkovsek normal form `(a, b, c_0)` is sigma-free and
  `c = c_0*N`. Gosper's equation `a(k)X(k+1) - b(k-1)X(k) = c(k)` is then
  linear in the coefficients of `X` and the sigmas *together*, and one null
  space gives both. Do not try to run plain Gosper on the pencil.
- **Use PolyMatrix for that null space.** `Elimination.rref` over rational
  functions of n swells the entries (an order-2 system was still running
  after a minute); the coefficients are polynomials in n, so
  `PolyMatrix.kernel` does it by evaluation and interpolation in
  milliseconds. `Zeilberger.row_reduce` is the fallback for a second
  parameter.
- **`Scalar.zero?` does not cancel.** `q + q*(q - 1)/(1 - q)` is zero and
  `Scalar.zero?` says no, so `Elimination.rref`/`Solve.linear_system` can
  declare a consistent system inconsistent. That is why the q-side has its
  own `QSummation.linear_solve`, which cancels every entry as it goes
  (and stays small because of it). Watch for this in any new code that row
  reduces over rational functions.
- **Assemble the certificate in the polynomial ring.** Building
  `R(k) = b(k-1)X(k)/(c_0(k)D(k))` as an expression and calling `cancel`
  took two minutes on a sum of three binomial cubes, because `as_fraction`
  builds a common denominator by multiplying. `Zeilberger.certificate_of`
  does it with polynomials and one gcd: milliseconds.
- **Scale the certificate with the coefficients.** `clear_denominators`
  multiplies the sigmas by a factor; the identity is linear in them, so the
  certificate has to be multiplied by the same factor or verification fails.
- **Verification is sampled, deliberately.** The linear algebra is exact
  (and `PolyMatrix.kernel` checks its own vectors), so the rational identity
  is checked at a few exact rational points instead of by a normal form -
  it is a check on the derivation, not on the arithmetic, and a normal form
  of the difference costs seconds.
- **Natural boundaries are not automatic.** Creative telescoping proves an
  identity under the summation sign. `binomial(n, k)/(k + 1)` has a pole at
  `k = -1`, its boundary terms do not vanish, and the recurrence it yields
  is false for the sum: `sumrecursion` therefore puts `sum_{k=0}^{n}` into
  the recurrence for the first few n and refuses when the residue is
  demonstrably non-zero (only then - an undecidable check must not reject).
- **`Summation.sum` calls Zeilberger with `max_order: 1`.** A sum with a
  hypergeometric closed form satisfies a first-order recurrence; the higher
  orders cost seconds on terms like `binomial(n, k)**4` that have no closed
  form anyway. `sumrecursion` goes to order 4 (q: 2) when asked directly.
- **q-terms cancel through the q-Pochhammer symbol.** `QFunctions.align`
  writes every `(a; q)_m` of one family on the lowest index that occurs and
  `merge_pochhammers` cancels them in a ratio; without that, a sum of
  q-terms is opaque to `cancel` (powers `q**k` are not polynomial in q
  either, which is what `QSummation.in_x` is for).
- **Petkovsek's answers start past the singularities.** The term of a ratio
  `r(n)` is `product(r(i), i, n0, n - 1)` with n0 past every non-negative
  integer root of numerator and denominator, which is why
  `u(n + 1) = n*u(n)` comes back as `(n - 1)!` and the q-twin replaces a
  degenerate `(q**(-m); q)_n` by `(q; q)_(n - m - 1)`.
- `Math.log(-1.0)`, `Math.asin(2.0)` and friends raise `Math::DomainError`,
  which is not a `StandardError` subclass you want reaching a user:
  `Functions.math_value` leaves the node alone instead. A divergent sum
  used to come back as "Numerical argument is out of domain - log".
- **`NotImplementedError` is a ScriptError**, not a StandardError: a bare
  `rescue` does not catch it (this bit while testing).

### The FPS algorithm (fps.rb)

Koepf's *Power series in computer algebra* [Koe92], the forward direction of
what `Summation.classical_series` does backwards. Four steps: holonomic
differential equation, coefficient recurrence, two-term solution, assembly.
What is load-bearing:

- **The ansatz splits each derivative into {monomial in the transcendental
  atoms => rational function of x}** and asks every monomial to cancel
  separately. That is *sufficient*, never spurious: a relation between the
  atoms (sin**2 + cos**2 = 1) is simply not used, so at worst a longer
  equation is found than the minimal one. Powers of a polynomial base split
  by the integer part of the exponent, which is what makes a derivative and
  its successor share the atom ((1 - x**2)**(-3/2) is (1 - x**2)**(-2) times
  the atom (1 - x**2)**(1/2)).
- **Clear denominators with one lcm in the polynomial ring.**
  `Fraction.as_fraction` on the assembled coefficient builds the common
  denominator by multiplying, which is quadratic in the number of terms, and
  the third derivative of a rational function already has fifty:
  `cleared`/`fraction_of` read each term's denominator off its factor map
  and take one lcm (7.3 s to 0.03 s on `(1 + x)**a/(1 - x)`).
- **The null space goes through `PolyMatrix.kernel`**, for the reason
  Zeilberger does it: with a parameter in the coefficients an elimination
  over the rational functions swells, and evaluation and interpolation do
  not (16 s to 1.7 s on the same example). `QSummation.linear_solve` is the
  fallback when there is no parameter, or more than one.
- **One equation per order is enough.** x**i times an equation of the same
  order is an equation again and its recurrence is the same one shifted, so
  the degree loop stops as soon as an order yields anything. Higher *orders*
  are still tried - a longer equation can have the two-term recurrence the
  minimal one lacks.
- **The coefficient is offered in three forms and the check decides**:
  factorials (Gauss's multiplication formula on the gammas), binomial
  coefficients (`gamma(b + k)/(gamma(b)*k!)` with upper negation, which is
  what makes `(1 + x)**a` the binomial series), then the bare product.
  Tidying can move the coefficient out of reach of its own first index -
  (2*k - 2)! has a pole at k = 0 where `gamma(k - 1/2)` had none - so
  `agrees?` picks the first form that reproduces the Taylor coefficients.
- `Products.parametric_product` (product.rb) was added for `a - k`: a linear
  factor whose root is a parameter, generically not inside the range.
  `Combinatorics.binomial_value` now folds `binomial(1/2, 3)` as well, which
  is what lets the sampled check evaluate a parametric answer.

## Definite integrals and poles (19 Sept 2026, from a review)

`Integrate.definite` is not `F(b) - F(a)`: `singular_points` finds the
poles strictly inside the bounds (`Analysis.denominators` and each of
*their factors*, since `Solve` can name the zeros of `x` and of `log(x)`
when it can make nothing of `x*log(x)`, plus the zeros of `cos(u)` under a
`tan`), `between` evaluates each piece with a
one-sided limit at every interior end, and the sum of `+oo` and `-oo` is
`undefined` because Simplify says so. The direction of each piece follows
the interval, so reversed bounds are evaluated from the right side. When a
piece comes out non-real - `log(cos(x))` past `pi/2` - the pieces are
taken again with `log|u|` (`real_logs`), which is an antiderivative on
each piece and the one a real integral wants; what is still not real stays
an `Integral` node. The bounds are split at the jumps of *F* as well
(`jump_points`): the Weierstrass substitution puts `tan(x/2)` into the
antiderivative, which breaks at every odd multiple of pi while
`1/(2 + cos(x))` is smooth there, so the integral over a period came back
as 0. `instantiate` counts out the members of a family like `pi + 4*pi*k`
that lie between the bounds and answers **nil**, not `[]`, when it cannot
(more than `MAX_BREAKS`, a second parameter, a step it cannot measure):
`[]` says "no breaks", and one family of the two dropping out that way
left the integral over `0..254*PI` wrong by a factor of two (found by the
fourth pass of the review, 20 Sept 2026). `MAX_BREAKS` is a budget for
the whole range, spent family by family, and **not** a limit per family:
how many families the breaks arrive in is a matter of how `solve` spells
them, and the reach halved silently (253 periods to 127) when
`merge_families` landed and two families of step `4*pi` became the one of
step `2*pi` that says the same thing. It is also the time guard - a break
costs about 0.048 s to split at, so 128 of them is some twelve seconds,
and that is what the number buys (both: 20 Sept 2026, the tenth pass of
the review). `jumps?` reads two samples
either side rather than two limits - splitting where F is continuous
costs two evaluations and nothing else, since the pieces telescope, while
missing a break costs a period, so the cheap test is also the safe one. `endpoint` also refuses a substituted value that is not defined
(`defined_value?`: `log(0)`, `tan(pi/2)`, `undefined`) and takes the
one-sided limit instead. A singularity rcas cannot classify (`:unknown`)
also stays formal rather than being subtracted through, and so does a
denominator whose zeros `Solve` cannot name when it *changes sign* between
the bounds (`changes_sign_between?`): "no pole" would be a claim, not an
answer. `singular_points` says that with `nil`, which the caller has to
test before splatting it into the bounds - `[from, *nil, to]` is
`[from, to]` and swallows it (the second pass of the review caught exactly
that).

## The integration rule chain

`Integrate.attempt` tries the rules in a fixed order and the order carries
meaning; five things in it are load-bearing and easy to undo by accident.

- **`piecewise` runs before `rational`.** An integrand with `abs`/`sign` is
  not a rational function, so every later layer would search in vain.
- **The continuity constant is not cosmetic.** `piecewise` returns
  `sign(u)*(F - F(x0))` with `x0` the root of `u`. Drop the `F(x0)` and each
  antiderivative is still right on both sides but jumps at `x0`, so definite
  integrals across it come out wrong. Only a *linear* `u` is handled, because
  that is the case where the breakpoint can be named.
- **`by_parts` must not trade down (`harder?`).** Integrating `exp(-x**2)`
  introduces `erf`, and `u' * v` is then the problem we started from:
  `x**2*exp(-x**2)` would recurse until MAX_DEPTH and answer with a correct
  but deeply nested expression instead of going to
  `Substitutions.gaussian_moment`. The guard rejects a `v` carrying `erf`
  or `erfc` when `dv` carries neither.
- **`real_log_part` is a fallback, never a first choice.** It runs only when
  `log_part` (Lazard-Rioboo-Trager) returns nil, splits `a/d` into partial
  fractions over the irreducible factors of `d`, and handles a quartic
  `x**4 + a*x**2 + b` (no odd powers) by its real quadratic factors: two
  branches, chosen by the sign of `a**2 - 4*b`, both guarded by `positive?`,
  which decides the sign of a constant radical expression by `evalf`.
- `Substitutions.root_of_ratio` sits *after* `root_of_linear`, so a root of a
  linear form keeps the simpler substitution.
- Arbitrary precision has two traps worth remembering. The tanh-sinh
  abscissa must be measured from the *near* end (1 - tanh(u) is
  2/(1 + exp(2*u))); computing centre + span*tanh(u) cancels away exactly
  the digits an endpoint singularity needs. And every exp is guarded by
  EXP_LIMIT: the doubly exponential maps reach arguments like 10**160,
  where BigMath grinds for ever instead of saying no.
- `IntegralFunctions.antiderivative` sits right after `table`, before
  `piecewise`: exp(u)/u, sin(u)/u, cos(u)/u and 1/log(u) are named
  integrals (Ei, Si, Ci, li), and the later layers would only find longer
  ways to fail. `exp(x)/(x + 1)` is handled there too (the substitution
  leaves a constant factor); everything else reaches it through `shift`.
  The four names are in `Integrate::SPECIAL`, so `by_parts` will not trade
  an elementary integrand for one of them.

An integrand rcas cannot differentiate (`floor`, an unknown function) must
stay formal: `linear` returns nil on ArgumentError and `attempt` swallows the
one whose message starts with `NO_DERIVATIVE`. A new rule that calls `diff`
on a subexpression has to keep that promise.

Every rule is tested by differentiating its answer and comparing numerically
at a few points; batteries of trial integrals belong in the scratchpad, not
in the repo.

## Line and surface integrals (vector_calculus.rb)

Everything is a parametrization followed by an ordinary integral, so the
module is small and the decisions are all about honesty:

- **The order of the ranges is the order of integration *and* the
  orientation.** `surface_integral(f, s, u: .., v: ..)` integrates u
  innermost (as `integrate` does) and takes the normal as `r_u x r_v` for
  the first parameter u and the second v. Exchanging the two ranges turns
  the normal round: the sphere's flux is `4*pi` written `v: 0..pi,
  u: 0..2*pi` and `-4*pi` the other way. That is the mathematics, not a
  bug, and the manual says so.
- **`norm` pulls perfect squares out of the length element**, because
  `sqrt(a**4*sin(v)**2)` would otherwise leave the sphere unintegrable.
  The sign of each factor is *proved* (`proven_sign`): in one range by
  `Analysis.sign_on_interval` (all zeros, families counted out, and no
  pole, jump or edge of the real domain inside), on a box only for a
  product of factors in one range each; anything else keeps `abs(...)`.
  (The sampling `sign_on` it replaced was T2 of the third review.) A radicand with trig functions
  is `trigsimp`ed first - which is what uncovered the `reduce_table` bug.
- **The coordinates of a field default to x, y, z**, which is what a
  student writes; the field's own variables are used instead when there are
  exactly as many of them as the parametrization has components (so a field
  in u, v works), and `vars:` settles it in any other case. For `green` and
  `divergence_theorem` the coordinates are the *range* variables sorted, so
  that `[P, Q]` belongs to x, y and not to the order of integration.
- The three theorems each compute the side over the region, which is
  usually the easier one; `line_integral`/`surface_integral` compute the
  other, and the tests put the two next to each other (Green against the
  four sides of a square, Stokes against the circulation around a disc,
  Gauss against the flux through the six faces of a cube). That is the
  property check for this file - there is no antiderivative to differentiate.

## Random objects (random.rb)

The user asked for these in Sept 2026 ("you need random matrices,
polynomials etc. all the time when fiddling around") and chose the shape:
on the structures, with a real vocabulary of keywords rather than a bare
`random_matrix`. So `random` sits beside `zero`, `one`, `gen`, `basis` and
`identity`, and the domain decides what an element looks like.

- **Two kinds of keyword, and the difference matters.** A *shape* (monic,
  symmetric, triangular, diagonal, a density of zeros, homogeneous) is
  built directly. A *property* is either constructed - unimodular from row
  operations, `det:` from a triangular matrix between two unimodular ones,
  `eigenvalues:` as P*D*P**-1, `definite:` as L*L.transpose, `roots:` and
  `factors:` as products - or sampled and checked (`irreducible:`,
  `squarefree:`, `invertible:`, `rank:`). Sampling gives up after
  `TRIES` with a message: "no such object" and "unlucky" look the same
  from in here, and a CAS that spins for ever is worse than one that says
  no.
- **Small entries are the point.** A unimodular matrix is the identity
  after 2n row operations with multipliers +-1 and a shuffle; with +-3 and
  3n operations (the first cut) a 3x3 with given eigenvalues had entries
  in the hundreds, which is no use to anyone working by hand. `det:` fixes
  the sign afterwards, because each unimodular factor may have determinant
  -1. And `eigenvalues:` redraws while the answer is triangular, which
  would show the eigenvalues on the diagonal.
- **`case domain when ZZ` bit again** (invariant 6): `NumberSet#===` is
  membership, so the number generator compares with `==`. It is written
  out in a comment there.
- **QQ and CC come back as `Num`**, NN/ZZ as Integer and RR as Float: a
  Rational inspects as `(-1/3)` and a Complex as `3-9i`, and the manual
  transcripts are `inspect` output. `Randoms.number` returns the raw Ruby
  value; the lifting happens in `NumberSet#random`, because the same
  generator fills polynomial coefficients and matrix entries, where a Num
  would be wrapped twice.
- **Manual transcripts seed per code block** (`RCAS.random = 2026` as the
  first line of each), never once for the section: manual_test runs every
  block of the manual in one workspace and in file order, so a seed set in
  an earlier section would make these depend on every random call before
  them.
- `Docs::STRUCTURES` was added for this: `doc(:random)` and `/help random`
  find a method of a ring or a space, which doc knew nothing about before
  (it had functions, Poly.*, expression methods and constants).

## What a declared domain means (17 Sept 2026)

`assume(x: ZZ)` used to change what `simplify` and `Infer` did and nothing
else, so `solve(sin(x) == 0, x)` answered `[0, pi]` for an integer x. Now
`Solve.restrict` filters every univariate answer (and every solution of a
system) by the unknown's domain *and* its sign, and `solve(f, x, domain: ZZ)`
names one without a session-wide assumption.

- **`Infer.excluded?(value, domain)` is one-sided on purpose.** It answers
  true only when the value is *demonstrably* outside: exactly for a `Num`,
  by the minimal polynomial for an algebraic constant (`2**(1/2)` is not
  rational), by transcendence for a rational multiple of `pi` or `e`, and
  numerically for integrality (`TOLERANCE = 1e-6`, and only after the exact
  routes have failed). `log(2)` is irrational and rcas cannot say why, so
  it survives a declared QQ - and should. A wrong answer kept is better
  than a right one dropped, and the manual says so.
- A family with a parameter in it (`2*pi*k` from `all: true`) is never
  excluded, because it holds for some k.
- `RCAS.assumption(name)` is the number set, `RCAS.signs[name]` the sign;
  they are two tables, and `assume` only ever puts a NumberSet in the first.
  `assume(...) { }` scopes both to the block (Mathematica's `Assuming`,
  Maple's `assuming`), by saving and restoring the whole of both tables, so
  an `assume` or a `forget` inside the block is local as well.
- The filter is at the one funnel (`solve`), not inside `univariate`, which
  recurses through the case splits.
- **An assumption is used in three more places since 17 Sept 2026.**
  `Trigonometry.reduce_period` drops a whole period from the argument of
  sin, cos or tan when the multiple is known to be an integer, which is
  what makes the `all: true` families checkable (`sin(pi/6 + 2*pi*k)` is
  `1/2` for an integer k, and nothing at all for an undeclared one).
  `Simplify.root_of_product` takes a factor that cannot be negative out of
  a root, `sqrt(c**2*w) = c*sqrt(w)`, and leaves the rest inside - only
  when the root divides that factor's exponent, so it is always a
  simplification and never churn. And `assumptions` lists Memberships, so
  `RCAS.assumptions` prints statements while `RCAS.assumption(name)` stays
  the domain that Infer and solve want.

## Branch cuts (22 Sept 2026, from a review)

Two rules that read like plain algebra are about *branches* and were being
applied everywhere, so that substituting before and after `simplify` gave
different values:

- `exp(u)**v = exp(u*v)` (`Simplify.exp_power_mergeable?`) holds for an
  integer `v`, where the power is a repeated product, and for a real `u`,
  where `exp(u)` is a positive real whose principal power is the real one.
  Not in between: `sqrt(exp(2*pi*i))` is `sqrt(1) = 1` and `exp(pi*i)` is
  -1. When the guard declines, the power is stored as the atom
  `Pow(exp(u), v)` rather than as a power of `Simplify.exp_base` - which is
  why the `when Fn` branch of `factorize` needs the same guard, not only
  the `when Pow` one. Integer exponents still merge, and they have to: an
  exponential is *stored* as a power of e in every factor table.
- `log(exp(u)) = u` (`Functions.principal_log?`) holds on the principal
  strip `-pi < im(u) <= pi` only; `log(exp(2*pi*i))` is `log(1) = 0`. Real
  `u` is always inside, and a numeric `u` is measured. `exp(log(u)) = u`
  needs no guard, being true for every u.

Both predicates ask `ComplexParts.real_valued?`, which is `Infer.domain(e)
<= RR`: an undeclared indeterminate is *not* real here, so `assume(x: RR)`
is what turns the rules back on. That is the same one-sided policy as
`Infer.excluded?` - a simplification declined is a value kept.

`Integrate::Substitutions.exponential` is the one place that may cancel
`log(exp(u))` itself: it put the exp there by substituting `t = exp(r*x)`,
and the integration variable is real. `real_log_exp` does it on the way
back, or `integrate(1/(1 + exp(x)), x)` ends in `log(exp(x))`.

## Differentiating under the integral sign (22 Sept 2026, same review)

`Differentiate.integral` used to look at the *bounds* of a definite
integral and answer 0 whenever they held no `var` - so `d/dx
integral(x*t, t, 0, 1)` was 0 rather than 1/2. Only the integration
variable is bound; the integrand's parameters are free. It now integrates
the parameter derivative, and bounds that move add Leibniz's two boundary
terms (`integral(f(x), x, 0, x)` names one thing twice and raises). The
new integrand is simplified on the way in, since an Integral is an atom to
Simplify and nothing would tidy it afterwards.

This made a *nested* definite integral reachable for the first time: its
derivative is another integral, so every integration rule that
differentiates grew one more layer for ever, and the double integral of
`surface_integral` never came back. `Integrate.attempt` therefore declines
at once when the integrand carries a definite Integral that depends on x
(rcas has no rule for the iterated integral), the same promise as the
`NO_DERIVATIVE` path.

## Radii, projections, events, curvature (22 Sept 2026, same review)

Four more answers that were wrong for one reason each. They are small, and
the reasoning behind each is what a future session needs:

- **`LinearAlgebra.project`** summed the single projections, which is the
  projection onto the span only for pairwise orthogonal targets:
  `project(e1, onto: [e1, e1 + e2])` was `(3/2, 1/2)` although those two
  span the plane. It orthogonalises first unless `orthogonal_family?` says
  it need not, and `gram_schmidt` calls `onto_orthogonal` directly - it has
  just built such a family, and going through `project` would orthogonalise
  its own output once per step.
- **`Distributions#probability`** read the operator and the right-hand side
  and ignored the left: `P(-X <= 0)` was 0 for a variable that is never
  negative. An event whose left side is not the bare variable goes through
  `Inequalities.solve` and the probability is taken over the RealSet that
  comes out, piece by piece; `cdf_at` answers the two infinities with 1 and
  0, which no closed form reaches on its own.
- **`Analysis.inflections`** accepted `sign_change == :saddle`, which is
  the answer for *no* change of sign, so `x**4` had an inflection at 0 and
  `x**5` had none. It wants `:minimum`/`:maximum` now, and an undecided
  third derivative goes to the sign chart rather than counting as a change.
- **`revolution_surface`/`revolution_volume`** used the signed `f` and `x`
  as radii, so the cylinder of radius one had surface `-2*pi` for
  `f = -1`. `Analysis.distance` writes `abs(u)` unless
  `VectorCalculus.sign_on` decides the sign on the range (an abs the
  integrator cannot see through would leave the answer formal). Shells
  about the y-axis also need the range on one side of the axis:
  `one_side!` refuses one that crosses it, because `abs(x)` would sweep
  the same shells twice.
- **`Analysis.domain_conditions`** recorded a condition only when its
  argument moved with x, so `log(-1) + x` - real nowhere - came back as
  the whole line. `condition_argument?` takes constant arguments too and
  lets `Inequalities.constant_case` decide them. An argument in a
  *parameter* is still skipped: the answer would be a case split on the
  parameter rather than a domain in x. What is still not checked is an
  expression that is complex for some other reason (`I*x`), which the
  manual now lists as a gap.

The reviewer also ran the suite under Ruby 4.0.7 and reported 45
failures/errors. Under the 3.3.10 the README names it is green before and
after this work; those 45 are Ruby 4 plus the environment (blocked ports,
spaces in the project path, missing optional chat dependencies), not
mathematics.

## The second review (22 Sept 2026): proofs, not samples

A peer review of `95f0a1c` found twelve counterexamples in six groups. All
of them reproduced, all are fixed. The theme is one sentence: **an exact
symbolic rewriting may not rest on finitely many samples or on an
uncertified float.** Four of the six were exactly that mistake.

- **A radius is not decided by sampling.** `Analysis.distance` asked
  `VectorCalculus.sign_on`, which reads five points; on 0..1 they all found
  `x - 1/10` positive and the abs came off, understating the surface of
  revolution by 2.4%. `Analysis.sign_on_interval` proves it instead: a
  continuous u keeps one sign on an interval in which it has no zero, so
  `Solve` names the zeros, one strictly inside means there is no single
  sign, and one it cannot name means rcas does not know. The interior
  samples stayed on as a *veto* - they can catch a root Solve did not
  report, never establish that there is none. `VectorCalculus.root_factor`
  goes through the same test in one variable (`proven_sign`); on a box of
  several ranges it still samples, and the manual lists that as a gap.
  Keeping the `abs` costs little, because `Integrate`'s piecewise rule
  integrates it when the argument is linear.
- **The principal strip is decided exactly.** `Functions.principal_log?`
  compared `im(u).evalf` against `Math::PI`, and `pi*(1 + 10**-20)` rounds
  to exactly that float: `log(exp(u))` was cut for a u outside the strip,
  an error of `2*pi*i` decided by a rounding error. It now takes `im(u)`
  with `ComplexParts`, compares a rational multiple of pi as a *rational*,
  and otherwise admits only `|im| <= PI_LOWER = 31/10`, which is a proof
  because 31/10 < pi. A value between 31/10 and pi is declined though it is
  inside - a node kept, never a value moved.
- **An inflection is decided by the order of vanishing.** The test asked
  whether `f'''(p)` was numerically above `1e-12` and otherwise sampled
  `f''` at `+-1e-4`. With `f'' = x**2*(x - a)` and `a = 10**-5` the sample
  stepped over `a` and reported an inflection at 0; with
  `f'' = x**3*(x - a)` the exactly non-zero `f'''(a) = 10**-15` read as
  zero and both real inflections were lost. `vanishing_order` now takes
  derivatives of f'' until `Scalar.zero?` says one of them is not zero:
  the order is exact for a rational point of a polynomial, and **odd order
  = sign change** is the whole rule. The chart is the fallback, on a step
  bounded by the distance to the nearest other candidate (`safe_step`), and
  when even that cannot decide, `inflection_at?` *raises* - `discuss`
  turns that into "not determined", which is the third answer the review
  asked the API to be able to give.
- **An event is a statement, not an operator and a bound.**
  `probability` took the direct cdf route whenever the left side was a
  bare variable, without asking whether the *right* side was free of it,
  so `P(X <= X)` was `X`. `direct_event?` now tests both sides. And the
  infinity handling that `cdf_at` added in the first round only ever ran on
  the solved route, so `P(X <= oo)` was `oo` - not a probability at all;
  every public form goes through `cdf_at`/`pdf_at` now.
- **A parameter condition is decided or refused, never skipped.**
  `real_domain(log(a) + x, x)` answered with the whole line even under
  `assume(a < 0)`. `decide_without_x` reads `RCAS.sign_of`; what the
  assumptions do not settle raises `NotImplementedError` naming the
  parameter, which is the policy `solved_condition` already had. And
  `real_locus` closes the gap the first review had named and the first
  round had only documented: an expression carrying `i` is real only where
  `im(f)` vanishes, so `real_domain(I*x, x)` is `{0}` and `x + i` is empty.

Three smaller things the same review was right about:

- `integral(f(x), x, 0, x)` is **not** ambiguous. The bound name is not the
  free one, and renaming gives `integral(f(t), t, 0, x)`, whose derivative
  is `f(x)`. `Differentiate.integral` computes it instead of refusing.
- Differentiating under the integral sign is applied, not verified. The
  hypotheses ([DLMF, 1.5(iv)]) belong to the caller, and the comment says
  so rather than implying the rule is unconditional.
- The shell refusal now says that two overlapping halves are a union and
  not a sum.

Finally, **the suite must run from a path containing a space.**
`Open3.capture3(BIN, ...)` with one string goes through the shell, which
split the project path and failed nine tests for the reviewer; the
interpreter and the script are separate arguments now
(`RbConfig.ruby, BIN`). `AppServerTest` skips when a sandbox refuses to
bind a loopback port, and the .app icon is asserted only when `sips` and
`iconutil` can actually be *run* - both were failures nobody could act on.
Check this the way it was found: copy the tree into a directory whose name
has a space in it and run `ruby -S rake` there.

## The third review (22 Sept 2026): policies, not cases

REVIEW.md and PEER_REVIEW2.md in `review/round3/` (gitignored) came with
151 failing regression tests; each one that passes moves into
`test/review_<area>_test.rb`. The review's point is that about 110 root
causes are seven mistakes repeated, so the fixes are policies:

- **`Decide` (decide.rb) is the one numeric decision procedure.**
  `Decide.sign(e)` (:positive/:negative/:zero/nil) and `Decide.zero?(e)`
  (true/false/nil) try a Num, then `Algebraic.exact`, then
  `Precision.evalf` at 30/60(/120) digits - a zero shrinks with the
  precision, a small value stays put - and last a Float, believed only
  well clear of the rounding of the largest intermediate value. A complex
  constant is split by `ComplexParts.parts` and each part decided. **nil
  is undecided and must be treated so**; never write a private tolerance
  again. `Solve.verify` (which substituted the literal `x:` and was a
  no-op for any other unknown name), `defined_roots` and
  `Scalar.vanishes?` go through it.
- **Bound variables.** `Expression#bound_variable` is the var of a
  definite Integral, a Sum, a Product and a Limit (not an indefinite
  integral, not a Derivative). `variables`, `constant?` and
  `each_free_variable` skip bound occurrences, and `replace_with` does not
  let a pattern that mentions the bound name into the body and renames the
  bound variable (`Expression.fresh_variable`: x1, x2, ...) when a
  replacement would be captured. That is what makes Leibniz's boundary
  terms right for nested integrals (T3). The body is `children[0]`, the
  var `children[1]`, the rest are bounds - keep that shape for a new
  binder.
- **Hash writes that should merge**: `rebuild_product` (i*i**(1/2)),
  `Functions.fold`'s reflection (Normal.cdf(-2) lost its sqrt(2)),
  `RCAS.assumptions` (a sign hid the domain; both are listed now, as an
  Array). Use `Simplify.add_factor`, never `factors[b] = e`, on a table
  that may already hold b.
- `assume` checks the whole statement before recording any of it, and
  refuses a negative sign for a variable declared in NN.
- `LaTeX.hash` was renamed `LaTeX.table`: a module method named `hash`
  replaces `Module#hash` and breaks every Hash keyed by the module.

## Traps we have hit (so you do not hit them again)

- `RCAS::IRB::AutoSymbol` turns an undefined `name(args)` with Expression,
  Numeric or Symbol arguments into `Fn.new(name, args)` (unknown function,
  for `rsolve`'s `u(n + 1)`); typos such as `sqr(2)` therefore print back
  instead of raising. The chat workspace mirrors it (one line in their
  `chat/workspace.rb`).
- Patching files from scripts: `String#sub(old, new)` with a *string*
  replacement interprets `\\` and `\1`; it turned `"\\sum_"` in latex.rb
  into `"\sum_"` (a space escape) once. Use the block form
  `sub(old) { new }`. Write the search and replacement text in *single*
  quotes or a `<<-'EOF'` heredoc: a double-quoted patch string interpolates
  the `#{...}` that belongs to the source being patched (this cost three
  attempts in one sitting). `<<~` heredocs strip indentation, so a squiggly
  heredoc never matches indented source; use `<<-`. Shell-quoted
  `ruby -e '...'` breaks on any `'` or `` in the payload: write the
  script to the scratchpad and run it.
- Multi-line results in the manual: the first line carries `=> `, every
  following line exactly three spaces (`manual_test` strips both). Generate
  such blocks from real output rather than typing them, or braille art and
  matrices will not match. `manual_test` applies *both* strips to the first
  line, so a result whose first line starts with three spaces (a box plot's
  empty gutter row) loses them: give such a plot a `title:`, whose line
  starts at column 0.
- In `test/manual_test.rb` locals persist across *all* code blocks of the
  manual (one workspace), so a transcript that uses `a`, `b`, `l`, `n` may
  pick up a matrix or number from an earlier section. Use fresh names
  (`u v w`, `lam`, `m`) in new transcripts - and *never assign* `u` or `q`:
  the q-analogue sections call the unknown function `u(q*x)`, which stops
  working the moment either name is a local (the arguments are then not
  Expressions any more and `u(...)` raises NoMethodError).
- `IntegrateTest#antiderivative` checks at x = 0.4, 0.9, 1.7, which is
  outside the real domain of `asin`, `acos` and of anything with
  `sqrt(1 - x**2)`: test those with points of your own inside (-1, 1).
- Tests that call `RCAS.assume` must `forget` in a teardown; a leak shows
  up only under some seeds as `has no free variables to build a ring`.
  The block form `assume(x: ZZ) { ... }` (17 Sept 2026, the user's idea)
  cannot leak - it saves both tables and puts them back in an `ensure` -
  so prefer it in a test that needs an assumption for one calculation.
- The chat REPL treats a line that parses but is incomplete (`what is 2 +`)
  as a continuation and waits for more input; use a real syntax error
  (`what is )`) when a test needs one.
- `hold` needs the block source: `RubyVM.keep_script_lines = true` is set
  when `rcas/hold` loads (irb sets it itself; `eval`'d code in the chat
  did not). Keyword args inside the block arrive as HASH/DOT2 nodes and
  are built structurally, not eval'd.
- irb resets `IRB.conf` inside `IRB.setup`; configure the prompt after
  `setup`, not before (`RCAS::IRB.start`).
- Hensel lifting needs a prime not dividing the leading coefficient; the
  "monic transform" trick produced 490-digit polynomials divisible by
  every small prime. We lift the non-monic polynomial directly.
- The primitive PRS drops exactly the resultant factors where a gcd degree
  jumps; the Rothstein-Trager resultant is computed as the determinant of
  the Sylvester matrix (`Polynomial#resultant`, Elimination) instead.
- Kronecker substitution does not preserve squarefreeness; factor the
  image with the full univariate pipeline and recombine by *indices*
  (`Array#-` removes all duplicates).
- `Polynomial#content` must be positive; `.abs` on Complex is a magnitude,
  never use `.abs` for sign handling of coefficients.
- `acos` is neither odd nor even: `Functions::REFLECTED` carries
  `acos(-u) = pi - acos(u)`, and it must not fall through to the ODD/EVEN
  branch, which would answer `acos(-0.5)` with `acos(0.5)`. A Float
  argument skips the reflection entirely and goes to `Math`.
- **`asin` and `acos` past the interval are values, not errors** (20 Sept
  2026, the tenth pass of the review). `Math.asin(2.0)` raises
  `Math::DomainError` and `math_value` used to hand the node back, which
  left the families `solve(cos(x) - 2, x)` answers with correct but inert:
  nothing numeric came out of them. `Functions.real_branch` writes the two
  out - `acos(x) = (x > 1 ? 0 : pi) - i*acosh(|x|)`, `asin = pi/2 - acos`,
  the branch every C library takes - rather than deriving them from the
  general formula, which picks the other lip of the cut for a real
  argument that carries no signed zero. On the negative side rcas's own
  oddness decides instead (`asin(-u)` is `-asin(u)`, so `asin(-2.0)`
  differs from C in the sign of its imaginary part), and what has to hold
  either way does: `sin(asin(u))` is `u`. `log(-1.0)` was
  deliberately left out of this list until the third review (C7): it is the
  principal value `log|x| + i*pi` now, and divergent series are caught by
  their radius (`Combinatorics.within_radius?`) instead of by a node that
  failed to evaluate. `INVERSE_PAIRS` is the other half: `cos(acos(u))` folds to `u`
  for every `u`, and only that direction, since `acos(cos(u))` is `u` only
  on `[0, pi]`; `tan(atan(i))` is the one exception, because `atan` has no
  value at `+-i`.
- Folding `Num` results back into a coefficient must skip the imaginary
  unit (`Simplify.imaginary_unit?`) or `i` disappears into a Complex
  coefficient and prints as `(1/2*i)`.
- **A test appended after a `private` in a test class never runs.** Minitest
  collects public methods only, and two tests sat there unnoticed until a
  count of `def test_` was compared with the reported runs (20 Sept 2026).
  Append above the `private`, and check the run count when adding to a file
  whose helpers live at the bottom.
- **Never `include RCAS::Functions` in a test class.** `Functions#diff`
  overrides `Minitest::Assertions#diff`, so the *first failing assertion*
  dies while formatting its message (a TypeError from `Expression.lift`)
  and you debug the wrong thing. Write `RCAS.sin(x)` in tests instead.
- OMFOREIGN is a *derived* object: the standard says in as many words that
  derived objects "are not OpenMath objects", which is why the first cut of
  openmath/ had no class for it and the reader raised on any document that
  annotated a formula with presentation MathML - the commonest annotated
  kind there is. It is legal as the value of an OMATTR and an argument of
  an OME and nowhere else; `OpenMath.object!` is what enforces that, and
  `Foreign#object?` is false.
- `assert_in_delta(exp, act, delta, msg)`: the third argument is the
  tolerance, not the message.
- `Trigonometry.reduce_table` rebuilt its term from the *original* factor
  map inside the loop, so a term with two reducible squares kept only the
  last replacement (cos(u)**2*cos(v)**2 lost one half) and sin**2 + cos**2
  = 1 never closed. It reduces all of them in one pass now; the length of
  a sphere's surface normal depends on it (simplify_test).
- Every Expression class needs a case in `LaTeX.print`; `RootOf` had none
  for a year because nothing typeset one until `discuss` put roots in a
  report. The audit is cheap: build one of each node and call `LaTeX.of`.
- `filter_map` drops `false` as well as `nil`: a block returning a boolean
  sign silently loses every negative piece (this ate a sign chart once).
  Map to symbols instead.
- `Expand.table(e)` returns `[constant, { {base => exponent} => coeff }]`,
  as `Simplify.factorize` returns `[coeff, factors]`; destructure both.
- `Expression#evalf` can come back symbolic because folding puts an exact
  constant back *after* floatify (`exp(-1.0)` is `1/e` again); it now makes
  one more pass (`refloat`) and keeps it only if that ends in a number.
- `Array#-` in recombination, `or return` after multiple assignment
  (syntax error), `@x ||=` on frozen objects (use a class-level cache),
  `return x if (x = ...)` (the body is parsed before the condition:
  NameError).
- A polynomial over `Frac(QQ[a])[x]` times a parameter expression such as
  `1/(2*a)`: `Polynomial.ring_for` would make `a` a new ring variable.
  `Polynomial#scalar_in_base` catches that first; keep it when touching
  `combine`/`rop`.
- `PolyMatrix.prepare` scales each row by the lcm of its denominators and
  scales extra right-hand-side columns the same way, so solutions of the
  scaled system are already solutions of the original; do not rescale
  again (that cost 23 s on a 6x6 inverse before it was removed).
- **`Math.respond_to?(name)` is not a guard.** `include RCAS::Functions`
  into Object - which README tells a library user to do - gives the `Math`
  module itself a `floor`, so `Math.public_send(:floor, 2.5)` lands back in
  `Functions#floor` and folding recurses until the stack ends. Float
  folding compares against `Functions::MATH_NAMES` instead (found by the
  sixth pass of the review, 20 Sept 2026; it bit only the library path,
  since the three front ends include into a session object).
- Ruby's `Integer#prime?` is Miller-Rabin only below about 3.3e24 and
  trial division above; `Prime.prime_division` is trial division always.
  `NumberTheory` has its own tests for that reason - and since 19 Sept 2026
  the stdlib `prime` is not loaded at all (it cost 27 ms of a 120 ms load):
  `SMALL_PRIMES` is a sieve, `each_prime` replaces `Prime.each`, and
  `sqrt`/`log`/`GF` go through `NumberTheory.prime_division`, which takes
  `hard: false` for a caller that is only tidying a number and must not
  disappear into a factorization nobody asked for.

## Audience sections

MANUAL.md opens with `## Courses`: School, High school, College, University,
each a short tour with a real transcript and pointers into the numbered
sections. When a feature lands, ask which of the four it serves and add a
line there; that is the user's test for whether a feature belongs.

## Known limits / candidate next steps

Not implemented (keep this in step with MANUAL.md "2. Reference", which
lists the same gaps for the reader): full Risch, special functions beyond
erf, Ei, Si, Ci and li (the dilogarithm, and with it log(x)/(1 + x)),
rational functions needing a real factor of degree three or more
(1/(x**3 - 2), 1/(x**8 + 1)), ANOVA and non-parametric tests (Wilcoxon, KS),
geometry in space, conics, curves in space (plot3d.rb draws surfaces, not
those), surfaces given implicitly rather than by a graph or a
parametrization (vector_calculus.rb and plot3d.rb both ask for one),
differential forms
of their own, Fourier transforms (the *series* are in
fourier.rb), group
theory, ODEs with variable coefficients beyond first
order, inequalities with 2+ parameters or
non-polynomial parts, number fields with more than two generators,
polynomials over a non-commutative base (a matrix ring: `Domain#scalar?` is
false for `MatrixSpace`/`VectorSpace` and `PolynomialRing` refuses them,
since `Polynomial`'s coefficients are Expressions),
infinite products, formal power series whose
coefficients are not hypergeometric (`tan`, `exp(x)/(1 - x)`, Fibonacci
generating functions: `fps` refuses rather than guesses). Conway polynomials
for GF(p^n) (we take the lexicographically smallest irreducible). Of
OpenMath: the binary encoding and strict content MathML (both are further
*encodings* of the object model in openmath/objects.rb, not new
phrasebooks), attributions for assumptions, one-sided limits (rcas's
Limit node carries no direction, so limit1.above/below stay held), and of
POPCORN the typed-expression form `a::b`. Of Koepf's
book (Sept 2026) what is left: Almkvist-Zeilberger (hyperexponential
integration), Abramov's rational solutions, hypergeometric solutions of
*inhomogeneous* recurrences, multivariate (holonomic) summation, and
q-hypergeometric series as objects of their own; the q-twin of the FPS
algorithm (q-holonomic equations for q-Taylor coefficients) is the obvious
next step after fps.rb.

A second review (22 Sept 2026, MATHEMATICAL_REVIEW.md, also brought in by
the user) found eight wrong answers, all reproduced and all fixed with
tests; see "Branch cuts", "Differentiating under the integral sign" and
"Radii, projections, events, curvature" above. Its own suggestion for
further work is worth keeping: check *invariants* rather than transcripts -
a projection onto the whole space is the identity, substitution and
simplification commute, an area is not negative. A third (PEER_REVIEW.md,
the same day) then showed that four of those fixes still rested on samples
or on a float and found twelve more counterexamples: "The second review"
above is what came of it, and its lesson is the one to keep - **a
non-negative answer is a necessary invariant, not a sufficient one**, and
an exact rewriting needs a proof, not agreement at five points.

A code review (19 Sept 2026, an artifact the user brought in) found four
wrong answers, four inputs that never returned, and a list of rough edges;
all of them are fixed and each has a test. What the review changed about
the *shape* of answers, so that a future session does not "fix" it back:
`solve` sorts real roots ascending and answers `0 = 0` with `RealSet`,
polynomial sums come back factored, a hypergeometric closed form is read
back as a binomial coefficient where one fits (`Combinatorics.as_binomial`,
guessed and then checked at four integers), and `nintegrate` without
`digits:` is the tanh-sinh quadrature, not adaptive Simpson.

The user has asked for feature ideas five times and chose:
factorials/inequalities/trig/algebraic numbers, then finite fields, then
(Sept 2026) non-homogeneous and higher-order ODEs, rationalizing
substitutions in integrate and Gröbner bases, then (16 Sept 2026) Fourier
series with the bounded-oscillation limits they needed, `piecewise`, and a
bundle of small ones: matrix factorizations (lu/qr/cholesky/diagonalize/
jordan), arc length and solids of revolution, parametric and polar plots,
and Ei/Si/Ci/li - then arbitrary-precision evalf, after
"we don't include BigDecimal yet?", and then `steps`, the worked-solution
layer, which had been on the suggestion list twice before it was picked
(all 16 Sept 2026). What followed came from the
user directly: product/rsolve/complex parts/rounding/sequences,
interpolate, statistics, hypothesis tests and confidence intervals,
plotting (text and pictures, function and statistical), `/help NAME` with
Wikipedia references, the UTF-8 set symbols, the audience sections and a
German translation of the manual (MANUAL-de.md, removed again on 17 Sept
2026: "the german Manual is somewhat strange, remove it and leave it away"
- do not reintroduce it, and do not translate the manual anywhere else),
the numbered session `In`/`Out` (Sept 2026, after a
question about Mathematica's own In/Out), the formal power series `fps`
(Sept 2026, after asking whether rcas had one), the named polynomial
families in the `Poly` namespace (Sept 2026: "there are named classes of
polynomials - it'd be convenient to have them directly accessible, but not
in the global namespace"; the user chose `Poly.legendre(4, x)` over
`Polynomials.` and over a ring method `ZZ[x].legendre(4)`), and then, from
Koepf's *Hypergeometric Summation* (Sept 2026, "implement what's in the book"):
Petkovsek, Zeilberger and the whole q-side, and `discuss` (16 Sept 2026,
after asking whether the Kurvendiskussion is a German school thing: the
ritual as one report, and `steps(f, x, :discuss)` for the whole write-up), and
OpenMath (17 Sept 2026: the user asked whether it was known and then set the
design - an object model first, XML as one encoding of it, parsing that holds,
"for '1+2' in OpenMath isn't 3, it's the formal addition expression", and the
whole vocabulary in one place rather than a method per class), and then
POPCORN and OMFOREIGN (17 Sept 2026, after the user pointed at
github.com/symcomp/org.symcomp.openmath - which is the user's own library:
POPCORN is Horn & Roozemond, CICM 2009, so check the grammar there rather
than guessing, and ask rather than reconstruct), and then line and surface
integrals with Green, Stokes and Gauss (17 Sept 2026, on the parametric
curves that had just landed: vector_calculus.rb), and then random objects
(17 Sept 2026, "we need some more parameters": on the structures, with the
keywords that make an object worth fiddling with), and then `plot3d`
(20 Sept 2026, "can you create a plot3d method to plot 3d surfaces": the
last of the plotting gaps the manual listed). ODEs with variable
coefficients (Bernoulli, Riccati, exact equations, Cauchy-Euler, and
Frobenius series solutions, which are fps.rb run backwards) are the most
requested-adjacent remaining item; a `steps`/`explain` layer that narrates
a derivation was the other suggestion the user liked but did not pick.
