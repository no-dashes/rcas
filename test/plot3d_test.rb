# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class Plot3dTest < Minitest::Test
  X = RCAS::Var.new(:x)
  Y = RCAS::Var.new(:y)

  def sphere(**opts)
    u = RCAS::Var.new(:u)
    v = RCAS::Var.new(:v)
    components = [RCAS.cos(u) * RCAS.sin(v), RCAS.sin(u) * RCAS.sin(v), RCAS.cos(v)]
    RCAS.plot3d(components, u: 0..2 * RCAS::PI, v: 0..RCAS::PI, **opts)
  end

  def test_a_surface_is_a_plot
    surface = RCAS.plot3d(X * Y, x: -1..1, y: -1..1)
    assert_kind_of RCAS::Plot, surface, "the chat and the window show anything that is a Plot"
    assert_equal surface.to_s, surface.inspect
    assert_includes surface.to_s, "⠀", "braille art"
    assert_equal [-1.0, 1.0], [surface.xlo, surface.xhi]
    assert_equal(surface.zlo..surface.zhi, surface.z_range)
    assert_equal %w[x y z], surface.axes
  end

  # The projection is the one the comment describes: across the picture runs
  # (-sin a, cos a, 0), up it runs the cross product with the line of sight,
  # and the depth grows towards the viewer.
  def test_the_projection_from_straight_ahead
    surface = RCAS.plot3d(X * Y, x: -1..1, y: -1..1, z: -1..1, view: [0, 0])
    assert_equal [0.0, 0.0, 0.0], surface.project([0, 0, 0]).map { |c| c.round(9) }
    assert_equal [0.5, 0.0, 0.0], surface.project([0, 1, 0]).map { |c| c.round(9) }, "y runs across"
    assert_equal [0.0, 0.5, 0.0], surface.project([0, 0, 1]).map { |c| c.round(9) }, "z runs up"
    assert_equal [0.0, 0.0, 0.5], surface.project([1, 0, 0]).map { |c| c.round(9) }, "x runs towards the eye"
    # from above, everything of the same height is at the same depth
    from_above = RCAS.plot3d(X * Y, x: -1..1, y: -1..1, z: -1..1, view: [0, 90])
    assert_equal [0.0, -0.5, 0.0], from_above.project([1, 0, 0]).map { |c| c.round(9) }
    assert_equal [0.0, 0.0, 0.5], from_above.project([0, 0, 1]).map { |c| c.round(9) }
  end

  # A turn of the view moves the surface round without stretching it, so the
  # picture keeps one scale for both screen directions.
  def test_the_two_screen_directions_keep_one_scale
    surface = RCAS.plot3d(X * Y, x: -1..1, y: -1..1, view: [37, 24])
    a = surface.screen([0.0, 0.0], 200, 200)
    b = surface.screen([0.1, 0.1], 200, 200)
    assert_in_delta((b[0] - a[0]).abs, (a[1] - b[1]).abs, 1e-9, "one scale for both directions")
    assert_operator surface.scale_for(200, 400), :>, surface.scale_for(200, 200), "the narrow side decides"
  end

  def test_the_mesh_and_its_faces
    surface = RCAS.plot3d(X + Y, x: 0..1, y: 0..1, n: 6)
    assert_equal [6, 6], [surface.rows, surface.columns]
    assert_equal 36, surface.faces.size
    assert surface.faces.all? { |f| surface.polygon(f) }, "a plane has no holes"
    assert_equal 4, surface.faces(3).size, "taken every third point, the mesh is two by two"
    depths = surface.faces.map(&:depth)
    assert_equal depths.sort, depths, "farthest first, so a nearer face paints over it"
    heights = surface.faces.map(&:height)
    assert_in_delta 0.0, heights.min, 0.2
    assert_in_delta 2.0, heights.max, 0.2, "the height of a face is the mean of its corners"
  end

  # The terminal takes the mesh coarsely - braille dots closer than APART
  # merge - while a picture takes every line of it.
  def test_the_terminal_takes_a_coarser_mesh
    surface = RCAS.plot3d(X + Y, x: 0..1, y: 0..1, n: 24)
    assert_operator surface.terminal_step, :>, 1
    assert_operator surface.faces(surface.terminal_step).size, :<, surface.faces.size
    assert_equal [0, 3, 6, 9, 12, 15, 18, 21, 24], surface.indices(24, 3)
    assert_equal [0, 4, 8, 10], surface.indices(10, 4), "the last point closes the rim"
    assert_equal (0..5).to_a, surface.indices(5, 1), "never finer than the mesh itself"
    assert_equal 1, RCAS.plot3d(X + Y, x: 0..1, y: 0..1, n: 4).terminal_step, "a coarse mesh is left alone"
  end

  # The depth sort: a face rubs out what lies inside it before drawing its own
  # edges, so the far wall of the box does not shine through the surface.
  def test_a_face_rubs_out_what_is_behind_it
    surface = RCAS.plot3d(X + Y, x: 0..1, y: 0..1, n: 4, width: 20, height: 5)
    canvas = RCAS::Plot::Canvas.new(20, 5)
    (0...canvas.pixel_width).each { |px| canvas.line(px, 0, px, canvas.pixel_height - 1) }
    dots = ->(c) { c.rows.join.chars.sum { |ch| (ch.ord - RCAS::Plot::BRAILLE_BLANK).digits(2).sum } }
    before = dots.call(canvas)
    face = surface.faces.find { |f| surface.polygon(f) }
    surface.erase(canvas, surface.polygon(face))
    assert_operator dots.call(canvas), :<, before, "the dots inside the face are gone"
    corner = surface.pixel(surface.polygon(face).first)
    refute set_at?(canvas.rows, corner[0], corner[1]), "its own corner among them"
  end

  # The same in the picture as a whole: the vertical post of the box stands at
  # the far corner, and the surface in front of it hides its lower half.
  def test_the_box_is_hidden_behind_the_surface
    round = sphere(width: 48, height: 16)
    foot, top = round.box_edges[4] # the four floor edges come first, then the post
    art = round.to_s.lines
    column = round.pixel(foot).first
    drawn = (round.pixel(top).last..round.pixel(foot).last).count { |py| set_at?(art, column, py) }
    assert drawn.positive?, "the post is drawn above the sphere"
    assert drawn < round.pixel(foot).last - round.pixel(top).last,
           "and rubbed out where the sphere stands in front of it"
  end

  # A point the function has no real value at is a hole, and so is one the z
  # range cuts off: the surface is torn there rather than stitched shut.
  def test_holes_and_clipping
    dome = RCAS.plot3d(RCAS.sqrt(1 - X**2 - Y**2), x: -1..1, y: -1..1, n: 8)
    torn = dome.faces.count { |f| dome.polygon(f).nil? }
    assert torn.positive?, "the corners of the square are outside the disc"
    assert dome.faces.count { |f| dome.polygon(f) }.positive?

    cut = RCAS.plot3d(X**2 + Y**2, x: -2..2, y: -2..2, z: 0..1, n: 8)
    assert_equal [0.0, 1.0], [cut.zlo, cut.zhi]
    assert cut.faces.count { |f| cut.polygon(f).nil? }.positive?, "the bowl leaves the box at the corners"
    assert cut.faces.all? { |f| f.height.between?(0.0, 1.0) }
  end

  def test_the_ranges_and_the_caption
    default = RCAS.plot3d(X * Y)
    assert_equal [-10.0, 10.0, -10.0, 10.0], [default.xlo, default.xhi, default.ylo, default.yhi],
                 "-10..10 in both when no range is given"
    named = RCAS.plot3d(RCAS.sin(:a) * :b, a: 0..1, b: 2..3, n: 8)
    assert_equal %w[a b z], named.axes, "the axes are named after the variables"
    assert_equal "a: 0..1   b: 2..3   z: #{RCAS::Plot.label(named.zlo)}..#{RCAS::Plot.label(named.zhi)}",
                 named.caption
    assert_equal named.caption, named.to_s.lines.last.chomp
  end

  # A surface in space keeps its shape: all three axes are scaled alike, so a
  # sphere is round. A graph z = f(x, y) fills the box instead, since its
  # height is not measured in the units of its base.
  def test_equal_scales_for_a_surface_in_space
    round = sphere(n: 12)
    assert_equal 1, round.spans.uniq.size, "one scale for x, y and z"
    assert_in_delta 1.0, round.faces.map { |f| f.corners.compact.map { |c| c[0].abs }.max }.max * 2, 0.3
    flat = RCAS.plot3d(X * Y / 100, x: -1..1, y: -1..1, n: 8)
    assert_equal 2.0, flat.spans[0]
    assert_operator flat.spans[2], :<, 0.1, "a shallow graph still fills the box"
    stretched = RCAS.plot3d(X * Y / 100, x: -1..1, y: -1..1, n: 8, equal: true)
    assert_equal [2.0] * 3, stretched.spans, "equal: true measures all three alike"
  end

  def test_a_parametric_surface
    round = sphere(n: 16)
    points = round.faces.flat_map { |f| f.corners.compact }
    refute_empty points
    assert_in_delta 1.1, round.xhi, 0.02
    assert_in_delta(-1.1, round.zlo, 0.02)
    assert_equal %w[x y z], round.axes, "the axes of a parametrization are the coordinates of space"
    # a torus: the hole means faces on the far side are painted first
    u = RCAS::Var.new(:u)
    v = RCAS::Var.new(:v)
    torus = RCAS.plot3d([(2 + RCAS.cos(v)) * RCAS.cos(u), (2 + RCAS.cos(v)) * RCAS.sin(u), RCAS.sin(v)],
                        u: 0..2 * RCAS::PI, v: 0..2 * RCAS::PI, n: 12)
    assert_in_delta 1.1, torus.zhi, 0.05, "the tube has radius one"
    assert_in_delta 3.3, torus.xhi, 0.05
  end

  def test_pictures
    surface = RCAS.plot3d(X**2 - Y**2, x: -1..1, y: -1..1, n: 6, title: "a saddle")
    svg = surface.to_svg(theme: "light")
    assert svg.start_with?("<svg"), "an SVG picture"
    assert_equal 36, svg.scan("<polygon").size, "one polygon per face, painted back to front"
    assert_includes svg, "a saddle"
    assert_includes svg, surface.caption
    assert_equal 7, svg.scan("<line").size, "the floor of the box, its post and the two top edges"
    Dir.mktmpdir("rcas-plot3d") do |dir|
      path = File.join(dir, "saddle.svg")
      assert_equal path, surface.save(path)
      assert File.read(path).start_with?("<svg")
    end
  end

  # The colour of a face follows its height, from the floor of the box to the
  # top of it, so a flat picture does not lose what the third axis said.
  def test_the_height_ramp
    surface = RCAS.plot3d(X + Y, x: 0..1, y: 0..1, n: 4)
    assert_equal RCAS::Plot3D::RAMP.first, surface.shade(surface.zlo)
    assert_equal RCAS::Plot3D::RAMP.last, surface.shade(surface.zhi)
    assert_equal RCAS::Plot3D::RAMP[1], surface.shade((surface.zlo + surface.zhi) / 2)
    assert_equal RCAS::Plot3D::RAMP.first, surface.shade(surface.zlo - 100), "clamped at both ends"
    assert_equal "#808080", surface.blend("#000000", "#ffffff", 0.5)
  end

  def test_what_it_refuses
    assert_raises(ArgumentError) { RCAS.plot3d(X * Y, x: -1..1) }
    assert_raises(ArgumentError) { RCAS.plot3d(X * Y, x: -1..1, y: -1..1, n: 0) }
    assert_raises(ArgumentError) { RCAS.plot3d(X * Y, x: -1..1, y: 1..1) }
    assert_raises(ArgumentError) { RCAS.plot3d(X * Y, x: -1..1, y: 0..RCAS::OO) }
    assert_raises(ArgumentError) { RCAS.plot3d(X * Y, x: -1..1, y: -1..1, view: [0]) }
    assert_raises(ArgumentError) { RCAS.plot3d([X, Y], u: 0..1, v: 0..1) }
    assert_raises(ArgumentError) { RCAS.plot3d([X, Y, X], u: 0..1) }
    one = assert_raises(ArgumentError) { RCAS.plot3d(RCAS.sin(X)) }
    assert_includes one.message, "a surface needs two"
    assert_raises(RCAS::Plot::Error) { RCAS.plot3d(RCAS.log(X + Y), x: -3..-2, y: -3..-2) }
  end

  private

  # Is the braille dot at this pixel set? +rows+ are art lines, no title.
  def set_at?(rows, px, py)
    row = rows[py / 4]
    return false if row.nil?
    cell = row.chars[px / 2]
    return false if cell.nil?
    (cell.ord - RCAS::Plot::BRAILLE_BLANK) & RCAS::Plot::DOTS[px % 2][py % 4] != 0
  end
end
