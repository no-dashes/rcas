# frozen_string_literal: true

module RCAS
  # Surfaces in space.
  #
  #   plot3d(sin(x)*cos(y), x: -3..3, y: -3..3)
  #   plot3d(x**2 - y**2)                                  # -10..10 in both
  #   plot3d([cos(u)*sin(v), sin(u)*sin(v), cos(v)], u: 0..2*PI, v: 0..PI)
  #   plot3d(x*y, x: -1..1, y: -1..1, view: [30, 60])      # from somewhere else
  #
  # The surface is sampled on a rectangular mesh, every mesh point is carried
  # into the picture by a parallel (axonometric) projection, and the
  # quadrilaterals are painted from the back forwards: each one first erases
  # what lies inside it and then draws its own edges. That is the depth sort,
  # or painter's algorithm [NNS72] - there is no z buffer here, only the
  # order - and it is what makes the picture read as a solid surface rather
  # than as a transparent net.
  #
  # A Plot3D is a Plot, so it prints as braille art, `to_svg` and `save`
  # write a picture and `show` puts one in the terminal. What it has not got
  # is a pair of labelled axes: the box is drawn as its floor and the two
  # walls behind the surface, and the three ranges are named underneath.
  #
  # Sources (keys: MANUAL.md, Sources): the depth sort [NNS72]; the braille
  # canvas and the line drawing are plot.rb's.
  class Plot3D < Plot
    # Azimuth and elevation in degrees: where the surface is looked at from.
    # The default is the familiar three-quarter view from above.
    VIEW = [-60.0, 30.0].freeze

    # Low, middle and high: the colour of a face in a picture follows its
    # height, which is the one thing a flat picture loses.
    RAMP = %w[#2563eb #059669 #d97706].freeze

    # At most this many mesh lines across the terminal picture, whatever the
    # mesh: every face is painted either way, so nothing hidden becomes
    # visible, but drawing every line of a fine mesh makes a blot of it.
    LINES = 10

    # And no two of them closer than this, in braille dots: below it the
    # dots of neighbouring lines merge and the surface stops reading.
    APART = 9

    # One quadrilateral of the mesh: its four projected corners (a missing one
    # is nil), how far away it is and how high it lies. The corners are also
    # the area it covers, when it has all four.
    Face = Struct.new(:corners, :depth, :height)

    attr_reader :zlo, :zhi, :axes, :azimuth, :elevation, :mesh, :rows, :columns, :spans

    def initialize(mesh, xlo:, xhi:, ylo:, yhi:, zlo:, zhi:, axes:, equal: false,
                   view: VIEW, title: nil, width: 60, height: 20)
      @xlo = xlo
      @xhi = xhi
      @ylo = ylo
      @yhi = yhi
      @zlo = zlo
      @zhi = zhi
      @axes = axes.map(&:to_s).freeze
      @azimuth, @elevation = view.map(&:to_f)
      @title = title
      @width = width
      @height = height
      @curves = [].freeze
      @var = Var.new(@axes.first.to_sym)
      @spans = axis_spans(equal)
      @cos_azimuth = Math.cos(@azimuth * Math::PI / 180)
      @sin_azimuth = Math.sin(@azimuth * Math::PI / 180)
      @cos_elevation = Math.cos(@elevation * Math::PI / 180)
      @sin_elevation = Math.sin(@elevation * Math::PI / 180)
      @mesh = mesh.map(&:freeze).freeze
      @rows = mesh.size - 1
      @columns = mesh.map(&:size).min - 1
      @centre_u, @centre_v, @span_u, @span_v = viewport
      freeze
    end

    def z_range = (zlo..zhi)

    # ---- the projection ----------------------------------------------------

    # How much of an axis one unit of the box is. Each axis is scaled to the
    # box on its own, because the x, y and z of a graph z = f(x, y) are not
    # in the same units; +equal+ gives all three the same scale instead,
    # which is what a surface in space wants - a sphere should look round.
    def axis_spans(equal)
      lengths = [@xhi - @xlo, @yhi - @ylo, @zhi - @zlo].map { |d| d.abs < 1e-12 ? 1.0 : d.to_f }
      (equal ? [lengths.max] * 3 : lengths).freeze
    end

    # A point of space as the picture sees it: the two screen coordinates and
    # the depth, which grows towards the viewer. The eye lies in the
    # direction (cos e cos a, cos e sin a, sin e); across the picture runs
    # (-sin a, cos a, 0), and up it runs their cross product.
    def project(point)
      x, y, z = point
      nx = (x - (@xlo + @xhi) / 2.0) / @spans[0]
      ny = (y - (@ylo + @yhi) / 2.0) / @spans[1]
      nz = (z - (@zlo + @zhi) / 2.0) / @spans[2]
      flat = nx * @cos_azimuth + ny * @sin_azimuth
      [-nx * @sin_azimuth + ny * @cos_azimuth,
       nz * @cos_elevation - flat * @sin_elevation,
       flat * @cos_elevation + nz * @sin_elevation]
    end

    # The box holds everything drawn, so its eight corners fix the picture:
    # the centre and the extent of the two screen coordinates.
    def viewport
      corners = [@xlo, @xhi].product([@ylo, @yhi], [@zlo, @zhi]).map { |p| project(p) }
      us = corners.map(&:first)
      vs = corners.map { |c| c[1] }
      span = ->(lo, hi) { (hi - lo).abs < 1e-12 ? 1.0 : hi - lo }
      [(us.min + us.max) / 2.0, (vs.min + vs.max) / 2.0,
       span.call(us.min, us.max), span.call(vs.min, vs.max)]
    end

    # One scale for both directions, so that turning the view moves the
    # surface round without stretching it.
    def scale_for(w, h) = [(w - 1) / @span_u, (h - 1) / @span_v].min

    # The projection centred in a w by h rectangle.
    def screen(point, w, h, left = 0.0, top = 0.0)
      scale = scale_for(w, h)
      [left + (w - 1) / 2.0 + (point[0] - @centre_u) * scale,
       top + (h - 1) / 2.0 - (point[1] - @centre_v) * scale]
    end

    def pixel(point) = screen(point, width * 2, height * 4).map(&:round)

    # ---- the mesh ----------------------------------------------------------

    # The quadrilaterals of the mesh, every +step+-th point of it, farthest
    # first. A cell with a missing corner - a hole in the surface, or a piece
    # the z range cut off - keeps the sides it has but covers nothing: there
    # is no area we could claim is in front.
    #
    # A coarser step is a coarser surface, and that is what the terminal
    # wants. Drawing every line of a fine mesh into a braille canvas does not
    # merely crowd it: neighbouring faces are then two or three dots wide,
    # each rubs out its neighbour's edge where they meet, and the picture
    # comes out speckled. A picture has the room, and takes every line.
    def faces(step = 1)
      down = indices(rows, step)
      across = indices(columns, step)
      faces = []
      down.each_cons(2) do |i0, i1|
        across.each_cons(2) do |j0, j1|
          corners = [[i0, j0], [i1, j0], [i1, j1], [i0, j1]].map { |i, j| mesh[i][j] }
          present = corners.compact
          next if present.size < 2
          points = corners.map { |c| c && project(c) }
          faces << Face.new(points, points.compact.sum { |p| p[2] } / present.size,
                            present.sum(&:last) / present.size.to_f)
        end
      end
      faces.sort_by!(&:depth)
      faces
    end

    # 0, step, 2*step, ... and the last point, so the surface keeps its rim.
    def indices(count, step) = (0..count).step([step, 1].max).to_a.push(count).uniq

    # A face with all four corners covers the quadrilateral they span.
    def polygon(face) = face.corners.all? ? face.corners : nil

    # The sides of a face that have both their ends.
    def sides(face)
      (0..3).filter_map do |k|
        a = face.corners[k]
        b = face.corners[(k + 1) % 4]
        [a, b] if a && b
      end
    end

    # How many mesh points to a face in the terminal: enough that no two mesh
    # lines land closer than APART braille dots, and no more than LINES of
    # them across the picture.
    def terminal_step
      narrow = [@span_u, @span_v].min * scale_for(width * 2, height * 4)
      wanted = [[(narrow / APART).round, 4].max, LINES].min
      [([rows, columns].max / wanted.to_f).round, 1].max
    end

    # The floor of the box and the two walls behind the surface: enough to
    # see which way the axes run, and no more, since a wall in front of the
    # surface would be a lie the depth sort cannot undo.
    def box_edges
      floor = [[@xlo, @ylo], [@xhi, @ylo], [@xhi, @yhi], [@xlo, @yhi]]
      rear = (0..3).min_by { |k| project([*floor[k], @zlo])[2] }
      edges = (0..3).map { |k| [[*floor[k], @zlo], [*floor[(k + 1) % 4], @zlo]] }
      edges << [[*floor[rear], @zlo], [*floor[rear], @zhi]]
      [-1, 1].each { |step| edges << [[*floor[rear], @zhi], [*floor[(rear + step) % 4], @zhi]] }
      edges.map { |a, b| [project(a), project(b)] }
    end

    # ---- the terminal picture ----------------------------------------------

    def to_s
      canvas = Canvas.new(width, height)
      box_edges.each { |a, b| canvas.line(*pixel(a), *pixel(b)) }
      faces(terminal_step).each do |face|
        area = polygon(face)
        erase(canvas, area) if area
        sides(face).each { |a, b| canvas.line(*pixel(a), *pixel(b)) }
      end
      frame(canvas.rows)
    end

    # What a face covers lies behind it. The dots inside the quadrilateral go
    # before its own edges are drawn, so an edge it shares with a neighbour is
    # rubbed out and put back rather than lost. The outline is walked as well
    # as filled: a fine mesh has faces two or three dots wide, and the
    # scanlines of one of those round away to nothing between the corners.
    def erase(canvas, area)
      points = area.map { |p| pixel(p) }
      points.each_index do |k|
        canvas.trace(*points[k], *points[(k + 1) % points.size]) { |px, py| canvas.unset(px, py) }
      end
      ys = points.map(&:last)
      (ys.min..ys.max).each do |py|
        crossings(points, py + 0.5).each_slice(2) do |left, right|
          next if right.nil?
          (left.round..right.round).each { |px| canvas.unset(px, py) }
        end
      end
    end

    # Where a horizontal line meets the outline, left to right. Taking the
    # crossings in pairs fills a quadrilateral that is not convex correctly,
    # which a projected mesh cell need not be.
    def crossings(points, y)
      points.each_index.filter_map do |k|
        x0, y0 = points[k]
        x1, y1 = points[(k + 1) % points.size]
        next if (y0 <= y) == (y1 <= y)
        x0 + (y - y0) * (x1 - x0).to_f / (y1 - y0)
      end.sort
    end

    # No gutter and no axis line: the numbers go underneath instead.
    def frame(art)
      lines = []
      lines << title if title
      lines.concat(art)
      lines << caption
      lines.join("\n")
    end

    # What each of the three axes runs over - the picture cannot say it.
    def caption
      [[axes[0], xlo, xhi], [axes[1], ylo, yhi], [axes[2], zlo, zhi]]
        .map { |name, lo, hi| "#{name}: #{self.class.label(lo)}..#{self.class.label(hi)}" }.join("   ")
    end

    # ---- pictures ----------------------------------------------------------

    def to_svg(theme: nil)
      w, h = svg_size
      theme = (theme || Render.theme).to_s
      background = theme == "light" ? "#ffffff" : "#111827"
      foreground = theme == "light" ? "#111827" : "#e5e7eb"
      grid = theme == "light" ? "#9ca3af" : "#4b5563"
      top = title ? 34 : 14
      area = h - top - 34
      place = ->(p) { screen(p, w - 32, area, 16.0, top.to_f).map { |c| c.round(2) } }
      parts = [%(<rect width="#{w}" height="#{h}" fill="#{background}"/>)]
      parts << %(<text x="#{w / 2}" y="22" fill="#{foreground}" font-family="sans-serif" font-size="16" text-anchor="middle">#{escape(title)}</text>) if title
      stroke = lambda do |a, b, colour, thick|
        (x1, y1) = place.call(a)
        (x2, y2) = place.call(b)
        parts << %(<line x1="#{x1}" y1="#{y1}" x2="#{x2}" y2="#{y2}" stroke="#{colour}" stroke-width="#{thick}"/>)
      end
      box_edges.each { |a, b| stroke.call(a, b, grid, 1) }
      faces.each do |face|
        colour = shade(face.height)
        area_of = polygon(face)
        if area_of
          points = area_of.map { |p| place.call(p).join(",") }.join(" ")
          parts << %(<polygon points="#{points}" fill="#{colour}" fill-opacity="0.9" stroke="#{darken(colour)}" stroke-width="0.7" stroke-linejoin="round"/>)
        else
          sides(face).each { |a, b| stroke.call(a, b, colour, 1.2) }
        end
      end
      parts << %(<text x="#{w / 2}" y="#{h - 12}" fill="#{foreground}" font-family="sans-serif" font-size="13" text-anchor="middle" xml:space="preserve">#{escape(caption)}</text>)
      %(<svg xmlns="http://www.w3.org/2000/svg" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}">#{parts.join}</svg>)
    end

    # The colour of a face: where its height lies between the floor of the
    # box and the top of it.
    def shade(z)
      t = (z - zlo) / (zhi - zlo).to_f
      t = 0.0 unless t.finite?
      t = [[t, 0.0].max, 1.0].min * (RAMP.size - 1)
      blend(RAMP[t.floor], RAMP[t.ceil], t - t.floor)
    end

    def blend(low, high, t)
      pairs = [low, high].map { |colour| channels(colour) }
      "#" + pairs[0].zip(pairs[1]).map { |a, b| format("%02x", (a + (b - a) * t).round) }.join
    end

    def darken(colour, factor = 0.65) = "#" + channels(colour).map { |c| format("%02x", (c * factor).round) }.join

    def channels(colour) = colour[1..].scan(/../).map { |pair| pair.to_i(16) }
  end

  # Building surfaces from expressions.
  module Plotting
    MESH = 24

    module_function

    # plot3d(f, x: -2..2, y: -2..2) for the graph z = f(x, y), or
    # plot3d([X, Y, Z], u: .., v: ..) for a surface given by a parametrization.
    def plot3d(f, n: MESH, z: nil, view: nil, equal: nil, title: nil, width: 60, height: 20, **ranges)
      spans = ranges.select { |_, r| r.is_a?(Range) }
      unnamed = ranges.keys - spans.keys
      raise ArgumentError, "plot3d: expected a range, e.g. #{unnamed.first}: -2..2" unless unnamed.empty?
      raise ArgumentError, "plot3d: give two ranges, e.g. plot3d(f, x: -2..2, y: -2..2)" unless spans.empty? || spans.size == 2
      raise ArgumentError, "plot3d: the mesh n: must be a positive integer" unless n.is_a?(Integer) && n.positive?
      angles = view_angles(view)
      if f.is_a?(Array)
        parametric_surface(f, spans, n, z, angles, equal.nil? || equal, title, width, height)
      else
        explicit_surface(f, spans, n, z, angles, !equal.nil? && equal, title, width, height)
      end
    end

    # The graph z = f(x, y) over a rectangle of the plane.
    def explicit_surface(f, spans, n, z, view, equal, title, width, height)
      g = Expression.lift(f)
      names = spans.empty? ? g.variables : spans.keys
      raise ArgumentError, "plot3d: #{g} has #{names.size} variables; a surface needs two, e.g. x: -2..2, y: -2..2" unless names.size == 2
      bounds = names.map { |name| spans.empty? ? [DEFAULT_LOW, DEFAULT_HIGH] : range_ends(spans[name], name) }
      tree = Expression.floatify_tree(g)
      grid = mesh_points(bounds, n) do |x, y|
        value = value_at(tree, names[0] => x, names[1] => y)
        value && [x, y, value]
      end
      heights = grid.flatten(1).compact.map(&:last)
      raise Plot::Error, "plot3d: #{g} has no finite values in this range" if heights.empty?
      zlo, zhi = z ? range_ends(z, :z) : autoscale(heights.sort)
      Plot3D.new(clip(grid, zlo, zhi),
                 xlo: bounds[0][0], xhi: bounds[0][1], ylo: bounds[1][0], yhi: bounds[1][1], zlo: zlo, zhi: zhi,
                 axes: [names[0], names[1], :z], equal: equal, view: view, title: title, width: width, height: height)
    end

    # A surface given by three components of two parameters. The axes are the
    # coordinates of space, whatever the parameters are called, and all three
    # keep the same scale unless equal: false says otherwise: a sphere drawn
    # in a box of its own would not be round.
    def parametric_surface(components, spans, n, z, view, equal, title, width, height)
      raise ArgumentError, "plot3d: a surface in space has three components, [x(u, v), y(u, v), z(u, v)]" unless components.size == 3
      raise ArgumentError, "plot3d: a parametric surface needs two ranges, e.g. u: 0..PI, v: 0..2*PI" unless spans.size == 2
      names = spans.keys
      bounds = names.map { |name| range_ends(spans[name], name) }
      trees = components.map { |c| Expression.floatify_tree(Expression.lift(c)) }
      grid = mesh_points(bounds, n) do |u, v|
        point = trees.map { |tree| value_at(tree, names[0] => u, names[1] => v) }
        point.all? ? point : nil
      end
      points = grid.flatten(1).compact
      raise Plot::Error, "plot3d: the surface has no finite points in this range" if points.empty?
      xlo, xhi = autoscale(points.map(&:first).sort)
      ylo, yhi = autoscale(points.map { |p| p[1] }.sort)
      zlo, zhi = z ? range_ends(z, :z) : autoscale(points.map(&:last).sort)
      Plot3D.new(clip(grid, zlo, zhi), xlo: xlo, xhi: xhi, ylo: ylo, yhi: yhi, zlo: zlo, zhi: zhi,
                 axes: %i[x y z], equal: equal, view: view, title: title, width: width, height: height)
    end

    # (n + 1) by (n + 1) points of the parameter rectangle, the first
    # parameter along the rows.
    def mesh_points(bounds, n)
      (0..n).map do |i|
        u = bounds[0][0] + (bounds[0][1] - bounds[0][0]) * i / n.to_f
        (0..n).map do |j|
          v = bounds[1][0] + (bounds[1][1] - bounds[1][0]) * j / n.to_f
          yield(u, v)
        end
      end
    end

    # A point above or below the box is a gap, as a value off the top of a
    # plot is: the surface is cut there rather than flattened against the lid.
    def clip(grid, zlo, zhi)
      grid.map { |row| row.map { |point| point&.last&.between?(zlo, zhi) ? point : nil } }
    end

    def value_at(tree, bindings)
      v = tree.call(**bindings)
      v = v.value if v.is_a?(Num)
      return nil unless v.is_a?(Numeric) && !v.is_a?(Complex)
      v = v.to_f
      v.finite? ? v : nil
    rescue StandardError => rescued
      RCAS.guard!(rescued)
      nil
    end

    def range_ends(range, name)
      raise ArgumentError, "plot3d: expected a range, e.g. #{name}: -2..2" unless range.is_a?(Range)
      lo = numeric(range.begin)
      hi = numeric(range.end)
      raise ArgumentError, "plot3d: the #{name} range must be finite, got #{range.begin}..#{range.end}" if lo.nil? || hi.nil?
      raise ArgumentError, "plot3d: the #{name} range is empty" if hi <= lo
      [lo, hi]
    end

    # view: [azimuth, elevation] in degrees - turning the surface round, and
    # raising the eye above it.
    def view_angles(view)
      return Plot3D::VIEW if view.nil?
      raise ArgumentError, "plot3d: view: [azimuth, elevation] in degrees" unless view.is_a?(Array) && view.size == 2
      angles = view.map { |a| numeric(a) }
      raise ArgumentError, "plot3d: the view angles must be numbers" if angles.any?(&:nil?)
      angles
    end
  end
end
