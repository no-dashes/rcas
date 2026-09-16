<p align="center">
  <img src="assets/rcas-logo.jpeg" alt="rcas - Ruby Computer Algebra System" width="360"><br>
  <em>Reinventing the wheel instead of building a CAS</em>™
</p>

# rcas Handbuch

rcas ist ein Computeralgebrasystem, das in Ruby lebt. Symbole sind die
Unbestimmten, die gewöhnlichen Operatoren bauen Ausdrucksbäume, und irb ist
die REPL. Dieses Handbuch führt durch alles, was fertig ist. Jede Sitzung
darin wird von `test/manual_test.rb` geprüft, die Ausgaben sind also genau
das, was der aktuelle Code druckt.

Dies ist die Übersetzung von MANUAL.md; die Beispiele sind dieselben und
werden aus der englischen Fassung übernommen, damit beide nicht
auseinanderlaufen.

Eine Sitzung beginnt mit

```
$ bin/rcas
```

oder die Bibliothek wird aus Ruby heraus benutzt: `require "rcas"`. In
reinem Ruby schreibt man Variablen als Symbole (`:x`) und ruft die
Funktionen am Modul auf (`RCAS.sin`, `RCAS.solve`), oder man holt sich mit
`include RCAS::Functions`, `RCAS::Sets` und `RCAS::Constants` die bloßen
Namen, die unten benutzt werden.

<!-- toc -->
- [Sitzungen und Einrichtung](#sitzungen-und-einrichtung)
- [Kurse](#kurse)
  - [Schule](#schule)
  - [Oberstufe](#oberstufe)
  - [Grundstudium](#grundstudium)
  - [Bachelorstudium](#bachelorstudium)
- [1. Mathematik](#1-mathematik)
  - [1.1 Ausdrücke](#11-ausdrücke)
    - [Variablen und Operatoren](#variablen-und-operatoren)
    - [simplify, expand, factor](#simplify-expand-factor)
    - [Einsetzen und Auswerten](#einsetzen-und-auswerten)
    - [Gleichheit](#gleichheit)
  - [1.2 Zahlen und Konstanten](#12-zahlen-und-konstanten)
    - [Komplexe Teile und Runden](#komplexe-teile-und-runden)
    - [Ganze Zahlen und Primzahlen](#ganze-zahlen-und-primzahlen)
  - [1.3 Analysis](#13-analysis)
    - [Ableitungen](#ableitungen)
    - [Stammfunktionen](#stammfunktionen)
    - [Bestimmte Integrale](#bestimmte-integrale)
    - [Integrale mit Namen](#integrale-mit-namen)
    - [Länge, Fläche und Volumen](#länge-fläche-und-volumen)
    - [Zahlen, wenn die Symbole nicht reichen](#zahlen-wenn-die-symbole-nicht-reichen)
    - [So viele Stellen, wie man will](#so-viele-stellen-wie-man-will)
    - [Kurvendiskussion](#kurvendiskussion)
    - [Die vollständige Kurvendiskussion](#die-vollständige-kurvendiskussion)
    - [Mehrere Veränderliche](#mehrere-veränderliche)
    - [Reihen](#reihen)
    - [Formale Potenzreihen](#formale-potenzreihen)
    - [Grenzwerte](#grenzwerte)
    - [Abschnittsweise definierte Funktionen](#abschnittsweise-definierte-funktionen)
    - [Fourier-Reihen](#fourier-reihen)
    - [Summen](#summen)
    - [Bestimmte Summen: kreatives Teleskopieren](#bestimmte-summen-kreatives-teleskopieren)
    - [Produkte](#produkte)
    - [hold und evaluate](#hold-und-evaluate)
    - [Fakultäten, Binomialkoeffizienten, Gamma](#fakultäten-binomialkoeffizienten-gamma)
    - [Trigonometrisches und logarithmisches Umformen](#trigonometrisches-und-logarithmisches-umformen)
  - [1.4 Gleichungen und Lösen](#14-gleichungen-und-lösen)
    - [Ungleichungen](#ungleichungen)
  - [1.5 Bereiche und Annahmen](#15-bereiche-und-annahmen)
  - [1.6 Polynomringe](#16-polynomringe)
    - [ggT und Division von Ausdrücken](#ggt-und-division-von-ausdrücken)
    - [Gröbnerbasen](#gröbnerbasen)
    - [Grad und Koeffizienten](#grad-und-koeffizienten)
    - [Interpolation](#interpolation)
    - [Benannte Polynome](#benannte-polynome)
    - [Algebraische Zahlen](#algebraische-zahlen)
    - [Endliche Körper](#endliche-körper)
  - [1.7 Lineare Algebra](#17-lineare-algebra)
    - [Zerlegungen](#zerlegungen)
    - [Orthogonalität und kleinste Quadrate](#orthogonalität-und-kleinste-quadrate)
  - [1.8 Differentialgleichungen und Rekursionen](#18-differentialgleichungen-und-rekursionen)
    - [Rekursionen](#rekursionen)
    - [Systeme](#systeme)
    - [Die Laplace-Transformation](#die-laplace-transformation)
  - [1.9 Geometrie](#19-geometrie)
  - [1.10 Statistik](#110-statistik)
    - [Beschreibende Statistik](#beschreibende-statistik)
    - [Regression](#regression)
    - [Verteilungen](#verteilungen)
    - [Hypothesentests](#hypothesentests)
    - [Konfidenzintervalle](#konfidenzintervalle)
  - [1.11 Grafik](#111-grafik)
    - [Parameter- und Polarkurven](#parameter--und-polarkurven)
    - [Statistische Grafiken](#statistische-grafiken)
  - [1.12 Die q-Analoga](#112-die-q-analoga)
    - [q-Summation](#q-summation)
    - [q-Differenzengleichungen](#q-differenzengleichungen)
  - [1.13 Rechenwege](#113-rechenwege)
  - [1.14 Hinweise zur Geschwindigkeit](#114-hinweise-zur-geschwindigkeit)
- [2. Referenz](#2-referenz)
- [3. Dateien](#3-dateien)
- [4. Quellen](#4-quellen)
- [5. Lizenz](#5-lizenz)
- [Anhang A. Typografischer Satz](#anhang-a-typografischer-satz)
  - [Bilder](#bilder)
- [Anhang B. rcas-chat](#anhang-b-rcas-chat)
  - [Eingabe](#eingabe)
  - [Claude](#claude)
  - [Ausgabemodi](#ausgabemodi)
  - [Hilfe](#hilfe)
  - [Fehler](#fehler)
  - [Sitzungen](#sitzungen)
  - [Befehle](#befehle)
  - [Optionen und Umgebung](#optionen-und-umgebung)
  - [Dateien](#dateien)
<!-- /toc -->

## Sitzungen und Einrichtung

`bin/rcas` startet irb, auf dessen oberstes Objekt `RCAS::IRB.setup`
angewandt wurde:

- Ein bloßer Bezeichner, der noch nicht definiert ist (`x`, `foo_bar`),
  ergibt das gleichnamige Symbol und wird einer lokalen Variablen
  zugewiesen; nach `e = x + 1` enthält die Variable `x` also `:x`. Ein
  undefinierter Name, der auf Ausdrücke oder Zahlen angewandt wird,
  `u(n + 1)` oder `f(x)`, ist eine unbekannte Funktion (die Schreibweise,
  die `rsolve` benutzt); mit einem Block oder anderen Arten von Argumenten
  kommt der übliche `NoMethodError`, und `respond_to?` bleibt unangetastet,
  damit Rubys implizite Umwandlungen unberührt bleiben.
- Die Funktionen des Referenzteils, die Konstanten `PI E I oo`, die
  Zahlbereiche `NN ZZ QQ RR CC` und `GF` stehen zur Verfügung, und
  `hold { ... }` kann den Quelltext von Blöcken lesen, die an der
  Eingabeaufforderung getippt wurden.
- Jeder Name, den Ruby als Bezeichner akzeptiert, funktioniert, Unicode
  eingeschlossen: `α`, `β₁`, `φ`, `δt`. Ein Name, der mit einem
  Großbuchstaben beginnt (`X`, `Δt`), ist für Ruby eine Konstante und
  deshalb nicht verfügbar. `π` und `∞` sind die Konstanten `pi` und `oo`;
  Ergebnisse drucken weiterhin `pi` und `oo`, damit man sie wieder
  einfügen kann.
- Namen, die Ruby schon benutzt, können auf diesem Weg keine Unbestimmten
  werden. Von den ein- und zweibuchstabigen Namen sind nur `p`, `pp` und
  (mit der JSON-Bibliothek) `j`, `jj` betroffen. Auch rcas' eigene `eq`,
  `pi` und `oo` sind belegt; alles andere Kurze ist frei.

**Vorbehalt: das Einzige, was rcas irb wegnimmt.** Alles oben *ergänzt* irb
nur. Die einzige Ausnahme: Kernels Druckfunktionen `p`, `pp`, `j` und `jj`
sind am Sitzungsobjekt aufgehoben, damit `p` eine Unbestimmte sein kann
(eine Primzahl etwa). `p(expr)` wirft deshalb in `bin/rcas` und
`bin/rcas-chat` einen `NoMethodError`; benutzen Sie `puts expr`, `print`
oder `Kernel.p(expr)`. Reines `irb` mit `require "rcas"` ist nicht
betroffen.
- Ergebnisse erscheinen als Text. `show(obj)` setzt einen Wert typografisch
  (Anhang A); `bin/rcas-chat` (Anhang B) zeigt Bilder direkt im Terminal.
- `doc(:factor)`, `doc("ZZ")`, `doc(:Matrix)` erklären einen Namen: seine
  Signatur, den Kommentar darüber im Quelltext, die Mathematik dahinter und
  die Handbuchabschnitte, die ihn behandeln. `bin/rcas-chat` hat dasselbe
  unter `/help factor`.

**Jede Zeile wird aufgehoben.** rcas nummeriert eine Sitzung wie
Mathematica: `In[3]` ist die dritte Eingabe der Sitzung, `Out[3]` ihr
Ergebnis. Eine negative Nummer zählt zurück, `Out[-1]` ist also das vorige
Ergebnis und `Out[-2]` das davor; `In` und `Out` allein drucken die ganze
Tabelle, eine Zeile je Zeile. Das `_` von irb (der letzte Wert)
funktioniert weiterhin.

```
rcas> (x + 1)*(x - 1)
=> (x + 1)*(x - 1)
rcas> expand(Out[-1])
=> -1 + x**2
rcas> Out[-1] - Out[-2]
=> -1 + x**2 - (x + 1)*(x - 1)
```

Beide Tabellen geben zurück, was da war, und zwar **festgehalten**:
`Out[n]` ist der Wert, wie er berechnet wurde, und wird nie neu berechnet;
`In[n]` ist die Zeile, wie sie getippt wurde, mit `hold` (1.3) zu einem
Ausdruck gebaut statt ausgeführt. Sie gibt also die Frage zurück, nicht die
Antwort; `doit` beantwortet sie.

```
rcas> integrate(sin(x), x)
=> -cos(x)
rcas> In[-1]
=> integral(sin(x), x)
rcas> In[-2].doit
=> -cos(x)
```

`In[n]` hält genau so viel fest wie `hold { ... }`: Arithmetik, die
rcas bekannten Funktionen und `integrate`, `diff`, `sum`, `product`,
`limit` bleiben unausgewertet, jeder andere Aufruf wird ausgeführt: `In[n]`
einer Zeile `factor(Out[1])` ist also die Zerlegung und nicht das Wort, und
das einer Zuweisung der zugewiesene Wert. Eine Zeile, die überhaupt keinen
Ausdruck baut — ein Satz für Claude, eine, die sich nicht einmal parsen
lässt — kommt als der getippte Text zurück. `Out.clear` (oder `In.clear`)
vergisst die Sitzung und beginnt die Nummerierung von vorn.

**Die Eingabeaufforderung trägt die Nummer** der kommenden Zeile, damit man
sich in einer langen Sitzung leichter auf frühere beziehen kann:
`rcas[3]> ` in `bin/rcas`, `[3]❯ ` in `bin/rcas-chat`. Die Ergebnisse
behalten ihren Pfeil.

```
[1]❯ (x + 1)*(x - 1)
=> (x + 1)*(x - 1)
[2]❯ expand(Out[1])
=> -1 + x**2
[3]❯ In
[1] (x + 1)*(x - 1)
[2] expand(Out[1])
[3] In
```

`RCAS.numbered = false` in `bin/rcas` (oder `RCAS_NUMBERED=0`, oder
`/numbered off` in `bin/rcas-chat`) gibt die schlichte Eingabeaufforderung
`rcas> ` zurück. Die Mitschnitte in diesem Handbuch sind so gedruckt, damit
jede Zeile genau das Ruby ist, das man tippen würde, und nichts sonst; `In`
und `Out` halten die Sitzung ohnehin fest.

Ohne den Starter: `require "rcas"` und dann `:x`, `RCAS::ZZ` oder
`include RCAS::Sets`, sowie `RCAS.sin(:x)` / `RCAS.assume(x: RCAS::ZZ)`.
Blöcke für `hold` funktionieren in Dateien und in irb; auch mit `eval`
zusammengesetzter Code ist erfasst, weil das Laden von rcas
`RubyVM.keep_script_lines` einschaltet.

## Kurse

rcas ist für Menschen geschrieben, die die Mathematik lernen, nicht nur für
solche, die das Ergebnis wollen. Diese vier Rundgänge sagen, was auf jeder
Stufe geht und wo man weiterliest; alles darin ist eine echte Sitzung.

### Schule

Auf das exakte Rechnen kommt es an: ein Drittel plus ein Sechstel ist fünf
Sechstel, nicht 0,8333. Ruby teilt ganze Zahlen ganzzahlig, schreiben Sie
also `1/2r` (oder `1/2.0`, wenn Sie wirklich eine Dezimalzahl wollen), wenn
ein Bruch gemeint ist. Primfaktorzerlegung, größter gemeinsamer Teiler,
einfache Gleichungen, Abstände und Mittelwerte sind alle da, und `plot`
zeichnet eine Funktion im Terminal. `steps` zeigt den Rechenweg statt nur
das Ergebnis - den euklidischen Algorithmus Zeile für Zeile etwa.

```
rcas> 2/3r + 1/6r
=> (5/6)
rcas> factor(360)
=> 2**3*3**2*5
rcas> [gcd(84, 36), lcm(4, 6), divisors(12)]
=> [12, 12, [1, 2, 3, 4, 6, 12]]
rcas> solve(eq(3*x + 5, 17), x)
=> [4]
rcas> distance(point(0, 0), point(3, 4))
=> 5
rcas> [mean([2, 4, 4, 5, 5]), median([2, 4, 4, 5, 5]), mode([2, 4, 4, 5, 5])]
=> [4, 4, [4, 5]]
```

Weiterlesen: 1.1 Ausdrücke, 1.2 Zahlen und Konstanten, 1.9 Geometrie,
1.10 Statistik, 1.11 Grafik.

### Oberstufe

Polynome faktorisieren, quadratische Gleichungen und Ungleichungen lösen,
und eine Ungleichung antwortet mit der Lösungsmenge (`[2, 3]` ist hier das
abgeschlossene Intervall, kein Paar). Trigonometrische Gleichungen liefern
die Lösungen einer Periode, mit `all: true` die ganze Schar. Dann die erste
Analysis: Ableitungen, Kurvendiskussion, bestimmte Integrale, Summen und
Wahrscheinlichkeit. Eine Funktion darf mit `piecewise` abschnittsweise
gegeben werden, und `discontinuities` und `kinks` nennen die Stellen, an
denen ihre Stücke nicht zusammenpassen. `discuss` beantwortet die ganze
Kurvendiskussion in einem Bericht, und `steps` schreibt den Rechenweg
aus: die Ableitungsregeln, wie sie benutzt werden, die Lösungsformel mit
ihren Zahlen darin, die Fragen einer Kurvendiskussion eine nach der
anderen.

```
rcas> factor(x**2 - 5*x + 6)
=> (-2 + x)*(-3 + x)
rcas> solve(x**2 - 5*x + 6, x)
=> [2, 3]
rcas> solve(x**2 - 5*x + 6 <= 0, x)
=> [2, 3]
rcas> solve(sin(x) - 1/2r, x, all: true)
=> [pi/6 + 2*pi*k, 5*pi/6 + 2*pi*k]
rcas> extrema(x**3 - 3*x, x)
=> [[-1, 2, :maximum], [1, -2, :minimum]]
rcas> integrate(x**2, x, 0, 3)
=> 9
rcas> sum(k, k: 1..100)
=> 5050
rcas> Binomial(10, 1/2r).probability(x >= 8)
=> 7/128
```

Weiterlesen: 1.3 Analysis, 1.4 Gleichungen und Lösen, 1.6 Polynomringe,
1.9 Geometrie, 1.10 Statistik.

### Grundstudium

Grenzwerte und Reihen (`fps` gibt den allgemeinen Koeffizienten, nicht nur
die ersten Glieder, und `fourier` tut dasselbe für eine Fourier-Reihe), die
Integrationstechniken, Differentialgleichungen,
Matrizen und ihre Eigenwerte, partielle Ableitungen sowie Statistik mit
Tests und Konfidenzintervallen. Die klassischen orthogonalen Polynome -
Legendre, Tschebyschow, Hermite, Laguerre - stehen in `Poly`. Wo es keine
geschlossene Form gibt, geben `nsolve` und `nintegrate` die Zahl, und sagen
auch, dass es eine ist, und `evalf(f, 50)` gibt fünfzig Stellen, wenn
sechzehn nicht reichen. Ein Integrand wie `sin(x)/x` bekommt den Namen
seiner Stammfunktion (`Si`), Bogenlängen und Rotationskörper haben eigene
Funktionen, und die benannten Matrixzerlegungen - `lu`, `qr`, `cholesky`,
`diagonalize`, `jordan` - sind alle exakt.

```
rcas> limit(sin(x)/x, x, 0)
=> 1
rcas> series(exp(x), x, 0, 5)
=> 1 + x + x**2/2 + x**3/6 + x**4/24 + O(x**5)
rcas> fps(sin(x), x)
=> sum((-1)**k*x**(1 + 2*k)/(1 + 2*k)!, k, 0, oo)
rcas> integrate(1/(x**2 - 1), x)
=> log(-1 + x)/2 - log(1 + x)/2
rcas> dsolve(eq(D(y, x, 2) + y, 0), y, x)
=> [y = C1*cos(x) + C2*sin(x)]
rcas> matrix([[2, 1], [1, 2]]).eigenvalues
=> [1, 3]
rcas> gradient(x**2*y, [x, y])
=> (2*x*y, x**2)
rcas> ttest([5.1, 4.9, 5.6, 5.2, 5.0], mu: 5)
=> one-sample t test: t = 1.32417, df = 4, p = 0.256044 (two-sided)
```

Weiterlesen: 1.3 Analysis, 1.7 Lineare Algebra, 1.8 Differentialgleichungen
und Rekursionen, 1.10 Statistik.

### Bachelorstudium

Ringe und Körper als Objekte: Polynomringe über ZZ, QQ oder einem endlichen
Körper, algebraische Zahlen mit ihren Minimalpolynomen, Gröbnerbasen für
polynomiale Systeme. Laplace-Transformationen und Systeme von
Differentialgleichungen für die angewandten Vorlesungen, mehrdimensionale
Analysis und die Zahlentheorie einer ersten Vorlesung darüber.

```
rcas> QQ[x].(x**4 - 1).factor
=> (-1 + x)*(1 + x)*(1 + x**2)
rcas> groebner([x**2 + y**2 - 1, x - y], [x, y])
=> [x - y, -1/2 + y**2]
rcas> minpoly(sqrt(2) + sqrt(3))
=> 1 - 10*x**2 + x**4
rcas> Poly.cyclotomic(12, x)
=> 1 - x**2 + x**4
rcas> GF(9).elements.first(4)
=> [0, 1, 2, a]
rcas> laplace(t*exp(3*t))
=> 1/(-3 + s)**2
rcas> dsolve([eq(D(x, t), y), eq(D(y, t), -x)], [x, y], t)
=> [x = C1*sin(t) + C2*cos(t), y = C1*cos(t) - C2*sin(t)]
rcas> [legendre(3, 7), order(3, 7)]
=> [-1, 6]
rcas> sumrecursion(binomial(n, k)**2, k, s(n))
=> s(n)*(-2 - 4*n) + s(1 + n)*(1 + n) = 0
rcas> qsolve(eq(u(q*x), (1 - t*x)*u(x)), u, x, q)
=> u(q**n) = C1*qpochhammer(t, q, n)
```

Weiterlesen: 1.5 Bereiche und Annahmen, 1.6 Polynomringe,
1.8 Differentialgleichungen und Rekursionen, 1.12 Die q-Analoga, und
Abschnitt 4, Quellen, für die Algorithmen und ihre Herkunft.

Jeder Name erklärt sich selbst: `doc(:factor)` (oder `/help factor` im
Chat) liefert die Signatur, was die Operation mathematisch ist, wie rcas
sie berechnet, die Quellen und einen Link zum Weiterlesen.

## 1. Mathematik

### 1.1 Ausdrücke

#### Variablen und Operatoren

In `bin/rcas` wird ein bloßer, noch nicht definierter Name zur
Unbestimmten: die Sitzung wertet `x` zum Symbol `:x` aus und merkt es sich
als lokale Variable, die dieses Symbol enthält. Rechnen mit Symbolen baut
Ausdrücke, und nichts wird umgeformt, bevor Sie es verlangen.

Ein Wort zu den Begriffen. Eine Ruby-*Variable* wie `e` enthält einen Wert.
Ein Symbol wie `:x` innerhalb eines Ausdrucks ist eine *Unbestimmte*: es
steht für nichts Bestimmtes, und `x**2 - 1` ist ein formaler Ausdruck,
keine Rechnung, die auf einen Wert wartet. Einer Unbestimmten einen Wert
geben, das tun `subs` und `call`; `x.in(ZZ)` schränkt ein, wofür sie stehen
darf, ohne sie festzulegen. Aus historischen Gründen heißt die Methode, die
die Unbestimmten eines Ausdrucks aufzählt, `variables`, wie in den meisten
Computeralgebrasystemen.

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

Der Baum wird mit dem Minimum an Klammern gedruckt, das ihn erhält. Die
Ausgabe ist gültiges Ruby, abgesehen von den Variablennamen, und lässt sich
also wieder einfügen.

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

`simplify` bringt einen Ausdruck in eine kanonische Form: Zahlen werden
exakt zusammengefasst, gleiche Terme und gleiche Faktoren verschmolzen,
Summen nach Grad geordnet. Produkte werden nie über Summen ausmultipliziert;
das tut `expand`, und `factor` geht den umgekehrten Weg.

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

Rationale Ausdrücke: `cancel` bringt alles über einen Nenner und kürzt mit
dem Polynom-ggT, `rationalize` beseitigt Quadratwurzeln aus Nennern. `numer`
und `denom` geben die beiden Hälften dieser Normalform, mit ganzzahligen
Koeffizienten und positivem Leitkoeffizienten im Nenner.

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

`apart` ist die Partialbruchzerlegung über QQ: ein Polynomanteil, dann ein
Term je Potenz jedes irreduziblen Faktors des Nenners. Andere Unbestimmte
sind Parameter; nennen Sie die, nach der zerlegt werden soll, wenn es
mehrere gibt.

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

Der letzte Nenner ist über QQ irreduzibel, es spaltet sich also nichts;
`apart` führt keine algebraischen Zahlen ein. Die Umformungsmethoden gibt es
auch als Funktionen, nach Art von MuPAD und Maple: `simplify(f)`,
`expand(f)`, `cancel(f)`, `rationalize(f)`.

#### Einsetzen und Auswerten

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

`call` (und die Kurzform `.()`) gibt eine gewöhnliche Ruby-Zahl zurück,
sobald jede Variable belegt ist. Positionsargumente belegen die Variablen in
alphabetischer Reihenfolge. `evalf` wertet numerisch aus und macht aus jeder
exakten Zahl eine Fließkommazahl; `to_f` tut dasselbe für einen konstanten
Ausdruck.

```
rcas> (sqrt(2) * x).evalf(x: 3)
=> 4.242640687119286
rcas> (PI**2 / 6).to_f
=> 1.6449340668482262
rcas> subs(x**2 + 1, x: 3)
=> 3**2 + 1
rcas> evalf(pi)
=> 3.141592653589793
```

`subs`, `evalf` und `diff` gibt es als Funktionen wie als Methoden.

#### Gleichheit

`==` ist strukturell: zwei Ausdrücke sind gleich, wenn sie derselbe Baum
sind. Vergleichen Sie kanonische Formen, wenn Sie mathematische Gleichheit
meinen.

```
rcas> x + 1 == 1 + x
=> false
rcas> (x + 1).simplify == (1 + x).simplify
=> true
rcas> (x - x).simplify == 0
=> true
```

### 1.2 Zahlen und Konstanten

Ganze Zahlen und Brüche bleiben exakt, Fließkommazahlen bleiben
Fließkommazahlen. `1/2` ist in Ruby eine Ganzzahldivision, schreiben Sie
also `1/2r` (oder `Rational(1, 2)`) für ein Halb.

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

`PI`, `E` und `I` sind die exakten Konstanten (`pi` und `π` gehen auch als
bloße Namen); `oo` und `∞` sind unendlich, als Grenzwertstelle und als
Summationsgrenze. Eine Funktion, die auf eine Konstante angewandt wird,
faltet sich sofort zusammen, so wie Ruby `1 + 2` zusammenfasst; ein
Operatorausdruck wie `I**2` bleibt stehen, bis `simplify` kommt.

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

Die Funktionen sind `sin cos tan asin acos atan exp log sinh cosh sqrt zeta`.
`sqrt(x)` ist `x**(1/2)`, und `exp(a)*exp(b)` verschmilzt zu `exp(a + b)`.

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

#### Komplexe Teile und Runden

`re`, `im`, `conj` und `arg` zerlegen einen Ausdruck nach dem
Ausmultiplizieren anhand seiner komplexen Koeffizienten. Eine Variable gilt
erst dann als reell, wenn sie so angenommen wurde (`assume(x: RR)`); bis
dahin bleibt `re(x)` stehen, wie in Maple und Mathematica. `arg` ist exakt
für die Winkel, die die `atan`-Tabelle kennt, und sonst eine
Fließkommazahl. `floor`, `ceil`, `round` und `mod` falten sich auf Zahlen
zusammen und bleiben auf Ausdrücken symbolisch.

```
rcas> [re(3 + 2*I), im((1 + I)**2), conj(2 - 3*I)]
=> [3, 2, 2 + 3*i]
rcas> [arg(-1), arg(I), arg(1 + I), arg(-1 - I)]
=> [pi, pi/2, pi/4, -3*pi/4]
rcas> re(x + I*y)
=> -im(y) + re(x)
rcas> assume(x: RR, y: RR)
=> true
rcas> [re(x + I*y), im((x + I*y)**2), conj(x + I*y)]
=> [x, 2*x*y, x - i*y]
rcas> forget
=> true
rcas> [floor(7/2r), ceil(7/2r), round(5/2r), floor(-7/2r), mod(-7, 3), floor(x)]
=> [3, 4, 3, -4, 2, floor(x)]
```

#### Ganze Zahlen und Primzahlen

`factor` auf einer ganzen oder rationalen Zahl gibt ihre Primfaktorzerlegung
als Objekt mit `unit`, `factors` (Paare aus Primzahl und Exponent),
`primes`, `expand` und `prime?`; `ifactor` ist dieselbe Funktion unter
Maples Namen. Auf die Probedivision durch kleine Primzahlen folgt Pollards
Rho-Methode, die Faktoren von etwa einem Dutzend Stellen schafft; `isprime`
ist ein Miller-Rabin-Test, exakt unterhalb von 3,3e24 und darüber ein
starker Wahrscheinlichkeitstest.

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

`chrem(residues, moduli)` löst die simultanen Kongruenzen (die Moduln müssen
nicht teilerfremd sein; ein widersprüchliches System wirft einen Fehler).
Modulare Potenzen, ggT und kgV ganzer Zahlen sind Rubys eigene `pow(e, m)`,
`gcd` und `lcm`. `bernoulli`, `fibonacci` und `harmonic` liefern exakte
Werte der klassischen Folgen und bleiben bei symbolischem Argument
symbolisch.

```
rcas> [bernoulli(12), fibonacci(100), harmonic(4)]
=> [-691/2730, 354224848179261915075, 25/12]
```

Die modulare Arithmetik hat ihr eigenes Vokabular: `congruence(f, x, m)`
löst f = 0 modulo m und gibt die Reste zurück, `legendre(a, p)` sagt, ob a
ein Quadrat modulo einer ungeraden Primzahl ist (`jacobi` erweitert das auf
ungerade zusammengesetzte Moduln), `order(a, m)` ist die multiplikative
Ordnung und `primitive_root(m)` ein Erzeuger. `continued_fraction` und
`convergents` geben die besten rationalen Näherungen einer Zahl.

```
rcas> congruence(3*z - 4, z, 7)
=> [6]
rcas> congruence(z**2 - 1, z, 8)
=> [1, 3, 5, 7]
rcas> [legendre(2, 7), legendre(3, 7), jacobi(1001, 9907)]
=> [1, -1, -1]
rcas> [order(3, 7), primitive_root(7)]
=> [6, 3]
rcas> continued_fraction(415/93r)
=> [4, 2, 6, 7]
rcas> convergents(PI.evalf, 4)
=> [(3/1), (22/7), (333/106), (355/113)]
```

### 1.3 Analysis

#### Ableitungen

```
rcas> (x**3 + sin(x)).diff(x)
=> cos(x) + 3*x**2
rcas> (x**x).diff(x)
=> x**x*(1 + log(x))
rcas> exp(x**2).diff(x)
=> 2*x*exp(x**2)
rcas> (x**3).diff(x, 2)
=> 6*x
rcas> diff(x**3, x, 2)
=> 6*x
rcas> atan(x).diff(x)
=> 1/(1 + x**2)
```

#### Stammfunktionen

`integrate(f, x)` (oder `f.integrate(x)`) gibt eine Stammfunktion ohne die
Konstante. Was sich nicht integrieren lässt, bleibt als `integral(...)`
stehen, Teilergebnisse bleiben also brauchbar, und `diff` macht `integrate`
rückgängig. Für jeden Term werden der Reihe nach vier Schichten versucht:

1. **Regeln.** Linearität und konstante Faktoren, eine Tabelle für `u**n`,
   `1/u`, `c**u` und `exp sin cos tan log atan sinh cosh` eines linearen
   Arguments, die Substitution nach der Kettenregel (`x*exp(x**2)`,
   `sin(x)*cos(x)**3`, `log(x)/x`) und partielle Integration für ein Polynom
   mal einen exponentiellen oder trigonometrischen Faktor sowie für einen
   Faktor, der beim Ableiten einfacher wird (`log atan asin acos erf erfc`).
   Beträge und Vorzeichen eines linearen Arguments gehören auch hierher:
   `abs(u)` ist `u*sign(u)`, und `sign(u)` ist auf jeder Seite der Nullstelle
   von `u` konstant, lässt sich also aus dem Integral ziehen; die
   Integrationskonstante wird dann so gewählt, dass die Stammfunktion an
   dieser Nullstelle stetig ist, was ein bestimmtes Integral darüber hinweg
   auch braucht.
2. **Rationale Funktionen, exakt.** Die Hermite-Reduktion beseitigt
   mehrfache Nennerfaktoren; der logarithmische Teil kommt aus der
   Rothstein-Trager-Resultante, deren rationale Nullstellen `log`-Terme
   liefern und deren irreduzible quadratische Faktoren `log` plus `atan`
   mit Quadratwurzeln geben. Hat eine Nullstelle Grad drei oder höher, wird
   der Nenner über seine irreduziblen Faktoren in Partialbrüche zerlegt, und
   eine Quartik ohne ungerade Potenzen, `x**4 + a*x**2 + b`, wird in reelle
   quadratische Faktoren zerlegt: `(x**2 + s*x + t)*(x**2 - s*x + t)` mit
   `t = sqrt(b)` und `s = sqrt(2*t - a)`, oder `(x**2 + p)*(x**2 + q)`, wenn
   `a**2 - 4*b` positiv ist. Das macht aus `1/(x**4 + 1)` zwei Logarithmen
   und zwei Arkustangens. Alles andere bleibt als `integral(...)` stehen.
3. **Risch-Norman-Heuristik.** Der Integrand wird als Laurent-Polynom in
   `x` und seinen transzendenten Atomen geschrieben (`exp(u)`, `log(u)`,
   `sin(u)`/`cos(u)`, `sinh`/`cosh`, `atan`, `c**u`, Wurzeln wie `x**(1/2)`,
   Polynomnenner). Ein Ansatz derselben Gestalt plus `log`-Terme wird
   symbolisch abgeleitet, `sin**2 + cos**2 = 1` herausgekürzt und die
   unbestimmten Koeffizienten werden als exaktes lineares System über QQ
   bestimmt. Eine abschließende lineare Substitution (`v = x + 1`) rettet
   Integranden wie `x*exp(x)/(x + 1)**2`.
4. **Rationalisierende Substitutionen.** Ein Integrand, der eine rationale
   Funktion von `x` und `sqrt(a*x**2 + b*x + c)` ist, wird in einen
   rationalen Teil und Stücke `P(x)/sqrt(Q)` zerlegt, die sich auf
   `S(x)*sqrt(Q)` und die beiden Grundformen `log(sqrt(Q) + ...)` und
   `asin(...)` zurückführen; lineare Nenner laufen über `x - alpha = 1/t`.
   Wurzeln aus einer linearen Form (`sqrt(x)/(1 + x)`) oder aus einem
   Quotienten zweier linearer Formen (`sqrt((1 - x)/(1 + x))`, die
   Möbius-Substitution), rationale
   Funktionen von `exp(k*x)` (auch `sinh`, `cosh`) und von `sin(x)`,
   `cos(x)` (`tan(x/2)`, die Weierstraß-Substitution) werden zu rationalen
   Funktionen der neuen Variablen und gehen an Schicht 2. Gerade Potenzen
   von `sin` oder `cos` über einer ungeraden Potenz der anderen werden
   zuerst mit `sin**2 + cos**2 = 1` umgeschrieben, damit `sin(x)**2/cos(x)`
   als `log((1 + sin(x))/cos(x)) - sin(x)` herauskommt und nicht in
   `tan(x/2)`.


```
rcas> integrate(abs(x), x)
=> x**2*sign(x)/2
rcas> integrate(abs(x - 1), x: 0..3)
=> 5/2
rcas> integrate(erf(x), x)
=> exp(-x**2)/pi**(1/2) + x*erf(x)
rcas> integrate(x/(x**4 + x**2 + 1), x)
=> 3**(1/2)*atan(3**(1/2)*(1 + 2*x**2)/3)/3
rcas> integrate(1/(x**4 + 1), x: 0..oo)
=> 2**(1/2)*pi/4
rcas> integrate(sqrt((1 - x)/(1 + x)), x)
=> 2*((1 - x)/(1 + x))**(1/2)/(1 + (1 - x)/(1 + x)) - 2*atan(((1 - x)/(1 + x))**(1/2))
rcas> integrate(floor(x), x)
=> integral(floor(x), x)
```

Dieselbe Maschinerie liefert `sqrt(tan(x))` in Logarithmen und Arkustangens,
über den quartischen Nenner, den die Substitution `t = sqrt(tan(x))`
zurücklässt. Ein Integrand, den rcas nicht einmal ableiten kann (`floor(x)`
oder eine unbekannte Funktion), bleibt ein `integral(...)`, statt einen
Fehler auszulösen.

Stammfunktionen mit Wurzeln und Logarithmen sind formal: sie abzuleiten
gibt den Integranden überall dort zurück, wo beide reell sind, und an einer
Singularität des Integranden kann die Konstante springen (wie in jedem CAS).
Irreduzible quadratische Nenner unter einer Wurzel
(`1/((x**2 + 1)*sqrt(x**2 + 2))`) und Radikanden vom Grad drei oder höher
bleiben als `integral(...)` stehen, ebenso eine rationale Funktion, deren
Nenner einen reellen Faktor vom Grad drei oder höher braucht
(`1/(x**3 - 2)`, `1/(x**8 + 1)`).

Die Testsuite prüft jede Stammfunktion, indem sie sie ableitet und an
einigen Stellen numerisch mit dem Integranden vergleicht.

```
rcas> integrate(x**2 * exp(x), x)
=> 2*exp(x) - 2*x*exp(x) + x**2*exp(x)
rcas> integrate(x * log(x), x)
=> -x**2/4 + x**2*log(x)/2
rcas> integrate(1 / (x**2 + 1), x)
=> atan(x)
rcas> integrate(1 / (x**3 + 1), x)
=> log(1 + x)/3 - log(1 - x + x**2)/6 + 3**(1/2)*atan(3**(1/2)*(-1 + 2*x)/3)/3
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
rcas> integrate(exp(-x**4) + x, x)
=> integral(exp(-x**4), x) + x**2/2
rcas> integrate(exp(-x**2), x)
=> pi**(1/2)*erf(x)/2
rcas> integrate(sqrt(x**2 + 1), x)
=> log((1 + x**2)**(1/2) + x)/2 + x*(1 + x**2)**(1/2)/2
rcas> integrate(sqrt(1 - x**2), x)
=> asin(x)/2 + x*(1 - x**2)**(1/2)/2
rcas> integrate(1/(x*sqrt(x**2 - 1)), x)
=> atan((-1 + x**2)**(1/2))
rcas> integrate(sqrt(x)/(1 + x), x)
=> -2*atan(x**(1/2)) + 2*x**(1/2)
rcas> integrate(1/(1 + exp(x)), x)
=> -log(1 + exp(x)) + x
rcas> integrate(1/cos(x), x)
=> log((1 + sin(x))/cos(x))
rcas> integrate(1/(2 + cos(x)), x)
=> 2*3**(1/2)*atan(3**(1/2)*tan(x/2)/3)/3
```

#### Bestimmte Integrale

Geben Sie die Grenzen als Argumente oder als Bereich der Variablen an; ein
Bereich ohne Ende bedeutet unendlich. Uneigentliche Integrale laufen über
Grenzwerte.

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
rcas> integrate(sqrt(1 - x**2), x: -1..1)
=> pi/2
rcas> integrate(exp(-x**2), x: 0..1)
=> pi**(1/2)*erf(1)/2
rcas> integrate(exp(-x**2), x: -oo..oo)
=> pi**(1/2)
```

#### Integrale mit Namen

Manche Integranden haben keine elementare Stammfunktion, aber eine mit
Namen, und das zu sagen nützt mehr als ein unausgewertetes
`integral(...)`. `Si` und `Ci` sind der Integralsinus und der
Integralkosinus, `Ei` der Integralexponent und `li = Ei(log(x))` der
Integrallogarithmus, der die Primzahlen zählt.

```
rcas> integrate(sin(x)/x, x)
=> Si(x)
rcas> integrate(exp(x)/x, x)
=> Ei(x)
rcas> integrate(1/log(x), x)
=> li(x)
rcas> integrate(exp(x)/(x + 1), x)
=> Ei(1 + x)/e
rcas> integrate(sin(x)/x, x: 0..oo)
=> pi/2
rcas> integrate(sin(x)/x, x: 0..1).evalf
=> 0.946083070367183
rcas> diff(Si(x), x)
=> sin(x)/x
rcas> dsolve(eq(D(y, x, 2) + y, 1/x), y, x)
=> [y = C1*cos(x) + C2*sin(x) + Ci(x)*sin(x) - Si(x)*cos(x)]
```

Sie kennen ihre Ableitungen, ihre Werte bei `0` und im Unendlichen (das
Integral über `sin(x)/x` von `0` bis `oo` ist also Dirichlets `pi/2`), und
`evalf` gibt ihre Zahlen. Sie tauchen auch dort auf, wo sie hingehören:
die Gleichung `y'' + y = 1/x` oben wird durch Variation der Konstanten
gelöst, und was dabei übrig bleibt, sind genau `Si` und `Ci`.

#### Länge, Fläche und Volumen

Die drei Fragen, mit denen eine erste Integralrechnung endet.
`arclength(f, x: a..b)` ist `integral(sqrt(1 + f'**2))` für einen Graphen
und `integral(sqrt(x'**2 + y'**2))` für eine Parameterkurve
`[x(t), y(t)]`; `revolution_volume` und `revolution_surface` drehen einen
Graphen um die x-Achse (oder mit `axis: :y` um die y-Achse, das ist die
Formel mit den Zylinderschalen).

```
rcas> arclength(x**2, x: 0..1)
=> 5**(1/2)/2 - log(2)/4 + log(4 + 2*5**(1/2))/4
rcas> arclength(x**2, x: 0..1).evalf
=> 1.4789428575445975
rcas> arclength([cos(t), sin(t)], t: 0..pi)
=> pi
rcas> revolution_volume(sqrt(x), x: 0..1)
=> pi/2
rcas> revolution_volume(sqrt(1 - x**2), x: -1..1)
=> 4*pi/3
rcas> revolution_surface(x, x: 0..1)
=> 2**(1/2)*pi
```

Die Wurzel aus einem Polynom hat selten eine elementare Stammfunktion,
eine Bogenlänge bleibt also oft ein `integral(...)`-Knoten; `evalf`
rechnet ihn aus.

#### Zahlen, wenn die Symbole nicht reichen

Nicht jede Gleichung hat eine Lösung in geschlossener Form, und die meisten
Funktionen haben keine elementare Stammfunktion. `nsolve` findet eine
Nullstelle als Dezimalzahl, aus einem einschließenden Bereich oder von einem
Startwert aus, und `nintegrate` berechnet ein bestimmtes Integral, auch mit
unendlichen Grenzen. `evalf` auf einem nicht ausgewerteten `integral` tut
dasselbe, ein formales Ergebnis lässt sich also immer in eine Zahl
verwandeln. Diese Ergebnisse sind Fließkommazahlen und werden auch so
gedruckt; ein exaktes Ergebnis wird niemals stillschweigend durch eines
ersetzt.

```
rcas> nsolve(cos(x) - x, x: 0..1)
=> 0.7390851332151607
rcas> nsolve(x**3 - 2*x - 5, x, 2)
=> 2.0945514815423265
rcas> nintegrate(sin(x)/x, x: 0..1)
=> 0.9460830703671829
rcas> nintegrate(exp(-x**2), x: -oo..oo)
=> 1.7724538509061416
rcas> integrate(exp(-x**4), x: 0..1).evalf
=> 0.8448385947571027
```

#### So viele Stellen, wie man will

`evalf(f, 50)` (oder `evalf(f, digits: 50)`) rechnet auf so viele
signifikante Stellen, statt auf die sechzehn, die ein Float trägt. Der
Baum wird in `BigDecimal` mit zehn Schutzstellen durchlaufen und einmal am
Ende gerundet, die Stellen, die zurückkommen, stimmen also.

```
rcas> evalf(pi, 50)
=> 3.1415926535897932384626433832795028841971693993751
rcas> evalf(pi)
=> 3.141592653589793
rcas> evalf(sqrt(2), 40)
=> 1.41421356237309504880168872420969807857
rcas> evalf(exp(1), 30)
=> 2.71828182845904523536028747135
rcas> evalf(1/3r, 25)
=> 0.3333333333333333333333333
rcas> evalf(sin(1)**2 + cos(1)**2, 40)
=> 1.0
rcas> evalf(solve(x**5 - x - 1, x).first, 40)
=> 1.167303978261418684256045899854842180721
rcas> evalf(0.1 * pi, 50)
=> 0.3141592653589793
```

Die letzten beiden Zeilen sind der eigentliche Grund für die Übung. Eine
algebraische Zahl wird aus ihrem Wert in doppelter Genauigkeit mit dem
Newton-Verfahren verfeinert, eine Nullstelle ohne Formel hat also trotzdem
alle Stellen, die man braucht. Und ein `Float` im Ausdruck trägt nur seine
eigenen sechzehn Stellen, das Ergebnis wird also mit sechzehn angegeben,
gleich wie viele verlangt waren: sie auf fünfzig aufzufüllen hieße,
vierunddreißig zu erfinden.

Die Konstanten, `exp`, `log`, die trigonometrischen und hyperbolischen
Funktionen samt Umkehrungen, Wurzeln, Potenzen, eine endliche `sum` und
ein reelles `RootOf` sind alle da, und ebenso die, die `BigMath` nicht hat:
`erf` und `erfc`, `Si`, `Ci`, `Ei` und `li` über ihre Reihen, `zeta` über
Euler-Maclaurin und die eulersche Konstante selbst über den Algorithmus von
Brent und McMillan. Auch `nsolve` und `nintegrate` nehmen `digits:` - eine
Nullstelle wird mit dem Newton-Verfahren nachgezogen, ein Integral mit der
doppeltexponentiellen Regel berechnet, die eine singuläre Grenze und einen
unendlichen Bereich ungefragt verkraftet. Ein bestimmtes `integral(...)`,
das symbolisch niemand lösen konnte, geht denselben Weg.

```
rcas> evalf(erf(1), 30)
=> 0.842700792949714869341220635083
rcas> evalf(zeta(3), 30)
=> 1.20205690315959428539973816151
rcas> nsolve(cos(x) - x, x: 0..1, digits: 40)
=> 0.7390851332151606416553120876738734040134
rcas> nintegrate(1/sqrt(x), x: 0..1, digits: 30)
=> 2.0
rcas> nintegrate(exp(-x**2), x: 0..oo, digits: 30)
=> 0.886226925452758013649083741671
rcas> evalf(integrate(exp(-x**4), x: 0..1), 30)
=> 0.8448385947571024007640469307
```

Was übrig bleibt, wirft `Precision::Unsupported` und nennt sich beim Namen,
statt sechzehn gute Stellen als fünfzig zu verkleiden: ein unbestimmtes
Integral, ein komplexer Wert, `zeta` an einer gebrochenen Stelle, eine
unbekannte Funktion und ein Argument, das so groß ist, dass die Reihe dazu
mehr Stellen wegkürzen würde, als die Arbeitsgenauigkeit hergibt. Das
gewöhnliche `evalf` beantwortet nach wie vor, was es kann.

Das Ergebnis ist ein `RCAS::Decimal`: ein `Numeric`, das weiß, auf wie
viele Stellen es gut ist, sie ausgibt und wie jede andere Zahl wieder in
einen Ausdruck eingeht.

#### Kurvendiskussion

Die Fragen, die man an einen Graphen stellt: wo er umkehrt, wo er die
Krümmung wechselt, welchen Geraden er sich nähert, wie seine Tangente
aussieht und wo er überhaupt definiert ist.

```
rcas> extrema(x**3 - 3*x, x)
=> [[-1, 2, :maximum], [1, -2, :minimum]]
rcas> inflections(x**3 - 3*x, x)
=> [0]
rcas> asymptotes((x**2 + 1)/x, x)
=> {:vertical=>[0], :horizontal=>[], :oblique=>[x]}
rcas> tangent(x**2, x, 1)
=> -1 + 2*x
rcas> real_domain(log(x - 1), x)
=> (1, oo)
```

`extrema` gibt die Stelle, den Wert und die Art zurück. Die zweite Ableitung
entscheidet; wo auch sie verschwindet, wie bei `x**4`, entscheidet das
Vorzeichen der ersten Ableitung links und rechts davon. `asymptotes` liefert
die senkrechten aus den Polstellen und die waagerechten oder schiefen aus
den Grenzwerten im Unendlichen.

#### Die vollständige Kurvendiskussion

`discuss(f, x)` stellt alle diese Fragen auf einmal, in der Reihenfolge, in
der der Unterricht sie stellt, und beantwortet sie in einem Bericht: wo die
Funktion definiert ist, ob sie symmetrisch oder periodisch ist, ihre
Nullstellen und ihren Wert an der Stelle 0, die Definitionslücken und was
an ihnen geschieht, die Grenzwerte im Unendlichen samt den Geraden, denen
sich der Graph nähert, und dann die Extrema, wo sie steigt und fällt, ihre
Wendepunkte und wo sie sich wie krümmt. Das Ritual hat nicht nur im
Deutschen einen eigenen Namen: im Französischen heißt es *étude de
fonction*, im Italienischen *studio di funzione*; das Englische nennt
dieselbe Arbeit curve sketching.

```
rcas> discuss(x**3 - 3*x, x)
=> f(x) = x**3 - 3*x
     domain       (-oo, oo)
     symmetry     odd: f(-x) = -f(x), symmetric about the origin
     zeros        -3**(1/2), 0, 3**(1/2)
     y intercept  f(0) = 0
     at infinity  f -> -oo as x -> -oo; f -> oo as x -> oo
     asymptotes   none
     extrema      maximum at (-1, 2); minimum at (1, -2)
     monotonic    increasing on (-oo, -1), decreasing on (-1, 1), increasing on (1, oo)
     inflections  (0, 0)
     curvature    concave on (-oo, 0), convex on (0, oo)
rcas> discuss((x**2 + 1)/x, x)
=> f(x) = (x**2 + 1)/x
     domain       (-oo, 0) ∪ (0, oo)
     symmetry     odd: f(-x) = -f(x), symmetric about the origin
     zeros        none
     gaps         0 (pole)
     at infinity  f -> -oo as x -> -oo; f -> oo as x -> oo
     asymptotes   x = 0, y = x
     extrema      maximum at (-1, -2); minimum at (1, 2)
     monotonic    increasing on (-oo, -1), decreasing on (-1, 0), decreasing on (0, 1), increasing on (1, oo)
     inflections  none
     curvature    concave on (-oo, 0), convex on (0, oo)
```

`none` und `not determined` sind verschiedene Antworten: das erste sagt,
dass es nichts zu berichten gibt, das zweite, dass rcas die Frage nicht
entscheiden konnte; übergangen wird keine. Der Definitionsbereich zählt
auch eine Lücke mit, die sich wegkürzt - `(x**2 - 1)/(x - 1)` ist an der
Stelle 1 weiterhin undefiniert -, und im Unendlichen wird nur nach den
Enden gefragt, die der Definitionsbereich erreicht. Monotonie und Krümmung
kommen aus einer Vorzeichentabelle: die Gerade wird an den Nullstellen von
`f'` (von `f''`) und an den Lücken zerschnitten, und das Vorzeichen jedes
Stücks wird an Stichstellen abgelesen, an dreien, damit ein Stück, dessen
Vorzeichen nicht konstant ist - eine Nullstelle, die das Lösen übersehen
hat -, offen bleibt, statt geraten zu werden.

Eine periodische Funktion wird über eine Periode diskutiert, und jede
Zeile, die sich wiederholt, sagt das:

```
rcas> discuss(sin(x), x)
=> f(x) = sin(x)
     domain       (-oo, oo)
     symmetry     odd: f(-x) = -f(x), symmetric about the origin
     period       2*pi
     zeros        0, pi (+ k*2*pi, k an integer)
     y intercept  f(0) = 0
     at infinity  no limit as x -> -oo; no limit as x -> oo
     asymptotes   none
     extrema      minimum at (-pi/2, -1); maximum at (pi/2, 1) (+ k*2*pi, k an integer)
     monotonic    increasing on (0, pi/2), decreasing on (pi/2, 3*pi/2), increasing on (3*pi/2, 2*pi) (+ k*2*pi, k an integer)
     inflections  (0, 0), (pi, 0) (+ k*2*pi, k an integer)
     curvature    concave on (0, pi), convex on (pi, 2*pi) (+ k*2*pi, k an integer)
```

Mit `steps` werden dieselben Fragen der Reihe nach durchgearbeitet, so wie
man die Lösung abgeben würde, und der Bericht ist die Zusammenfassung am
Schluss. Beide Schreibweisen tun es: `steps(f, x, :discuss)` oder die
Blockform `steps { discuss(f, x) }`, denn `hold` hält eine
Kurvendiskussion ebenso unausgewertet fest wie ein Integral:

```
rcas> steps(x**3 - 3*x, x, :discuss)
=> discuss(x**3 - 3*x, x)
     1. the domain: nothing to exclude, so every real x
       D = (-oo, oo)
     2. symmetry: put -x in for x
       f(-x) = 3*x - x**3
       that is -f(x): the graph is symmetric about the origin
     3. the zeros: solve f(x) = 0
       x = -3**(1/2), 0, 3**(1/2)
       f(0) = 0, where the graph crosses the vertical axis
     4. at infinity: the limits, and the lines the graph approaches
       limit(f, x, -oo) = -oo
       limit(f, x, oo) = oo
     5. the derivatives
       f'(x) = -3 + 3*x**2
       f''(x) = 6*x
       f'''(x) = 6
     6. the extrema: solve f'(x) = 0, then the second derivative decides
       f'(x) = 0 at x = -1, 1
       f''(-1) = -6 < 0: a maximum at (-1, 2)
       f''(1) = 6 > 0: a minimum at (1, -2)
     7. the monotonicity: the sign of f' between its zeros
       f' > 0 on (-oo, -1): increasing
       f' < 0 on (-1, 1): decreasing
       f' > 0 on (1, oo): increasing
     8. the inflections: solve f''(x) = 0
       f''(x) = 0 at x = 0
       f'''(0) = 6, not 0: an inflection at (0, 0)
     9. the curvature: the sign of f''
       f'' < 0 on (-oo, 0): concave
       f'' > 0 on (0, oo): convex
   = f(x) = x**3 - 3*x
     domain       (-oo, oo)
     symmetry     odd: f(-x) = -f(x), symmetric about the origin
     zeros        -3**(1/2), 0, 3**(1/2)
     y intercept  f(0) = 0
     at infinity  f -> -oo as x -> -oo; f -> oo as x -> oo
     asymptotes   none
     extrema      maximum at (-1, 2); minimum at (1, -2)
     monotonic    increasing on (-oo, -1), decreasing on (-1, 1), increasing on (1, oo)
     inflections  (0, 0)
     curvature    concave on (-oo, 0), convex on (0, oo)
```

#### Mehrere Veränderliche

`diff` bildet bereits eine partielle Ableitung, denn es leitet nach der
Variablen ab, die Sie nennen. Diese hier sammeln sie ein: den Gradienten als
Vektor, die Hesse- und die Jacobi-Matrix als Matrizen, Divergenz, Rotation
und Laplace-Operator eines Feldes, iterierte Integrale über einen Quader und
Lagrange-Multiplikatoren für ein Extremum unter einer Nebenbedingung.

```
rcas> gradient(x**2*y, [x, y])
=> (2*x*y, x**2)
rcas> hessian(x**2*y, [x, y])
=> [2*y 2*x]
   [2*x   0]
rcas> jacobian([x*y, x + y], [x, y])
=> [y x]
   [1 1]
rcas> laplacian(x**2 + y**2, [x, y])
=> 4
rcas> curl([y, -x, 0], [x, y, z])
=> (0, 0, -2)
rcas> integrate(x*y, x: 0..1, y: 0..2)
=> 1
rcas> lagrange(x + y, [x**2 + y**2 - 1], [x, y])
=> [{x=>-2**(1/2)/2, y=>-2**(1/2)/2}, {x=>2**(1/2)/2, y=>2**(1/2)/2}]
```

#### Reihen

`series(f, x, a, n)` entwickelt um `a` bis zur Ordnung `n` mit einem
`O(...)`-Term; `taylor` lässt das `O` weg. Laurent- und Puiseux-Reihen
(negative und gebrochene Potenzen) und Entwicklungen im Unendlichen
funktionieren.

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

#### Formale Potenzreihen

`fps(f, x, a)`, auch `series(f, x, formal: true)`, gibt den *allgemeinen*
Koeffizienten statt der ersten Glieder: `f` als `sum(c(k)*(x - a)**k)` mit
`c(k)` in geschlossener Form. rcas sucht eine Differentialgleichung mit
polynomialen Koeffizienten für `f`, liest die Rekursion ab, der die
Taylor-Koeffizienten genügen, und löst diese; das Ergebnis ist eine
gewöhnliche `sum`, die `doit` wieder aufsummiert.

```
rcas> fps(exp(x), x)
=> sum(x**k/k!, k, 0, oo)
rcas> fps(sin(x), x)
=> sum((-1)**k*x**(1 + 2*k)/(1 + 2*k)!, k, 0, oo)
rcas> fps(cosh(x), x)
=> sum(x**(2*k)/(2*k)!, k, 0, oo)
rcas> fps(log(1 + x), x)
=> sum(-((-1)**k*x**k)/k, k, 1, oo)
rcas> fps(atan(x), x)
=> sum((-1)**k*x**(1 + 2*k)/(1 + 2*k), k, 0, oo)
rcas> fps((1 + x)**a, x)
=> sum(x**k*binomial(a, k), k, 0, oo)
rcas> fps(1 / sqrt(1 - 4*x), x)
=> sum(x**k*(2*k)!/k!**2, k, 0, oo)
rcas> series(asin(x), x, formal: true)
=> sum((1/4)**k*x**(1 + 2*k)*(2*k)!/(k!**2*(1 + 2*k)), k, 0, oo)
rcas> fps(exp(x), x, 1)
=> sum((x - 1)**k*e/k!, k, 0, oo)
rcas> fps(sin(x), x).doit
=> sin(x)
```

Jede Summe beginnt dort, wo ihre Rekursion beginnt: `log(1 + x)` hat kein
konstantes Glied, und Koeffizienten, die sich erst später einpendeln,
stehen mit ihren ersten Gliedern vor der Summe.

```
rcas> fps(cos(x)**2, x)
=> 1 + sum((-4)**k*x**(2*k)/(2*(2*k)!), k, 1, oo)
```

Die Koeffizienten müssen hypergeometrisch sein, das heißt `c(k + m)/c(k)`
eine rationale Funktion von `k`. Der Tangens (Bernoulli-Zahlen),
`exp(x)/(1 - x)` und `x/(1 - x - x**2)` (Fibonacci-Zahlen, eine
dreigliedrige Rekursion) sind es nicht; `fps` sagt das mit einem
`SeriesError`, statt zu raten, und `series` entwickelt sie weiterhin bis zu
einer Ordnung.

#### Grenzwerte

Grenzwerte lesen den führenden Term der Reihe ab. `oo` und `-oo` sind
zulässige Stellen; `dir: :right` oder `:left` gibt einseitige Grenzwerte,
und ein zweiseitiger Grenzwert, dessen Seiten nicht übereinstimmen, bleibt
unausgewertet. Einen Faktor, der für eine Reihe zu schnell oszilliert,
erledigt der Einschnürungssatz: `sin`, `cos`, `sign`, `atan`, `erf` und
`tanh` sind als beschränkt bekannt, ein Produkt aus einem von ihnen und
einem Faktor, der gegen null geht, geht also gegen null. Eine ungedämpfte
Oszillation hat keinen Grenzwert und sagt das auch.

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
=> 0
rcas> limit(exp(-x) * cos(3*x), x, oo)
=> 0
rcas> limit(x * sin(1/x), x, 0)
=> 0
rcas> limit(sin(x), x, oo)
=> limit(sin(x), x, oo)
```

#### Abschnittsweise definierte Funktionen

`piecewise(Bedingung => Wert, ...)` ist eine Funktion, die Zweig für Zweig
gegeben ist. Die Bedingungen sind Ungleichungen (oder Gleichungen, oder
`interval(...)`), die letzte darf `:else` sein, und die erste zutreffende
Bedingung entscheidet. Solange die Unbestimmte keinen Wert hat, wird nichts
ausgewählt, der Knoten wird also so ausgegeben, wie er geschrieben wurde;
`call`, `diff`, `integrate`, `limit` und `solve` arbeiten zweigweise.

```
rcas> pwf = piecewise(x < 0 => -x, :else => x**2)
=> piecewise(x < 0 => -x, :else => x**2)
rcas> pwf.call(x: -3)
=> 3
rcas> diff(pwf, x)
=> piecewise(x < 0 => -1, :else => 2*x)
rcas> kinks(pwf)
=> [0]
rcas> integrate(pwf, x)
=> piecewise(x < 0 => -x**2/2, :else => x**3/3)
rcas> integrate(pwf, x: -2..3)
=> 11
rcas> solve(eq(pwf, 4), x)
=> [-4, 2]
```

Interessant an einer solchen Funktion sind die Stellen, an denen die
Stücke aufeinandertreffen. `discontinuities` nennt die Sprungstellen (die
einseitigen Grenzwerte existieren, stimmen aber nicht überein, oder der
Funktionswert ist nicht der Grenzwert), `kinks` die Knickstellen, an denen
die Funktion stetig ist, die beiden Steigungen sich aber unterscheiden. Ein
zweiseitiger Grenzwert an einer Sprungstelle bleibt wie immer unausgewertet.

```
rcas> jump = piecewise(x < 0 => 0, :else => 1)
=> piecewise(x < 0 => 0, :else => 1)
rcas> [limit(jump, x, 0, :left), limit(jump, x, 0, :right)]
=> [0, 1]
rcas> limit(jump, x, 0)
=> limit(piecewise(x < 0 => 0, :else => 1), x, 0)
rcas> discontinuities(jump)
=> [0]
```

Die Stammfunktion verdient einen zweiten Blick. Jeder Zweig wird für sich
integriert und dann um die Konstante verschoben, die ihn am gemeinsamen
Endpunkt an den vorigen Zweig anschließt: ohne sie wäre jedes Stück zwar
weiterhin eine Stammfunktion seines eigenen Stücks, die Funktion spränge
aber bei `1`, und ein bestimmtes Integral darüber hinweg käme falsch heraus.

```
rcas> fee = piecewise(x < 1 => 1, :else => x)
=> piecewise(x < 1 => 1, :else => x)
rcas> integrate(fee, x)
=> piecewise(x < 1 => x, :else => 1/2 + x**2/2)
rcas> integrate(fee, x: 0..2)
=> 5/2
```

#### Fourier-Reihen

`fourier(f, x: a..b)` schreibt die periodische Funktion, die auf `[a, b]`
mit `f` übereinstimmt, als Summe von Sinus und Kosinus. Mit `n:` kommt die
Partialsumme mit so vielen Harmonischen zurück (voreingestellt vier), mit
`formal: true` die ganze Reihe als `sum(...)`-Knoten mit dem allgemeinen
Koeffizienten - dasselbe Paar, das `series` und `fps` für Potenzreihen
bilden.

```
rcas> fourier(x, x: -pi..pi, formal: true)
=> sum(-2*(-1)**k*sin(k*x)/k, k, 1, oo)
rcas> fourier(x, x: -pi..pi)
=> -sin(2*x) + 2*sin(3*x)/3 - sin(4*x)/2 + 2*sin(x)
rcas> fourier(x**2, x: -pi..pi, formal: true)
=> pi**2/3 + sum(4*(-1)**k*cos(k*x)/k**2, k, 1, oo)
```

Die Koeffizienten sind die Integrale `(2/T)*integral(f*cos(k*omega*x))`
und dasselbe mit `sin`, und sie ergeben sich in geschlossener Form, weil
der Index während ihrer Berechnung eine ganze Zahl ist: `sin(k*pi)` ist
dann `0` und `cos(k*pi)` ist `(-1)**k`. (`assume(k: ZZ)` liefert diese
beiden Identitäten auch sonst überall.)

Eine abschnittsweise definierte Funktion ist erlaubt, und die
Rechteckschwingung ist der Klassiker: nur die ungeraden Harmonischen
überleben, und die Partialsumme schießt an der Sprungstelle über das Ziel
hinaus, gleich wie viele Glieder man nimmt - das Gibbssche Phänomen.

```
rcas> wave = piecewise(x < 0 => -1, :else => 1)
=> piecewise(x < 0 => -1, :else => 1)
rcas> fourier(wave, x: -pi..pi, formal: true)
=> sum(sin(k*x)*(2/k - 2*(-1)**k/k)/pi, k, 1, oo)
rcas> fourier(wave, x: -pi..pi, n: 3)
=> 4*sin(3*x)/(3*pi) + 4*sin(x)/pi
rcas> plot(fourier(wave, x: -pi..pi, n: 9), x: -pi..pi, height: 12, title: "nine harmonics")
=> nine harmonics
    1.301 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⣠⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡤⣄⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⢰⠁⠀⠳⣄⣠⠔⠋⠙⠢⢄⡤⠖⠋⠓⠢⢄⡤⠖⠉⠙⢦⣀⣠⠊⠀⠸⡀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢣⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢵⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⡄
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡝⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢱
          │⢣⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⢰⠅⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀
          │⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡸⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠈⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠇⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⢣⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠈⡆⠀⡠⠋⠉⠳⣄⣀⠴⠚⠑⠢⢤⣠⠴⠚⠑⠢⣄⣠⠔⠋⠙⢦⠀⢀⠇⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
   -1.301 ┤⠀⠀⠙⠚⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠋⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          └────────────────────────────────────────────────────────────
           -3.142                                                 3.142
```

Auf einem halben Intervall entwickeln `kind: :sine` und `kind: :cosine`
die ungerade und die gerade Fortsetzung von `f`, die beiden Reihen, die
ein Randwertproblem mit festen oder mit isolierten Enden lösen. Jedes
Intervall ist zulässig; die Periode ist seine Länge.

```
rcas> fourier(x, x: 0..1, kind: :sine, formal: true)
=> sum(-2*(-1)**k*sin(pi*k*x)/(pi*k), k, 1, oo)
rcas> fourier(x, x: 0..2, n: 2)
=> 1 - sin(2*pi*x)/pi - 2*sin(pi*x)/pi
```

Die Konvergenz wird nicht geprüft: die Reihe wird formal hingeschrieben,
wie es eine Tabelle auch tut. An einer Sprungstelle konvergiert sie gegen
das Mittel der beiden einseitigen Werte, was die Zeichnung oben bei `0`
zeigt.

#### Summen

`sum(f, k, a, b)` oder `sum(f, k: a..b)`; `k: a..` summiert bis unendlich
und `a...b` schließt `b` aus. Polynome in `k` bekommen geschlossene Formen,
hypergeometrische Terme laufen über Gospers Algorithmus, `1/n**s` bis
unendlich über die Zetafunktion, und endliche Summen mit ganzzahligen
Grenzen werden exakt aufsummiert, wenn nichts anderes greift.

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
=> harmonic(n)
```

#### Bestimmte Summen: kreatives Teleskopieren

Gospers Algorithmus beantwortet die *unbestimmte* Frage, ob ein Term eine
Antidifferenz hat. Bei einer bestimmten Summe wie
`sum(binomial(n, k)**2, k: 0..n)` steht eine zweite Frage im Raum, und
Zeilbergers Algorithmus beantwortet sie: die Summe erfüllt eine lineare
Rekursion in `n`, und der Algorithmus findet eine samt Beweis.

`sumrecursion(F, k, s(n))` liefert diese Rekursion für
`S(n) = sum_k F(n, k)` in einer Folge, die Sie benennen, so dass `rsolve`
weitermachen kann.

```
rcas> sumrecursion(binomial(n, k)**2, k, s(n))
=> s(n)*(-2 - 4*n) + s(1 + n)*(1 + n) = 0
rcas> rsolve(Out[-1], s, n, init: {0 => 1})
=> s(n) = 2**(2*n)*gamma(1/2 + n)/(pi**(1/2)*n!)
```

`sum` tut dasselbe von sich aus, wenn nichts Einfacheres greift; die
geschlossene Form einer bestimmten hypergeometrischen Summe kommt also in
einem Schritt. Hier ist sie `binomial(2*n, n)`, geschrieben mit der
Gammafunktion (Abschnitt 1.3, *Fakultäten, Binomialkoeffizienten, Gamma*,
sagt, warum Produkte linearer Faktoren so aussehen).

```
rcas> sum(binomial(n, k)**2, k: 0..n)
=> 2**(2*n)*gamma(1/2 + n)/(pi**(1/2)*n!)
rcas> Out[-1].subs(n => 5).simplify
=> 252
```

Die Ordnung der Rekursion ist die, welche die Summe braucht. Drei
Binomialkoeffizienten brauchen zwei, und dann gibt es überhaupt keine
hypergeometrische geschlossene Form mehr - die Rekursion ist alles, was da
ist, und `sum` sagt das, indem es unausgewertet bleibt:

```
rcas> sumrecursion(binomial(n, k)**3, k, s(n))
=> s(1 + n)*(-16 - 21*n - 7*n**2) + s(n)*(-8 - 16*n - 8*n**2) + s(2 + n)*(4 + 4*n + n**2) = 0
rcas> sum(binomial(n, k)**3, k: 0..n)
=> sum(binomial(n, k)**3, k, 0, oo)
```

`sumcertificate(F, k, s(n))` gibt die rationale Funktion `R` dahinter: mit
`G(k) = R*F(n, k)` lässt sich die Identität
`sum_j sigma_j*F(n + j, k) = G(k + 1) - G(k)` von Hand nachrechnen, und ihre
Summation über `k` ist der Beweis der Rekursion.

```
rcas> sumcertificate(binomial(n, k), k, s(n))
=> k/(-1 + k - n)
```

Dieser letzte Schritt verlangt, dass die Randterme verschwinden, dass also
`F(n, k) = 0` außerhalb des summierten Bereichs gilt. Binomialkoeffizienten
sorgen selbst dafür; ein Term wie `binomial(n, k)/(k + 1)` mit seinem Pol
bei `k = -1` nicht, und statt eine Rekursion zurückzugeben, der die Summe
gar nicht genügt, sagt `sumrecursion`, woran es liegt.

#### Produkte

`product(f, k, a, b)` oder `product(f, k: a..b)`. Konstanten geben Potenzen,
`a**u(k)` gibt `a**sum(u)`, und ein Polynom in `k`, dessen Faktoren über QQ
linear sind, gibt Fakultäten (bei ganzzahligen Verschiebungen) oder
`gamma`-Werte (bei rationalen), denn das Produkt von `k + r` von `a` bis `b`
ist `gamma(b + r + 1)/gamma(a + r)`. Eine Verschiebung, die ein Parameter
ist, gibt dasselbe Verhältnis, generisch: die Nullstelle wird als außerhalb
des Bereichs angenommen. Alles andere mit ganzzahligen Grenzen wird
ausmultipliziert; sonst bleibt das Produkt formal.

```
rcas> product(k, k: 1..n)
=> n!
rcas> product(2*k, k: 1..n)
=> 2**n*n!
rcas> product(2*k - 1, k: 1..n)
=> 2**n*gamma(1/2 + n)/pi**(1/2)
rcas> product(a**k, k: 1..n)
=> a**(n/2 + n**2/2)
rcas> product((k + 1)/k, k: 1..n)
=> 1 + n
rcas> product(k + b, k: 1..n)
=> gamma(1 + b + n)/gamma(1 + b)
rcas> product(k, k: 1..5)
=> 120
rcas> product(factorial(k), k: 1..n)
=> product(k!, k, 1, n)
```

#### hold und evaluate

Ruby fasst `1 + 2` zusammen, bevor rcas es sieht. `hold { ... }` liest
stattdessen den Quelltext des Blocks und behält ihn, wie er geschrieben
wurde. Innerhalb des Blocks bleiben `integrate`, `diff`, `sum`, `limit`
und `discuss` formal; `evaluate` (auch `unhold`, `doit`) rechnet sie aus,
wie MuPADs `eval`. Alles andere arbeitet auf festgehaltenen Ausdrücken wie gewohnt.

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

Innerhalb von `hold` baut `==` eine Gleichung und `!=` eine
Ungleichheitsrelation (außerhalb von `hold` vergleichen beide die Struktur);
`<`, `<=`, `>`, `>=` bauen Ungleichungen wie überall sonst.

```
rcas> hold { x**2 - 3 != 0 }.solve
=> (-oo, -3**(1/2)) ∪ (-3**(1/2), 3**(1/2)) ∪ (3**(1/2), oo)
```

#### Fakultäten, Binomialkoeffizienten, Gamma

`factorial(n)` wird als `n!` gedruckt. Werte falten sich exakt zusammen,
halbzahlige über die Gammafunktion; `(k + 2)!/k!` kürzt sich zu einem
Polynom, und genau das erlaubt es `sum`, Terme mit Fakultäten und
Binomialkoeffizienten zu behandeln.

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

Die unendlichen Summen kommen aus den klassischen Potenzreihen (`exp`,
`sin`, `cos`, `sinh`, `cosh`, `log(1 + x)`, `atan`, der binomische Satz),
erkannt am Verhältnis aufeinanderfolgender Terme; die endlichen aus Gospers
Algorithmus.

#### Trigonometrisches und logarithmisches Umformen

`simplify` ist eine kanonische Form und lässt `sin(x)**2 + cos(x)**2` in
Ruhe. `trigsimp` probiert die Umformungen mit `sin**2 + cos**2 = 1` (mit
`tan` als `sin/cos` geschrieben, mit und ohne `expand_trig`) und gibt das
kürzeste Ergebnis zurück; `expand_trig` schreibt Summen und Vielfache von
Winkeln aus.

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

`expand_log` und `logcombine` setzen positive Argumente voraus.

### 1.4 Gleichungen und Lösen

`eq(lhs, rhs)` (oder `lhs.eq(rhs)`) baut eine Gleichung. `solve` nimmt eine
Gleichung oder einen Ausdruck, der null sein soll, und eine Variable; es
gibt ein Array von Lösungen zurück.

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

Polynome werden exakt gelöst: durch Faktorisieren über den rationalen
Zahlen, die Mitternachtsformel, k-te Wurzeln bei Binomen und die
symbolische quadratische Formel; ein irreduzibler Faktor vom Grad drei oder
höher mit numerischen Koeffizienten bekommt Gleitkomma-Nullstellen.
Transzendente Gleichungen werden auf ein Polynom in einem Atom
zurückgeführt und invertiert; die Umkehrfunktionen der Winkelfunktionen
geben die Hauptlösungen einer Periode.

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

Eine Gleichung mit `abs` oder `sign` darin wird in ihre Fälle zerlegt -
`|u|` ist `u`, wo `u >= 0` ist, und `-u`, wo `u <= 0` ist, und `sign(u)`
ist 1, -1 oder 0 an denselben drei Stellen -, was 2**n gewöhnliche
Gleichungen ergibt. Jeder Kandidat wird in die ursprüngliche Gleichung
zurückgesetzt, sodass nur die Lösungen übrig bleiben, die in dem Fall
liegen, aus dem sie stammen.

```
rcas> solve(abs(x) - 1, x)
=> [1, -1]
rcas> solve(abs(x - 2) - 3, x)
=> [5, -1]
rcas> solve(abs(x**2 - 4) - 1, x)
=> [-5**(1/2), 5**(1/2), -3**(1/2), 3**(1/2)]
rcas> solve(abs(x) + abs(x - 1) - 3, x)
=> [2, -1]
rcas> solve(abs(x) + 1, x)
=> []
```

Systeme nehmen ein Array von Gleichungen und eines von Unbekannten und
geben ein Array von Hashes zurück. Lineare Systeme werden nach den
Pivot-Unbekannten in Abhängigkeit von den freien aufgelöst. Polynomiale
Systeme mit rationalen Koeffizienten laufen über eine lexikographische
Gröbnerbasis (siehe 1.6): sie ist dreiecksförmig, die letzte Unbekannte hat
also ein Polynom in einer Variablen, dessen Nullstellen Unbekannte für
Unbekannte zurückgesetzt werden. Ein System mit unendlich vielen Lösungen
wirft einen Fehler, der die Basis zeigt; zwei Gleichungen mit Parametern
laufen über eine Resultante.

```
rcas> solve([eq(x + y, 3), eq(x - y, 1)], [x, y])
=> [{x=>2, y=>1}]
rcas> solve([x + y + z - 1, x - y], [x, y, z])
=> [{x=>1/2 - z/2, y=>1/2 - z/2}]
rcas> solve([x + y - 1, x + y - 2], [x, y])
=> []
rcas> solve([x**2 + y**2 - 25, x + y - 7], [x, y])
=> [{x=>4, y=>3}, {x=>3, y=>4}]
rcas> solve([x**2 - y, y**2 - x], [x, y])
=> [{x=>1, y=>1}, {x=>0, y=>0}, {x=>-1/2 + i*3**(1/2)/2, y=>-1/2 - i*3**(1/2)/2}, {x=>-1/2 - i*3**(1/2)/2, y=>-1/2 + i*3**(1/2)/2}]
rcas> solve([x**2 - 1, y - x, z**2 - x], [x, y, z])
=> [{x=>1, y=>1, z=>1}, {x=>1, y=>1, z=>-1}, {x=>-1, y=>-1, z=>-i}, {x=>-1, y=>-1, z=>i}]
```

Eine trigonometrische Gleichung hat unendlich viele Lösungen. `solve` gibt
die einer einzigen Periode zurück, so wie eine Schulbuchlösung aussieht;
`all: true` fügt die Periode mit einem ganzzahligen Parameter hinzu, sodass
die Schar vollständig ist.

```
rcas> solve(sin(x) - 1/2r, x)
=> [pi/6, 5*pi/6]
rcas> solve(sin(x) - 1/2r, x, all: true)
=> [pi/6 + 2*pi*k, 5*pi/6 + 2*pi*k]
rcas> solve(tan(x) - 1, x, all: true)
=> [pi/4 + pi*k]
```

Nullstellen irreduzibler Polynome vom Grad drei oder höher sind exakte
`RootOf`-Objekte, außer bei Binomen `a*x**n + b` und biquadratischen
Polynomen `a*x**4 + b*x**2 + c`, die in Wurzeln herauskommen; `evalf` gibt
die Zahl, und das Rechnen mit `RootOf` ist exakt (siehe algebraische Zahlen
weiter unten).

```
rcas> solve(x**3 - x - 1, x)
=> [RootOf(-1 - x + x**3, 0), RootOf(-1 - x + x**3, 1), RootOf(-1 - x + x**3, 2)]
rcas> solve(x**4 - 4*x**2 + 1, x)
=> [-(2 - 3**(1/2))**(1/2), (2 - 3**(1/2))**(1/2), -(2 + 3**(1/2))**(1/2), (2 + 3**(1/2))**(1/2)]
```

Gleichungsobjekte beherrschen seitenweises Rechnen, `subs`, `swap`,
`holds?`, `lhs`, `rhs` und `solve`.

```
rcas> eqn = eq(x + 1, 3)
=> x + 1 = 3
rcas> (eqn - 1).simplify
=> x = 2
rcas> eqn.solve
=> [2]
rcas> eqn.holds?(x: 2)
=> true
```

#### Ungleichungen

`<`, `<=`, `>`, `>=` zwischen einem Ausdruck (oder einem bloßen Symbol) und
einer Zahl oder einem Ausdruck bauen eine Ungleichung; `solve` gibt die
Lösungsmenge als Vereinigung von Intervallen zurück. Polynomiale und
rationale Ungleichungen laufen über eine Vorzeichentabelle an den reellen
Nullstellen, Beträge über das Zerschneiden der Geraden an den Nullstellen
ihrer Argumente; eine Liste von Ungleichungen wird geschnitten.

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

Steht ein Parameter in der Ungleichung, hängt die Antwort von ihm ab, und
`solve` gibt die Fälle zurück: die Parametergerade wird dort zerschnitten,
wo Nullstellen reell werden, zusammenfallen oder der Grad fällt, jedes Stück
wird exakt gelöst, und Stücke mit derselben Lösung werden verschmolzen.
`at(wert)` wählt den Fall für einen konkreten Parameter.

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

`abs` und `sign` sind Funktionen (`abs(-x)` vereinfacht sich zu `abs(x)`,
die Ableitung von `abs(x)` ist `sign(x)`). Der Vergleich zweier bloßer
Symbole behält Rubys Bedeutung; schreiben Sie `x.to_expr < y` oder setzen
Sie in diesem Fall einen Ausdruck nach links.

### 1.5 Bereiche und Annahmen

`NN ZZ QQ RR CC` sind die Zahlbereiche (NN enthält 0). Sie beantworten
`include?` (und `===`) für Zahlen und Ausdrücke, vergleichen sich als
Mengen und wissen, welche von ihnen Ringe und Körper sind. Die
Zugehörigkeit einer Zahl richtet sich bei exakten Typen nach dem Wert
(`4/2r` ist eine ganze Zahl) und bei Fließkommazahlen nach dem Typ
(Fließkommazahlen sind reell).

```
rcas> [NN.include?(3), NN.include?(-3), ZZ.include?(-3), QQ === 1/2r, RR.include?(2.0)]
=> [true, false, true, true, true]
rcas> NN < ZZ && ZZ < QQ && QQ < RR && RR < CC
=> true
rcas> [ZZ.ring?, ZZ.field?, QQ.field?]
=> [true, false, true]
```

`ℕ ℤ ℚ ℝ ℂ` sind dieselben Mengen unter ihren üblichen Zeichen; sie sind
Konstanten, `ℤ[x]` ist also `ZZ[x]`. Die Ausgabe bleibt ASCII, solange Sie
nichts anderes verlangen: `RCAS.unicode = true` (oder `/unicode on` in
`bin/rcas-chat`, oder `RCAS_UNICODE=1`) druckt `ℤ`, `π` und `∞` statt `ZZ`,
`pi` und `oo`. Der typografische Satz bleibt unberührt, denn LaTeX hat
eigene Namen dafür.

```
rcas> [ℤ == ZZ, ℚ[x] == QQ[x], ℝ.include?(2.0)]
=> [true, true, true]
rcas> RCAS.unicode = true
=> true
rcas> [ZZ[x], PI, OO]
=> [ℤ[x], π, ∞]
rcas> RCAS.unicode = false
=> false
```

Eine Variable wird mit `x.in(ZZ)` oder `assume(x: ZZ)` Element einer Menge.
Ausdrücke leiten daraus die kleinste Menge ab, die ihren Wert enthalten
muss. Auch ein Vorzeichen ist eine Annahme: `assume(x > 0)` (oder `>=`,
`<`, `<=`) erlaubt es der Vereinfachung, ein Quadrat gegen eine
Quadratwurzel zu kürzen und `abs` aufzulösen, was sie bei unbekanntem
Vorzeichen nicht darf, denn `sqrt(x**2)` ist `abs(x)`.

```
rcas> assume(x > 0)
=> true
rcas> sqrt(x**2).simplify
=> x
rcas> abs(x).simplify
=> x
rcas> assumptions
=> {:x=>x > 0}
rcas> forget
=> true
```

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

### 1.6 Polynomringe

`ZZ[x]`, `QQ[x, y]`, `RR[t]` sind Polynomringe. `R.(ausdruck)` wandelt einen
Ausdruck in ein Ringelement um, ein `RCAS::Polynomial`, gespeichert als
Abbildung von Exponenten auf Koeffizienten. Ringe sind zugleich Mengen.

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

Das Rechnen mischt sich frei mit Ausdrücken und Zahlen. Koeffizienten
werden bei Bedarf erweitert, neue Variablen vergrößern den Ring, und ein
nichtpolynomialer Partner fällt auf einen gewöhnlichen Ausdruck zurück.

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

Division, ggT und Faktorisierung:

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

`factor` gibt ein Faktorisierungsobjekt mit `unit`, `factors` (Paare aus
Polynom und Vielfachheit), `expand` und `to_expr` zurück. Die
Faktorisierung ist exakt über ZZ und QQ (quadratfreie Zerlegung,
Cantor-Zassenhaus, Hensel-Lifting, Rekombination; Kronecker-Substitution
bei mehreren Variablen). Der ggT über ZZ und QQ arbeitet in beliebig vielen
Variablen.

```
rcas> fact = R.(2*x**2 + 4*x + 2).factor
=> 2*(1 + x)**2
rcas> [fact.unit, fact.factors.size, fact.expand]
=> [2, 1, 2 + 4*x + 2*x**2]
rcas> ZZ[x, y].(x**2 * y - y).gcd(x * y**2 - y**2)
=> -y + x*y
```

#### ggT und Division von Ausdrücken

`gcd`, `lcm`, `quo`, `rem` und `divmod` arbeiten auf gewöhnlichen Ausdrücken
ebenso wie auf Ringelementen und ganzen Zahlen. Geteilt wird über QQ; bei
mehreren Unbestimmten nennen Sie die, nach der geteilt werden soll, die
übrigen werden zu Parametern.

```
rcas> [gcd(12, 18), gcd(2*x + 2, 4*x**2 - 4), lcm(x**2 - 1, x**2 + 2*x + 1)]
=> [6, 2 + 2*x, -1 - x + x**2 + x**3]
rcas> [quo(x**3 - 1, x - 1), rem(x**3 + 1, x - 1), divmod(x**2 + 1, 2*x)]
=> [1 + x + x**2, 2, [x/2, 1]]
rcas> divmod(a*x**2 + x - a, x - 1, x)
=> [1 + a + a*x, 1]
```

#### Gröbnerbasen

`groebner(polys, vars)` gibt die reduzierte Gröbnerbasis des Ideals zurück,
das die Polynome erzeugen, über `QQ[vars]` (oder `Frac(QQ[params])[vars]`,
wenn andere Symbole in den Koeffizienten vorkommen). Die voreingestellte
Monomordnung ist `:lex`, die Variablen in der angegebenen Reihenfolge
verglichen; `order: :grlex` und `:grevlex` sind die graduierten Ordnungen.
`reduce(f, basis, vars)` ist die Normalform von `f` modulo der Basis, genau
dann null, wenn `f` im Ideal liegt. Eine lexikographische Basis ist
dreiecksförmig, und so behandelt `solve` polynomiale Systeme (1.4).

```
rcas> g = groebner([x**2 + y**2 - 1, x - y], [x, y])
=> [x - y, -1/2 + y**2]
rcas> reduce(x**3, g, [x, y])
=> y/2
rcas> reduce(x**2 - y**2, g, [x, y])
=> 0
rcas> groebner([x + y + z, x*y + y*z + z*x, x*y*z - 1], [x, y, z])
=> [x + y + z, y**2 + y*z + z**2, -1 + z**3]
rcas> groebner([x**2 - y, y**2 - x], [x, y], order: :grevlex)
=> [-y + x**2, -x + y**2]
rcas> groebner([x**2 - a, x - y], [x, y])
=> [x - y, -a + y**2]
```

#### Grad und Koeffizienten

`degree`, `ldegree`, `lcoeff`, `tcoeff`, `coeff`, `coeffs` und `collect`
lesen die Polynomstruktur eines gewöhnlichen Ausdrucks, ohne erst einen Ring
zu bauen. Sie multiplizieren intern aus, die Eingabe muss also nicht
ausmultipliziert sein, und Koeffizienten kommen in kanonischer Form zurück.
Alle gibt es auch als Methoden auf Ausdrücken (`f.degree(x)`,
`f.coeff(x, 2)`).

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

Ohne Unbestimmte wird der ganze Ausdruck betrachtet: `degree` ist der
Gesamtgrad, `coeffs` listet die Koeffizienten der kanonischen Summe in der
gedruckten Reihenfolge, und `lcoeff`/`tcoeff` gehören zu ihrem letzten und
ihrem ersten Term. Das Nullpolynom hat den Grad -1, wie in `ZZ[x]`, und
keine Koeffizienten.

```
rcas> [degree(x**2*y + x*y**3), coeffs((x + y)**2), degree(x**2 + 1, y)]
=> [4, [1, 2, 1], 0]
rcas> [degree(0), coeffs(0, x), degree(pi*x**2 + sqrt(2), x)]
=> [-1, [], 2]
```

Ein Ausdruck, der in der Unbestimmten kein Polynom ist (`sin(x)`, `1/x`,
`x**n`, `sqrt(x)`), wirft einen `DomainError`, statt zu raten;
`degree(x*sin(y), x)` ist in Ordnung, weil `sin(y)` bezüglich `x` eine
Konstante ist. `coeff(f, x, k)` braucht ein ganzzahliges `k`; gebrochene
Exponenten sind keine Polynomterme.

`resultant(f, g, x)` und `discriminant(f, x)` werden aus der
Sylvester-Matrix berechnet; jedes andere Symbol ist ein Parameter.

```
rcas> resultant(x**2 - 1, x + 3, x)
=> 8
rcas> resultant(x**2 + y**2 - 1, x - y, x)
=> -1 + 2*y**2
rcas> discriminant(x**2 + b*x + c, x)
=> -4*c + b**2
rcas> discriminant(x**3 + a*x + b, x)
=> -27*b**2 - 4*a**3
```

#### Interpolation

`interpolate(punkte, x)` gibt das Polynom kleinsten Grades durch die Punkte
zurück, angegeben als Paare oder als Hash, nach Newtons dividierten
Differenzen. Das Rechnen ist exakt, Stützstellen und Werte dürfen also
rationale Zahlen, algebraische Zahlen oder Parameter sein.

```
rcas> interpolate([[0, 1], [1, 3], [2, 7]], x)
=> 1 + x + x**2
rcas> interpolate([[1, 1], [2, 4], [3, 9], [4, 16]], x)
=> x**2
rcas> interpolate({0 => a, 1 => b}, x)
=> a - a*x + b*x
```

#### Benannte Polynome

Die klassischen Familien haben einen eigenen Namensraum, `Poly`: es sind
viele, und die bloßen Namen werden anderswo gebraucht - `legendre` ist das
Legendre-Symbol, `bernoulli` die Bernoulli-Zahl, `fibonacci` die
Fibonacci-Zahl. Jede nimmt den Grad und danach die Unbestimmte, die
voreingestellt `x` ist; das Ergebnis ist ein gewöhnlicher ausmultiplizierter
Ausdruck.

| Familie | Aufruf |
|---|---|
| Tschebyschow, erster und zweiter Art | `Poly.chebyshev_t(n, x)`, `Poly.chebyshev_u(n, x)` |
| Legendre | `Poly.legendre(n, x)` |
| Hermite, physikalisch und probabilistisch | `Poly.hermite(n, x)`, `Poly.hermite_prob(n, x)` |
| Laguerre, verallgemeinert | `Poly.laguerre(n, x)`, `Poly.laguerre(n, x, alpha: 1)` |
| Gegenbauer (ultrasphärisch) | `Poly.gegenbauer(n, x, alpha: 2)` |
| Jacobi | `Poly.jacobi(n, x, alpha: 1, beta: 2)` |
| Bernoulli, Euler | `Poly.bernoulli(n, x)`, `Poly.euler(n, x)` |
| Kreisteilungspolynom | `Poly.cyclotomic(n, x)` |
| Swinnerton-Dyer | `Poly.swinnerton_dyer(n, x)` |
| Abel | `Poly.abel(n, x, a: 1)` |
| Fibonacci, Lucas | `Poly.fibonacci(n, x)`, `Poly.lucas(n, x)` |
| Bell (Touchard) | `Poly.bell(n, x)` |

```
rcas> Poly.chebyshev_t(5, x)
=> 5*x - 20*x**3 + 16*x**5
rcas> Poly.legendre(4, x)
=> 3/8 - 15*x**2/4 + 35*x**4/8
rcas> Poly.hermite(3, x)
=> -12*x + 8*x**3
rcas> Poly.laguerre(3, x)
=> 1 - 3*x + 3*x**2/2 - x**3/6
```

Jede Familie wird aus ihrer Dreitermrekursion mit exakten Koeffizienten
aufgebaut, und so kommen die Identitäten, die sie definieren, exakt zurück:
die Legendre-Polynome sind auf `[-1, 1]` orthogonal, die Nullstellen von
`P_n` sind die Stützstellen der Gauß-Quadratur, und die Ableitung von `T_n`
ist `n*U_(n-1)`.

```
rcas> integrate(Poly.legendre(2, x)*Poly.legendre(3, x), x: -1..1)
=> 0
rcas> integrate(Poly.legendre(3, x)**2, x: -1..1)
=> 2/7
rcas> solve(Poly.legendre(3, x), x)
=> [0, -15**(1/2)/5, 15**(1/2)/5]
rcas> nsolve(Poly.legendre(5, x), x: 0.9)
=> 0.9061798459386641
rcas> (diff(Poly.chebyshev_t(4, x), x) - 4*Poly.chebyshev_u(3, x)).simplify
=> 0
```

Das zweite Argument ist ein beliebiger Ausdruck, nicht nur eine
Unbestimmte, und eine Zahl ergibt eine Zahl: `T_n(cos(t))` ist das Polynom
im Kosinus, das gleich `cos(n*t)` ist.

```
rcas> Poly.chebyshev_t(3, cos(t))
=> -3*cos(t) + 4*cos(t)**3
rcas> Poly.hermite(3, 2)
=> 40
rcas> Poly.legendre(2, 1 + y)
=> 1 + 3*y + 3*y**2/2
```

Die Parameter der drei Familien, die welche haben, bleiben symbolisch,
solange kein Wert angegeben wird, so dass man das allgemeine Glied ansehen
kann; mit Werten spezialisieren sie sich, und Legendre, Tschebyschow und
Gegenbauer sind die Sonderfälle von Jacobi.

```
rcas> Poly.gegenbauer(2, x)
=> -alpha + 2*alpha*x**2 + 2*alpha**2*x**2
rcas> Poly.jacobi(1, x)
=> alpha/2 - beta/2 + x + alpha*x/2 + beta*x/2
rcas> Poly.laguerre(2, x, alpha: 1)
=> 3 - 3*x + x**2/2
rcas> (Poly.jacobi(2, x, alpha: 0, beta: 0) - Poly.legendre(2, x)).simplify
=> 0
rcas> (Poly.gegenbauer(3, x, alpha: 1) - Poly.chebyshev_u(3, x)).simplify
=> 0
```

Neben den orthogonalen Familien stehen die zählenden und die
zahlentheoretischen. `Poly.bernoulli(n, x)` ist das Polynom mit
`B_n(x + 1) - B_n(x) = n*x**(n - 1)`, woher Faulhabers Potenzsummen kommen;
bei `Poly.bell(n, x)` ist der Koeffizient von `x**k` die Anzahl der
Zerlegungen von `n` unterscheidbaren Objekten in `k` Blöcke, sein Wert an
der Stelle 1 also die Bell-Zahl.

```
rcas> Poly.bernoulli(4, x)
=> -1/30 + x**2 - 2*x**3 + x**4
rcas> (Poly.bernoulli(3, x + 1) - Poly.bernoulli(3, x)).simplify
=> 3*x**2
rcas> Poly.euler(3, x)
=> 1/4 - 3*x**2/2 + x**3
rcas> Poly.bell(4, x)
=> x + 7*x**2 + 6*x**3 + x**4
rcas> Poly.bell(6, 1)
=> 203
rcas> Poly.fibonacci(6, x)
=> 3*x + 4*x**3 + x**5
rcas> Poly.abel(3, x)
=> 9*x - 6*x**2 + x**3
```

Das Kreisteilungspolynom `Phi_n` ist das Minimalpolynom einer primitiven
`n`-ten Einheitswurzel: die `Phi_d` über die Teiler `d` von `n` ergeben
multipliziert `x**n - 1`, und genau so berechnet rcas sie; ihre
Koeffizienten sind klein, aber nicht immer 0 und ±1 - `Phi_105` ist das
erste mit einer -2. Das Swinnerton-Dyer-Polynom ist das Minimalpolynom von
`sqrt(2) + sqrt(3) + ...` über die ersten `n` Primzahlen: über den
rationalen Zahlen irreduzibel, vom Grad `2**n` und modulo jeder Primzahl
reduzibel, was es zum klassischen schweren Fall der Faktorisierung macht.

```
rcas> Poly.cyclotomic(12, x)
=> 1 - x**2 + x**4
rcas> Poly.cyclotomic(105, x).degree(x)
=> 48
rcas> coeff(Poly.cyclotomic(105, x), x, 7)
=> -2
rcas> Poly.swinnerton_dyer(2, x)
=> 1 - 10*x**2 + x**4
rcas> minpoly(sqrt(2) + sqrt(3))
=> 1 - 10*x**2 + x**4
rcas> factor(Poly.swinnerton_dyer(2, x), extension: sqrt(2))
=> (-1 + 2*2**(1/2)*x + x**2)*(-1 - 2*2**(1/2)*x + x**2)
rcas> Poly.swinnerton_dyer(3, x)
=> 576 - 960*x**2 + 352*x**4 - 40*x**6 + x**8
```

`doc("Poly.legendre")` (`/help Poly.legendre` im Chat) nennt die verwendete
Rekursion, die Gewichtsfunktion, für die die Familie orthogonal ist, und wo
man weiterliest; `doc(:Poly)` listet alle auf.

#### Algebraische Zahlen

Konstante Ausdrücke aus rationalen Zahlen, `i`, Wurzeln (`sqrt(2)`,
`cbrt(2)`, `root(5, 4)`) und `RootOf` werden als Elemente eines Zahlkörpers
`QQ(alpha)` erkannt, in dem exakt gerechnet wird. Das macht Nulltests auf
solchen Konstanten exakt, beseitigt Nenner allgemein, liefert
Minimalpolynome, exakte Eigenvektoren und die Faktorisierung über einer
Körpererweiterung.

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

Körper mit einem Erzeuger (jede Wurzel oder `RootOf`) und Körper, die von
zwei Quadratwurzeln erzeugt werden, werden unterstützt; andere
Kombinationen fallen auf numerische Nulltests zurück.

#### Endliche Körper

`GF(p)` und `GF(p**n)` sind Körper; `GF(9, :b)` benennt den Erzeuger.
Elemente sind gewöhnliche Werte, die als Reste gedruckt werden (oder als
Polynome im Erzeuger) und in Ausdrücke aufsteigen, sobald sie ein Symbol
treffen, sodass Polynomringe, Vektoren und Matrizen über ihnen wie überall
sonst funktionieren.

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

Erweiterungskörper benutzen das lexikographisch kleinste normierte
irreduzible Polynom des richtigen Grades (`modulus` listet seine
Koeffizienten vom konstanten Term aufwärts):

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

Die Faktorisierung über einem endlichen Körper ist quadratfreie Zerlegung in
Charakteristik `p`, gefolgt von Cantor-Zassenhaus; `GF(6)` und andere
Nicht-Primzahlpotenzen werden abgelehnt.

### 1.7 Lineare Algebra

`QQ**3` ist ein Vektorraum, `QQ**[2, 3]` ein Raum von 2x3-Matrizen (über ZZ
sind es freie Moduln mit derselben Schnittstelle). Das Indizieren eines
Raumes baut ein Element und prüft, ob jeder Eintrag zum Bereich gehört.

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

`vector(1, 2, 3)` (oder `vector([1, 2, 3])`) und `matrix([[1, 2], [3, 4]])`
bauen Elemente, deren Bereich aus den Einträgen erschlossen wird; geben Sie
ihn zuerst an, um zu wählen: `vector(QQ, 1, 2, 3)`.

```
rcas> vector([1, 2, 3]).space
=> ZZ**3
rcas> vector(QQ, 1, 2, 3).space
=> QQ**3
```

`v * w` ist das Skalarprodukt. Die Ergebnisräume folgen den Skalaren: einen
ganzzahligen Vektor durch 2 zu teilen, landet in `QQ**3`. Einträge außerhalb
des Bereichs werden abgelehnt, und ein nicht deklarierter symbolischer
Eintrag sagt Ihnen, was zu deklarieren ist.

```
rcas> (ZZ**3)[1, 2, 3].space
=> ZZ**3
rcas> ((ZZ**3)[1, 2, 3] / 2).space
=> QQ**3
```

Matrizen:

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

Eigenwerte sind die Nullstellen des charakteristischen Polynoms, exakt
immer dann, wenn `solve` es ist; `eigenvectors` listet
`[Eigenwert, Vielfachheit, Basis]`.

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

Symbolische Einträge sind erlaubt, sobald ihre Variablen deklariert sind.
Wenn jeder Eintrag ein Polynom oder eine rationale Funktion in einer
Unbestimmten mit rationalen Koeffizienten ist, arbeiten `det`, `inverse`,
`solve` und `kernel` über Auswertung und Interpolation: eine Gradschranke
für das Ergebnis, exakte Elimination an ebenso vielen rationalen Stellen,
Newton-Interpolation zurück (Horn, *Faktorisierung in Schief-Polynomringen*,
Kassel 2008, Kapitel 6). Eine 8x8-Matrix aus kubischen Polynomen braucht
einige Hundertstelsekunden, wo die Entwicklung nach Unterdeterminanten nicht
fertig würde. Alles andere fällt auf Laplace-Entwicklung und
Zeilenumformungen über Ausdrücken zurück, halten Sie diese also klein.

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
rcas> sm = RR.matrix([[x, 1], [1, x]])
=> [x 1]
   [1 x]
rcas> sm.det
=> -1 + x**2
rcas> sm.inverse
=> [ x/(-1 + x**2) -1/(-1 + x**2)]
   [-1/(-1 + x**2)  x/(-1 + x**2)]
rcas> sm.charpoly(l)
=> -1 + l**2 - 2*l*x + x**2
rcas> forget
=> true
```

#### Zerlegungen

Die benannten Zerlegungen einer quadratischen Matrix, alle exakt. `lu`
gibt `[l, u, p]` mit `p*a == l*u` (Zeilen werden nur getauscht, um einem
Pivot null auszuweichen, denn exaktes Rechnen muss um keine Rundung
herumsteuern), `qr` gibt `[q, r]` mit orthonormalen Spalten in `q`,
`cholesky` das `l` mit `a == l*l.transpose` für ein symmetrisches, positiv
definites `a`, `diagonalize` das Paar `[p, d]` und `jordan` das Paar
`[p, j]`, beide mit `a == p*d*p.inverse`.

```
rcas> am = matrix([[0, 1], [2, 3]])
=> [0 1]
   [2 3]
rcas> lmat, umat, pmat = lu(am); umat
=> [2 3]
   [0 1]
rcas> pmat*am == lmat*umat
=> true
rcas> qmat, rmat = qr(matrix([[1, 1], [1, 0]])); qmat
=> [2**(1/2)/2  2**(1/2)/2]
   [2**(1/2)/2 -2**(1/2)/2]
rcas> cholesky(matrix([[4, 12], [12, 37]]))
=> [2 0]
   [6 1]
rcas> jordan(matrix([[5, 4, 2, 1], [0, 1, -1, -1], [-1, -1, 3, 0], [1, 1, -1, 2]])).last
=> [1 0 0 0]
   [0 2 0 0]
   [0 0 4 1]
   [0 0 0 4]
```

`jordan` ist die Zerlegung, die es immer gibt: zu jedem Eigenwert werden
die Kerne von `(a - lambda)**k` aufgebaut und darin eine Basis aus Ketten
`v, (a - lambda)*v, ...` gewählt, ein Jordanblock je Kette. Die Matrix
oben hat die Eigenwerte 1, 2 und eine doppelte 4 mit nur einem
Eigenvektor, der Block zur 4 hat also die Größe zwei. `diagonalize` lehnt
eine solche Matrix ab und sagt, warum.

#### Orthogonalität und kleinste Quadrate

`gram_schmidt` macht aus einer Basis eine orthogonale, mit
`normalize: true` eine orthonormale, indem es von jedem Vektor seine
Projektion auf die vorherigen abzieht. `project(v, onto: u)` ist diese
Projektion, für einen Vektor oder für eine Liste, die einen Unterraum
aufspannt. `least_squares(A, b)` löst die Normalengleichungen, die beste
Näherung, wenn `A*x = b` keine Lösung hat; es ist die Matrixform von
`linreg` (Abschnitt 1.10).

```
rcas> gram_schmidt([vector(1, 1, 0), vector(1, 0, 1)])
=> [(1, 1, 0), (1/2, -1/2, 1)]
rcas> gram_schmidt([vector(1, 1, 0), vector(1, 0, 1)], normalize: true)
=> [(2**(1/2)/2, 2**(1/2)/2, 0), (2**(1/2)*3**(1/2)/6, -(2**(1/2)*3**(1/2))/6, 2**(1/2)*3**(1/2)/3)]
rcas> project(vector(1, 2), onto: vector(1, 0))
=> (1, 0)
rcas> least_squares(matrix([[1, 1], [1, 2], [1, 3]]), vector(1, 2, 4))
=> (-2/3, 3/2)
```

### 1.8 Differentialgleichungen und Rekursionen

`D(y, x, n)` ist die n-te Ableitung einer unbekannten Funktion `y`.
`dsolve` behandelt trennbare und lineare Gleichungen erster Ordnung sowie
lineare Gleichungen beliebiger Ordnung mit konstanten Koeffizienten und
gibt Gleichungen `y = ...` mit den Konstanten `C1`, `C2`, ... zurück.

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
rcas> dsolve(D(y, x, 4) - 2*D(y, x, 2) + y, y, x)
=> [y = exp(-x)*(C1 + C2*x) + exp(x)*(C3 + C4*x)]
```

Eine Störfunktion, die eine Summe aus Polynomen mal Exponentialfunktionen
mal Sinus oder Kosinus ist, wird mit dem Ansatz der unbestimmten
Koeffizienten behandelt, Resonanz eingeschlossen; eine Gleichung zweiter
Ordnung mit einer anderen Störfunktion läuft über Variation der Konstanten,
und ein Integral, das rcas nicht kann, bleibt als `integral(...)` in der
Antwort stehen.

```
rcas> dsolve(eq(D(y, x, 2) + y, x*exp(x)), y, x)
=> [y = exp(x)*(-1/2 + x/2) + C1*cos(x) + C2*sin(x)]
rcas> dsolve(eq(D(y, x, 2) + 4*y, cos(2*x)), y, x)
=> [y = C1*cos(2*x) + C2*sin(2*x) + x*sin(2*x)/4]
rcas> dsolve(eq(D(y, x, 2) - 2*D(y, x) + y, exp(x)/x), y, x)
=> [y = -(x*exp(x)) + exp(x)*(C1 + C2*x) + x*exp(x)*log(x)]
rcas> dsolve(eq(D(y, x, 2) + y, 1/cos(x)), y, x)
=> [y = C1*cos(x) + C2*sin(x) + cos(x)*log(cos(x)) + x*sin(x)]
```

#### Rekursionen

`rsolve(gleichung, u, n)` löst lineare Rekursionen mit konstanten
Koeffizienten. Die unbekannte Folge wird als Funktion des Index
geschrieben, `u(n + 1)`: in `bin/rcas` ist ein undefinierter Name, der auf
einen Ausdruck angewandt wird, genau das. Die charakteristischen Wurzeln
geben den homogenen Teil (eine mehrfache Wurzel bringt Faktoren `n`,
`n**2`, ...), Störfunktionen der Form Polynom mal `b**n` laufen über
unbestimmte Koeffizienten, und `init:` legt die Konstanten anhand der
Anfangswerte fest.

```
rcas> rsolve(eq(u(n + 2), u(n + 1) + u(n)), u, n)
=> u(n) = C2*(1/2 + 5**(1/2)/2)**n + C1*(1/2 - 5**(1/2)/2)**n
rcas> rsolve(eq(u(n + 2), u(n + 1) + u(n)), u, n, init: {0 => 0, 1 => 1})
=> u(n) = 5**(1/2)*(1/2 + 5**(1/2)/2)**n/5 - 5**(1/2)*(1/2 - 5**(1/2)/2)**n/5
rcas> rsolve(eq(u(n + 1), 2*u(n) + 1), u, n, init: {0 => 0})
=> u(n) = -1 + 2**n
rcas> rsolve(eq(u(n + 2), 4*u(n + 1) - 4*u(n)), u, n, init: {0 => 1, 1 => 4})
=> u(n) = 2**n*(1 + n)
rcas> rsolve(eq(u(n + 1), u(n) + n), u, n, init: {0 => 0})
=> u(n) = -n/2 + n**2/2
rcas> rsolve(eq(u(n + 1), 3*u(n) + 2**n), u, n)
=> u(n) = -2**n + 3**n*C1
```

**Polynomiale Koeffizienten.** Hängt ein Koeffizient von `n` ab, hat das
charakteristische Polynom nichts mehr zu sagen und Petkovšeks Algorithmus
übernimmt. Er findet die *hypergeometrischen* Lösungen, also die, deren
Verhältnis `u(n + 1)/u(n)` eine rationale Funktion ist - genau das, was
eine Fakultät ist:

```
rcas> rsolve(eq(u(n + 1), n*u(n)), u, n)
=> u(n) = C1*(-1 + n)!
rcas> rsolve(eq(u(n + 1), 2*(n + 1)*u(n)), u, n, init: {0 => 1})
=> u(n) = 2**n*n!
rcas> rsolve(eq((n + 2)*u(n + 1), u(n)), u, n)
=> u(n) = C1/(1 + n)!
```

Eine Rekursion der Ordnung `r` hat einen `r`-dimensionalen Lösungsraum, und
erst ebenso viele hypergeometrische Lösungen spannen ihn auf. `hyper`
listet auf, was es gibt, und `rsolve` gibt einen Teil des Lösungsraums
nicht als das Ganze aus:

```
rcas> hyper(eq((n + 2)*u(n + 2), (2*n + 3)*u(n + 1) - (n + 1)*u(n)), u, n)
=> [1]
rcas> hyper(eq(u(n + 2), u(n + 1) + (n + 1)*u(n)), u, n)
=> []
```

Die erste hat die konstante Lösung und eine zweite, die nicht
hypergeometrisch ist, weshalb `rsolve` eine von zwei meldet; die zweite hat
gar keine.

#### Systeme

`dsolve` nimmt eine Liste von Gleichungen und eine Liste unbekannter
Funktionen. Ein lineares System mit konstanten Koeffizienten wird über die
Eigenwerte seiner Matrix gelöst: reelle geben Exponentialfunktionen, ein
konjugiertes Paar eine gedämpfte Drehung, und ein mehrfacher Eigenwert mit
zu wenigen Eigenvektoren die `t*exp(lambda*t)`-Terme einer Jordan-Kette.
Eine konstante Störfunktion fügt den stationären Zustand hinzu.

```
rcas> dsolve([eq(D(x, t), y), eq(D(y, t), -x)], [x, y], t)
=> [x = C1*sin(t) + C2*cos(t), y = C1*cos(t) - C2*sin(t)]
rcas> dsolve([eq(D(x, t), x + 2*y), eq(D(y, t), 3*x + 2*y)], [x, y], t)
=> [x = 2*C1*exp(4*t)/3 - C2*exp(-t), y = C1*exp(4*t) + C2*exp(-t)]
rcas> dsolve([eq(D(x, t), x), eq(D(y, t), x + y)], [x, y], t)
=> [x = C2*exp(t), y = C1*exp(t) + C2*t*exp(t)]
```

#### Die Laplace-Transformation

Die Transformation macht aus dem Ableiten eine Multiplikation mit `s`, und
deshalb löst sie lineare Gleichungen durch Algebra. rcas berechnet sie aus
der Tabelle mit zwei Regeln, dem ersten Verschiebungssatz und der
Multiplikation mit `t`, und invertiert eine rationale Transformierte über
die Partialbruchzerlegung.

```
rcas> laplace(exp(3*t), t, s)
=> 1/(-3 + s)
rcas> laplace(t*sin(t), t, s)
=> 2*s/(1 + s**2)**2
rcas> laplace(exp(-t)*sin(2*t), t, s)
=> 2/(4 + (1 + s)**2)
rcas> inverse_laplace(1/(s**2 + 2*s + 5), s, t)
=> exp(-t)*sin(2*t)/2
rcas> inverse_laplace(1/((s - 1)*(s - 2)), s, t)
=> exp(2*t) - exp(t)
```

### 1.9 Geometrie

Ebene Geometrie mit exakten Koordinaten. `point(x, y)`, `line(p, q)` (oder
`line(p, slope: m)`) und `circle(mittelpunkt, r)` sind die Figuren; eine
Gerade wird als `a*x + b*y + c = 0` gehalten, senkrechte Geraden brauchen
also keinen Sonderfall. Die Fragen sind `distance` (zwischen Punkten, von
einem Punkt zu einer Geraden, zwischen parallelen Geraden), `midpoint`,
`angle`, `area`, `perimeter`, `collinear?`, `centroid`, `intersect`,
`circumcircle`, `perpendicular_bisector`, `parallel_through` und
`perpendicular_through`.

```
rcas> p1 = point(0, 0)
=> (0, 0)
rcas> p2 = point(4, 0)
=> (4, 0)
rcas> p3 = point(0, 3)
=> (0, 3)
rcas> [distance(p1, p2), distance(p2, p3), area(p1, p2, p3)]
=> [4, 5, 6]
rcas> angle(p2, p1, p3)
=> pi/2
rcas> angle(p1, p2, p3)
=> acos(4/5)
rcas> line(p2, p3)
=> -12 + 3*x + 4*y = 0
rcas> distance(p1, line(p2, p3))
=> 12/5
rcas> circumcircle(p1, p2, p3)
=> circle((2, 3/2), 5/2)
rcas> intersect(line(p1, p3), circle(p1, 2))
=> [(0, 2), (0, -2)]
rcas> perpendicular_bisector(p1, p2)
=> -2 + x = 0
rcas> circle(point(1, 2), 3).equation
=> (-1 + x)**2 + (-2 + y)**2 = 9
```

Nichts wird gerundet: ein Abstand ist eine Quadratwurzel, ein rechter Winkel
ist genau `pi/2`, und ein Winkel, der kein vertrauter ist, bleibt
`acos(...)`, bis man `evalf` nach einer Zahl fragt. Koordinaten dürfen
symbolisch sein.

```
rcas> midpoint(point(0, 0), point(px, py))
=> (px/2, py/2)
rcas> distance(point(0, 0), point(px, py))
=> (px**2 + py**2)**(1/2)
rcas> collinear?(point(0, 0), point(1, 1), point(2, 2))
=> true
```

Nicht umgesetzt: drei Dimensionen, andere Kegelschnitte als Kreise und
Abbildungen (Drehungen, Spiegelungen) als Objekte.

### 1.10 Statistik

#### Beschreibende Statistik

Die Funktionen nehmen eine Liste von Werten und liefern exakte Ergebnisse;
symbolische Werte sind überall dort erlaubt, wo keine Ordnung gebraucht
wird. `variance`, `stdev` und `covariance` teilen durch `n - 1`, sofern
nicht `sample: false` gesetzt ist, `skewness` und `kurtosis` sind die
standardisierten zentralen Momente (3 bei einer normalverteilten
Stichprobe), und `quantile` interpoliert zwischen den Ordnungsstatistiken
so, wie R und Excel es voreingestellt tun.

```
rcas> data = [2, 4, 4, 4, 5, 5, 7, 9]
=> [2, 4, 4, 4, 5, 5, 7, 9]
rcas> [mean(data), median(data), mode(data), variance(data), stdev(data, sample: false)]
=> [5, 9/2, 4, 32/7, 2]
rcas> [quantile(data, 1/4r), quartiles([1, 2, 3, 4, 5, 6, 7, 8]), iqr([1, 2, 3, 4, 5, 6, 7, 8])]
=> [4, [11/4, 9/2, 25/4], 7/2]
rcas> [skewness([1, 2, 3, 10]), kurtosis([1, 2, 3, 4]), moment([1, 2, 3, 4], 2, central: false)]
=> [18*2**(1/2)/25, 41/25, 15/2]
rcas> [geometric_mean([2, 8]), harmonic_mean([1, 2, 4]), frequencies([3, 1, 3, 2, 3])]
=> [4, 12/7, {1=>1, 2=>1, 3=>3}]
rcas> [mean([d1, d2, d3]), variance([d1, d2])]
=> [d1/3 + d2/3 + d3/3, d1**2/2 - d1*d2 + d2**2/2]
```

#### Regression

`covariance` und `correlation` nehmen zwei Listen; `linreg(xs, ys, x)` ist
die Ausgleichsgerade nach kleinsten Quadraten als Ausdruck in `x`.

Abschnitt 1.11 zeichnet das: `histogram`, `boxplot`, `barchart` und
`scatter(xs, ys, fit: true)` mit der Ausgleichsgeraden.

```
rcas> [covariance([1, 2, 3], [2, 4, 7]), correlation([1, 2, 3], [2, 4, 6])]
=> [5/2, 1]
rcas> linreg([1, 2, 3], [2, 4, 7], x)
=> -2/3 + 5*x/2
```

#### Verteilungen

`Normal(mu, sigma)`, `Uniform(a, b)`, `Exponential(rate)`, `Bernoulli(p)`,
`Binomial(n, p)`, `Poisson(rate)`, `Geometric(p)` (Fehlversuche vor dem
ersten Erfolg, `k = 0, 1, ...`), `DiscreteUniform(a, b)` und die drei
Prüfverteilungen `StudentT(nu)`, `ChiSquare(k)`, `FRatio(d1, d2)` sind
Verteilungsobjekte, symbolische Parameter erlaubt. Sie beantworten `pdf`
(Dichte oder Wahrscheinlichkeit), `cdf`, `quantile`, `mean`, `variance`,
`stdev`, `median`, `skewness`, `kurtosis`, `probability` eines Bereichs
oder einer Ungleichung, `expectation(f, x)` einer Funktion (ein Integral
oder eine Summe über den Träger, formal, wenn rcas es nicht kann),
`moment(k)` und `sample(n)`. Die Verteilungsfunktion der Normalverteilung
wird mit der Fehlerfunktion `erf` geschrieben; ihr Quantil ist numerisch,
außer bei `1/2`.

```
rcas> X = Normal(0, 1)
=> Normal(0, 1)
rcas> [X.pdf(x), X.cdf(x)]
=> [2**(1/2)*exp(-x**2/2)/(2*pi**(1/2)), 1/2 + erf(2**(1/2)*x/2)/2]
rcas> [X.probability(x > 1), X.probability(-1..1).evalf, X.quantile(0.975)]
=> [1/2 - erf(2**(1/2)/2)/2, 0.6826894921370861, 1.9599639845400536]
rcas> Normal(mu, sigma).pdf(x)
=> 2**(1/2)*exp(-(-mu + x)**2/(2*sigma**2))/(2*pi**(1/2)*sigma)
rcas> B = Binomial(10, 1/2r)
=> Binomial(10, 1/2)
rcas> [B.pdf(3), B.cdf(3), B.probability(x >= 8), B.mean, B.variance]
=> [15/128, 11/64, 7/128, 5, 5/2]
rcas> [Binomial(cnt, prob).pdf(k), Poisson(rate).pdf(k), Geometric(1/2r).cdf(k)]
=> [prob**k*binomial(cnt, k)*(1 - prob)**(cnt - k), rate**k*exp(-rate)/k!, 1 - (1/2)**k/2]
rcas> D = DiscreteUniform(1, 6)
=> DiscreteUniform(1, 6)
rcas> [D.mean, D.variance, D.probability(x >= 5), D.sample(5, random: Random.new(1))]
=> [7/2, 35/12, 1/3, [3, 5, 1, 2, 1]]
rcas> [Uniform(0, 1).expectation(x**2, x), Exponential(2).quantile(1/2r), Exponential(rate).cdf(x)]
=> [1/3, log(2)/2, 1 - exp(-(rate*x))]
rcas> [Normal(0, 1).expectation(x**2, x), Normal(mu, sigma).moment(2), Exponential(rate).moment(2)]
=> [1, mu**2 + sigma**2, 2/rate**2]
```

Die Dichten sind exakt; die Verteilungsfunktionen von `StudentT`,
`ChiSquare` und `FRatio` sind exakt, wo es eine geschlossene Form gibt
(`nu = 1, 2` bei `StudentT`, gerades `k` bei `ChiSquare`), und sonst
numerisch, aus der regularisierten unvollständigen Gamma- und Betafunktion.
Quantile jenseits der Fälle mit Formel sind numerisch.

```
rcas> [StudentT(1).cdf(1), ChiSquare(2).cdf(x), StudentT(10).quantile(0.975)]
=> [3/4, 1 - exp(-x/2), 2.228138851986274]
rcas> [ChiSquare(3).quantile(0.95), FRatio(3, 10).quantile(0.95), Normal(0, 1).quantile(0.975)]
=> [7.814727903251181, 3.708264819046842, 1.9599639845400536]
rcas> ChiSquare(k).pdf(x)
=> 2**(-k/2)*x**(-1 + k/2)*exp(-x/2)/gamma(k/2)
rcas> StudentT(nu).pdf(t)
=> gamma(1/2 + nu/2)*(1 + t**2/nu)**(-1/2 - nu/2)/(gamma(nu/2)*(pi*nu)**(1/2))
```

`erf` und `erfc` sind gewöhnliche Funktionen: exakt bei 0 und im
Unendlichen, numerisch auf Fließkommazahlen, mit der Ableitung
`2*exp(-x**2)/sqrt(pi)`, einer Taylorreihe, und `integrate` kennt
`exp(a*x**2 + b*x + c)` für `a < 0` (Abschnitt 1.3).

#### Hypothesentests

Jeder Test gibt ein Ergebnisobjekt zurück, das sich in einer Zeile druckt
und `statistic`, `pvalue`, `parameters`, `distribution` und
`reject?(alpha)` (0,05 als Voreinstellung) beantwortet. `alternative:` ist
`:two_sided` (die Voreinstellung), `:less` oder `:greater`. Die
Prüfgrößen bleiben exakt, solange die Daten exakt sind; die p-Werte kommen
aus den Verteilungsfunktionen von t, Chi-Quadrat, F und der
Normalverteilung und sind numerisch, außer beim Binomialtest, der exakt ist.

`ttest(data, mu: 0)` ist der Einstichproben-t-Test, `ttest(xs, ys)` der
Zweistichproben-Test nach Welch (`equal_variance: true` für den gepoolten,
`paired: true` für den verbundenen) und `ztest(data, sigma:, mu: 0)` der
Test mit bekannter Standardabweichung.

```
rcas> ttest([5.1, 4.9, 5.6, 5.2, 5.0], mu: 5)
=> one-sample t test: t = 1.32417, df = 4, p = 0.256044 (two-sided)
rcas> ttest([1, 2, 3, 4, 5], mu: 1, alternative: :greater)
=> one-sample t test: t = 2.82843, df = 4, p = 0.0237103 (greater)
rcas> ttest([12, 15, 14, 16, 13], [10, 11, 9, 12, 10])
=> Welch t test: t = 4.12948, df = 7.27456, p = 0.0040545 (two-sided)
rcas> ttest([12, 15, 14, 16, 13], [10, 11, 9, 12, 10], paired: true).reject?(0.01)
=> true
rcas> ztest([101, 99, 104, 98, 103], sigma: 2, mu: 100)
=> z test: z = 1.11803, n = 5, p = 0.263552 (two-sided)
```

`chisquare_test(counts)` ist der Anpassungstest gegen `expected:`
(Anzahlen oder Wahrscheinlichkeiten, gleichverteilt als Voreinstellung;
`df:` senkt die Freiheitsgrade für geschätzte Parameter), und
`chisquare_test(rows)` auf einer Tafel von Zeilen ist der
Unabhängigkeitstest, ohne Stetigkeitskorrektur. `ftest(xs, ys)` vergleicht
zwei Varianzen, und `binomial_test(k, n, p:)` ist der exakte Test: sein
p-Wert ist die Summe der Wahrscheinlichkeiten aller Ausgänge, die nicht
wahrscheinlicher sind als der beobachtete, und bleibt rational.

```
rcas> chisquare_test([18, 22, 20, 25, 15])
=> chi-square goodness of fit: X^2 = 29/10, df = 4, p = 0.574697 (greater)
rcas> chisquare_test([[30, 20], [15, 35]])
=> chi-square test of independence: X^2 = 100/11, df = 1, p = 0.00256883 (greater)
rcas> ftest([12, 15, 14, 16, 13], [10, 11, 9, 12, 10])
=> F test of two variances: F = 25/13, df1 = 4, df2 = 4, p = 0.542062 (two-sided)
rcas> binomial_test(9, 10)
=> exact binomial test: k = 9, n = 10, p = 11/512 (two-sided)
```

#### Konfidenzintervalle

`confidence_interval(data, level: 0.95)` ist das t-Intervall für den
Mittelwert, das Normalintervall, wenn `sigma:` angegeben ist, und das
Chi-Quadrat-Intervall für die Streuung mit `parameter: :variance` oder
`:stdev`. `proportion_interval(k, n)` ist Wilsons Score-Intervall. Alle
geben ein `Interval` zurück (Abschnitt 1.4), `include?` funktioniert also.

```
rcas> confidence_interval([5.1, 4.9, 5.6, 5.2, 5.0])
=> [4.8245208615073345, 5.495479138492666]
rcas> confidence_interval([5.1, 4.9, 5.6, 5.2, 5.0], sigma: 0.3)
=> [4.897043237827026, 5.422956762172975]
rcas> confidence_interval([5.1, 4.9, 5.6, 5.2, 5.0], parameter: :stdev)
=> [0.1618768601247171, 0.7763919787687242]
rcas> proportion_interval(41, 100)
=> [0.3186731302113651, 0.5079856994658921]
```

Nicht umgesetzt: Varianzanalyse, nichtparametrische Tests (Wilcoxon,
Kolmogorow-Smirnow), multiple Regression und Zeitreihen.

### 1.11 Grafik

`plot(f)` tastet eine Funktion ab und zeichnet sie mit Unicode-Braillepunkten,
wofür es nichts als ein Terminal braucht; das Ergebnis ist das, was
`inspect` zeigt, ein Bild erscheint also, sobald Sie es tippen. Der Bereich
ist `-10..10`, solange Sie keinen angeben. Werte, die komplex, unendlich
oder undefiniert sind, lassen eine Lücke, und ein Sprung über eine Polstelle
unterbricht die Linie, statt einen senkrechten Strich zu ziehen. Die Achsen
sind gepunktete Hilfslinien, gezeichnet, wenn der Ursprung im Bild liegt.

```
rcas> plot(sin(x), x: 0..2*PI, width: 30, height: 6)
=>  1.1 ┤⠀⠀⠀⠀⣀⡤⠖⠒⠒⠤⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        │⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⠈⠙⢦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        │⣠⠞⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢆⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        │⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠱⣅⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⢀⡵⠋
        │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠳⣄⡀⠀⠀⠀⠀⠀⢀⡴⠋⠀⠀
   -1.1 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠒⠤⠤⠴⠚⠉⠀⠀⠀⠀
        └──────────────────────────────
         0                        6.283
rcas> plot(1/x, x: -3..3, width: 30, height: 6)
=>   9.12 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢽⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠝⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠙⠢⠤⣀⣀⣀⣀⣀⣀⣀⠀⠀⠀⠀
          │⠓⠒⠓⠒⠓⠒⠓⠒⠓⠒⠧⠤⣅⡀⠁⠅⠁⠀⠁⠀⠁⠀⠁⠀⠁⠈⠉⠉⠉⠉
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠱⡀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
   -8.194 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          └──────────────────────────────
           -3                           3
```

`plot([f, g], x: a..b)` zeichnet mehrere Funktionen und nennt sie darunter,
`plot(verteilung)` zeichnet eine Dichte (eine diskrete als Stängel über
ihrem Träger), und `scatter(xs, ys)` zeichnet Datenpunkte.

```
rcas> plot([x**2, x**3], x: -1..1, width: 30, height: 6)
=>  1.1 ┤⠲⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⡶
        │⠀⠀⠙⠲⢤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣶⠟⠁⠀
        │⠀⠀⠀⠀⠀⠈⠉⠓⠲⠤⢄⣀⣀⣀⣀⣅⣀⣀⣀⣠⣤⣶⠾⠝⠛⠉⠀⠀⠀⠀
        │⠁⠀⠁⠀⣁⡤⠕⠒⠋⠉⠉⠉⠉⠉⠉⠅⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀
        │⠀⢀⡴⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
   -1.1 ┤⠞⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        └──────────────────────────────
         -1                           1
     x**2, x**3
rcas> plot(Binomial(6, 1/2r), width: 30, height: 6)
=> Binomial(6, 1/2)
   0.3273 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⠀⠀⡇⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⡇⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⡇⠀⠀⠀⢸⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⡇⠀⠀⠀⠀⡇⠀⠀⠀⢸⠀⠀⠀⠀⢸⠀⠀⠀⠀⠀
        0 ┤⡄⠀⠀⠀⠀⡇⠀⠀⠀⠀⡇⠀⠀⠀⠀⡇⠀⠀⠀⢸⠀⠀⠀⠀⢸⠀⠀⠀⠀⢠
          └──────────────────────────────
           0                            6
rcas> scatter([1, 2, 3, 4], [2, 4, 7, 8], width: 30, height: 6)
=> 8.3 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠂⠀
       │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
       │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
       │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
       │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
   1.7 ┤⠀⠠⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
       └──────────────────────────────
        0.85                      4.15
```

#### Parameter- und Polarkurven

`parametric([x(t), y(t)], t: a..b)` zeichnet eine Kurve, die kein
Funktionsgraph sein muss: die Punkte werden in der Reihenfolge verbunden,
in der der Parameter sie durchläuft, die Kurve darf sich also schließen
und selbst schneiden. `polar(r, t: a..b)` tut dasselbe für `r` als
Funktion des Winkels, gezeichnet als `(r*cos(t), r*sin(t))`; der Winkel
läuft über eine volle Umdrehung, wenn kein anderer Bereich angegeben ist.

```
rcas> parametric([cos(t), sin(t)], t: 0..2*pi, width: 40, height: 12, title: "the unit circle")
=> the unit circle
    1.1 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣠⠤⠤⠤⠥⠤⠤⣄⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        │⠀⠀⠀⠀⠀⠀⠀⠀⣀⠤⠖⠚⠉⠉⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠉⠉⠓⠲⠤⣀⠀⠀⠀⠀⠀⠀⠀⠀
        │⠀⠀⠀⠀⠀⣠⠔⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠢⣄⠀⠀⠀⠀⠀
        │⠀⠀⠀⣠⠞⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠳⣄⠀⠀⠀
        │⠀⠀⣰⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣆⠀⠀
        │⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⠀
        │⠁⠀⡇⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠅⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⢸⠁⠀
        │⠀⠀⠹⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⠏⠀⠀
        │⠀⠀⠀⠙⢦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠋⠀⠀⠀
        │⠀⠀⠀⠀⠀⠙⠢⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠔⠋⠀⠀⠀⠀⠀
        │⠀⠀⠀⠀⠀⠀⠀⠀⠉⠒⠦⢤⣀⣀⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠀⣀⣀⡤⠴⠒⠉⠀⠀⠀⠀⠀⠀⠀⠀
   -1.1 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠙⠒⠒⠒⠗⠒⠒⠋⠉⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
        └────────────────────────────────────────
         -1.1                                 1.1
rcas> polar(1 + cos(t), width: 40, height: 12, title: "r = 1 + cos(t)")
=> r = 1 + cos(t)
    1.429 ┤⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⣀⣀⣀⡤⠤⠤⠤⠤⠤⠤⢄⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⢀⣥⠴⠒⠊⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠒⠒⠤⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⡠⠞⠉⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠒⢤⡀⠀⠀⠀⠀⠀
          │⠀⠀⡞⠁⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠢⡀⠀⠀⠀
          │⠀⠀⡇⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣆⠀⠀
          │⠀⠀⠘⠦⣄⣀⡅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⠀
          │⠁⠀⢡⠖⠋⠉⠅⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⠀⠁⢸⠁⠀
          │⠀⠀⡇⠀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⠏⠀⠀
          │⠀⠀⢧⡀⠀⠀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠔⠁⠀⠀⠀
          │⠀⠀⠀⠑⢦⣀⠅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⠤⠚⠁⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠈⠝⠲⠤⢄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⠤⠤⠒⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀
   -1.429 ┤⠀⠀⠀⠀⠀⠀⠅⠀⠀⠀⠀⠉⠉⠉⠓⠒⠒⠒⠒⠒⠒⠊⠉⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          └────────────────────────────────────────
           -0.3625                            2.112
```

#### Statistische Grafiken

`histogram(data, bins: 4)` zählt die Werte in gleich breiten Klassen (die
Anzahl folgt der Sturges-Regel, solange Sie keine angeben; `density: true`
zeigt Anteile statt Anzahlen), und `boxplot` zeichnet den Median, die
Quartile und Antennen bis zum letzten Wert innerhalb des 1,5-fachen
Quartilsabstands, alles darüber hinaus als Ausreißer. Mehrere benannte
Reihen werden übereinander gezeichnet.

```
rcas> histogram([2, 4, 4, 5, 5, 5, 6, 6, 7, 9, 3, 5], bins: 4, width: 40, height: 7)
=> 7 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢀⣀⣀⣀⣀⣀⣀⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⡇⣀⣀⣀⣀⣀⣀⣀⣀⣀⡀
   0 ┤⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⢸⣿⣿⣿⣿⣿⣿⣿⣿⡇⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇
     └────────────────────────────────────────
      2                                      9
rcas> boxplot("before" => [2, 4, 5, 5, 6, 7, 20], "after" => [3, 5, 6, 6, 7, 8], title: "reaction times", width: 40)
=> reaction times
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⡀⠀⠀⠀⠀⣀⣀⣀⣀⡀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
   before ┤⠀⠀⣇⣀⣀⣀⣀⡇⡇⠀⠀⣇⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀
          │⠀⠀⡇⠀⠀⠀⠀⣇⣇⣀⣀⡇⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⡇⠀⠀⠀⢸⠉⡏⢹⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    after ┤⠀⠀⠀⠀⡏⠉⠉⠉⢹⠀⡇⢸⠉⠉⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠁⠀⠀⠀⠈⠉⠉⠉⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
          └────────────────────────────────────────
           1.1                                 20.9
```

`barchart` nimmt die Kategorien und ihre Anzahlen, passt also zu
`frequencies` (Abschnitt 1.10), und `scatter(xs, ys, fit: true)` fügt die
Ausgleichsgerade hinzu, deren Gleichung exakt bleibt, solange die Daten es
sind.

```
rcas> barchart(frequencies([:a, :b, :a, :c, :a, :b]), width: 40, height: 6)
=> 4 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⠀⠀⠀⢠⣤⣤⣤⣤⣤⣤⣤⣤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
     │⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⣶⣶⣶⣶⣶⣶⣶⣶⡆⠀⠀⠀
   0 ┤⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀
     └────────────────────────────────────────
             a            b           c
rcas> scatter([1, 2, 3, 4], [2, 4, 7, 8], fit: true, width: 40, height: 7)
=> 9.062 ┤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡠⠤⠒
         │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⢀⣀⡠⠤⠒⠊⠉⠀⠈⠀⠀
         │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠤⠔⠒⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
         │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⠤⠔⠒⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
         │⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡠⠤⠖⠊⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
         │⠀⠀⠀⠀⢀⣀⠤⠔⠒⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
   1.438 ┤⠤⠒⠊⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
         └────────────────────────────────────────
          0.85                                4.15
     21*x/10
```

`width:`, `height:`, `y:`, `title:` und `labels:` formen das Bild.
`to_svg` und `save("f.svg")` schreiben eine Vektorgrafik und brauchen
nichts weiter; `to_png("f.png")` und `show` (ein Bild direkt im iTerm2)
rastern sie mit demselben Chrome im Kopflosmodus, den auch der
typografische Satz benutzt; in `bin/rcas-chat` lässt `/plotstyle image`
jedes Bild als Grafik erscheinen (Anhang B). Abgetastet wird gleichmäßig
mit 400 Punkten, ein Merkmal schmaler als eine Pixelspalte kann also
verloren gehen; der y-Bereich wird auf die mittleren 96 Prozent der
abgetasteten Werte beschnitten, wenn eine Polstelle das Bild sonst
plattdrücken würde.

### 1.12 Die q-Analoga

Ersetzt man die ganze Zahl `n` durch `[n]_q = 1 + q + ... + q**(n - 1)`,
bekommt jede Formel dieses Kapitels einen Zwilling. Geht `q` gegen 1, wird
aus dem Zwilling wieder das Original, und unterwegs sagt er mehr: der
Gaußsche Binomialkoeffizient zählt Unterräume eines Vektorraums über einem
Körper mit `q` Elementen, wo der gewöhnliche Teilmengen zählt.

```
rcas> qbracket(5, q)
=> 1 + q + q**2 + q**3 + q**4
rcas> qbinomial(4, 2, q)
=> 1 + q + 2*q**2 + q**3 + q**4
rcas> qbinomial(4, 2, q).subs(q => 1).simplify
=> 6
rcas> qfactorial(3, q)
=> 1 + 2*q + 2*q**2 + q**3
```

Alles ruht auf dem q-Pochhammer-Symbol
`(a; q)_n = (1 - a)(1 - a*q)...(1 - a*q**(n - 1))`, das die Rolle spielt,
die bei gewöhnlichen hypergeometrischen Termen die steigende Fakultät hat:
`qfactorial(n, q)` ist `(q; q)_n/(1 - q)**n` und `qbinomial(n, k, q)` ist
`(q; q)_n/((q; q)_k*(q; q)_(n - k))`. Ganzzahlige Argumente rechnen sich
aus, symbolische bleiben stehen, und die Algorithmen entfalten sie selbst.

```
rcas> qpochhammer(t, q, 3)
=> (1 - q**2*t)*(1 - q*t)*(1 - t)
```

#### q-Summation

Ein Term heißt *q-hypergeometrisch*, wenn `t(k + 1)/t(k)` eine rationale
Funktion von `q**k` ist statt von `k`. Schreibt man `x` für `q**k`, wird aus
der Verschiebung `k -> k + 1` die Streckung `x -> q*x`, und Gospers
Algorithmus geht mit dieser einen Änderung durch. `qgosper(f, q, k)` ist die
q-Antidifferenz, `qsum(f, q, k: a..b)` die bestimmte Summe; die geometrische
Reihe ist das q-Analogon von `sum(1, k: 0..n-1) = n`:

```
rcas> qgosper(q**k, q, k)
=> q**k/(-1 + q)
rcas> qsum(q**k, q, k: 0..n-1)
=> -1/(-1 + q) + q**n/(-1 + q)
```

Diese Antwort ist `[n]_q`. Eine Summe ohne q-Antidifferenz bleibt
unausgewertet, wie eine gewöhnliche auch:

```
rcas> qsum(qbinomial(n, k, q), q, k: 0..n)
=> sum(qbinomial(n, k, q), k, 0, n)
```

`qsumrecursion(F, k, q, s(n))` ist Zeilbergers Algorithmus in der q-Welt:
er beweist eine Identität, indem er die Rekursion findet, der beide Seiten
genügen. Hier der q-binomische Satz, dessen Summe `(-z; q)_n` ist:

```
rcas> qsumrecursion(qbinomial(n, k, q)*q**(k*(k - 1)/2)*z**k, k, q, s(n))
=> s(1 + n) + s(n)*(-1 - q**n*z) = 0
```

und zuletzt die Summe aller Gaußschen Binomialkoeffizienten einer Zeile
(die Galois-Zahlen), die eine Rekursion zweiter Ordnung erfüllt:

```
rcas> qsumrecursion(qbinomial(n, k, q), k, q, s(n))
=> -2*s(1 + n) + s(2 + n) + s(n)*(1 - q**(1 + n)) = 0
```

#### q-Differenzengleichungen

Eine q-Differenzengleichung verbindet `f(x)`, `f(q*x)`, `f(q**2*x)`, ... so
wie eine Rekursion `u(n)`, `u(n + 1)`, `u(n + 2)` verbindet. Die Einsetzung
`x = q**n` macht aus der einen die andere, und deshalb meldet `qsolve`
seine Antworten bei `x = q**n`: dort ist eine q-hypergeometrische Lösung ein
Produkt aus q-Pochhammer-Symbolen und Potenzen.

`qsolve(equation, f, x, q)` findet die q-hypergeometrischen Lösungen mit
Petkovšeks Algorithmus, mit `x -> q*x` anstelle von `n -> n + 1`. Das
q-Pochhammer-Symbol löst seine eigene Gleichung, und die Rekursion, die der
q-binomische Satz oben ergab, ist genau von dieser Art:

```
rcas> qsolve(eq(u(q*x), (1 - t*x)*u(x)), u, x, q)
=> u(q**n) = C1*qpochhammer(t, q, n)
rcas> qsolve(eq(u(q*x), (1 + z*x)*u(x)), u, x, q)
=> u(q**n) = C1*qpochhammer(-z, q, n)
rcas> qsolve(eq((1 - x)*u(q*x), u(x)), u, x, q)
=> u(q**n) = C1/qpochhammer(q, q, -1 + n)
```

Die letzte beginnt ihr Produkt hinter der Nullstelle von `(1; q)_n`, so wie
`rsolve` auf `u(n + 1) = n*u(n)` mit `(n - 1)!` antwortet. `qhyper` listet
die Verhältnisse `f(q*x)/f(x)` selbst auf und ist leer, wenn es nichts
q-Hypergeometrisches zu finden gibt - bei der q-Airy-Gleichung etwa:

```
rcas> qhyper(eq(u(q**2*x), u(q*x) + x*u(x)), u, x, q)
=> []
```

### 1.13 Rechenwege

`steps` gibt den Rechenweg, nicht nur das Ergebnis. Es nimmt die
*Aufgabe* statt ihres Werts, also entweder einen Block -
`steps { diff(f, x) }`, den `hold` unausgewertet festhält - oder die Sache
zusammen mit dem, was damit zu tun ist: `steps(f, :solve)`,
`steps(f, :apart)`, `steps(m, :rref)`, `steps(a, b, :gcd)`,
`steps(f, x, :discuss)` - was auch `steps { discuss(f, x) }` tut, denn
`hold` hält auch eine Kurvendiskussion fest.

```
rcas> steps { diff(x**2*sin(x), x) }
=> D(x**2*sin(x), x)
     product rule (u*v)' = u'*v + u*v', with u = x**2 and v = sin(x)
       power rule (u**n)' = n*u**(n - 1)*u', with u = x and n = 2
       d/dx (x**2) = 2*x
       d/du sin(u) = cos(u), from the table
       d/dx (sin(x)) = cos(x)
   = 2*x*sin(x) + x**2*cos(x)
rcas> steps { integrate(x*exp(x), x) }
=> integral(x*exp(x), x)
     by parts with u = x and dv = exp(x) dx
     du = 1 dx and v = exp(x)
     u*v - integral(v*du) leaves integral(exp(x), x)
   = -exp(x) + x*exp(x)
rcas> steps { integrate(x*exp(x**2), x) }
=> integral(x*exp(x**2), x)
     substitute u = x**2, so du = 2*x dx
     the integral becomes integral(exp(u)/2, u)
   = exp(x**2)/2
```

Jeder Erzähler entscheidet, welche Regel greift, und fragt die Bibliothek
dann nach dem Stück, das er benennt; der Rechenweg kann also nirgendwo
anders enden, als `diff` oder `integrate` von sich aus enden würden. Wo
keine Lehrbuchregel passt - bei einer rationalen Funktion etwa, die
Lazard-Rioboo-Trager braucht -, sagt die Zeile das, statt eine Herleitung
zu erfinden.

```
rcas> steps(x**2 - 5*x + 6, :solve)
=> x**2 - 5*x + 6 = 0
     a quadratic a*x**2 + b*x + c = 0 with a = 1, b = -5, c = 6
     the discriminant b**2 - 4*a*c = 1
     x = (-b +- sqrt(b**2 - 4*a*c))/(2*a) = (5 +- 1)/2
   = [2, 3]
rcas> steps(1/(x**2 - 1), :apart)
=> apart(1/(-1 + x**2))
     numerator 1 over denominator -1 + x**2
     factor the denominator: -1 + x**2 = (-1 + x)*(1 + x)
     the ansatz: (1)/(-1 + x**2) = A/(-1 + x) + B/(1 + x)
     comparing the coefficients of x: A = 1/2, B = -1/2
   = 1/(2*(-1 + x)) - 1/(2*(1 + x))
rcas> steps(1071, 462, :gcd)
=> gcd(1071, 462)
     1071 = 2*462 + 147
     462 = 3*147 + 21
     147 = 7*21 + 0
     the last remainder that is not zero is the gcd
   = 21
```

Faktorisiert wird so, wie es unterrichtet wird: ausklammern, was in jedem
Term steckt, eine Differenz von Quadraten erkennen, eine rationale
Nullstelle p/q suchen, bei der p das Absolutglied und q den Leitkoeffizienten
teilt, sie herausdividieren und mit dem Rest weitermachen. Eine
quadratische Gleichung endet bei ihrer Diskriminante - ist sie eine
Quadratzahl, zerfällt das Polynom über den rationalen Zahlen, sonst nicht.
Eine Zahl wird der Reihe nach durch die Primzahlen geteilt.

```
rcas> steps(x**3 - 2*x**2 - 5*x + 6, :factor)
=> factor(x**3 - 2*x**2 - 5*x + 6)
     a rational root p/q has p dividing 6 and q dividing 1: try -6, -3, -2, -1, 1, 2, 3, 6
     f(-2) = 0, so 2 + x divides it
     6 - 5*x - 2*x**2 + x**3 = (2 + x)*(3 - 4*x + x**2)
     the quadratic 3 - 4*x + x**2: its discriminant is 4
     2**2, a square, so the roots (4 +- 2)/2 are rational and it factors
   = (-1 + x)*(-3 + x)*(2 + x)
rcas> steps(x**2 - 9, :factor)
=> factor(x**2 - 9)
     a difference of squares: u**2 - v**2 = (u - v)*(u + v) with u = x and v = 3
   = (-3 + x)*(3 + x)
rcas> steps(360, :factor)
=> factor(360)
     360 = 2*180
     180 = 2*90
     90 = 2*45
     45 = 3*15
     15 = 3*5
     5 is prime, and the trial division stops there
   = 2**3*3**2*5
```

Gibt es keine rationale Nullstelle (`x**4 + 1`) oder mehrere Variablen,
sagt die Zeile, auf welchen Algorithmus rcas zurückfällt, statt ein
Handverfahren vorzutäuschen.

Dasselbe für die Algebra einer ersten Vorlesung über lineare Algebra, eine
Zeilenumformung nach der anderen:

```
rcas> steps(matrix([[2, 1, 5], [1, -1, 1]]), :rref)
=> [2  1 5]
   [1 -1 1]
     R1 := R1/(2)
     [1 1/2 5/2]
     [1  -1   1]
     R2 := R2 - (1)*R1
     [1  1/2  5/2]
     [0 -3/2 -3/2]
     R2 := R2/(-3/2)
     [1 1/2 5/2]
     [0   1   1]
     R1 := R1 - (1/2)*R2
     [1 0 2]
     [0 1 1]
   = [1 0 2]
   [0 1 1]
```

Abgedeckt ist, was eine Vorlesung verlangt: Summen-, Produkt-, Quotienten-,
Potenz- und Kettenregel; die Potenzregel, die Tabelle mit linearem
Argument, Substitution und partielle Integration; lineare und quadratische
Gleichungen mit ausgeschriebener Diskriminante und Lösungsformel;
Faktorisieren über Ausklammern, Quadratdifferenz und rationale
Nullstellen, und eine Zahl über Probedivision; der
Partialbruchansatz samt aufgelösten Unbekannten; der Gauß-Algorithmus;
der euklidische Algorithmus für Zahlen und für Polynome; und die
vollständige Kurvendiskussion (1.3 Analysis, Die vollständige
Kurvendiskussion). Das Ergebnis ist
eine `Derivation`, die sich wie oben ausgibt und in `rcas-chat` als
ausgerichteter Block gesetzt wird.

### 1.14 Hinweise zur Geschwindigkeit

`expand` und die Umwandlung in Polynome fassen gleiche Terme schon beim
Multiplizieren zusammen, ein Produkt vieler Summen erzeugt also nie mehr
Terme, als das Ergebnis hat; ein Produkt aus zehn Summen mit je einem
Dutzend Termen auszumultiplizieren dauert Millisekunden. `simplify`
verflacht Summen und Produkte in einem Durchgang, und kanonische Ergebnisse
mit mehr als 32 Termen werden als balancierte Bäume kurzer Ketten gebaut,
was jeden rekursiven Algorithmus (Drucken, Gleichheit, Einsetzen, Ableiten)
auf logarithmischer Tiefe hält. Eine Summe aus 20000 Termen vereinfacht,
druckt und wandelt sich deutlich unter einer Sekunde in ein Polynom um.

Selbst gebaute Ausdrücke werden genau so gespeichert, wie sie geschrieben
wurden, eine als eine lange Kette getippte Summe aus 20000 Termen ist also
20000 Ebenen tief. `simplify`, `expand`, `to_s`, `variables` und `to_poly`
kommen damit zurecht; `==`, `subs`, `diff` und `hash` steigen auf einer
solchen rohen Kette weiterhin Term für Term hinab, vereinfachen Sie also
zuerst.

Die Polynomfaktorisierung über ZZ ist bis zu Graden im Dutzendbereich
schnell; der Rekombinationsschritt ist exponentiell in der Zahl der
modularen Faktoren, ein Produkt aus zwanzig zufälligen Faktoren vom Grad bis
zwanzig braucht also etwa eine Minute. Die mehrdimensionale Faktorisierung
läuft über die Kronecker-Substitution und ist für kleine Beispiele gedacht.
Symbolische Determinanten und Inverse benutzen die Entwicklung nach
Unterdeterminanten; halten Sie symbolische Matrizen klein.

## 2. Referenz

Funktionen der obersten Ebene (bloß in `bin/rcas`, sonst `RCAS.name`):

| Zweck | Funktionen |
|---|---|
| elementare Funktionen | `sin cos tan asin acos atan exp log sinh cosh sqrt cbrt root zeta abs sign erf erfc` |
| Kombinatorik | `factorial binomial gamma` |
| Umformen | `simplify expand cancel rationalize trigsimp expand_trig expand_log logcombine minpoly` |
| rationale Funktionen | `numer denom apart gcd lcm quo rem divmod` |
| ganze Zahlen | `factor ifactor isprime nextprime prevprime divisors totient invmod chrem congruence legendre jacobi order primitive_root continued_fraction convergents` |
| Polynomstruktur | `degree ldegree lcoeff tcoeff coeff coeffs collect resultant discriminant interpolate` |
| benannte Polynome | `Poly.chebyshev_t Poly.chebyshev_u Poly.legendre Poly.hermite Poly.hermite_prob Poly.laguerre Poly.gegenbauer Poly.jacobi Poly.bernoulli Poly.euler Poly.cyclotomic Poly.swinnerton_dyer Poly.abel Poly.fibonacci Poly.lucas Poly.bell` (ein Namensraum, keine bloßen Namen) |
| Konstanten | `PI E I oo` (bloß `pi`, `π`, `oo`, `∞`) |
| Auswerten | `subs evalf` (`evalf(f, 50)` für fünfzig Stellen) |
| Analysis | `integrate diff series taylor fps fourier limit sum product` |
| abschnittsweise | `piecewise discontinuities kinks` |
| hypergeometrische Summation | `sumrecursion sumcertificate hyper` |
| q-Analoga | `qbracket qfactorial qbinomial qpochhammer qgosper qsum qsumrecursion qsumcertificate qsolve qhyper` |
| Numerik | `nsolve nintegrate` (beide nehmen `digits:`) |
| Kurvendiskussion | `critical_points extrema inflections asymptotes tangent normal real_domain`, `discuss` für alles auf einmal |
| Länge, Fläche, Volumen | `arclength revolution_volume revolution_surface` |
| mehrere Veränderliche | `gradient hessian jacobian divergence curl laplacian lagrange` |
| Algebra | `solve eq factor groebner reduce interval` |
| Differentialgleichungen, Rekursionen | `D dsolve rsolve hyper laplace inverse_laplace` |
| komplexe Zahlen | `re im conj arg` |
| Runden | `floor ceil round mod` |
| Folgen | `bernoulli fibonacci harmonic` |
| Statistik | `mean median mode variance stdev quantile quartiles iqr moment skewness kurtosis geometric_mean harmonic_mean frequencies covariance correlation linreg` |
| Verteilungen | `Normal Uniform Exponential Bernoulli Binomial Poisson Geometric DiscreteUniform StudentT ChiSquare FRatio pdf cdf probability` |
| Tests und Intervalle | `ttest ztest chisquare_test ftest binomial_test confidence_interval proportion_interval` |
| Grafik | `plot parametric polar scatter histogram boxplot barchart` |
| Geometrie | `point line circle distance midpoint angle area perimeter collinear? centroid intersect circumcircle perpendicular_bisector parallel_through perpendicular_through` |
| spezielle Funktionen | `erf erfc Ei Si Ci li` |
| Bereiche | `NN ZZ QQ RR CC` (auch `ℕ ℤ ℚ ℝ ℂ`), `GF assume forget assumptions` |
| lineare Algebra | `vector matrix gram_schmidt least_squares project orthogonal? lu qr cholesky diagonalize jordan` |
| Festhalten | `hold evaluate` |
| Rechenwege | `steps` (ein Block, oder `:solve :factor :apart :rref :gcd`) |
| Hilfe | `doc` (`/help NAME` in rcas-chat) |
| Sitzung | `In`, `Out` (die nummerierten Zeilen), `_` (irbs letzter Wert) |

Methoden auf Ausdrücken: `simplify expand factor cancel rationalize collect
numer denom apart gcd lcm quo rem divmod subs call evalf to_f diff integrate
series taylor limit solve eq variables degree ldegree lcoeff tcoeff coeff
coeffs domain in in? to_poly to_sexp`, das zu `hold` Gehörige und
`evaluate`.

Nicht umgesetzt: der vollständige Risch-Algorithmus und spezielle Funktionen
über `erf`, `Ei`, `Si`, `Ci` und `li` hinaus (der Dilogarithmus, also
`log(x)/(1 + x)`), Varianzanalyse und nichtparametrische Tests,
dreidimensionale Grafiken, Geometrie im Raum,
Fourier-Transformationen, Gruppentheorie, Differentialgleichungen mit
variablen Koeffizienten jenseits der ersten Ordnung, Ungleichungen jenseits
polynomialer, rationaler und Betragsungleichungen, Zahlkörper mit mehr als
zwei Erzeugern, die zugeordneten Legendre-Funktionen und die
mehrdimensionalen (partiellen) Bell-Polynome, hypergeometrische Lösungen *inhomogener* Rekursionen mit
polynomialen Koeffizienten, Abramovs rationale Lösungen, der
Almkvist-Zeilberger-Algorithmus für hyperexponentielle Integrale,
mehrdimensionale (holonome) Summation und formale Potenzreihen, deren
Koeffizienten nicht hypergeometrisch sind (`tan`, `exp(x)/(1 - x)`).

## 3. Dateien

```
lib/rcas.rb                 entry point
lib/rcas/expression.rb      Expression tree: Var Num Const Neg Add Sub Mul Div Pow Fn
lib/rcas/printer.rb         precedence-aware to_s
lib/rcas/simplify.rb        canonical sums/products, exact number folding
lib/rcas/expand.rb          distribution with like-term merging
lib/rcas/differentiate.rb   derivative rules
lib/rcas/integrate.rb       rules, rational functions, Risch-Norman heuristic
lib/rcas/integrate_substitutions.rb  rationalizing substitutions (roots, exp, sin/cos)
lib/rcas/series.rb          Puiseux series, limits
lib/rcas/piecewise.rb       functions defined case by case
lib/rcas/fourier.rb         Fourier series
lib/rcas/integral_functions.rb  Ei, Si, Ci, li
lib/rcas/precision.rb       Decimal and evalf to a number of digits
lib/rcas/steps.rb           worked solutions
lib/rcas/decompositions.rb  LU, QR, Cholesky, Jordan
lib/rcas/summation.rb       Faulhaber, Gosper, zeta
lib/rcas/poly_recurrence.rb polynomial solutions of a linear recurrence
lib/rcas/petkovsek.rb       hypergeometric solutions of a recurrence
lib/rcas/zeilberger.rb      creative telescoping for definite sums
lib/rcas/q_functions.rb     q-Pochhammer, q-bracket, q-factorial, Gaussian binomials
lib/rcas/q_summation.rb     q-Gosper: q-antidifferences and q-sums
lib/rcas/q_zeilberger.rb    creative telescoping in the q-world
lib/rcas/q_difference.rb    q-difference equations (q-Petkovsek)
lib/rcas/product.rb         symbolic products; Product node
lib/rcas/recurrence.rb      rsolve: linear recurrences with constant coefficients
lib/rcas/complex_parts.rb   re, im, conj, arg
lib/rcas/statistics.rb      descriptive statistics, covariance, correlation, linreg
lib/rcas/distributions.rb   Normal, Uniform, Exponential, Bernoulli, Binomial, Poisson, Geometric, DiscreteUniform, StudentT, ChiSquare, FRatio
lib/rcas/special.rb         incomplete gamma and beta, numerically
lib/rcas/hypothesis.rb      t, z, chi-square, F and binomial tests; confidence intervals
lib/rcas/numerics.rb        nsolve and nintegrate: numbers when the symbols run out
lib/rcas/analysis.rb        curve sketching and several variables
lib/rcas/discussion.rb      the whole curve discussion in one report
lib/rcas/geometry.rb        points, lines and circles in the plane
lib/rcas/linear_algebra.rb  orthogonality, projections and least squares
lib/rcas/laplace.rb         the Laplace transform and its inverse
lib/rcas/plot.rb            function plotting: braille art, SVG, PNG
lib/rcas/docs.rb            doc(name): signatures and comments read from the source
lib/rcas/results.rb         In and Out: the numbered lines of a session
lib/rcas/background.rb      the mathematics behind each name, its sources and Wikipedia links
lib/rcas/solve.rb           equations, solve, systems
lib/rcas/groebner.rb        Gröbner bases: Buchberger, normal forms, monomial orders
lib/rcas/interpolate.rb     Newton interpolation
lib/rcas/named_polynomials.rb  Poly: the named polynomial families
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

Die Tests laufen mit `ruby -S rake`.

## 4. Quellen

Die nichttrivialen Algorithmen und ihre Herkunft. Die Schlüssel in Klammern
werden in den Quelltextkommentaren benutzt (`# [GCL92, ch. 8]`). Die
Literaturangaben stehen in der Sprache der Werke.

| Algorithmus | Datei | Quelle |
|---|---|---|
| kanonische Form, Ausmultiplizieren auf Termtabellen | simplify.rb, expand.rb | eigener Entwurf; Ordnung nach Art von Mathematica |
| quadratfreie Zerlegung (Yun) | factor.rb | [Yun76]; [vzGG13, §14.6] |
| Faktorisieren über ZZ: Cantor-Zassenhaus mod p, Hensel-Lifting, Mignotte-Schranke, Rekombination | factor.rb | [Zas69]; [CZ81]; [Mig74]; [GCL92, ch. 8]; [vzGG13, ch. 15] |
| mehrdimensionales Faktorisieren durch Kronecker-Substitution | factor.rb | [Knu98, §4.6.2]; [vzGG13, §8.4] |
| Polynom-ggT: Euklid, primitive Pseudodivisionsketten | gcd.rb | [Knu98, §4.6.1, Algorithm E]; [GCL92, ch. 7] |
| Resultante, Diskriminante (Sylvester-Matrix) | polynomial.rb | [GCL92, ch. 7]; [CLO15, §3.6] |
| Partialbrüche (Aufspalten teilerfremder Faktoren mit dem erweiterten Euklid, p-adische Entwicklung) | rational_function.rb | [Bro05, §2.1] |
| rationale Integration: Hermite-Reduktion (Macks lineare Fassung), logarithmischer Teil nach Lazard-Rioboo-Trager, Rothstein-Trager-Resultante | integrate.rb | [Her72]; [Mac75]; [Bro05, §2.2, §2.4, §2.5]; [RT76]; [LR90]; [GCL92, ch. 11] |
| Risch-Norman-Heuristik (paralleler Risch) | integrate.rb | [NM77]; [GS89] |
| rationalisierende Substitutionen: Wurzel aus einer quadratischen Form (Reduktion auf S*sqrt(Q) + lambda*int 1/sqrt(Q), x - alpha = 1/t), Wurzeln linearer Formen, Exponentialfunktionen, tan(x/2) | integrate_substitutions.rb | [Zor15, §5.7]; [Har16, ch. V-VI] |
| reelle quadratische Faktoren eines biquadratischen Nenners; Möbius-Substitution für die Wurzel aus einem Quotienten linearer Formen | integrate.rb, integrate_substitutions.rb | [Har16, ch. II-III]; [GCL92, ch. 11] |
| Puiseux-Reihen mit Logarithmustermen, Grenzwerte über den führenden Term | series.rb | Potenzreihenarithmetik wie in [Knu98, §4.7]; die Grenzwertstrategie ist die des Lehrbuchs, nicht Gruntz' MRV-Algorithmus [Gru96] |
| Einschnürungssatz für einen beschränkten mal einen Nullfaktor | series.rb | [Rud76, th. 3.19] |
| Abschnittsweise Funktionen: Zweigwahl, stetige Stammfunktion | piecewise.rb | [Spi08, ch. 13] |
| Fourier-Reihen und halbseitige Entwicklungen | fourier.rb | [Spi08, ch. 13]; die Koeffizienten sind rcas' eigene Integrale |
| Ei, Si, Ci, li: Reihen und Kettenbrüche | integral_functions.rb | [AS64, §5.1, §5.2]; [PTVF07, §6.3]; Lentz [Len76] |
| evalf mit beliebiger Genauigkeit über BigDecimal, Nullstellen mit Newton | precision.rb | [AS64, §4.1, §4.3]; [PTVF07, §9.4] |
| Die eulersche Konstante auf beliebige Genauigkeit | precision.rb | Brent-McMillan [BM80] |
| Doppeltexponentielle (tanh-sinh) Quadratur | precision.rb | [TM74] |
| erf, Si, Ci, Ei, li und zeta in BigDecimal | precision.rb | die Reihen aus [AS64, §5.1, §5.2, §7.1]; Euler-Maclaurin [AS64, §23.2] |
| Rechenwege: die Regeln benannt, wie sie benutzt werden | steps.rb | [Spi08, ch. 10, 18, 19]; Euklid [Knu98, §4.5.2] |
| Bogenlänge, Rotationskörper | analysis.rb | [Spi08, ch. 13] |
| LU, QR, Cholesky, Diagonalisierung | decompositions.rb | [Str16, ch. 2, 4, 6] |
| Jordansche Normalform aus Ketten verallgemeinerter Eigenvektoren | decompositions.rb | [HK71, ch. 7] |
| Faulhaber-Summen durch Newton-Interpolation, Bernoulli-Zahlen, zeta(2m) | summation.rb | [GKP94, §6.5]; Euler-Maclaurin-Rest [GKP94, §9.5] |
| Gospers Algorithmus mit der Gradschranke für den Polynomansatz | summation.rb | [Gos78]; [PWZ96, ch. 5] |
| Produkte: Fakultäts- und Gammaquotienten bei linearen Faktoren, exp von Summen | product.rb | [GKP94, §5.5] |
| Rekursionen: charakteristische Wurzeln, unbestimmte Koeffizienten, Anfangswerte | recurrence.rb | [GKP94, §7.3] |
| hypergeometrische Lösungen einer Rekursion mit polynomialen Koeffizienten (Petkovšek), polynomiale Lösungen mit Abramovs Gradschranke | petkovsek.rb, poly_recurrence.rb | [Pet92]; [Koe14, ch. 9]; [PWZ96, ch. 8] |
| formale Potenzreihen (Koepfs FPS-Algorithmus): holonome Differentialgleichung, Rekursion für die Koeffizienten, hypergeometrische Lösung; Gaußsche Multiplikationsformel für die Gammafaktoren | fps.rb | [Koe92]; [Koe14, ch. 10]; [Sta99, ch. 6]; [AS64, §6.1] |
| bestimmte hypergeometrische Summen durch kreatives Teleskopieren (Zeilberger), mit rationalem Zertifikat | zeilberger.rb | [Zei91]; [Koe14, ch. 7]; [PWZ96, ch. 6] |
| q-Analoga: q-Pochhammer und Gaußsche Binomialkoeffizienten, q-Gosper, q-Zeilberger, q-Petkovšek für q-Differenzengleichungen | q_functions.rb, q_summation.rb, q_zeilberger.rb, q_difference.rb | [Koo93]; [Koe14, ch. 10-12]; [APP98]; [GR04] |
| beschreibende Statistik, Stichprobenquantile (Definition 7), Ausgleichsgerade | statistics.rb | [HF96]; [Ros14, ch. 7] |
| Verteilungen: Dichten, Verteilungsfunktionen, Momente; Normalverteilung über erf, Quantil durch Bisektion und Newton | distributions.rb | [Ros14, ch. 4-5]; [AS64, §7.1] |
| unvollständige Gamma- und Betafunktion durch Reihen und Kettenbrüche (Lentz) | special.rb | [AS64, §6.5, §26.5]; [PTVF07, §6.2, §6.4]; [Len76] |
| t-, Chi-Quadrat- und F-Test, exakter Binomialtest, Konfidenzintervalle | hypothesis.rb | [Ros14, ch. 8-9]; Welchs Freiheitsgrade [Wel47]; Wilsons Score-Intervall [Wil27] |
| Gamma-Zufallszahlen für Stichproben (Marsaglia-Tsang) | distributions.rb | [MT00] |
| Grafik: Braille-Leinwand (die Technik von drawille und UnicodePlots.jl), Linienzeichnen | plot.rb | [Bre65] |
| Klassenzahl des Histogramms, Boxplot-Antennen beim 1,5-fachen Quartilsabstand | plot.rb | [Stu26]; [Tuk77] |
| Gauß-Integrale: exp(quadratisch) durch quadratische Ergänzung, x**n exp(quadratisch) durch Reduktion | integrate_substitutions.rb | [AS64, §7.1, §7.4] |
| polynomiale Systeme: lexikographische Gröbnerbasis und dreiecksförmiges Rückwärtseinsetzen; Resultanten bei zwei Gleichungen mit Parametern | solve.rb | [CLO15, ch. 2 §8, ch. 3 §1]; [GCL92, ch. 9-10] |
| Newton-Interpolation mit dividierten Differenzen | interpolate.rb | [Knu98, §4.6.4]; [vzGG13, ch. 5] |
| benannte Polynomfamilien: Dreitermrekursionen, Kreisteilungspolynome durch exakte Division von x**n - 1, Swinnerton-Dyer durch eine Konjugation je Primzahl | named_polynomials.rb | [AS64, ch. 22-23]; [Sze75]; [GKP94, ch. 5-6]; [vzGG13, ch. 14]; [Coh93] |
| Gröbnerbasen: Buchbergers Algorithmus mit dem Produktkriterium, Normalformen, reduzierte Basen, Dimensionstest | groebner.rb | [Buc65]; [CLO15, ch. 2 §§3, 7, 9-10; ch. 5 §3]; [GCL92, ch. 10] |
| numerische Polynomnullstellen: Durand-Kerner-Iteration (Weierstraß) | solve.rb | [Ker66] |
| Minimalpolynom über Resultanten, Arithmetik in QQ(alpha) | algebraic.rb | [Loo83]; [Coh93, §4.2] |
| Faktorisieren über QQ(alpha) mit Normen (Trager) | algebraic.rb | [Tra76]; [Coh93, Algorithm 3.6.4] |
| endliche Körper: Faktorisierung nach Grad und gleichem Grad, Rabins Irreduzibilitätstest | finite_field.rb | [CZ81]; [vzGG13, §14.2-14.3]; [Rab80] |
| lineare Algebra: Gauß-Elimination, reduzierte Zeilenstufenform, Entwicklung nach Unterdeterminanten | matrix.rb | Lehrbuch |
| Polynommatrizen: PolyDet, RatDet, PolyLinearSolve, Kern durch Auswertung und Interpolation | poly_matrix.rb | [Hor08, ch. 6]; die Idee der modularen Determinante auch in [vzGG13, §5.5] |
| Faktorisierung ganzer Zahlen: Probedivision, Pollard-Brent-Rho | number_theory.rb | [Pol75]; [Bre80]; [Knu98, §4.5.4]; [Coh93, §8.5] |
| Primzahltest: Miller-Rabin, deterministische Basen unter 3,3e24 | number_theory.rb | [Mil76]; [Rab80b]; [SW17]; [Knu98, §4.5.4, Algorithm P] |
| chinesischer Restsatz, modulares Inverses, Totient, Teiler | number_theory.rb | [Coh93, §1.3]; [Knu98, §4.3.2]; [HW08, §5.5, §16.3] |
| Differentialgleichungen: trennbar, integrierender Faktor, charakteristische Wurzeln, unbestimmte Koeffizienten, Variation der Konstanten | ode.rb | [BD12, ch. 2-4] |
| Ungleichungen über Vorzeichentabellen an den exakten reellen Nullstellen | inequalities.rb | Lehrbuch; Nullstellen aus solve.rb |
| numerische Nullstellen (Bisektion mit Newton-Schritten) und adaptive Simpson-Quadratur | numerics.rb | [PTVF07, §4.2, §9.1-9.4] |
| Kurvendiskussion: kritische Stellen, Test mit der zweiten Ableitung, Asymptoten aus Grenzwerten, die vollständige Diskussion mit ihrer Vorzeichentabelle | analysis.rb, discussion.rb | [Spi08, ch. 11] |
| mehrere Veränderliche: Gradient, Hesse-Matrix, Jacobi-Matrix, Lagrange-Multiplikatoren | analysis.rb | [Rud76, ch. 9]; [Spi08, ch. 17] |
| analytische Geometrie: Geraden und Kreise, Fläche nach der Schnürsenkelformel | geometry.rb | [Spi08, ch. 4]; [Bra86] |
| Gram-Schmidt-Orthogonalisierung, kleinste Quadrate über die Normalengleichungen | linear_algebra.rb | [Str16, ch. 4] |
| Laplace-Transformation aus der Tabelle mit den Verschiebungssätzen, Rücktransformation über Partialbrüche | laplace.rb | [BD12, ch. 6] |
| Systeme von Differentialgleichungen über Eigenwerte, mit Jordan-Ketten bei zu wenigen Eigenvektoren | ode.rb | [BD12, ch. 7] |
| Kongruenzen, Legendre- und Jacobi-Symbol, multiplikative Ordnung, Kettenbrüche | number_theory.rb | [Coh93, §1.4]; [Knu98, §4.5.3]; [HW08, ch. 10] |

- [APP98] S. A. Abramov, P. Paule, M. Petkovšek, q-Hypergeometric
  solutions of q-difference equations, *Discrete Math.* 180 (1998), 3-22.
- [AS64] M. Abramowitz, I. A. Stegun (eds.), *Handbook of Mathematical
  Functions*, National Bureau of Standards 1964, ch. 7 (error function).
- [BD12] W. E. Boyce, R. C. DiPrima, *Elementary Differential Equations and
  Boundary Value Problems*, 10th ed., Wiley 2012.
- [BM80] R. P. Brent, E. M. McMillan, Some new algorithms for high-precision
  computation of Euler's constant, *Math. Comp.* 34 (1980), 305-312.
- [Bra86] B. Braden, The surveyor's area formula, *College Mathematics
  Journal* 17 (1986), 326-337.
- [Bre80] R. P. Brent, An improved Monte Carlo factorization algorithm,
  *BIT* 20 (1980), 176-184.
- [Bre65] J. E. Bresenham, Algorithm for computer control of a digital
  plotter, *IBM Systems Journal* 4 (1965), 25-30.
- [Bro05] M. Bronstein, *Symbolic Integration I: Transcendental Functions*,
  2nd ed., Springer 2005.
- [Buc65] B. Buchberger, *Ein Algorithmus zum Auffinden der Basiselemente des
  Restklassenringes nach einem nulldimensionalen Polynomideal*, Dissertation,
  Universität Innsbruck 1965; English translation in *J. Symbolic Comput.*
  41 (2006), 475-511.
- [CLO15] D. Cox, J. Little, D. O'Shea, *Ideals, Varieties, and
  Algorithms*, 4th ed., Springer 2015.
- [Coh93] H. Cohen, *A Course in Computational Algebraic Number Theory*,
  GTM 138, Springer 1993.
- [CZ81] D. G. Cantor, H. Zassenhaus, A new algorithm for factoring
  polynomials over finite fields, *Math. Comp.* 36 (1981), 587-592.
- [GCL92] K. O. Geddes, S. R. Czapor, G. Labahn, *Algorithms for Computer
  Algebra*, Kluwer 1992.
- [GKP94] R. L. Graham, D. E. Knuth, O. Patashnik, *Concrete Mathematics*,
  2nd ed., Addison-Wesley 1994.
- [Gos78] R. W. Gosper, Decision procedure for indefinite hypergeometric
  summation, *Proc. Natl. Acad. Sci. USA* 75 (1978), 40-42.
- [GR04] G. Gasper, M. Rahman, *Basic Hypergeometric Series*, 2nd ed.,
  Encyclopedia of Mathematics and its Applications 96, Cambridge University
  Press 2004.
- [Gru96] D. Gruntz, *On Computing Limits in a Symbolic Manipulation
  System*, Diss. ETH Zürich 1996.
- [GS89] K. O. Geddes, L. Y. Stefanus, On the Risch-Norman integration
  method and its implementation in Maple, *Proc. ISSAC '89*, ACM 1989,
  212-217.
- [Har16] G. H. Hardy, *The Integration of Functions of a Single Variable*,
  2nd ed., Cambridge Tracts in Mathematics 2, Cambridge University Press
  1916.
- [Her72] C. Hermite, Sur l'intégration des fractions rationnelles, *Ann.
  Sci. École Norm. Sup.* (2) 1 (1872), 215-218.
- [HF96] R. J. Hyndman, Y. Fan, Sample quantiles in statistical packages,
  *The American Statistician* 50 (1996), 361-365.
- [HK71] K. Hoffman, R. Kunze, *Linear Algebra*, 2nd ed., Prentice-Hall
  1971.
- [Hor08] P. Horn, *Faktorisierung in Schief-Polynomringen*, Dissertation,
  Universität Kassel 2008, chapter 6 (Lineare Algebra mit Polynom-Matrizen).
- [HW08] G. H. Hardy, E. M. Wright, *An Introduction to the Theory of
  Numbers*, 6th ed., Oxford University Press 2008.
- [Ker66] I. O. Kerner, Ein Gesamtschrittverfahren zur Berechnung der
  Nullstellen von Polynomen, *Numer. Math.* 8 (1966), 290-294.
- [Knu98] D. E. Knuth, *The Art of Computer Programming, vol. 2:
  Seminumerical Algorithms*, 3rd ed., Addison-Wesley 1998.
- [Len76] W. J. Lentz, Generating Bessel functions in Mie scattering
  calculations using continued fractions, *Applied Optics* 15 (1976),
  668-671.
- [Koe92] W. Koepf, Power series in computer algebra, *J. Symbolic Comput.*
  13 (1992), 581-603.
- [Koe14] W. Koepf, *Hypergeometric Summation: An Algorithmic Approach to
  Summation and Special Function Identities*, 2nd ed., Universitext,
  Springer 2014.
- [Koo93] T. H. Koornwinder, On Zeilberger's algorithm and its q-analogue,
  *J. Comput. Appl. Math.* 48 (1993), 91-111.
- [Loo83] R. Loos, Computing in algebraic extensions, in: B. Buchberger,
  G. E. Collins, R. Loos (eds.), *Computer Algebra: Symbolic and Algebraic
  Computation*, 2nd ed., Springer 1983, 173-187.
- [LR90] D. Lazard, R. Rioboo, Integration of rational functions: rational
  computation of the logarithmic part, *J. Symbolic Comput.* 9 (1990),
  113-115.
- [Mac75] D. Mack, On rational integration, Technical Report UCP-38,
  University of Utah 1975.
- [Mig74] M. Mignotte, An inequality about factors of polynomials, *Math.
  Comp.* 28 (1974), 1153-1157.
- [Mil76] G. L. Miller, Riemann's hypothesis and tests for primality, *J.
  Comput. System Sci.* 13 (1976), 300-317.
- [MT00] G. Marsaglia, W. W. Tsang, A simple method for generating gamma
  variables, *ACM Trans. Math. Software* 26 (2000), 363-372.
- [NM77] A. C. Norman, P. M. A. Moore, Implementing the new Risch
  integration algorithm, *Proc. 4th Int. Colloquium on Advanced Computing
  Methods in Theoretical Physics*, Marseille 1977, 99-110.
- [Pol75] J. M. Pollard, A Monte Carlo method for factorization, *BIT* 15
  (1975), 331-334.
- [Pet92] M. Petkovšek, Hypergeometric solutions of linear recurrences
  with polynomial coefficients, *J. Symbolic Comput.* 14 (1992), 243-264.
- [PTVF07] W. H. Press, S. A. Teukolsky, W. T. Vetterling, B. P. Flannery,
  *Numerical Recipes*, 3rd ed., Cambridge University Press 2007.
- [PWZ96] M. Petkovšek, H. S. Wilf, D. Zeilberger, *A = B*, A K Peters
  1996.
- [Rab80] M. O. Rabin, Probabilistic algorithms in finite fields, *SIAM J.
  Comput.* 9 (1980), 273-280.
- [Rab80b] M. O. Rabin, Probabilistic algorithm for testing primality, *J.
  Number Theory* 12 (1980), 128-138.
- [Ros14] S. M. Ross, *A First Course in Probability*, 9th ed., Pearson
  2014.
- [RT76] M. Rothstein, *Aspects of Symbolic Integration and Simplification
  of Exponential and Primitive Functions*, PhD thesis, University of
  Wisconsin-Madison 1976; B. M. Trager, Algebraic factoring and rational
  function integration, *Proc. SYMSAC '76*, ACM 1976, 219-226.
- [Stu26] H. A. Sturges, The choice of a class interval, *J. Amer. Statist.
  Assoc.* 21 (1926), 65-66.
- [Rud76] W. Rudin, *Principles of Mathematical Analysis*, 3rd ed.,
  McGraw-Hill 1976.
- [Spi08] M. Spivak, *Calculus*, 4th ed., Publish or Perish 2008.
- [Sta99] R. P. Stanley, *Enumerative Combinatorics, vol. 2*, Cambridge
  University Press 1999.
- [Str16] G. Strang, *Introduction to Linear Algebra*, 5th ed.,
  Wellesley-Cambridge Press 2016.
- [SW17] J. Sorenson, J. Webster, Strong pseudoprimes to twelve prime
  bases, *Math. Comp.* 86 (2017), 985-1003.
- [Sze75] G. Szegő, *Orthogonal Polynomials*, 4th ed., American Mathematical
  Society Colloquium Publications 23, AMS 1975.
- [TM74] H. Takahasi, M. Mori, Double exponential formulas for numerical
  integration, *Publ. RIMS Kyoto Univ.* 9 (1974), 721-741.
- [Tra76] B. M. Trager, Algebraic factoring and rational function
  integration, *Proc. SYMSAC '76*, ACM 1976, 219-226.
- [Tuk77] J. W. Tukey, *Exploratory Data Analysis*, Addison-Wesley 1977.
- [vzGG13] J. von zur Gathen, J. Gerhard, *Modern Computer Algebra*, 3rd
  ed., Cambridge University Press 2013.
- [Wel47] B. L. Welch, The generalization of 'Student's' problem when
  several different population variances are involved, *Biometrika* 34
  (1947), 28-35.
- [Wil27] E. B. Wilson, Probable inference, the law of succession, and
  statistical inference, *J. Amer. Statist. Assoc.* 22 (1927), 209-212.
- [Yun76] D. Y. Y. Yun, On square-free decomposition algorithms, *Proc.
  SYMSAC '76*, ACM 1976, 26-35.
- [Zas69] H. Zassenhaus, On Hensel factorization I, *J. Number Theory* 1
  (1969), 291-311.
- [Zei91] D. Zeilberger, The method of creative telescoping, *J. Symbolic
  Comput.* 11 (1991), 195-204.
- [Zor15] V. A. Zorich, *Mathematical Analysis I*, 2nd ed., Universitext,
  Springer 2015, §5.7 (primitives of rational functions of x and a root,
  of exp, and of sin and cos).

## 5. Lizenz

rcas steht unter der MIT-Lizenz; siehe `LICENSE`.

## Anhang A. Typografischer Satz

Alles, was rcas erzeugt, hat eine `to_latex`-Methode: Ausdrücke, Polynome,
Faktorisierungen, die Zahlbereiche und Ringe, Räume, Vektoren und Matrizen,
Gleichungen und Ableitungen, ebenso Symbole, Zahlen, Arrays und Hashes. Das
LaTeX folgt dem Baum genau so, wie `to_s` es tut, und fügt nur hinzu, was
ein Setzer erwartet: `\frac` für die Division, implizite Multiplikation,
`\sqrt` für den Exponenten 1/2, `\sin^{2} x`, `e^{x}`, `\ln`, `\pi`,
`\mathbb{Q}[x]`, `pmatrix` für Matrizen. Zeichenketten werden hier so
gezeigt, wie Ruby sie mit `inspect` druckt, jeder Rückstrich erscheint also
doppelt.

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

Lange Ergebnisse lassen sich umbrechen. `to_latex(wrap: n)` zerlegt die
äußerste Summe oder das äußerste Produkt (oder ein langes Array, ein
Element je Zeile) in einen `aligned`-Block, dessen Zeilen etwa `n` gesetzte
Zeichen breit sind, mit eingerückten Fortsetzungszeilen, die der Operator
anführt. Passt das Ergebnis, ändert sich nichts.

```
rcas> (x + 1).to_latex(wrap: 40)
=> "x + 1"
rcas> ((x + 1)**8).expand.to_latex(wrap: 40)
=> "\\begin{aligned} & 1 + 8 x + 28 x^{2} + 56 x^{3} + 70 x^{4} + 56 x^{5} \\\\ &\\quad {} + 28 x^{6} + 8 x^{7} + x^{8} \\end{aligned}"
```

### Bilder

`show(obj)` (oder `obj.show`) setzt einen Wert. In iTerm2 erscheint er als
Bild mitten im Terminal; überall sonst wird der LaTeX-Quelltext gedruckt.
`obj.to_png("f.png")` schreibt das Bild in eine Datei. `bin/rcas` selbst
bleibt unverändert: es druckt Text wie zuvor und setzt nur, wenn Sie mit
`show` darum bitten.

Zwei Renderer werden unterstützt und in dieser Reihenfolge versucht:

* **KaTeX** ([katex.org](https://katex.org)). Einmal `npm install` im
  Projektverzeichnis holt das in `package.json` genannte Paket `katex`.
  node setzt die Formel nach HTML, und ein lokales Google Chrome (oder
  Chromium, Brave, Edge, Arc) rastert sie. `RCAS_NODE` und `RCAS_CHROME`
  zeigen auf andere Programme.
* **LaTeX**. Eine TeX-Installation mit `latex` und `dvipng` (oder
  `pdflatex` und ImageMagick).

Wählen Sie mit `RCAS::Render.backend = :latex` oder
`RCAS_TEX_BACKEND=latex`. Bilder liegen während einer Sitzung in
`/tmp/rcas` (`RCAS_CACHE_DIR`), und die von ihr erzeugten werden am Ende
gelöscht, eine Formel wird also einmal gerendert. Die Einstellungen, jede
auch als Umgebungsvariable:

| Einstellung | Umgebung | Bedeutung |
|---|---|---|
| `RCAS::Render.scale = 1.5` | `RCAS_TEX_SCALE` | Vergrößerung, 1 ist die natürliche Größe |
| `RCAS::Render.theme = "light"` | `RCAS_TEX_THEME` | Farbe des Textes; ohne Angabe aus iTerm2s Hintergrund oder `COLORFGBG` erkannt |
| `RCAS::Render.device_scale = 1` | `RCAS_TEX_DEVICE_SCALE` | Bildpunkte je Punkt, 2 für Retina-Anzeigen |
| | `RCAS_TEX_WRAP` | Zeilenbreite für den Umbruch, sonst aus der Terminalbreite abgeleitet |
| `RCAS::Render.inline = false` | `RCAS_TEX_INLINE=0` | niemals Bilder im Terminal drucken |

## Anhang B. rcas-chat

`bin/rcas-chat` ist eine zweite Oberfläche: eine Terminalsitzung mit
Eingabeaufforderung, Verlauf, gespeicherten Sitzungen und typografischem
Satz. Sie tippen Ruby und bekommen das Ergebnis als Text und, in iTerm2,
als gesetztes Bild.

```
$ bin/rcas-chat
╭─────────────────────────────────────────────────────────────╮
│ ✻ rcas 0.1.0 - symbols are indeterminates; type Ruby        │
│   output   both via katex                                   │
│   session  20260912-143012-a1b2                             │
│                                                             │
│   try      e = (x + 1) * (1 - x)                            │
│            e.expand                                         │
│            ZZ[x].(x**6 - 1).factor                          │
╰─────────────────────────────────────────────────────────────╯
──────────────────────────────────────────────────────────────
❯ e = (x + 1) * (1 - x)
=> (x + 1)*(1 - x)
   [picture]
──────────────────────────────────────────────────────────────
❯ ZZ[x].(x**6 - 1).factor
=> (-1 + x)*(1 + x)*(1 + x + x**2)*(1 - x + x**2)
   [picture]
```

Wahlweise nimmt dieselbe Eingabeaufforderung, wenn das `anthropic`-Gem
installiert und ein API-Schlüssel gesetzt ist, auch Fragen in natürlicher
Sprache entgegen (siehe „Claude“ weiter unten). Ohne beides weist nichts im
Programm darauf hin.

### Eingabe

Jede Eingabe steht beim Tippen zwischen zwei Linien; die obere bleibt im
Verlauf als Trenner zwischen den Zügen stehen. Was Sie tippen, wird nach
dem ersten Zeichen sortiert und dann danach, ob es Ruby ist:

* `/wort` ist ein Befehl (siehe die Tabelle unten), `!befehl` führt einen
  Shell-Befehl aus.
* `? frage` geht an Claude.
* Alles, was sich als Ruby lesen und ausführen lässt, wird ausgewertet,
  nach denselben Regeln wie in `bin/rcas`: bloße Namen sind Variablen, die
  Funktionen und Mengen sind verfügbar, `_` ist das letzte Ergebnis.
  Unvollständiges Ruby (ein offenes `def`, eine offene Klammer oder
  Zeichenkette) läuft in der nächsten Zeile weiter.
* Alles andere ist eine Frage an Claude. Auch eine Zeile, die sich als Ruby
  lesen lässt, aber an einem unbekannten Namen scheitert und wie ein Satz
  klingt („what is x squared“), wird als Frage behandelt.

Die Tabulatortaste vervollständigt Befehlsnamen, Variablen und häufige
Methodennamen; der Eingabeverlauf liegt in `~/.rcas/history`. Ein Rädchen
dreht sich, während Ruby rechnet, während Claude nachdenkt und während
einer seiner Aufrufe läuft; ein Ergebnis, das länger als ein, zwei Sekunden
gebraucht hat, wird von seiner Zeit gefolgt.

### Claude

Dieser Abschnitt gilt nur, wenn das `anthropic`-Gem installiert und
`ANTHROPIC_API_KEY` (oder ein Profil aus `ant auth login`) vorhanden ist;
das Begrüßungsfeld zeigt dann eine `model`-Zeile, `/help` listet die
untenstehenden Befehle, und eine Zeile, die kein Ruby ist, wird als Frage
geschickt. Claude antwortet, indem es rcas-Code in Ihrer Sitzung ausführt
und jeden Aufruf mit seinem Ergebnis zeigt:

```
❯ factor x**6 - 1 over the integers
⏺ rcas_eval(ZZ[x].(x**6 - 1).factor)
  ⎿  => (-1 + x)*(1 + x)*(1 + x + x**2)*(1 - x + x**2)
   [picture]
⏺ Four irreducible factors over ZZ; over QQ the factorization is the same.
```

Fragen beantwortet `claude-opus-5` (zu ändern mit `/model`, `--model` oder
`RCAS_MODEL`). Claude hat ein einziges Werkzeug, `rcas_eval`, das Ruby in
Ihrer Sitzung auswertet: es sieht Ihre Variablen und Annahmen, und was es
definiert, bleibt definiert, nach einer Faktorisierung können Sie also mit
`_` oder den Variablen weiterarbeiten, die es angelegt hat. Jeder Aufruf
erscheint als `⏺ rcas_eval(code)` mit dem Ergebnis darunter, und
Ergebnisse, die Claude anzeigen lässt, werden gesetzt wie Ihre eigenen. Die
Antwort selbst bleibt kurz.

Die Zugangsdaten kommen aus dem SDK: `ANTHROPIC_API_KEY` oder ein Profil aus
`ant auth login`. Lehnt Claude eine Anfrage ab, weicht die Schnittstelle
serverseitig auf `claude-opus-4-8` aus; `/fallbacks off` oder
`RCAS_FALLBACKS=0` schaltet das ab. `/cost` zeigt die verbrauchten Token der
Sitzung mit einem groben Preis, `/compact` vergisst das Gespräch und behält
Ihre Variablen.

### Ausgabemodi

`/output` wählt, wie Ergebnisse gezeigt werden, für Ihr eigenes Ruby wie
für Claudes Aufrufe:

| Modus | zeigt |
|---|---|
| `text` | nur den einfachen rcas-Text (die Voreinstellung außerhalb von iTerm2) |
| `tex` | nur das gesetzte Bild, Text, wenn ein Wert keine LaTeX-Form hat |
| `both` | Text, dann das Bild (die Voreinstellung in iTerm2) |
| `latex` | Text, dann den LaTeX-Quelltext |

Grafiken sind in jedem Modus voreingestellt Braille-Kunst. `/plotstyle image`
zeigt sie stattdessen als Bilder, wo Terminal und Chrome es erlauben (sonst
bleibt die Kunst stehen, und der Befehl sagt das); `/show plot(...)`
zeichnet unabhängig vom Stil ein Bild, und `/png plot(...) DATEI` schreibt
es. `RCAS_PLOT_STYLE` setzt die Voreinstellung außerhalb einer Sitzung.

`/backend katex|latex`, `/scale N` und `/theme dark|light` sind die
Einstellungen aus Anhang A; `/settings` zeigt sie, `/settings save`
schreibt sie als Voreinstellungen für spätere Sitzungen nach
`~/.rcas/settings.json`, und `/settings reset` löscht diese Datei.
`/latex AUSDRUCK` druckt das LaTeX eines Ausdrucks, `/show AUSDRUCK` setzt
einen unabhängig vom Modus, `/png AUSDRUCK DATEI` schreibt eine Datei.

### Hilfe

`/help` listet die Befehle; `/help factor`, `/help ZZ`, `/help Matrix` oder
`/help /output` erklären einen Namen. Das meiste davon wird in dem
Augenblick aus dem Quelltext gelesen, in dem Sie fragen: die `def`-Zeile,
der Kommentar darüber (rcas dokumentiert jede öffentliche Funktion so) und
die Handbuchabschnitte, die den Namen nennen; es kann also nicht vom Code
abweichen. `maths:` und `method:` ergänzen den mathematischen Hintergrund:
was die Operation ist und wie rcas sie berechnet. `sources:` schreibt die
Literaturangaben aus Abschnitt 4 vollständig aus, und `read:` verweist auf
den englischen Wikipedia-Artikel zum Thema für eine erste Orientierung.
`doc(:factor)` zeigt dasselbe in `bin/rcas`.

```
❯ /help gcd
  gcd(f, g)
    gcd(f, g), lcm(f, g) of integers or polynomials
  also: e.gcd
  maths: The greatest common divisor: the polynomial (or integer) of
         largest degree dividing both, unique up to a unit.
  method: Euclid's algorithm with primitive pseudo-remainder sequences,
          which keeps the coefficients from blowing up [Knu98, §4.6.1],
          [GCL92].
  sources: [Knu98] D. E. Knuth, The Art of Computer Programming, vol. 2:
           Seminumerical Algorithms, 3rd ed., Addison-Wesley 1998
           [GCL92] K. O. Geddes, S. R. Czapor, G. Labahn, Algorithms for
           Computer Algebra, Kluwer 1992
  read: https://en.wikipedia.org/wiki/Euclidean_algorithm
        https://en.wikipedia.org/wiki/Polynomial_greatest_common_divisor
  manual: 1.6 Polynomial rings; Integers and primes; gcd and division of expressions
```

### Fehler

Ein Fehler erscheint in einer Zeile. Ein `ArgumentError` aus einer
rcas-Funktion kommt mit einem Hinweis zur Benutzung, der aus dem
Dokumentationskommentar der Funktion stammt: der Signatur und dem Beispiel,
das er gibt.

```
❯ sum(x)
  ArgumentError: sum: which variable?
  usage: sum(f, k = nil, from = nil, to = nil, **range)
  sum(k**2, k, 1, n) or sum(k**2, k: 1..n); an endless range means infinity
```

Claude bekommt denselben Hinweis, wenn einer seiner Aufrufe scheitert, und
kann sich so selbst berichtigen. Bereichsfehler (`DomainError`) beschreiben
die Mathematik statt des Aufrufs und kommen ohne Hinweis.

### Sitzungen

Jede Eingabe wird nach `~/.rcas/sessions/<id>.json` (`RCAS_SESSION_DIR`)
gesichert: der Verlauf, das Gespräch mit Claude und die Einstellungen.
Variablen werden nicht gespeichert; sie entstehen neu, indem beim
Fortsetzen das Ruby der Sitzung noch einmal abgespielt wird, Claudes
Aufrufe eingeschlossen.

* `/rename NAME` benennt die laufende Sitzung. Unbenannte Sitzungen laufen
  unter ihrer ersten Eingabe.
* `/resume` öffnet eine Auswahl über die anderen gespeicherten Sitzungen:
  Pfeiltasten oder Strg-N/Strg-P bewegen, Tippen filtert nach Name, erster
  Eingabe oder Kennung, Eingabetaste setzt fort, Esc bricht ab. Jede Zeile
  zeigt, wann die Sitzung zuletzt benutzt wurde, wie viele Eingaben sie hat,
  ihren Namen und ihre erste Frage. Das Fortsetzen zeigt den jüngsten
  Verlauf der Sitzung und führt sie dann weiter.
* `/resume NAME` wechselt unmittelbar; eine Kennung, ein eindeutiger Anfang
  von beidem oder eine Nummer aus `/sessions` gehen genauso.
* `rcas-chat --continue` öffnet die jüngste Sitzung wieder, `rcas-chat
  --resume` öffnet die Auswahl und `rcas-chat --resume NAME` setzt nach
  Namen fort.
* `/save [DATEI]` schreibt einen Markdown-Verlauf mit dem LaTeX jedes
  Ergebnisses; `/reset` beginnt eine frische Sitzung.

### Befehle

```
/help [NAME]                      these commands, or what one name does
/output [text|tex|both|latex]     how results are shown
/backend [katex|latex]            typesetting backend
/scale N                          zoom factor for pictures
/theme dark|light                 colour of the pictures
/plotstyle [text|image]           how plots are shown
/unicode [on|off]                 print ℤ, π and ∞ instead of ZZ, pi and oo
/numbered [on|off]                number the session's lines in the prompt (on)
/latex EXPR   /show EXPR   /png EXPR FILE
/ask TEXT                         ask Claude (also: ? TEXT)        [with Claude configured]
/vars                             the session's variables
/assumptions   /forget [x ...]    variable domains
/model [ID]   /fallbacks [on|off]   /cost   /compact   [with Claude configured]
/sessions   /resume [NAME|ID|N]   /rename NAME   /reset   /save [FILE]
/clear   /exit                    (Ctrl-D also leaves)
!CMD                              run a shell command
```

### Optionen und Umgebung

```
rcas-chat [-c|--continue] [-r|--resume [NAME|ID]] [--model ID]
          [--output=MODE] [--tex|--no-tex] [--backend=katex|latex] [--no-color]
```

| Variable | Bedeutung |
|---|---|
| `ANTHROPIC_API_KEY` | Zugangsdaten für Claude (oder ein Profil aus `ant auth login`) |
| `RCAS_MODEL` | voreingestelltes Modell |
| `RCAS_FALLBACKS=0` | kein serverseitiges Ausweichen bei Ablehnungen |
| `RCAS_SESSION_DIR` | wo Sitzungen gespeichert werden |
| `RCAS_TEX_*`, `RCAS_CACHE_DIR`, `RCAS_NODE`, `RCAS_CHROME` | typografischer Satz, siehe Anhang A |
| `NO_COLOR` | schlichte Ausgabe |

### Dateien

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
