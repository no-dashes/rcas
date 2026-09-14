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
end
