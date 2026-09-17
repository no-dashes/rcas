# frozen_string_literal: true

module RCAS
  # The mathematics behind a name, for the reader who wants more than the
  # result: what the operation is, and how rcas computes it. `doc(:integrate)`
  # and `/help integrate` show it; the keys in brackets are the sources listed
  # in MANUAL.md, section 4, so the curious can go to the original.
  #
  # Every entry is either { maths:, method: } or a Symbol pointing at another
  # entry. test/docs_test.rb checks that the names exist and that every source
  # key is in the bibliography.
  module Background
    ENTRIES = {
      # ---- expressions ---------------------------------------------------------
      simplify: {
        maths: "A canonical form: two expressions that are equal as polynomials in their atoms simplify to the same tree, so a - b simplifies to 0 exactly when a = b.",
        method: "Sums and products become term tables {factors => coefficient}, numbers fold, like terms merge, and the result is rebuilt in a fixed order: ascending degree, then graded lexicographic."
      },
      expand: {
        maths: "Distribute every product over the sums inside it and multiply out integer powers, giving a sum of monomials.",
        method: "One pass over the same term tables, merging like terms while multiplying, so (a + b)**n costs the size of its result, not the size of the tree."
      },
      factor: {
        maths: "Write a polynomial as a unit times powers of irreducible factors, over the integers or rationals (or an algebraic extension), or an integer as a product of primes. The factorization is unique.",
        method: "Squarefree decomposition [Yun76], factoring modulo a prime by Cantor-Zassenhaus [CZ81], Hensel lifting of that factorization and recombination [Zas69]; several variables by Kronecker substitution [Knu98]; over QQ(alpha) by Trager's norm trick [Tra76]; integers by trial division and Pollard-Brent rho [Bre80]."
      },
      cancel: {
        maths: "The rational normal form p/q with p and q coprime: nothing is lost, and a zero numerator is visible.",
        method: "Numerator and denominator are built over a polynomial ring and divided by their gcd."
      },
      rationalize: { maths: "Clear the denominators inside an expression, turning a nest of fractions into one fraction.", method: "Recursive normalisation with cancel." },
      apart: {
        maths: "Partial fractions: a rational function as a polynomial plus terms c/(irreducible)**k, which is what makes it integrable term by term.",
        method: "Squarefree factorization of the denominator, coprime splitting by the extended Euclidean algorithm, then a p-adic expansion for repeated factors [Bro05]."
      },
      gcd: {
        maths: "The greatest common divisor: the polynomial (or integer) of largest degree dividing both, unique up to a unit.",
        method: "Euclid's algorithm with primitive pseudo-remainder sequences, which keeps the coefficients from blowing up [Knu98, §4.6.1], [GCL92]."
      },
      lcm: :gcd,
      quo: { maths: "Division with remainder: f = q*g + r with deg r < deg g, the polynomial analogue of integer division.", method: "Long division over the field of fractions of the coefficients." },
      rem: :quo,
      divmod: :quo,
      numer: { maths: "Numerator and denominator of the integral normal form, so that f = numer(f)/denom(f) with polynomial parts.", method: "Term tables sort the factors by the sign of their exponent." },
      denom: :numer,
      degree: {
        maths: "The degree of a polynomial: the largest exponent of the indeterminate (ldegree the smallest, so a Laurent polynomial is bounded on both sides).",
        method: "Read off the term table; an expression that is not a polynomial in that indeterminate raises rather than guessing."
      },
      ldegree: :degree, lcoeff: :degree, tcoeff: :degree, coeff: :degree, coeffs: :degree,
      collect: { maths: "Write an expression as a sum of coefficient times power of one indeterminate, the other symbols becoming coefficients.", method: "Group the term table by the exponent of that indeterminate." },
      subs: { maths: "Substitution: replace a subexpression by another everywhere it occurs. Structural, not mathematical, so x**2 is found but not x*x.", method: "A bottom-up rebuild that compares subtrees with ==." },
      evalf: {
        maths: "A numeric value: every exact number becomes a decimal, so the result is an approximation and says so. With a number of digits it is an arbitrary-precision one, and then the digits are all true: a Float in the expression carries only its own sixteen, and the answer is reported with sixteen.",
        method: "Without digits the tree is floatified once and evaluated; integer exponents stay exact, so x**2 keeps its shape. With digits it is walked in BigDecimal with ten guard digits and rounded once at the end: the elementary functions from BigMath [AS64, §4.1, §4.3], erf, Si, Ci, Ei and li from their series, zeta by Euler-Maclaurin [AS64, §23.2], Euler's constant by Brent-McMillan [BM80], a real RootOf by Newton's method [PTVF07, §9.4] and a definite integral by the double-exponential rule [TM74]. What is left says so instead of padding sixteen good digits out to fifty."
      },
      steps: {
        maths: "The working, not only the answer: which rule applies, what its pieces are, and what they give. A student who is learning the mathematics needs the derivation; someone who only wants the number has diff, integrate and solve already.",
        method: "One narrator per topic decides which rule applies and then asks the library for the piece it names, so the working cannot end anywhere other than the ordinary answer. Covered: the rules of differentiation; the power rule, the table, substitution and parts; linear and quadratic equations; factoring by common factors, difference of squares and rational roots, and integers by trial division; the partial-fraction ansatz; Gaussian elimination; and Euclid's algorithm [Spi08], [Knu98, §4.5.2]. Where no textbook rule fits, the line says so."
      },
      hold: {
        maths: "An unevaluated expression, MuPAD's hold: the notation itself, not its value. evaluate (also doit) computes it later.",
        method: "The block's source is read back from Ruby's abstract syntax tree, so integrate, diff, sum and limit inside it become formal nodes."
      },
      evaluate: :hold,

      openmath: {
        maths: "OpenMath [OM19] writes down what a mathematical object *means*, with the notation left out. A symbol is a name in a content dictionary - arith1.plus is that dictionary's addition - so two systems agree on the mathematics rather than on the spelling. The object is an abstract tree; XML, the binary encoding and strict content MathML are ways of writing it down.",
        method: "One table maps rcas's nodes to the symbols of the official dictionaries in both directions: applications for the operators and functions, fns1.lambda bindings for the bound variable of an integral, sum, limit or derivative, and rcas's own dictionary for the names OpenMath has none for. A symbol with no row stays as an unknown function named after its dictionary, so a document survives the round trip unchanged."
      },
      from_openmath: :openmath,

      # ---- calculus -------------------------------------------------------------
      diff: {
        maths: "The derivative: the limit of the difference quotient, computed by the rules rather than the limit.",
        method: "Sum, product, quotient and chain rules applied structurally; a power with the variable in both base and exponent goes through u**v = exp(v log u). An unknown function stays a Derivative node."
      },
      piecewise: {
        maths: "A function given case by case, f(x) = -x for x < 0 and x**2 otherwise. The pieces need not fit together: where they do not, the function jumps or has a corner, and that is exactly what makes these functions worth studying.",
        method: "The conditions become real sets (inequalities.rb) and the first one that holds decides. Differentiating and integrating work branch by branch; the antiderivative of each piece is shifted by the constant that continues the previous piece at their common endpoint, so that it is continuous and definite integrals across a breakpoint are right."
      },
      discontinuities: {
        maths: "The points where a function jumps: the one-sided limits exist but disagree, or they agree and the value is different.",
        method: "The breakpoints of the piecewise definition are the only candidates; at each one the two one-sided limits and the value are compared."
      },
      kinks: {
        maths: "The corners: points where the function is continuous but has no derivative, because the slopes on the two sides differ (|x| at 0).",
        method: "Each branch is differentiated and the one-sided limits of the derivative are compared at the breakpoints that are not jumps."
      },
      integrate: {
        maths: "An antiderivative F with F' = f, or a definite integral F(b) - F(a) with limits at infinite or singular ends. Not every elementary function has an elementary antiderivative, so a piece that has none stays an integral(...) node.",
        method: "Four layers: a table of standard forms with derivative-divides substitution, integration by parts and absolute values of a linear argument; rational functions exactly by Hermite reduction and the Lazard-Rioboo-Trager logarithmic part [Her72], [Mac75], [LR90], [Bro05], falling back on the real quadratic factors of a biquadratic denominator [Har16]; a Risch-Norman ansatz whose undetermined coefficients come from linear algebra [NM77]; and substitutions that rationalize roots, ratios of linear forms, exponentials and sin/cos [Zor15]."
      },
      limit: {
        maths: "The value a function approaches, one-sided with dir:, and at infinity. A two-sided limit whose sides disagree stays unevaluated rather than being invented.",
        method: "The point is moved to 0, the function expanded as a Puiseux series with log terms, and the leading term decides. An exponential fallback takes the limit of the logarithm, and the squeeze rule [Rud76] handles a bounded factor (sin, cos, sign, atan, erf, tanh) times one that tends to zero, which has no series at the point. This is the textbook strategy, not Gruntz's MRV algorithm [Gru96]."
      },
      series: {
        maths: "The Puiseux expansion around a point: a power series with rational exponents and log terms, truncated with an O term that states the order.",
        method: "Series arithmetic on {exponent => coefficient} maps, with composition for the elementary functions [Knu98, §4.7]. taylor is the same without the O term."
      },
      taylor: :series,
      Si: {
        maths: "The sine integral Si(x) = integral(sin(t)/t, t, 0, x). sin(x)/x has no elementary antiderivative, so this is the answer, not a way of avoiding one; Si(oo) = pi/2 is the Dirichlet integral.",
        method: "Values by the power series below 2 and by a continued fraction above it [PTVF07, §6.3], [AS64, §5.2]."
      },
      Ci: :Si,
      Ei: {
        maths: "The exponential integral Ei(x) = integral(exp(t)/t, t, -oo, x) as a principal value, the antiderivative of exp(x)/x. The logarithmic integral li(x) = Ei(log(x)) counts the primes below x better than x/log(x) does.",
        method: "The series gamma + log|x| + sum(x**k/(k*k!)) for moderate x, the asymptotic expansion exp(x)/x*sum(k!/x**k) beyond it [AS64, §5.1], [PTVF07, §6.3]."
      },
      li: :Ei,
      arclength: {
        maths: "The length of a curve: integral(sqrt(1 + f'**2)) for a graph, integral(sqrt(x'**2 + y'**2)) for a parametric one. The integrand is a square root of a polynomial, so the integral is often not elementary - that is the nature of the question, not a gap.",
        method: "The integrand is assembled and handed to integrate; what it cannot do stays an integral(...) node for evalf or nintegrate [Spi08, ch. 13]."
      },
      revolution_volume: {
        maths: "The volume a graph sweeps out when it is turned about an axis: pi*integral(f**2) about the x-axis (discs), 2*pi*integral(x*f) about the y-axis (cylindrical shells).",
        method: "The integral of the disc or shell formula [Spi08, ch. 13]."
      },
      revolution_surface: {
        maths: "The area of that surface: 2*pi*integral(f*sqrt(1 + f'**2)), the arc length element turned about the axis.",
        method: "The integral of the frustum formula [Spi08, ch. 13]."
      },
      lu: {
        maths: "P*A = L*U: Gaussian elimination written as a product. L records the multipliers, U is what elimination leaves, P the row swaps. Determinants, solving and inverting all read off it.",
        method: "Elimination in exact arithmetic, so rows are swapped only to get away from a zero pivot - there is no rounding to steer around [Str16, ch. 2]."
      },
      qr: {
        maths: "A = Q*R with the columns of Q orthonormal: Gram-Schmidt on the columns of A, kept as a factorization. It is what least squares problems are solved with.",
        method: "Exact Gram-Schmidt (linear_algebra.rb), so the entries of Q carry square roots; R is Q'*A [Str16, ch. 4]."
      },
      cholesky: {
        maths: "A = L*L' for a symmetric positive definite A: the square root of a matrix, half the work of LU and the test for positive definiteness at the same time.",
        method: "The entries in order, each one a square root or a division; a non-positive diagonal entry means the matrix is not positive definite [Str16, ch. 6]."
      },
      diagonalize: {
        maths: "A = P*D*P**-1 with D diagonal: the eigenvectors as the columns of P. It exists exactly when there are enough independent eigenvectors, and then powers and exponentials of A are easy.",
        method: "The eigenvectors of matrix.rb, checked for independence [Str16, ch. 6]."
      },
      jordan: {
        maths: "A = P*J*P**-1 with J made of Jordan blocks: the normal form every square matrix has, diagonal where there are enough eigenvectors and with ones above the diagonal where there are not.",
        method: "For each eigenvalue the kernels of (A - lambda)**k are built up, and a basis of chains v, (A - lambda)v, ... is chosen in them; one block per chain [HK71, ch. 7]."
      },
      parametric: {
        maths: "A curve given by its two coordinates as functions of a parameter. It may loop and cross itself, which the graph of a function cannot.",
        method: "The parameter is sampled and the points joined in that order."
      },
      polar: {
        maths: "A curve given by its distance from the origin as a function of the angle: r = 1 + cos(t) is a cardioid, r = t a spiral. A negative r points the other way.",
        method: "Drawn as the parametric curve (r*cos(t), r*sin(t)); the angle runs over a full turn unless another range is given."
      },
      fourier: {
        maths: "The Fourier series of a periodic function: a sum of sines and cosines with the coefficients a_k = (2/T)*integral(f*cos(k*omega*x)) and b_k the same with sin. Where f jumps, the series converges to the mean of the two sides, and the partial sums overshoot however many terms are taken (Gibbs' phenomenon).",
        method: "The coefficients are the definite integrals, computed with the index assumed to be an integer, which is what turns sin(k*pi) into 0 and cos(k*pi) into (-1)**k and so gives the general coefficient in closed form. The half-range forms expand the odd or the even extension on [0, L]. Convergence is not checked [Spi08, ch. 13]."
      },
      fps: {
        maths: "The formal power series of a function: the general coefficient in closed form, sum(x**k/k!, k, 0, oo) for exp(x), rather than the first few terms of the expansion.",
        method: "Koepf's FPS algorithm [Koe92], [Koe14, ch. 10]: a homogeneous differential equation with polynomial coefficients is found for f with undetermined coefficients, its coefficient recurrence is read off, and the two-term case - the one an m-fold symmetric hypergeometric coefficient satisfies - is solved by multiplying up the ratio. Gauss's multiplication formula [AS64, §6.1] turns the gammas back into factorials."
      },
      sum: {
        maths: "A closed form for a finite or infinite sum, so that sum(k**2, k: 1..n) becomes a polynomial in n rather than a loop.",
        method: "Polynomials by Faulhaber's formula through Newton interpolation [GKP94]; hypergeometric terms by Gosper's algorithm, which decides whether an antidifference exists [Gos78]; 1/n**s by the zeta function; classical power series recognised from the ratio of consecutive terms; a definite sum in one other variable by creative telescoping, whose recurrence is then solved [Zei91]."
      },
      product: {
        maths: "The product analogue of sum: prod(k, k: 1..n) is n!, and a polynomial factor gives ratios of gamma values since prod(k + r) = gamma(b + r + 1)/gamma(a + r).",
        method: "The term is split into factors: constants give powers, a**u(k) gives a**sum(u), and a polynomial is factored into linear factors over QQ [GKP94, §5.5]."
      },

      sumrecursion: {
        maths: "Zeilberger's algorithm, creative telescoping: a definite hypergeometric sum such as sum_k binomial(n, k)**2 satisfies a linear recurrence in n, and that recurrence is what a computer can find and prove even when the sum itself has no closed form.",
        method: "Gosper's algorithm applied to a whole pencil sum_j sigma_j*F(n + j, k) at once: dividing by F(n, k) leaves rational functions, the sigmas sit linearly in the c part of the Gosper-Petkovsek normal form, and one null space gives the sigmas and the certificate together [Zei91], [Koe14, ch. 7]. Carrying the identity over to the sum needs the boundary terms to vanish, which is checked."
      },
      sumcertificate: :sumrecursion,
      hyper: {
        maths: "Petkovsek's algorithm: the hypergeometric solutions of a linear recurrence with polynomial coefficients, that is the solutions whose ratio u(n + 1)/u(n) is rational. As many of them as the order of the recurrence span its solution space; fewer means the rest are not hypergeometric.",
        method: "Every such ratio is z*a(n)/b(n)*c(n + 1)/c(n) with a dividing p_0, b dividing p_r(n + r - 1) and gcd(a(n), b(n + h)) = 1 for h >= 0, so the monic divisors are run through, the possible z read off the leading coefficients, and the polynomial c found with a degree bound of Abramov's [Pet92], [Koe14, ch. 9], [PWZ96, ch. 8]."
      },
      qbinomial: {
        maths: "The q-analogues: [n]_q = 1 + q + ... + q**(n - 1) becomes n as q approaches 1, and with it the q-factorial, the Gaussian binomial coefficient and the q-Pochhammer symbol (a; q)_n = (1 - a)(1 - a*q)...(1 - a*q**(n - 1)), which plays the part the rising factorial plays for ordinary hypergeometric terms.",
        method: "Integer arguments fold to polynomials in q; symbolic ones stay as they are and the algorithms expand them into q-Pochhammer symbols themselves [Koe14, ch. 10], [GR04, ch. 1]."
      },
      qpochhammer: :qbinomial,
      qfactorial: :qbinomial,
      qbracket: :qbinomial,
      qsum: {
        maths: "The q-analogue of Gosper's algorithm: a term is q-hypergeometric when t(k + 1)/t(k) is a rational function of q**k, and the question is again whether it has an antidifference of the same kind.",
        method: "With x = q**k the shift k -> k + 1 becomes x -> q*x, and Gosper's steps go through unchanged: the q-Gosper-Petkovsek normal form a(x)/b(x)*c(q*x)/c(x) with gcd(a(x), b(q**h*x)) = 1 for h >= 0, then a polynomial X with a(x)*X(q*x) - b(x/q)*X(x) = c(x) [Koo93], [Koe14, ch. 11]."
      },
      qgosper: :qsum,
      qsumrecursion: {
        maths: "Zeilberger's algorithm in the q-world: the recurrence a definite q-hypergeometric sum obeys, which is how identities such as the q-binomial theorem are proved.",
        method: "q-Gosper applied to the pencil sum_j sigma_j*F(n + j, k), with x = q**k and y = q**n; the sigmas come out rational in q**n [Koe14, ch. 12], [Zei91]."
      },
      qsumcertificate: :qsumrecursion,
      qsolve: {
        maths: "Linear q-difference equations, p_0(x)*f(x) + ... + p_r(x)*f(q**r*x) = 0, and their q-hypergeometric solutions. At x = q**n such a solution is a product of q-Pochhammer symbols and powers, which is the form these answers are written in.",
        method: "Petkovsek's algorithm with the shift x -> q*x: divisors of p_0 and of p_r(q**(r - 1)*x), the possible z from the leading coefficients, and a polynomial c whose degree is read off the roots of sum_j lc(Q_j)*(q**d)**j [APP98], [Koe14, ch. 12]."
      },
      qhyper: :qsolve,

      # ---- equations -------------------------------------------------------------
      solve: {
        maths: "Exact solutions. A polynomial of degree n has n complex roots with multiplicity, but only degrees 1 to 4 have general radical formulas, so a root that cannot be written in radicals is returned as an exact RootOf object you can still compute with.",
        method: "Factor over QQ, then radicals for linear, quadratic, binomial and biquadratic factors, RootOf otherwise; transcendental equations by substituting an atom and inverting; abs and sign by the case split, every candidate substituted back; linear systems by row reduction; polynomial systems by a lex Gröbner basis, which is triangular, then back-substitution [CLO15]."
      },
      groebner: {
        maths: "A Gröbner basis generates the same ideal but with a unique remainder on division, so it answers ideal membership and, in the lex order, triangularizes a polynomial system the way row reduction triangularizes a linear one.",
        method: "Buchberger's algorithm: reduce S-polynomials until none is left, skipping pairs with coprime leading monomials, then make the basis minimal and reduced [Buc65], [CLO15]."
      },
      reduce: { maths: "The normal form of f modulo a basis: the remainder of multivariate division, which is zero exactly when f lies in the ideal.", method: "Repeated cancellation of the leading monomial, in the given monomial order [CLO15]." },
      dsolve: {
        maths: "Solutions of an ordinary differential equation. A linear equation of order n has an n-dimensional solution space, hence the constants C1, C2, ...; a particular solution is added when the equation has a forcing term.",
        method: "First order by separation of variables or the integrating factor; constant coefficients by the roots of the characteristic polynomial, with x**j factors for repeated roots; forcing terms by undetermined coefficients, otherwise variation of parameters [BD12]."
      },
      rsolve: {
        maths: "The discrete twin of dsolve: a linear recurrence solved in closed form, so the Fibonacci rule gives Binet's formula and u(n + 1) = n*u(n) gives the factorial.",
        method: "Constant coefficients: characteristic roots for the homogeneous part, undetermined coefficients for a polynomial times b**n, initial values fixed by a linear system [GKP94, §7.3]. Coefficients that depend on n: Petkovsek's algorithm for the hypergeometric solutions, and a general solution only when there are as many of them as the order of the recurrence [Pet92]."
      },
      interpolate: { maths: "The unique polynomial of degree below n through n points with distinct nodes.", method: "Newton's divided differences, in exact arithmetic, so rational or symbolic data gives an exact polynomial [Knu98, §4.6.4]." },
      resultant: {
        maths: "A polynomial in the coefficients that vanishes exactly when two polynomials share a root; eliminating a variable from two equations.",
        method: "The determinant of the Sylvester matrix, computed by fraction-free elimination [GCL92], [CLO15]."
      },
      discriminant: { maths: "Vanishes exactly when a polynomial has a repeated root; for a quadratic it is the familiar b**2 - 4ac.", method: "The resultant of f and its derivative, divided by the leading coefficient." },
      minpoly: { maths: "The monic rational polynomial of least degree having the given algebraic number as a root; it defines the number and its field extension.", method: "Resultants eliminate the radicals, and the correct factor is chosen numerically [Loo83]." },

      # ---- numbers ----------------------------------------------------------------
      isprime: { maths: "Primality: no divisor besides 1 and itself.", method: "Miller-Rabin, deterministic below 3.3e24 with the known witness sets, a strong probable-prime test beyond [Mil76], [Rab80b], [SW17]." },
      ifactor: { maths: "The prime factorization of an integer, unique by the fundamental theorem of arithmetic.", method: "Trial division by small primes, then Pollard-Brent rho, whose expected cost grows as the fourth root of the number [Pol75], [Bre80]." },
      divisors: { maths: "All positive divisors, from the prime factorization.", method: "Every product of the prime powers, sorted." },
      totient: { maths: "Euler's phi: how many numbers below n are coprime to n, and the exponent in Euler's theorem.", method: "The product formula over the prime factors." },
      invmod: { maths: "The inverse modulo m, which exists exactly when the number is coprime to m.", method: "The extended Euclidean algorithm." },
      chrem: { maths: "The Chinese remainder theorem: simultaneous congruences have one solution modulo the lcm of the moduli, when they are consistent.", method: "Pairwise combination with the extended Euclidean algorithm [Coh93, §1.3]." },
      binomial: { maths: "The number of k-subsets of n things, the coefficient in (1 + x)**n, extended to any upper index by the falling factorial.", method: "The falling factorial over k!, cancelled exactly; symbolic upper index stays unevaluated." },
      factorial: { maths: "n! counts the orderings of n things; gamma extends it to non-integers with gamma(n + 1) = n!.", method: "Exact for integers and half-integers (the gamma reflection gives sqrt(pi)), and ratios such as (k + 2)!/k! cancel to polynomials, which is what lets sum handle them." },
      gamma: :factorial,
      fibonacci: { maths: "The sequence with F(n) = F(n-1) + F(n-2); its growth rate is the golden ratio, which rsolve derives.", method: "Fast doubling, so F(n) costs O(log n) multiplications." },
      bernoulli: { maths: "The Bernoulli numbers, the coefficients in the expansion of x/(e**x - 1); they appear in Faulhaber's sum formula and in zeta(2m).", method: "The recurrence from the defining series, cached." },
      harmonic: { maths: "H(n) = 1 + 1/2 + ... + 1/n, the discrete logarithm: it diverges like log n, which is why sum(1/k) has no closed form.", method: "Exact rational summation." },
      erf: { maths: "The error function: twice the area under the normal curve from 0 to x, scaled so that erf(oo) = 1. It is not elementary, which is why the integral of exp(-x**2) is written with it.", method: "A Taylor series for small arguments and a Ruby float otherwise; integrate produces it by completing the square [AS64, §7.1]." },
      erfc: :erf,

      # ---- structures ---------------------------------------------------------------
      assume: { maths: "Declaring the domain of an indeterminate: with x in ZZ, statements that hold only for integers become available, and inference can narrow the domain of an expression.", method: "A table of assumptions consulted by Infer, which computes the smallest of NN, ZZ, QQ, RR, CC that must contain a value." },
      GF: { maths: "The finite field with q = p**n elements, unique up to isomorphism: arithmetic modulo a prime for n = 1, and polynomials modulo an irreducible one otherwise.", method: "Mod arithmetic, an irreducible polynomial found by Rabin's test, and factorization by distinct-degree and equal-degree splitting [CZ81], [Rab80]." },
      matrix: { maths: "A matrix over a domain: a linear map in coordinates. Determinant, rank, kernel and eigenvalues are the invariants a first course computes.", method: "Gaussian elimination with exact arithmetic, cofactor expansion for small sizes, and for polynomial entries evaluation at rational points with Newton interpolation [Hor08]." },
      vector: { maths: "An element of a free module or vector space, with dot and cross products and a norm.", method: "Entries stay exact; the space records the domain, which widens as needed." },
      plot: { maths: "A picture of a function: pairs (x, f(x)) joined into a curve. What a sampled picture cannot show is what happens between the samples, so a pole is broken rather than bridged.", method: "Uniform sampling, Bresenham line drawing on a braille canvas [Bre65], and a y range trimmed to the central 96 per cent so one pole does not flatten the rest." },

      # ---- statistics -----------------------------------------------------------------
      mean: { maths: "The arithmetic mean, the balance point of the data; the median is the middle value and resists outliers, the mode is the most frequent one.", method: "Exact rational arithmetic, so no rounding creeps in." },
      median: :mean, mode: :mean,
      variance: {
        maths: "The mean squared deviation. Dividing by n - 1 (Bessel's correction) makes it an unbiased estimate of the variance of the population the sample came from; sample: false gives the population value. The standard deviation is its square root.",
        method: "Exact sums of squared deviations about the sample mean."
      },
      stdev: :variance,
      quantile: { maths: "The value below which a given share of the data lies; the quartiles cut it into four.", method: "Linear interpolation between order statistics, definition 7 of Hyndman and Fan, the default of R and Excel [HF96]." },
      quartiles: :quantile, iqr: :quantile,
      skewness: { maths: "Standardized third and fourth central moments: skewness measures the lopsidedness, kurtosis the weight of the tails (3 for a normal sample).", method: "Central moments divided by the appropriate power of the second one." },
      kurtosis: :skewness, moment: :skewness,
      covariance: { maths: "How two variables vary together; the correlation is the covariance divided by both standard deviations, so it lies between -1 and 1 and is dimensionless.", method: "Exact sums of products of deviations." },
      correlation: :covariance,
      linreg: { maths: "The least squares line: the one minimising the sum of squared vertical distances. Its slope is the covariance over the variance of x, and it passes through the mean point.", method: "The closed form, evaluated exactly [Ros14, ch. 7]." },
      histogram: { maths: "The shape of a sample: how many values fall in each equal bin, an estimate of the density.", method: "Equal bins over the range, their number from Sturges' rule unless you give one [Stu26]." },
      boxplot: { maths: "The five-number summary: median, quartiles, and whiskers to the last value within 1.5 interquartile ranges, with the rest marked as outliers, so the spread and the strays are visible at once.", method: "Order statistics as in quantile, Tukey's rule for the whiskers [Tuk77]." },
      barchart: { maths: "One bar per category: the frequency distribution of data that is not numeric.", method: "Counts as given, or from frequencies." },
      pdf: { maths: "The density of a continuous distribution (its integral over an interval is the probability) or the probability of one value for a discrete one; the cdf is the probability of not exceeding x, and the quantile inverts it.", method: "Exact formulas in the parameters; the normal cdf through erf, the t, chi-square and F cdfs through the regularized incomplete beta and gamma functions [AS64], [PTVF07]." },
      cdf: :pdf, probability: :pdf,
      ttest: {
        maths: "Tests whether a mean differs from a claim, or two means from each other. Under the null hypothesis the statistic follows Student's t distribution, and the p value is the probability of a statistic at least as extreme; it is not the probability that the hypothesis is true.",
        method: "Welch's unequal-variance test by default, with its fractional degrees of freedom [Wel47]; the pooled and paired variants on request [Ros14, ch. 9]."
      },
      ztest: { maths: "The same comparison of means when the standard deviation is known, so the statistic is normal rather than t.", method: "The normal cdf." },
      chisquare_test: { maths: "Compares counts with what a model expects: the goodness-of-fit test against given probabilities, or the test of independence in a contingency table, where the expected counts come from the row and column totals.", method: "The sum of (observed - expected)**2/expected, exact when the data is, against the chi-square distribution with the degrees of freedom left after fitting." },
      ftest: { maths: "Compares two variances through their ratio, which follows the F distribution under the null hypothesis of equal variances.", method: "The ratio of sample variances against the F cdf." },
      binomial_test: { maths: "The exact test for a proportion: no approximation at all, the p value is a sum of binomial probabilities.", method: "Two-sided, the sum of the probabilities of every outcome no more likely than the observed one, which keeps the p value a rational number." },
      confidence_interval: {
        maths: "An interval that would cover the true parameter in the stated share of repeated samples. It is a statement about the procedure, not a probability that this one interval contains the value.",
        method: "Student t for a mean (normal when sigma is known), the chi-square distribution for a variance, and Wilson's score interval for a proportion [Wil27]."
      },
      proportion_interval: :confidence_interval,
      nsolve: {
        maths: "A root as a decimal, for an equation no formula solves: cos(x) = x has exactly one, and no expression in radicals, logarithms or roots gives it.",
        method: "Bisection on a bracketing interval, taking a Newton step whenever it stays inside the bracket, so it converges quickly and cannot run away [PTVF07, §9.1-9.4]. With digits: the double-precision root is refined by Newton's method in BigDecimal, which doubles the number of correct digits at every step."
      },
      nintegrate: {
        maths: "A definite integral as a decimal. Most elementary functions have no elementary antiderivative, so this is the usual way to a number; the result is an approximation and prints as one.",
        method: "Adaptive Simpson quadrature, halving an interval until the two halves agree [PTVF07, §4.2]; an infinite range is mapped to a finite one by a substitution. With digits: the double-exponential (tanh-sinh) rule [TM74], which converges doubly exponentially and smothers a singular endpoint; the point is measured from the near end so that nothing cancels there."
      },
      extrema: {
        maths: "The high and low points of a graph. They lie among the critical points, where the derivative vanishes, and the second derivative tells a maximum from a minimum; where it also vanishes the first derivative changes sign, or does not, as for x**3.",
        method: "solve on the derivative, then the sign of the second derivative, falling back to a numeric comparison on either side."
      },
      critical_points: :extrema,
      discuss: {
        maths: "Every question a course asks about a graph, in the order it asks them: the domain, symmetry and periodicity, the zeros and the value at 0, the gaps and what happens at them, the limits at infinity and the lines the graph approaches, then the extrema, the monotonicity, the inflections and the curvature. The point of the ritual is that the answers hold each other up: an extremum between two zeros, a sign of f' that fits the shape, a pole where an asymptote is.",
        method: "Each question goes to the function that owns it (real_domain, solve, limit, extrema, inflections, asymptotes), so the report cannot disagree with them; what rcas cannot decide is reported as undecided rather than dropped. Monotonicity and curvature come from a sign chart: the line cut at the zeros of f' (of f'') and at the gaps, the sign of each piece read off three sample points [Spi08, ch. 11]. steps(f, x, :discuss) writes the whole thing out."
      },
      inflections: { maths: "Where the curvature changes sign, so the graph turns from bending one way to the other; the second derivative vanishes and changes sign there.", method: "solve on the second derivative, with the third derivative or a sign check to confirm." },
      asymptotes: {
        maths: "The lines a graph approaches: vertical at a pole, horizontal or oblique at infinity, where the function comes arbitrarily close to a line y = m*x + c.",
        method: "The zeros of the denominator for the vertical ones; for the others the limits of f and of f/x at plus and minus infinity."
      },
      tangent: { maths: "The line touching the graph at a point, f(a) + f'(a)*(x - a): the best linear approximation there, which is what the derivative means. The normal is perpendicular to it.", method: "Two evaluations of f and its derivative." },
      normal: :tangent,
      real_domain: { maths: "Where a real expression makes sense: denominators non-zero, even roots of non-negative numbers, logarithms of positive ones.", method: "Each condition becomes an inequality, and the sign-chart solver intersects the solutions." },
      gradient: {
        maths: "The vector of partial derivatives. It points in the direction of steepest increase and is perpendicular to the level curves, which is why it appears in every optimisation problem.",
        method: "One derivative per variable."
      },
      hessian: { maths: "The matrix of second derivatives. Its definiteness classifies a critical point in several variables the way the second derivative does in one; the determinant test is the two-variable case.", method: "Second partial derivatives; they commute for the smooth functions rcas handles." },
      jacobian: { maths: "The matrix of first derivatives of a map from several variables to several. It is the linear map the function looks like near a point, and its determinant is the factor by which areas or volumes change.", method: "One row per component." },
      divergence: { maths: "How much a vector field spreads out of a point (the trace of its Jacobian); the curl measures how much it circulates; the Laplacian is the divergence of the gradient.", method: "The sums of the appropriate partial derivatives." },
      curl: :divergence,
      laplacian: :divergence,
      lagrange: {
        maths: "Extremes under a constraint: at a constrained extreme the gradient of the objective is a combination of the gradients of the constraints, because no direction along the constraint improves the value. The multipliers are those coefficients.",
        method: "The multiplier equations together with the constraints are handed to the polynomial system solver [Spi08, ch. 17]."
      },
      point: { maths: "Analytic geometry: a point is a pair of coordinates, a line the solutions of a*x + b*y + c = 0, a circle the points at a fixed distance from a centre. Geometry becomes algebra, which is what makes it computable.", method: "Exact coordinates throughout, so a distance is a square root and a right angle is exactly pi/2." },
      line: :point, circle: :point,
      distance: { maths: "Between two points the Pythagorean length; from a point to a line the shortest one, along the perpendicular; between parallel lines the constant gap.", method: "The Pythagorean formula, and for a line the normal form |a*x + b*y + c| divided by the length of (a, b)." },
      midpoint: :distance,
      angle: { maths: "The angle in a corner, from the cosine rule in the form of the dot product: cos of the angle is the dot product over the product of the lengths.", method: "acos of that quotient, which folds to a multiple of pi at the familiar values." },
      area: { maths: "The area of a triangle from its corners by the shoelace formula, half the absolute value of a cross product; for a circle pi*r**2.", method: "The determinant of the two edge vectors [Bra86]." },
      perimeter: :area,
      intersect: { maths: "Where two figures meet: two lines in one point unless they are parallel, a line and a circle in two points, one or none, two circles likewise.", method: "A 2 by 2 system for two lines; for a circle the foot of the perpendicular from the centre and the Pythagorean half-chord; two circles are subtracted to give the radical line." },
      circumcircle: { maths: "The circle through three points, centred where the perpendicular bisectors meet, since that point is equidistant from all three.", method: "Intersecting two perpendicular bisectors." },
      collinear?: { maths: "Whether three points lie on one line, which is exactly when the triangle they span has zero area.", method: "The cross product of the two edge vectors." },
      centroid: { maths: "The average of the corners: the centre of mass of equal weights, where the medians of a triangle meet.", method: "The mean of the coordinates." },
      perpendicular_bisector: { maths: "The line of all points equidistant from two given ones; it meets the segment at its midpoint at a right angle.", method: "The direction of the segment as the normal, through the midpoint." },
      gram_schmidt: {
        maths: "An orthogonal basis of the same span: each vector has the projection onto the earlier ones subtracted, so what remains is perpendicular to them. Normalising gives an orthonormal basis, in which coordinates are just dot products.",
        method: "The classical Gram-Schmidt process, exactly, so the normalised vectors keep their square roots [Str16, ch. 4]."
      },
      project: { maths: "The projection of a vector onto another, or onto the span of several: the closest point of that subspace, with the difference perpendicular to it.", method: "The sum of the projections onto an orthogonal spanning set." },
      least_squares: {
        maths: "The best fit when a system has no solution: the x minimising the length of A*x - b. Geometrically b is projected onto the column space, which is why the residual is perpendicular to it.",
        method: "The normal equations A'*A*x = A'*b, solved exactly [Str16, ch. 4]."
      },
      orthogonal?: :project,
      laplace: {
        maths: "The transform that turns differentiation into multiplication by s, so a linear differential equation becomes an algebraic one. Initial values enter the transform, which is why it suits initial value problems.",
        method: "A table plus two rules: the first shift for exp(a*t)*f(t), and multiplication by t as differentiation in s [BD12, ch. 6]."
      },
      inverse_laplace: {
        maths: "Back from the transform to the function, the step that finishes the solution of a differential equation.",
        method: "Partial fractions, then the table read backwards: a linear factor gives an exponential, a repeated one a power of t, an irreducible quadratic a damped sine and cosine."
      },
      congruence: {
        maths: "Solutions of a polynomial equation modulo m, the arithmetic of remainders. A linear congruence a*x = b has gcd(a, m) solutions when that gcd divides b, and none otherwise.",
        method: "The extended Euclidean algorithm for the linear case, a search over the residues otherwise."
      },
      legendre: {
        maths: "Whether a is a square modulo the odd prime p: the Legendre symbol is 1 when it is, -1 when it is not, 0 when p divides a. The Jacobi symbol extends it to odd composite moduli.",
        method: "Euler's criterion for Legendre, quadratic reciprocity for Jacobi [Coh93, §1.4]."
      },
      jacobi: :legendre,
      order: { maths: "The multiplicative order of a modulo m is the smallest k with a**k = 1; it divides Euler's phi (Lagrange's theorem). A primitive root is an element whose order is phi, that is a generator of the group.", method: "Testing the divisors of phi in increasing order." },
      primitive_root: :order,
      continued_fraction: {
        maths: "Every real number is a0 + 1/(a1 + 1/(a2 + ...)); the expansion stops exactly for rationals, repeats for quadratic irrationals, and its convergents are the best rational approximations there are, which is how 355/113 approximates pi.",
        method: "Repeatedly take the whole part and invert the rest; the convergents come from the recurrence p(n) = a(n)*p(n-1) + p(n-2) [Knu98, §4.5.3], [HW08, ch. 10]."
      },
      convergents: :continued_fraction,


      # ---- distributions ----------------------------------------------------------------
      Normal: {
        maths: "The bell curve: the limit of a sum of many small independent effects (the central limit theorem), which is why so much is approximately normal. Two thirds of the mass lies within one standard deviation of the mean, 95 per cent within two.",
        method: "The density in closed form; the distribution function through erf, since it has no elementary antiderivative; quantiles by bisection and a Newton step."
      },
      Uniform: { maths: "Every value in an interval equally likely: the density is constant, so probabilities are lengths.", method: "Closed forms throughout." },
      Exponential: { maths: "The waiting time until the next event when events arrive at a constant rate, the continuous counterpart of the geometric distribution. It is memoryless: waiting longer does not bring the event nearer.", method: "Closed forms; the k-th moment is k!/rate**k." },
      Bernoulli: { maths: "One trial with two outcomes, the building block of the binomial distribution.", method: "Closed forms." },
      Binomial: { maths: "The number of successes in n independent trials with the same probability. Its mean is n*p, and for large n it approaches a normal distribution.", method: "The binomial coefficient times the powers, exact in rational arithmetic, so probabilities stay fractions." },
      Poisson: { maths: "The number of events in a fixed interval when they arrive independently at a constant rate; the limit of Binomial(n, rate/n) as n grows. Mean and variance are both the rate.", method: "The closed form with the factorial; the distribution function as a finite sum." },
      Geometric: { maths: "The number of failures before the first success, the discrete memoryless distribution.", method: "Closed forms; here k counts failures, so it starts at 0, as in Maple and Mathematica." },
      DiscreteUniform: { maths: "Every integer in a range equally likely, as a fair die.", method: "Closed forms." },
      StudentT: {
        maths: "The distribution of a sample mean when the standard deviation is estimated from the same small sample: heavier tails than the normal, approaching it as the degrees of freedom grow. With one degree of freedom it is the Cauchy distribution, which has no mean.",
        method: "The density in closed form; the distribution function exactly for one and two degrees of freedom, otherwise through the regularized incomplete beta function [AS64], [PTVF07]."
      },
      ChiSquare: { maths: "The distribution of a sum of squares of k independent standard normal values; it measures how far counts stray from expectation, hence its use in goodness-of-fit tests.", method: "The density in closed form; the distribution function exactly for even k, otherwise through the regularized incomplete gamma function." },
      FRatio: { maths: "The distribution of a ratio of two independent sample variances, which is what compares spreads.", method: "Through the regularized incomplete beta function." },

      # ---- elementary functions and notation -----------------------------------------------
      sin: {
        maths: "The circular functions: on the unit circle sin and cos are the coordinates at angle x, so sin**2 + cos**2 = 1 and both have period 2*pi. Arguments are radians.",
        method: "Exact values at the multiples of pi/6 and pi/4 fold immediately; everything else stays symbolic until asked. trigsimp reduces with the Pythagorean identity, expand_trig with the addition formulas."
      },
      cos: :sin, tan: :sin, asin: :sin, acos: :sin, atan: :sin,
      sinh: { maths: "The hyperbolic functions: the same construction on the hyperbola, cosh and sinh being (e**x + e**-x)/2 and (e**x - e**-x)/2, with cosh**2 - sinh**2 = 1.", method: "Rewritten with exponentials where that helps, as in integration." },
      cosh: :sinh,
      exp: {
        maths: "The exponential function is its own derivative and turns sums into products; the natural logarithm inverts it. log here is always the natural one.",
        method: "exp(a)*exp(b) merges into exp(a + b) in the canonical form, and log(exp(x)) folds; expand_log and logcombine move between log(a*b) and log(a) + log(b)."
      },
      log: :exp,
      sqrt: {
        maths: "A square root has two values; sqrt is the principal one, and root(x, n) likewise the principal n-th root. That is why sqrt(x**2) is not simplified to x, which would be false for negative x.",
        method: "Written as the power x**(1/2), so the ordinary power rules apply; perfect powers are extracted and a negative number under an even root becomes an imaginary unit."
      },
      root: :sqrt, cbrt: :sqrt,
      abs: { maths: "The distance from zero, and sign its direction; abs is not differentiable at 0, where diff gives sign.", method: "Folded for numbers and for values whose inferred domain is non-negative." },
      sign: :abs,
      floor: { maths: "Rounding to an integer: floor down, ceil up, round to nearest. mod(a, m) is the remainder that keeps the sign of the modulus, so mod(-7, 3) is 2.", method: "Folded for real numbers, kept symbolic otherwise." },
      ceil: :floor, round: :floor, mod: :floor,
      re: { maths: "Every complex number is re + i*im; the conjugate flips the sign of im, and arg is the angle in the plane, so a number is re + i*im = abs * exp(i*arg).", method: "The expression is expanded and split by the complex coefficients; a symbol counts as real only once assumed so, otherwise re(x) stays unevaluated." },
      im: :re, conj: :re, arg: :re,
      zeta: { maths: "The Riemann zeta function, the sum of 1/n**s. It is exact at even integers (zeta(2) = pi**2/6, Euler's Basel problem) and its zeros carry the deepest open question about the primes.", method: "Exact at even integers through the Bernoulli numbers; numerically by Euler-Maclaurin." },
      eq: { maths: "An equation is a statement, not a value: eq(lhs, rhs) keeps both sides so that solve, subs and sidewise arithmetic can work on it. Structural equality (==) is a different thing and is decided by the canonical form.", method: "An Equation node holding both sides." },
      D: { maths: "The derivative of an unknown function, the notation of a differential equation: D(y, x, 2) is y''.", method: "A formal Derivative node that dsolve reads and diff differentiates further." },
      trigsimp: { maths: "Simplification with the trigonometric identities: reduce sin**2 + cos**2 to 1 and shrink what follows from it.", method: "Rewrite even powers of sin through cos and cancel on term tables." },
      expand_trig: { maths: "The addition and multiple-angle formulas: sin(2x) as 2 sin x cos x, so that a trigonometric expression becomes a polynomial in sin x and cos x.", method: "The addition formulas applied structurally." },
      expand_log: { maths: "log(a*b) = log a + log b and log(a**n) = n log a, valid for positive arguments; logcombine goes the other way.", method: "Applied on term tables, only where the factors are known to be positive." },
      logcombine: :expand_log,
      nextprime: { maths: "The next and previous prime; by Bertrand's postulate the next one is always below twice the number.", method: "Sieve the small factors, then test candidates with isprime." },
      prevprime: :nextprime,
      frequencies: { maths: "The frequency distribution: how often each value occurs, the raw material of a bar chart.", method: "A tally, ordered by value where the data is numeric." },
      geometric_mean: { maths: "The geometric mean is the n-th root of the product, the right average for growth rates; the harmonic mean is n over the sum of reciprocals, the right average for speeds. Both are at most the arithmetic mean.", method: "Exact roots and reciprocals." },
      harmonic_mean: :geometric_mean,
      scatter: { maths: "The points of a two-variable sample, where a relationship becomes visible; fit: true draws the least squares line through them.", method: "Points on the braille canvas, the line from linreg." },
      # ---- the named polynomials (Poly) ----------------------------------------
      Poly: {
        maths: "The classical families: solutions of the equations of mathematical physics, orthogonal systems for approximation, and the polynomials that count. Each is fixed by a three-term recurrence and a pair of starting values.",
        method: "The recurrence is run on lists of exact coefficients and the result is expanded in the indeterminate given; the parameters may stay symbolic [AS64, ch. 22]."
      },
      "Poly.chebyshev_t": {
        maths: "T_n(cos(u)) = cos(n*u): the polynomial that turns a cosine of a multiple angle into a polynomial in the cosine. Its extrema are equal in size, which is what makes the Chebyshev nodes the good interpolation points and T_n the polynomial of least deviation from zero.",
        method: "T_(k+1) = 2*x*T_k - T_(k-1) from T_0 = 1, T_1 = x [AS64, ch. 22]."
      },
      "Poly.chebyshev_u": {
        maths: "U_n(cos(u)) = sin((n + 1)*u)/sin(u), the second kind: orthogonal on [-1, 1] with weight sqrt(1 - x**2), and the derivative of T_(n+1) up to a factor.",
        method: "The same recurrence from U_0 = 1, U_1 = 2*x [AS64, ch. 22]."
      },
      "Poly.legendre": {
        maths: "The orthogonal system on [-1, 1] with weight 1: P_n has n simple roots there, the Gauss quadrature nodes, and the P_n are the multipole terms of a potential in spherical symmetry.",
        method: "Bonnet's recurrence k*P_k = (2*k - 1)*x*P_(k-1) - (k - 1)*P_(k-2) [AS64, ch. 22], [Sze75]."
      },
      "Poly.hermite": {
        maths: "Orthogonal with the Gaussian weight exp(-x**2): the physicists' H_n, whose product with exp(-x**2/2) gives the states of the harmonic oscillator.",
        method: "H_(k+1) = 2*x*H_k - 2*k*H_(k-1) [AS64, ch. 22]."
      },
      "Poly.hermite_prob": {
        maths: "The probabilists' He_n, orthogonal with the weight of the standard normal distribution, so that He_n of a standard normal variable has expectation zero for every n >= 1; the Edgeworth expansions are written in them. He_n(x) = 2**(-n/2)*H_n(x/sqrt(2)).",
        method: "He_(k+1) = x*He_k - k*He_(k-1) [AS64, ch. 22]."
      },
      "Poly.laguerre": {
        maths: "Orthogonal on [0, oo) with weight exp(-x), and with weight x**alpha*exp(-x) in the generalized form; the radial part of the hydrogen atom is a generalized Laguerre polynomial.",
        method: "k*L_k = (2*k - 1 + alpha - x)*L_(k-1) - (k - 1 + alpha)*L_(k-2), which keeps alpha symbolic [AS64, ch. 22]."
      },
      "Poly.gegenbauer": {
        maths: "The ultraspherical polynomials, orthogonal with weight (1 - x**2)**(alpha - 1/2): Legendre is alpha = 1/2 and Chebyshev of the second kind is alpha = 1, so they interpolate between the two.",
        method: "k*C_k = 2*(k - 1 + alpha)*x*C_(k-1) - (k - 2 + 2*alpha)*C_(k-2) [AS64, ch. 22], [Sze75]."
      },
      "Poly.jacobi": {
        maths: "The most general classical family, orthogonal with weight (1 - x)**alpha*(1 + x)**beta; Legendre, Chebyshev and Gegenbauer are the special cases of its two parameters.",
        method: "The explicit sum of binomial(n + alpha, n - s)*binomial(n + beta, s)*((x - 1)/2)**s*((x + 1)/2)**(n - s), with the binomials expanded as polynomials in alpha and beta [AS64, ch. 22], [Sze75]."
      },
      "Poly.bernoulli": {
        maths: "B_n(x) is the polynomial with B_n(x + 1) - B_n(x) = n*x**(n - 1), which is why sums of powers are Bernoulli polynomials (Faulhaber) and why B_n(0) is the Bernoulli number.",
        method: "B_n(x) = sum(binomial(n, k)*B_(n-k)*x**k) with the Bernoulli numbers of summation.rb [AS64, ch. 23], [GKP94, ch. 6]."
      },
      "Poly.euler": {
        maths: "E_n(x) is to alternating sums what B_n(x) is to sums: E_n(x + 1) + E_n(x) = 2*x**n; 2**n*E_n(1/2) is the Euler number.",
        method: "E_n(x) = 2/(n + 1)*(B_(n+1)(x) - 2**(n+1)*B_(n+1)(x/2)), read off the Bernoulli coefficients [AS64, ch. 23]."
      },
      "Poly.cyclotomic": {
        maths: "Phi_n is the minimal polynomial of a primitive n-th root of unity: it is irreducible over the rationals, its degree is Euler's totient of n, and the x**n - 1 factor into the Phi_d over the divisors d of n. Its coefficients are not always 0 and +-1: Phi_105 has a -2.",
        method: "Exact division of x**n - 1 by the Phi_d of the proper divisors, over the integers [vzGG13, ch. 14]."
      },
      "Poly.swinnerton_dyer": {
        maths: "The minimal polynomial of sqrt(2) + sqrt(3) + ... over the first n primes: degree 2**n, irreducible over the rationals, but reducible modulo every prime. That is what makes it the hard case for factorization by Hensel lifting, where recombination has to try every subset.",
        method: "One conjugation at a time: with f(x + s) = u(x) + s*v(x) and s**2 = p, the product over both signs is u**2 - p*v**2, so the coefficients stay integers [Coh93]."
      },
      "Poly.abel": {
        maths: "A_n(x; a) = x*(x - a*n)**(n - 1), the polynomials of Abel's binomial theorem; they are the sequence of binomial type behind Cayley's count of labelled trees.",
        method: "The binomial expansion of the linear factor, multiplied by x [GKP94, ch. 5]."
      },
      "Poly.fibonacci": {
        maths: "F_n(x) = x*F_(n-1)(x) + F_(n-2)(x): the Fibonacci rule with the sum replaced by a weighted one, so F_n(1) is the Fibonacci number and F_n(2) the Pell number.",
        method: "The recurrence on coefficient lists [GKP94, ch. 6]."
      },
      "Poly.lucas": {
        maths: "The companion of the Fibonacci polynomials, from L_0 = 2 and L_1 = x; L_n(1) is the Lucas number and L_n(x) = F_(n+1)(x) + F_(n-1)(x).",
        method: "The same recurrence with the other starting values [GKP94, ch. 6]."
      },
      "Poly.bell": {
        maths: "The Bell (Touchard) polynomial: its k-th coefficient counts the ways to split n labelled objects into k non-empty blocks, so its value at 1 is the Bell number, the number of all such splittings.",
        method: "The Stirling numbers of the second kind by S(n, k) = k*S(n-1, k) + S(n-1, k-1) [GKP94, ch. 6], [Sta99]."
      },
      assumptions: :assume, forget: :assume, doit: :hold
    }.freeze

    # Where a student can read on: article titles on the English Wikipedia,
    # turned into links by Background.url. Broad articles are preferred to
    # narrow ones, and aliases inherit the list of the entry they point at.
    # Every title was checked against the Wikipedia API on 2026-09-14 (see
    # CLAUDE.md for the one-liner that repeats the check). Two of them are
    # deliberate ASCII redirects, because the canonical titles use an en dash:
    # Line-line intersection and Gram-Schmidt process.
    READING = {
      simplify: ["Canonical form", "Computer algebra system"],
      expand: ["Distributive property"],
      factor: ["Factorization of polynomials", "Factorization of polynomials over finite fields", "Integer factorization"],
      cancel: ["Rational function"],
      rationalize: ["Rational function"],
      apart: ["Partial fraction decomposition"],
      gcd: ["Euclidean algorithm", "Polynomial greatest common divisor"],
      quo: ["Polynomial long division"],
      numer: ["Rational function"],
      degree: ["Degree of a polynomial"],
      collect: ["Polynomial"],
      subs: ["Expression (mathematics)"],
      evalf: ["Floating-point arithmetic", "Arbitrary-precision arithmetic", "Significant figures"],
      steps: ["Worked-example effect", "Quadratic formula", "Partial fraction decomposition", "Euclidean algorithm"],
      hold: ["Computer algebra"],
      openmath: ["OpenMath", "MathML"],
      diff: ["Derivative", "Differentiation rules"],
      integrate: ["Symbolic integration", "Risch algorithm", "Integration by parts"],
      limit: ["Limit of a function", "Squeeze theorem"],
      piecewise: ["Piecewise function", "Heaviside step function"],
      discontinuities: ["Classification of discontinuities", "Continuous function"],
      kinks: ["Differentiable function", "Semi-differentiability"],
      series: ["Taylor series", "Puiseux series"],
      fourier: ["Fourier series", "Gibbs phenomenon", "Joseph Fourier"],
      Si: ["Trigonometric integral", "Dirichlet integral"],
      Ci: ["Trigonometric integral"],
      Ei: ["Exponential integral", "Logarithmic integral function"],
      li: ["Logarithmic integral function", "Prime-counting function"],
      arclength: ["Arc length", "Catenary"],
      revolution_volume: ["Solid of revolution", "Disc integration", "Shell integration"],
      revolution_surface: ["Surface of revolution"],
      lu: ["LU decomposition", "Gaussian elimination"],
      qr: ["QR decomposition", "Gram-Schmidt process"],
      cholesky: ["Cholesky decomposition", "Definite matrix"],
      diagonalize: ["Diagonalizable matrix", "Eigendecomposition of a matrix"],
      jordan: ["Jordan normal form", "Generalized eigenvector"],
      parametric: ["Parametric equation"],
      polar: ["Polar coordinate system", "Rose (mathematics)"],
      fps: ["Formal power series", "Holonomic function", "Binomial series"],
      sum: ["Summation", "Faulhaber's formula", "Gosper's algorithm", "Hypergeometric identity"],
      sumrecursion: ["Wilf-Zeilberger pair", "Hypergeometric identity", "Doron Zeilberger"],
      hyper: ["Petkovsek's algorithm", "Recurrence relation", "Hypergeometric identity"],
      qbinomial: ["Gaussian binomial coefficient", "Q-Pochhammer symbol", "Q-analog"],
      qsum: ["Basic hypergeometric series", "Gosper's algorithm", "Quantum calculus"],
      qsumrecursion: ["Basic hypergeometric series", "Wilf-Zeilberger pair"],
      qsolve: ["Basic hypergeometric series", "Q-derivative", "Quantum calculus"],
      product: ["Factorial", "Gamma function"],
      solve: ["Algebraic equation", "System of polynomial equations"],
      groebner: ["Buchberger's algorithm", "Monomial order"],
      reduce: ["Buchberger's algorithm"],
      dsolve: ["Ordinary differential equation", "Linear differential equation", "Method of undetermined coefficients"],
      rsolve: ["Recurrence relation", "Linear recurrence with constant coefficients"],
      interpolate: ["Polynomial interpolation", "Newton polynomial"],
      resultant: ["Resultant"],
      discriminant: ["Discriminant"],
      minpoly: ["Minimal polynomial (field theory)"],
      isprime: ["Primality test"],
      ifactor: ["Integer factorization", "Pollard's rho algorithm"],
      divisors: ["Divisor"],
      totient: ["Euler's totient function"],
      invmod: ["Modular multiplicative inverse"],
      chrem: ["Chinese remainder theorem"],
      binomial: ["Binomial coefficient"],
      factorial: ["Factorial", "Gamma function"],
      fibonacci: ["Fibonacci sequence"],
      bernoulli: ["Bernoulli number"],
      harmonic: ["Harmonic number"],
      erf: ["Error function"],
      assume: ["Ring (mathematics)", "Field (mathematics)"],
      GF: ["Finite field", "Finite field arithmetic"],
      matrix: ["Matrix (mathematics)", "Gaussian elimination", "Eigenvalues and eigenvectors"],
      vector: ["Vector space", "Euclidean vector"],
      plot: ["Graph of a function"],
      scatter: ["Scatter plot"],
      mean: ["Arithmetic mean", "Median", "Mode (statistics)"],
      variance: ["Variance", "Standard deviation", "Bessel's correction"],
      quantile: ["Quantile", "Quartile"],
      skewness: ["Skewness", "Kurtosis"],
      covariance: ["Covariance", "Correlation"],
      linreg: ["Simple linear regression", "Ordinary least squares"],
      histogram: ["Histogram"],
      boxplot: ["Box plot"],
      barchart: ["Bar chart"],
      frequencies: ["Frequency (statistics)"],
      geometric_mean: ["Geometric mean", "Harmonic mean"],
      pdf: ["Probability density function", "Cumulative distribution function"],
      ttest: ["Student's t-test", "Welch's t-test", "P-value"],
      ztest: ["Z-test"],
      chisquare_test: ["Chi-squared test", "Pearson's chi-squared test"],
      ftest: ["F-test"],
      binomial_test: ["Binomial test"],
      confidence_interval: ["Confidence interval", "Binomial proportion confidence interval"],
      Normal: ["Normal distribution", "Central limit theorem"],
      Uniform: ["Continuous uniform distribution"],
      Exponential: ["Exponential distribution"],
      Bernoulli: ["Bernoulli distribution"],
      Binomial: ["Binomial distribution"],
      Poisson: ["Poisson distribution"],
      Geometric: ["Geometric distribution"],
      DiscreteUniform: ["Discrete uniform distribution"],
      StudentT: ["Student's t-distribution"],
      ChiSquare: ["Chi-squared distribution"],
      FRatio: ["F-distribution"],
      sin: ["Trigonometric functions", "List of trigonometric identities"],
      sinh: ["Hyperbolic functions"],
      exp: ["Exponential function", "Natural logarithm"],
      sqrt: ["Square root", "Nth root"],
      abs: ["Absolute value"],
      floor: ["Floor and ceiling functions", "Modulo"],
      re: ["Complex number"],
      zeta: ["Riemann zeta function", "Basel problem"],
      eq: ["Equation"],
      D: ["Notation for differentiation"],
      trigsimp: ["List of trigonometric identities"],
      expand_trig: ["List of trigonometric identities"],
      expand_log: ["Logarithm"],
      nextprime: ["Prime number"],
      nsolve: ["Root-finding algorithm", "Newton's method", "Bisection method"],
      nintegrate: ["Numerical integration", "Simpson's rule", "Tanh-sinh quadrature"],
      extrema: ["Maximum and minimum", "Derivative test", "Critical point (mathematics)"],
      discuss: ["Curve sketching", "Monotonic function", "Concave function"],
      inflections: ["Inflection point"],
      asymptotes: ["Asymptote"],
      tangent: ["Tangent", "Linear approximation"],
      real_domain: ["Domain of a function"],
      gradient: ["Gradient", "Partial derivative", "Level set"],
      hessian: ["Hessian matrix", "Second partial derivative test"],
      jacobian: ["Jacobian matrix and determinant"],
      divergence: ["Divergence", "Curl (mathematics)", "Laplace operator"],
      lagrange: ["Lagrange multiplier"],
      point: ["Analytic geometry", "Cartesian coordinate system"],
      distance: ["Euclidean distance", "Distance from a point to a line"],
      angle: ["Angle", "Dot product"],
      area: ["Shoelace formula", "Area"],
      intersect: ["Line-line intersection", "Circle"],
      circumcircle: ["Circumcircle"],
      collinear?: ["Collinearity"],
      centroid: ["Centroid"],
      perpendicular_bisector: ["Bisection"],
      gram_schmidt: ["Gram-Schmidt process", "Orthonormal basis"],
      project: ["Projection (linear algebra)", "Vector projection"],
      least_squares: ["Least squares", "Linear least squares"],
      laplace: ["Laplace transform"],
      inverse_laplace: ["Inverse Laplace transform"],
      congruence: ["Modular arithmetic", "Chinese remainder theorem"],
      legendre: ["Legendre symbol", "Quadratic reciprocity", "Jacobi symbol"],
      order: ["Multiplicative order", "Primitive root modulo n"],
      continued_fraction: ["Continued fraction", "Simple continued fraction"],
      Poly: ["Orthogonal polynomials", "Classical orthogonal polynomials"],
      "Poly.chebyshev_t": ["Chebyshev polynomials"],
      "Poly.chebyshev_u": ["Chebyshev polynomials"],
      "Poly.legendre": ["Legendre polynomials"],
      "Poly.hermite": ["Hermite polynomials"],
      "Poly.hermite_prob": ["Hermite polynomials"],
      "Poly.laguerre": ["Laguerre polynomials"],
      "Poly.gegenbauer": ["Gegenbauer polynomials"],
      "Poly.jacobi": ["Jacobi polynomials"],
      "Poly.bernoulli": ["Bernoulli polynomials"],
      "Poly.euler": ["Bernoulli polynomials"],
      "Poly.cyclotomic": ["Cyclotomic polynomial", "Root of unity"],
      "Poly.swinnerton_dyer": ["Minimal polynomial (field theory)"],
      "Poly.abel": ["Abel polynomials"],
      "Poly.fibonacci": ["Fibonacci polynomials"],
      "Poly.lucas": ["Fibonacci polynomials", "Lucas sequence"],
      "Poly.bell": ["Touchard polynomials", "Bell number", "Stirling numbers of the second kind"]
    }.freeze

    BASE = "https://en.wikipedia.org/wiki/"


    module_function

    def url(title) = BASE + title.tr(" ", "_")

    # => { maths:, method: } or nil
    def [](name)
      entry = ENTRIES[name.to_s.to_sym]
      entry.is_a?(Symbol) ? ENTRIES[entry] : entry
    end

def key?(name) = !self[name].nil?

# => [url, ...]; an alias inherits the list it points at.
def reading(name)
  key = name.to_s.to_sym
  key = ENTRIES[key] if ENTRIES[key].is_a?(Symbol)
  Array(READING[key]).map { |title| url(title) }
end
  end
end
