# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class PlotTest < Minitest::Test
  X = RCAS::Var.new(:x)

  def test_braille_cells
    canvas = RCAS::Plot::Canvas.new(1, 1)
    assert_equal ["⠀"], canvas.rows, "an empty cell is blank braille"
    canvas.set(0, 0)
    assert_equal ["⠁"], canvas.rows
    canvas.set(1, 3)
    assert_equal ["⢁"], canvas.rows, "the lower right dot is bit 8"
    full = RCAS::Plot::Canvas.new(1, 1)
    (0..1).each { |px| (0..3).each { |py| full.set(px, py) } }
    assert_equal ["⣿"], full.rows
    outside = RCAS::Plot::Canvas.new(1, 1)
    [[-1, 0], [0, -1], [2, 0], [0, 4]].each { |px, py| outside.set(px, py) }
    assert_equal ["⠀"], outside.rows, "pixels outside the canvas are dropped"
  end

  def test_a_straight_line_is_drawn_exactly
    plot = RCAS.plot(X, x: 0..1, y: 0..1, width: 4, height: 2)
    assert_equal <<~ART.chomp, plot.to_s
      1 ┤⠀⠀⡠⠊
      0 ┤⡠⠊⠁⠀
        └────
         0  1
    ART
  end

  def test_axes_are_drawn_when_zero_is_in_range
    inside = RCAS::Plot::Canvas.new(6, 2)
    RCAS.plot(X, x: -1..1, y: -1..1, width: 6, height: 2).draw_axes(inside)
    refute_equal "⠀" * 12, inside.rows.join, "the dotted guides mark the axes"
    outside = RCAS::Plot::Canvas.new(6, 2)
    RCAS.plot(X, x: 1..2, y: 1..2, width: 6, height: 2).draw_axes(outside)
    assert_equal "⠀" * 12, outside.rows.join, "no guides when the origin is outside the picture"
  end

  def test_ranges_and_gaps
    plot = RCAS.plot(RCAS.sin(X))
    assert_equal [-10.0, 10.0], [plot.xlo, plot.xhi], "the default range is -10..10"
    assert_in_delta(-1.1, plot.ylo, 1e-3)
    assert_in_delta 1.1, plot.yhi, 1e-3
    given = RCAS.plot(X**2, x: -2..2, y: 0..3)
    assert_equal [0.0, 3.0], [given.ylo, given.yhi]
    # sqrt(x) is undefined on the left half: those samples are gaps
    root = RCAS.plot(RCAS.sqrt(X), x: -1..1)
    points = root.curves.first.points
    assert points.first(150).all?(&:nil?), "no points where the function is complex"
    assert points.last(150).none?(&:nil?)
    assert_in_delta 0.0, root.ylo, 0.06
  end

  def test_poles_break_the_line
    plot = RCAS.plot(1 / X, x: -3..3, width: 30, height: 10)
    assert plot.ylo > -20 && plot.yhi < 20, "the y range is trimmed around the pole, got #{plot.ylo}..#{plot.yhi}"
    pieces = plot.segments(plot.curves.first)
    assert_equal 2, pieces.size, "one piece on each side of the pole"
    assert pieces.first.all? { |x, _| x.negative? } && pieces.last.all? { |x, _| x.positive? }
    assert pieces.first.all? { |_, y| y.negative? } && pieces.last.all? { |_, y| y.positive? }
  end

  def test_several_curves_and_labels
    plot = RCAS.plot([RCAS.sin(X), RCAS.cos(X)], x: 0..1, width: 20, height: 4)
    assert_equal ["sin(x)", "cos(x)"], plot.curves.map(&:label)
    assert_includes plot.to_s, "sin(x), cos(x)"
    titled = RCAS.plot(X, x: 0..1, title: "a line", labels: ["id"], width: 10, height: 3)
    assert titled.to_s.start_with?("a line\n")
    assert_includes titled.to_s, "id"
  end

  def test_distributions_and_data
    normal = RCAS.plot(RCAS.Normal(0, 1), width: 20, height: 5)
    assert_equal "Normal(0, 1)", normal.title
    assert_equal [-4.0, 4.0], [normal.xlo, normal.xhi], "mean plus or minus four standard deviations"
    assert_equal 0.0, normal.ylo.round(6).abs.zero? ? 0.0 : normal.ylo.round(6) if normal.ylo.positive?
    binomial = RCAS.plot(RCAS.Binomial(10, Rational(1, 2)), width: 20, height: 5)
    assert_equal [0.0, 10.0], [binomial.xlo, binomial.xhi], "a discrete density is drawn over its support"
    assert_equal :stem, binomial.curves.first.marker
    assert_equal 11, binomial.curves.first.points.size
    points = RCAS.scatter([1, 2, 3], [2, 4, 7], width: 20, height: 5)
    assert_equal :dot, points.curves.first.marker
    assert_equal [[1.0, 2.0], [2.0, 4.0], [3.0, 7.0]], points.curves.first.points
    assert_in_delta 0.9, points.xlo, 1e-9
    same = RCAS.scatter([[1, 2], [2, 4], [3, 7]], width: 20, height: 5)
    assert_equal points.curves.first.points, same.curves.first.points
  end

  def test_svg_and_files
    svg = RCAS.plot([RCAS.sin(X), RCAS.cos(X)], x: 0..1, title: "two & one").to_svg
    assert svg.start_with?("<svg xmlns=")
    assert svg.end_with?("</svg>")
    assert_equal 2, svg.scan("<polyline").size
    assert_includes svg, "two &amp; one", "the title is escaped"
    assert_includes svg, "sin(x)"
    stems = RCAS.plot(RCAS.Binomial(5, Rational(1, 2))).to_svg
    assert_equal 6, stems.scan("<circle").size
    Dir.mktmpdir("rcas-plot-test") do |dir|
      file = File.join(dir, "p.svg")
      assert_equal file, RCAS.plot(X, x: 0..1).save(file)
      assert File.read(file).start_with?("<svg")
    end
  end

  def test_expression_method_and_errors
    assert_equal RCAS.plot(X**2, x: -1..1).to_s, (X**2).plot(x: -1..1).to_s
    assert_equal RCAS.plot(X**2, :x, -1, 1).to_s, RCAS.plot(X**2, x: -1..1).to_s
    assert_raises(ArgumentError) { RCAS.plot(RCAS::Num.new(2)) }
    assert_raises(ArgumentError) { RCAS.plot(X * RCAS::Var.new(:y)) }
    assert_raises(ArgumentError) { RCAS.plot(X, x: 1..1) }
    assert_raises(RCAS::Plot::Error) { RCAS.plot(RCAS.log(X), x: -3..-1) }
    assert_raises(ArgumentError) { RCAS.scatter([1, 2], [1]) }
  end
def test_style_and_pictures
  assert_equal :text, RCAS::Plot.style, "text art is the default"
  refute RCAS::Plot.image?
  RCAS::Plot.style = "image"
  assert RCAS::Plot.image?
  assert_equal :image, RCAS::Plot.style
  assert_raises(RCAS::Plot::Error) { RCAS::Plot.style = :ascii }
  assert_equal :image, RCAS::Plot.style, "a bad value leaves the style alone"
  # a StringIO is not a terminal, so no picture can be drawn there
  plot = RCAS.plot(X, x: 0..1, width: 6, height: 2)
  refute RCAS::Plot.pictures?(StringIO.new)
  refute plot.picture?(StringIO.new)
  out = StringIO.new
  refute plot.picture(io: out)
  assert_equal "", out.string
  plot.show(io: out)
  assert_equal plot.to_s + "\n", out.string, "show falls back to the text art"
ensure
  RCAS::Plot.style = :text
end
  DATA = [2, 4, 4, 4, 5, 5, 7, 9, 3, 6, 5, 4, 8, 5, 6, 2, 7, 5, 4, 6].freeze

  def test_histogram
    plot = RCAS.histogram(DATA, bins: 4)
    curve = plot.curves.first
    assert_equal :bar, curve.marker
    assert_equal 4, curve.points.size
    assert_equal DATA.size, curve.points.sum { |_, count| count }, "every value falls in a bin"
    assert_equal [2.0, 9.0], [plot.xlo, plot.xhi]
    assert_equal 0.0, plot.ylo, "counts stand on zero"
    assert_equal plot.yhi, plot.yhi.round, "the top of a count axis is a whole number"
    assert_in_delta 1.75, curve.width, 1e-9, "four bins over 2..9"
    # Sturges' rule sets the default
    assert_equal Math.log2(DATA.size).ceil + 1, RCAS.histogram(DATA).curves.first.points.size
    shares = RCAS.histogram(DATA, bins: 4, density: true).curves.first
    assert_in_delta 1.0, shares.points.sum { |_, v| v }, 1e-12
    flat = RCAS.histogram([3, 3, 3]).curves.first
    assert_equal 3, flat.points.sum { |_, c| c }, "a constant sample is counted, not dropped"
    assert_raises(ArgumentError) { RCAS.histogram(DATA, bins: 0) }
    assert_raises(ArgumentError) { RCAS.histogram([]) }
  end

  def test_boxplot
    plot = RCAS.boxplot([2, 4, 5, 5, 6, 7, 20])
    low, q1, median, q3, high = plot.curves.first.points.first(5).map(&:first)
    assert_equal [2.0, 4.5, 5.0, 6.5, 7.0], [low, q1, median, q3, high]
    outliers = plot.curves.first.points.drop(5).map(&:first)
    assert_equal [20.0], outliers, "1.5 interquartile ranges beyond the box"
    assert_equal :box, plot.curves.first.marker
    named = RCAS.boxplot("before" => [1, 2, 3, 4], "after" => [2, 3, 4, 5])
    assert_equal %w[after before], named.ylabels.values.sort
    assert_equal 2, named.curves.size
    listed = RCAS.boxplot([[1, 2, 3], [4, 5, 6]])
    assert_equal %w[1 2], listed.ylabels.values.sort
    assert_includes named.to_s, "before ┤"
    assert_raises(ArgumentError) { RCAS.boxplot(3) }
  end

  def test_barchart
    plot = RCAS.barchart(RCAS.frequencies([:a, :b, :a, :c, :a, :b]))
    assert_equal [[1.0, 3.0], [2.0, 2.0], [3.0, 1.0]], plot.curves.first.points
    assert_equal %w[a b c], plot.xlabels.map(&:last)
    assert_includes plot.to_s.lines[-1], "a"
    same = RCAS.barchart(%w[a b c], [3, 2, 1])
    assert_equal plot.curves.first.points, same.curves.first.points
    assert_equal 0.0, plot.ylo
    assert_raises(ArgumentError) { RCAS.barchart(%w[a b], [1]) }
    assert_raises(ArgumentError) { RCAS.barchart({}) }
  end

  def test_scatter_with_a_fitted_line
    plot = RCAS.scatter([1, 2, 3, 4], [2, 4, 7, 8], fit: true)
    assert_equal 2, plot.curves.size
    assert_equal :dot, plot.curves.first.marker
    assert_equal "21*x/10", plot.curves.last.label, "exact data gives an exact line"
    assert_equal RCAS.linreg([1, 2, 3, 4], [2, 4, 7, 8]).to_s, plot.curves.last.label
    assert_includes plot.to_s, "21*x/10"
    assert_equal 1, RCAS.scatter([1, 2, 3, 4], [2, 4, 7, 8]).curves.size
  end

  def test_statistical_plots_as_svg
    svg = RCAS.histogram(DATA, bins: 4).to_svg
    assert_equal 4, svg.scan("<rect").size - 2, "one rectangle per bin, besides the background and the frame"
    boxes = RCAS.boxplot("a" => [1, 2, 3, 4, 99]).to_svg
    assert_includes boxes, "<circle", "the outlier is drawn"
    assert_includes RCAS.barchart({ "x" => 2, "y" => 5 }).to_svg, "<rect"
  end
  def test_parametric_and_polar
    circle = RCAS.parametric([RCAS.cos(:t), RCAS.sin(:t)], t: 0..2 * RCAS::PI, width: 20, height: 8)
    points = circle.curves.first.points.compact
    assert_in_delta 1.0, points.map { |x, y| Math.sqrt(x * x + y * y) }.max, 1e-9, "every point is on the unit circle"
    assert_in_delta(-1.0, circle.x_range.first, 0.2)
    assert_includes circle.to_s, "\u2800", "braille art"

    cardioid = RCAS.polar(1 + RCAS.cos(:t), width: 20, height: 8)
    xs = cardioid.curves.first.points.compact.map(&:first)
    assert_in_delta 2.0, xs.max, 1e-9, "r = 2 at the angle zero"
    assert_in_delta(-0.25, xs.min, 1e-4, "the dimple of the cardioid, up to the sampling")

    spiral = RCAS.polar(:t, t: 0..4 * RCAS::PI, width: 20, height: 8)
    assert_equal 401, spiral.curves.first.points.size

    assert_raises(ArgumentError) { RCAS.parametric([:t], t: 0..1) }
    assert_raises(ArgumentError) { RCAS.parametric([:t, :t], t: 0..RCAS::OO) }
  end
  # A segment with both ends outside the picture is the run-up to a pole or
  # the leap across one; drawing it left a vertical stroke at the frame edge
  # where the graph has no line at all. And a few samples beside a pole must
  # not decide the scale for everything else.
  def test_a_pole_breaks_the_line_and_does_not_set_the_scale
    x = RCAS::Var.new(:x)
    plot = RCAS.plot(1 / x, x, -2, 2)
    assert_operator plot.yhi, :<, 10, "the scale follows the hyperbola, not the pole"
    assert_operator plot.yhi, :>, 2
    # the two branches are separate segments in the SVG as well
    assert_equal 2, plot.send(:segments, plot.curves.first).size
    # a function without a pole keeps its own range
    parabola = RCAS.plot(x**2, x, -3, 3)
    assert_in_delta 9.0, parabola.yhi, 1.0
    assert_equal 1, parabola.send(:segments, parabola.curves.first).size
  end

end
