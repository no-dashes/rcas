# frozen_string_literal: true

require_relative "test_helper"

class LatexTest < Minitest::Test
  include RCAS::Sets

  def setup
    RCAS.forget
  end

  def teardown
    RCAS.forget
  end

  def x = :x
  def y = :y

  def test_expressions_follow_the_tree
    assert_equal '\left(x + 1\right) \left(1 - x\right)', ((x + 1) * (1 - x)).to_latex
    assert_equal "1 - x^{2}", ((x + 1) * (1 - x)).expand.to_latex
    assert_equal '\frac{x + 1}{x - 1}', ((x + 1) / (x - 1)).to_latex
    assert_equal 'x - \left(y + 1\right)', (x - (y + 1)).to_latex
    assert_equal '\left(x + 1\right)^{-2}', ((x + 1)**-2).to_latex
    assert_equal "2^{x}", (2**x).to_latex
    assert_equal '\left(\frac{1}{2}\right)^{x}', ((1/2r)**x).to_latex
    assert_equal '-\left(x + 1\right)', (-(x + 1)).to_latex
    assert_equal "-2 x", (-(2 * x)).to_latex
    assert_equal 'x \cdot 2', RCAS::Mul.new(RCAS::Var.new(:x), RCAS::Num.new(2)).to_latex
  end

  def test_display_niceties
    assert_equal '2 x \cos\left(x^{2}\right)', RCAS.sin(x**2).diff(x).to_latex
    assert_equal '\frac{1}{2 \sqrt{x}}', RCAS.sqrt(x).diff(x).to_latex
    assert_equal '\sqrt[3]{x}', (x**(1/3r)).to_latex
    assert_equal '\sin^{2} x + \cos^{2} x', (RCAS.sin(x)**2 + RCAS.cos(x)**2).to_latex
    assert_equal '-e^{x} + x e^{x}', (x * RCAS.exp(x)).integrate(x).to_latex
    assert_equal '\frac{1}{1 + x}', RCAS.log(x + 1).diff(x).to_latex
    assert_equal '\arctan x', RCAS.atan(x).to_latex
    assert_equal '\operatorname{foo}\left(x, y\right)', RCAS::Fn.new(:foo, [x, y]).to_latex
    assert_equal "x - y", RCAS::Add.new(RCAS::Var.new(:x), RCAS::Neg.new(RCAS::Var.new(:y))).to_latex
    assert_equal "x - 1", RCAS::Add.new(RCAS::Var.new(:x), RCAS::Num.new(-1)).to_latex
    assert_equal '-\frac{1}{x + 1}', (RCAS::Num.new(-1) / (x + 1)).to_latex
    assert_equal '\int \left(x + 1\right)\, dx', RCAS::Integral.new(x + 1, RCAS::Var.new(:x)).to_latex
  end

  def test_variables_and_numbers
    assert_equal 'x_{1} + \alpha_{2} + \mathit{foo\_bar} + \beta', (:x_1 + :alpha2 + :foo_bar + :beta).to_latex
    assert_equal '\frac{3}{4} + \frac{x}{2}', (x / 2 + 3/4r).simplify.to_latex
    assert_equal '-\frac{1}{2}', (-1/2r).to_latex
    assert_equal '1.5 \times 10^{-7} x', (1.5e-7 * x).to_latex
    assert_equal '\left(1 - 2\,i\right) x', (Complex(1, -2) * x).to_latex
    assert_equal "i", Complex(0, 1).to_latex
    assert_equal "3", 3.to_latex
    assert_equal '\gamma', :gamma.to_latex
  end

  def test_polynomials_and_factorizations
    r = ZZ[x]
    assert_equal "-1 + x^{2}", r.(x**2 - 1).to_latex
    assert_equal '\left(-1 + x\right) \left(1 + x\right) \left(1 + x + x^{2}\right) \left(1 - x + x^{2}\right)', r.(x**6 - 1).factor.to_latex
    assert_equal '\frac{1}{4} \left(-1 + 2 x\right) \left(1 + 2 x\right)', QQ[x].(x**2 - 1/4r).factor.to_latex
    assert_equal '-\left(-1 + x\right) \left(1 + x\right)', r.(1 - x**2).factor.to_latex
    assert_equal '\left(x + y\right)^{2}', ZZ[x, y].(x**2 + 2 * x * y + y**2).factor.to_latex
  end

  def test_domains_and_spaces
    assert_equal '\mathbb{Z}', ZZ.to_latex
    assert_equal '\mathbb{N}', NN.to_latex
    assert_equal '\mathbb{Q}[x, y]', QQ[x, y].to_latex
    assert_equal '\operatorname{Frac}\left(\mathbb{Z}[x]\right)', ZZ[x].fraction_field.to_latex
    assert_equal '\mathbb{Q}^{3}', (QQ**3).to_latex
    assert_equal '\mathbb{R}^{2 \times 3}', (RR**[2, 3]).to_latex
  end

  def test_vectors_and_matrices
    # A display-size fraction is taller than one baseline distance, so a
    # matrix holding one asks for extra leading; a matrix of numbers does not.
    assert_equal '\begin{pmatrix} 1 \\\\[0.8em] \displaystyle \frac{1}{2} \\\\[0.8em] -1 \end{pmatrix}',
                 (QQ**3)[1, 1/2r, -1].to_latex
    assert_equal '\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \end{pmatrix}', (QQ**[2, 2])[[1, 2], [3, 4]].to_latex
    RCAS.assume(t: RR)
    inv = RR.matrix([[:t, 1], [1, :t]]).inverse
    assert_equal '\begin{pmatrix} \displaystyle \frac{t}{-1 + t^{2}} & \displaystyle -\frac{1}{-1 + t^{2}} \\\\[0.8em] ' \
                 '\displaystyle -\frac{1}{-1 + t^{2}} & \displaystyle \frac{t}{-1 + t^{2}} \end{pmatrix}', inv.to_latex
    assert_equal '\left[\,\right]', (QQ**[0, 0])[].to_latex
  end

  def test_collections_and_misc
    assert_equal '\left[1,\; x,\; \mathbb{Q}\right]', [1, x, QQ].to_latex
    RCAS.assume(x: ZZ, y: RR)
    assert_equal 'x \in \mathbb{Z},\; y \in \mathbb{R}', RCAS.assumptions.to_latex
    assert_equal '1 \mapsto 2', { 1 => 2 }.to_latex
    assert_equal '\mathrm{true}', RCAS::LaTeX.of(true)
    assert_equal '\text{a\_b \& c}', RCAS::LaTeX.of("a_b & c")
  end

  def test_long_sums_do_not_recurse_per_term
    e = (1..3000).map { |i| :x**i }.reduce(:+)
    assert e.to_latex.start_with?("x^{1} + x^{2} + x^{3}")
  end
end

class LatexWrapTest < Minitest::Test
  include RCAS::Sets

  def x = :x
  def y = :y

  def poly = (0..20).map { |i| (i + 1) * x**i }.reduce(:+).simplify

  def test_width_estimate
    assert_equal 8, RCAS::LaTeX.width('\frac{1}{2} + \left(x\right)^{2}')
    assert_equal 7, RCAS::LaTeX.width('\sin x + \alpha')
  end

  def test_short_expressions_are_left_alone
    assert_equal "x + 1", (x + 1).to_latex(wrap: 50)
    assert_equal poly.to_latex, poly.to_latex(wrap: 500)
    assert_equal '\mathbb{Q}', RCAS::LaTeX.of(QQ, wrap: 10)
  end

  def test_long_sums_break_into_aligned_lines
    tex = poly.to_latex(wrap: 50)
    assert tex.start_with?('\begin{aligned} & 1 + 2 x + 3 x^{2}')
    assert tex.end_with?('+ 21 x^{20} \end{aligned}')
    assert_includes tex, ' \\\\ &\quad {} + 9 x^{8}'
    lines = tex.split('\\\\')
    assert lines.size >= 3
    lines.each do |l|
      body = l.gsub(/\\(begin|end)\{aligned\}|&\\quad|&/, "").strip
      assert RCAS::LaTeX.width(body) <= 50, "line too wide: #{body}"
    end
  end

  def test_products_break_with_times
    f = ZZ[x].((1..7).map { |i| x**i + i }.reduce(:*)).factor
    tex = f.to_latex(wrap: 50)
    assert_includes tex, '\right) \\\\ &\quad {} \times \left(3 + x^{3}\right)'
    assert_equal '\begin{aligned} & -2 x y \\\\ &\quad {} \times \left(x + 1\right) \end{aligned}', (-(2 * x * y * (x + 1))).to_latex(wrap: 6)
  end

  def test_negated_sums_keep_their_fences_on_one_level
    assert_equal '-\left(\begin{aligned} & x \\\\ &\quad {} + y \\\\ &\quad {} + 1 \end{aligned}\right)', (-(x + y + 1)).to_latex(wrap: 4)
    assert_equal '-\left(x + y + 1\right)', (-(x + y + 1)).to_latex(wrap: 40)
  end

  def test_wide_arrays_go_one_element_per_line
    tex = [poly, x + 1].to_latex(wrap: 50)
    assert tex.start_with?('\left[\begin{aligned} & \begin{aligned} & 1 + 2 x')
    assert tex.end_with?(', \\\\ & x + 1 \end{aligned}\right]')
    assert_equal '\left[1,\; x\right]', [1, x].to_latex(wrap: 50)
  end

  # A stand-in for a terminal of a given size.
  Terminal = Struct.new(:columns) do
    def tty? = true
    def winsize = [40, columns]
  end

  def test_render_derives_the_width_from_the_terminal
    saved = ENV["COLUMNS"]
    ENV["COLUMNS"] = "100"
    # not a terminal: COLUMNS decides
    assert_equal 52, RCAS::Render.wrap_width(StringIO.new)
    # a terminal's own width wins over COLUMNS, which is often stale
    assert_equal 63, RCAS::Render.wrap_width(Terminal.new(120))
    # :auto takes whatever the real $stdout measures. Comparing with 52 held
    # only when $stdout was no terminal - it failed in a terminal once
    # another test had loaded io/console (which gives IO#winsize), so it
    # depended on the seed and never showed in a piped run
    assert_equal poly.to_latex(wrap: RCAS::Render.wrap_width), RCAS::Render.latex(poly, wrap: :auto)
    assert_equal poly.to_latex, RCAS::Render.latex(poly)
    ENV["COLUMNS"] = "400"
    assert_equal 200, RCAS::Render.wrap_width(StringIO.new)
  ensure
    saved ? ENV["COLUMNS"] = saved : ENV.delete("COLUMNS")
  end
end

class LatexOtherNodesTest < Minitest::Test
  def test_constants_derivatives_and_equations
    x, y = :x, :y
    assert_equal '2 \pi x', (2 * RCAS::PI * x).to_latex
    assert_equal "e", RCAS::E.to_latex
    assert_equal '\frac{d y}{dx}', RCAS::Derivative.new(y, x).to_latex
    assert_equal '\frac{d^{2} y}{dx^{2}}', RCAS::Derivative.new(y, x, 2).to_latex
    assert_equal '\frac{d}{dx}\left(x^{2} + 1\right)', RCAS::Derivative.new(x**2 + 1, x).to_latex
    eq = RCAS::Equation.new(RCAS::Derivative.new(y, x), 2 * x * y)
    assert_equal '\frac{d y}{dx} = 2 x y', eq.to_latex
    assert_equal eq.to_latex, RCAS::LaTeX.of(eq)
    assert_includes RCAS::Equation.new(y, (0..12).map { |i| x**i }.reduce(:+)).to_latex(wrap: 30), '\begin{aligned}'
  end

  def test_a_root_with_no_radical_form_keeps_its_name
    root = RCAS.solve(:x**3 - :x - 1, :x).first
    assert_instance_of RCAS::RootOf, root
    assert_equal '\operatorname{RootOf}\left(-1 - x + x^{3}, 0\right)', root.to_latex
    assert_equal root.to_s, "RootOf(#{root.poly.to_expr.subs(RCAS::Var.new(root.var) => RCAS::Var.new(:x))}, 0)"
    assert_includes RCAS::LaTeX.of(RCAS.discuss(2 * :x**2 - 4 * :x - 2 + 1 / :x, :x)), '\operatorname{RootOf}'
  end
end
