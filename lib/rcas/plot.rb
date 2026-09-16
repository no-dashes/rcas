# frozen_string_literal: true

module RCAS
  # Function plotting.
  #
  #   plot(sin(x))                          # -10..10, drawn in the terminal
  #   plot(x**2 - 1, x: -3..3)
  #   plot([sin(x), cos(x)], x: 0..2*PI)
  #   plot(Normal(0, 1))                    # the density of a distribution
  #   scatter([1, 2, 3], [2, 4, 7])         # data, with linreg(...) alongside
  #   plot(1/x, x: -3..3).save("hyperbola.svg")
  #   plot(sin(x)).show                     # inline picture in iTerm2
  #
  # A Plot prints as Unicode braille art, which needs nothing but a terminal
  # and is what `inspect` shows; `to_svg` and `save` write a picture, `to_png`
  # and `show` rasterize it with headless Chrome (the renderer the typeset
  # output already uses). Sampling is uniform; values that are complex,
  # infinite or undefined leave a gap, and a jump across a pole breaks the
  # line rather than drawing a vertical stroke.
  #
  # Sources (keys: MANUAL.md, Sources): line drawing [Bre65]; the braille
  # canvas is the technique of drawille and UnicodePlots.jl; the y range for
  # functions with poles is trimmed to the central 96 per cent of the sampled
  # values, as gnuplot's autoscaling does in spirit.
  class Plot
    class Error < StandardError; end

    # Braille cells are 2 by 4 dots; these are the bit values of the dots.
    DOTS = [[0x01, 0x02, 0x04, 0x40], [0x08, 0x10, 0x20, 0x80]].freeze
    BRAILLE_BLANK = 0x2800
    COLORS = %w[#2563eb #dc2626 #059669 #d97706 #7c3aed #0891b2].freeze
    DEFAULT_RANGE = (-10.0..10.0)

    Curve = Struct.new(:label, :points, :marker, :width)

    # How a front end shows a plot: :text (braille art, works everywhere) or
    # :image (an inline picture, needs an iTerm2-style terminal and Chrome).
    # RCAS_PLOT_STYLE sets the default; rcas-chat has /plotstyle.
    STYLES = %i[text image].freeze

    class << self
      def style = @style || ENV.fetch("RCAS_PLOT_STYLE", "text").to_sym

      def style=(value)
        wanted = value.to_s.to_sym
        raise Error, "plot style must be one of #{STYLES.join(', ')}" unless STYLES.include?(wanted)
        @style = wanted
      end

      def image? = style == :image

      # Can this terminal show pictures at all?
      def pictures?(io = $stdout) = Render.inline?(io) && !Render.which(*Render::KaTeX::CHROME_CANDIDATES).nil?
    end

    attr_reader :curves, :var, :xlo, :xhi, :ylo, :yhi, :title, :width, :height, :ylabels, :xlabels

    def initialize(curves, var:, xlo:, xhi:, ylo:, yhi:, title: nil, width: 60, height: 15, ylabels: nil, xlabels: nil)
      @curves = curves
      @var = var
      @xlo = xlo
      @xhi = xhi
      @ylo = ylo
      @yhi = yhi
      @title = title
      @width = width
      @height = height
      @ylabels = ylabels   # { value => text } instead of the y range
      @xlabels = xlabels   # [[value, text], ...] instead of the x range
      freeze
    end

    def x_range = (xlo..xhi)
    def y_range = (ylo..yhi)

    # ---- the terminal picture ------------------------------------------------

    def to_s
      canvas = Canvas.new(width, height)
      draw_axes(canvas)
      curves.each { |curve| draw_curve(canvas, curve) }
      frame(canvas.rows)
    end

    def inspect = to_s

    def draw_axes(canvas)
      if ylo < 0 && yhi > 0
        row = pixel_y(0)
        (0...canvas.pixel_width).step(4) { |px| canvas.set(px, row) }
      end
      return unless xlo < 0 && xhi > 0
      column = pixel_x(0)
      (0...canvas.pixel_height).step(2) { |py| canvas.set(column, py) }
    end

    def draw_curve(canvas, curve)
      previous = nil
      curve.points.each do |point|
        if point.nil?
          previous = nil
          next
        end
        x, y = point
        px = pixel_x(x)
        py = pixel_y(y)
        if curve.marker == :bar
          draw_bar(canvas, x, y, curve.width)
          previous = point
          next
        elsif curve.marker == :box
          draw_box(canvas, curve)
          return
        elsif curve.marker == :stem
          base = pixel_y([0.0, ylo].max)
          canvas.line(px, base, px, py)
          canvas.set(px, py)
        elsif curve.marker
          canvas.set(px, py)
        elsif previous && !jump?(previous, point)
          canvas.line(pixel_x(previous[0]), pixel_y(previous[1]), px, py)
        elsif inside?(y)
          canvas.set(px, py)
        end
        previous = point
      end
    end

    # A filled bar of +span+ x units, centred on x, standing on the baseline.
    def draw_bar(canvas, x, y, span)
      left = pixel_x(x - span / 2.0) + 1
      right = pixel_x(x + span / 2.0) - 1
      right = left if right < left
      base = pixel_y([0.0, ylo].max)
      top = pixel_y(y)
      (left..right).each { |px| canvas.line(px, base, px, top) }
    end

    # Box and whiskers: [low, q1, median, q3, high, *outliers] at one height.
    def draw_box(canvas, curve)
      low, q1, median, q3, high = curve.points.first(5).map(&:first)
      y = curve.points.first.last
      middle = pixel_y(y)
      half = [(middle - pixel_y(y + curve.width)).abs, 1].max
      canvas.line(pixel_x(low), middle, pixel_x(q1), middle)          # whiskers
      canvas.line(pixel_x(q3), middle, pixel_x(high), middle)
      [low, high].each { |v| canvas.line(pixel_x(v), middle - half, pixel_x(v), middle + half) }
      [q1, q3, median].each { |v| canvas.line(pixel_x(v), middle - half, pixel_x(v), middle + half) }
      [middle - half, middle + half].each { |row| canvas.line(pixel_x(q1), row, pixel_x(q3), row) }
      curve.points.drop(5).each { |v, _| canvas.set(pixel_x(v), middle) } # outliers
    end

    # A pole: the two samples straddle the whole picture in opposite directions.
    def jump?(a, b)
      return false unless (b[1] - a[1]).abs > (yhi - ylo)
      (a[1] <=> 0) != (b[1] <=> 0)
    end

    def inside?(y) = y >= ylo && y <= yhi

    def pixel_x(x) = (((x - xlo) / (xhi - xlo)) * (width * 2 - 1)).round
    def pixel_y(y) = (((yhi - y) / (yhi - ylo)) * (height * 4 - 1)).round

    def self.label(value)
      return "0" if value.zero?
      text = format("%.4g", value)
      text.include?("e") ? text : text.sub(/\.0+\z/, "")
    end

    # y labels in a gutter, the canvas, then the x axis and its labels.
    def frame(rows)
      gutter_labels = row_labels(rows.size)
      gutter = gutter_labels.compact.map(&:size).max || 0
      lines = []
      lines << title if title
      rows.each_with_index do |row, i|
        mark = gutter_labels[i] ? gutter_labels[i].rjust(gutter) + " ┤" : (" " * gutter) + " │"
        lines << mark + row
      end
      lines << (" " * (gutter + 1)) + "└" + "─" * width
      lines << (" " * (gutter + 2)) + column_labels
      lines << "  " + legend if legend && !legend.empty?
      lines.join("\n")
    end

    # The label for each canvas row: the y range, or the names of a box plot.
    def row_labels(count)
      return Array.new(count) { |i| i.zero? ? self.class.label(yhi) : (i == count - 1 ? self.class.label(ylo) : nil) } unless ylabels
      labels = Array.new(count)
      ylabels.each do |value, text|
        row = pixel_y(value) / 4
        labels[row] = text.to_s if row.between?(0, count - 1)
      end
      labels
    end

    # Under the axis: the ends of the x range, or names centred on their bars.
    def column_labels
      unless xlabels
        left = self.class.label(xlo)
        right = self.class.label(xhi)
        return left + (" " * [width - left.size - right.size, 1].max) + right
      end
      line = " " * width
      xlabels.each do |value, text|
        text = text.to_s
        start = pixel_x(value) / 2 - (text.size - 1) / 2
        start = [[start, 0].max, width - text.size].min
        next if start.negative? || line[start, text.size].to_s.strip != ""
        line[start, text.size] = text
      end
      line.rstrip
    end

    def legend
      names = curves.map(&:label).compact
      names.empty? ? nil : names.join(", ")
    end

    # Counts deserve a whole number at the top of the axis.
    def self.head_room(heights)
      top = heights.max * 1.08
      heights.all? { |h| h == h.round } ? top.ceil.to_f : top
    end

    # ---- pictures --------------------------------------------------------------

    def svg_size = [720, 440]

    def to_svg(theme: nil)
      w, h = svg_size
      theme = (theme || Render.theme).to_s
      background = theme == "light" ? "#ffffff" : "#111827"
      foreground = theme == "light" ? "#111827" : "#e5e7eb"
      grid = theme == "light" ? "#9ca3af" : "#4b5563"
      left = 60
      right = 20
      top = title ? 34 : 16
      bottom = 40
      plot_w = w - left - right
      plot_h = h - top - bottom
      sx = ->(x) { left + (x - xlo) / (xhi - xlo) * plot_w }
      sy = ->(y) { top + (yhi - y) / (yhi - ylo) * plot_h }

      parts = []
      parts << %(<rect width="#{w}" height="#{h}" fill="#{background}"/>)
      parts << %(<text x="#{w / 2}" y="22" fill="#{foreground}" font-family="sans-serif" font-size="16" text-anchor="middle">#{escape(title)}</text>) if title
      parts << %(<rect x="#{left}" y="#{top}" width="#{plot_w}" height="#{plot_h}" fill="none" stroke="#{grid}" stroke-width="1"/>)
      if ylo < 0 && yhi > 0
        y0 = sy.call(0).round(2)
        parts << %(<line x1="#{left}" y1="#{y0}" x2="#{left + plot_w}" y2="#{y0}" stroke="#{grid}" stroke-width="1" stroke-dasharray="4 3"/>)
      end
      if xlo < 0 && xhi > 0
        x0 = sx.call(0).round(2)
        parts << %(<line x1="#{x0}" y1="#{top}" x2="#{x0}" y2="#{top + plot_h}" stroke="#{grid}" stroke-width="1" stroke-dasharray="4 3"/>)
      end
      [[xlo, :x], [xhi, :x]].each_with_index do |(value, _), i|
        x = i.zero? ? left : left + plot_w
        anchor = i.zero? ? "start" : "end"
        parts << %(<text x="#{x}" y="#{h - 14}" fill="#{foreground}" font-family="sans-serif" font-size="13" text-anchor="#{anchor}">#{self.class.label(value)}</text>)
      end
      [[yhi, top + 4], [ylo, top + plot_h]].each do |value, y|
        parts << %(<text x="#{left - 8}" y="#{y}" fill="#{foreground}" font-family="sans-serif" font-size="13" text-anchor="end">#{self.class.label(value)}</text>)
      end
      curves.each_with_index do |curve, i|
        color = COLORS[i % COLORS.size]
        if curve.marker == :bar
          base = sy.call([0.0, ylo].max)
          curve.points.each do |x, y|
            x0 = sx.call(x - curve.width / 2.0)
            x1 = sx.call(x + curve.width / 2.0)
            top_y = sy.call(y)
            parts << %(<rect x="#{x0.round(2)}" y="#{top_y.round(2)}" width="#{[(x1 - x0).abs - 1, 1].max.round(2)}" height="#{(base - top_y).abs.round(2)}" fill="#{color}" fill-opacity="0.75" stroke="#{color}"/>)
          end
        elsif curve.marker == :box
          low, q1, median, q3, high = curve.points.first(5).map(&:first)
          y = curve.points.first.last
          middle = sy.call(y)
          half = (middle - sy.call(y + curve.width)).abs
          parts << %(<line x1="#{sx.call(low).round(2)}" y1="#{middle.round(2)}" x2="#{sx.call(high).round(2)}" y2="#{middle.round(2)}" stroke="#{color}" stroke-width="1.5"/>)
          parts << %(<rect x="#{sx.call(q1).round(2)}" y="#{(middle - half).round(2)}" width="#{(sx.call(q3) - sx.call(q1)).abs.round(2)}" height="#{(2 * half).round(2)}" fill="#{color}" fill-opacity="0.2" stroke="#{color}" stroke-width="1.5"/>)
          [[low, 0.6], [high, 0.6], [median, 1.0]].each do |value, scale_factor|
            parts << %(<line x1="#{sx.call(value).round(2)}" y1="#{(middle - half * scale_factor).round(2)}" x2="#{sx.call(value).round(2)}" y2="#{(middle + half * scale_factor).round(2)}" stroke="#{color}" stroke-width="#{value == median ? 2.5 : 1.5}"/>)
          end
          curve.points.drop(5).each { |v, _| parts << %(<circle cx="#{sx.call(v).round(2)}" cy="#{middle.round(2)}" r="3" fill="none" stroke="#{color}"/>) }
        elsif curve.marker
          base = sy.call([0.0, ylo].max).round(2)
          curve.points.compact.select { |_, y| inside?(y) }.each do |x, y|
            cx = sx.call(x).round(2)
            cy = sy.call(y).round(2)
            parts << %(<line x1="#{cx}" y1="#{base}" x2="#{cx}" y2="#{cy}" stroke="#{color}" stroke-width="2"/>) if curve.marker == :stem
            parts << %(<circle cx="#{cx}" cy="#{cy}" r="3.5" fill="#{color}"/>)
          end
        else
          segments(curve).each do |segment|
            points = segment.map { |x, y| "#{sx.call(x).round(2)},#{sy.call([[y, ylo].max, yhi].min).round(2)}" }.join(" ")
            parts << %(<polyline points="#{points}" fill="none" stroke="#{color}" stroke-width="2" stroke-linejoin="round"/>)
          end
        end
        next unless curve.label
        parts << %(<text x="#{left + 10}" y="#{top + 18 + i * 18}" fill="#{color}" font-family="sans-serif" font-size="13">#{escape(curve.label)}</text>)
      end
      %(<svg xmlns="http://www.w3.org/2000/svg" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}">#{parts.join}</svg>)
    end

    # Pieces of the curve without gaps or jumps across a pole.
    def segments(curve)
      out = []
      current = []
      previous = nil
      curve.points.each do |point|
        if point.nil? || (previous && jump?(previous, point))
          out << current if current.size > 1
          current = []
        end
        current << point if point
        previous = point
      end
      out << current if current.size > 1
      out
    end

    def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

    def to_png(path = nil, theme: nil)
      chrome = Render.which(*Render::KaTeX::CHROME_CANDIDATES)
      raise Error, "a picture needs Google Chrome or Chromium; save(\"plot.svg\") needs nothing" if chrome.nil?
      w, h = svg_size
      bytes = Dir.mktmpdir("rcas-plot") do |dir|
        page = File.join(dir, "plot.html")
        File.write(page, %(<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0}</style></head><body>#{to_svg(theme: theme)}</body></html>))
        shot = File.join(dir, "plot.png")
        Render.run(chrome, "--headless=new", "--disable-gpu", "--no-sandbox", "--hide-scrollbars", "--no-first-run",
                   "--force-device-scale-factor=#{Render.device_scale}", "--window-size=#{w},#{h}",
                   "--screenshot=#{shot}", "file://#{page}")
        raise Error, "Chrome produced no picture" unless File.file?(shot)
        File.binread(shot)
      end
      return bytes if path.nil?
      File.binwrite(path, bytes)
      path
    end

    # "plot.svg" needs nothing, "plot.png" needs Chrome.
    def save(path)
      if File.extname(path).downcase == ".png"
        to_png(path)
      else
        File.write(path, to_svg)
      end
      path
    end

    def picture?(io = $stdout) = self.class.pictures?(io)

    # The picture alone: true when one was written, false when it could not be.
    def picture(io: $stdout)
      return false unless picture?(io)
      io.print(Render.inline_image(to_png, name: "plot.png"))
      io.puts
      true
    rescue Error, Render::Error
      false
    end

    # Inline in iTerm2 when the terminal and Chrome allow it, text otherwise.
    def show(io: $stdout)
      io.puts(to_s) unless picture(io: io)
      nil
    end

    # A grid of braille dots.
    class Canvas
      def initialize(width, height)
        @width = width
        @height = height
        @cells = Array.new(width * height, 0)
      end

      def pixel_width = @width * 2
      def pixel_height = @height * 4

      def set(px, py)
        return if px.negative? || py.negative? || px >= pixel_width || py >= pixel_height
        @cells[(py / 4) * @width + (px / 2)] |= DOTS[px % 2][py % 4]
      end

      # Bresenham's line algorithm [Bre65].
      def line(x0, y0, x1, y1)
        dx = (x1 - x0).abs
        dy = -(y1 - y0).abs
        sx = x0 < x1 ? 1 : -1
        sy = y0 < y1 ? 1 : -1
        error = dx + dy
        x = x0
        y = y0
        loop do
          set(x, y)
          break if x == x1 && y == y1
          double = 2 * error
          if double >= dy
            error += dy
            x += sx
          end
          if double <= dx
            error += dx
            y += sy
          end
        end
      end

      def rows
        (0...@height).map do |cy|
          (0...@width).map { |cx| (BRAILLE_BLANK + @cells[cy * @width + cx]).chr(Encoding::UTF_8) }.join
        end
      end
    end
  end

  # Building plots from expressions, distributions and data.
  module Plotting
    SAMPLES = 400

    module_function

    # plot(f, x: -5..5), plot([f, g], x: 0..1), plot(f, :t, -1, 1)
    def plot(f, var = nil, from = nil, to = nil, x: nil, y: nil, n: SAMPLES, title: nil, labels: nil, width: 60, height: 15)
      functions = f.is_a?(Array) ? f : [f]
      return distribution_plot(functions, var, from, to, x, y, n, title, labels, width, height) if functions.first.is_a?(Distributions::Distribution)
      functions = functions.map { |g| Expression.lift(g) }
      variable = plot_variable(functions, var, x)
      lo, hi = plot_range(var, from, to, x)
      curves = functions.each_with_index.map do |g, i|
        Curve_for(g, variable, lo, hi, n, labels ? labels[i] : (functions.size > 1 ? g.to_s : nil))
      end
      ylo, yhi = y_range(curves, y)
      Plot.new(curves, var: variable, xlo: lo, xhi: hi, ylo: ylo, yhi: yhi, title: title, width: width, height: height)
    end

    def Curve_for(g, variable, lo, hi, n, label)
      Plot::Curve.new(label, sample(g, variable, lo, hi, n), false)
    end

    # The density of a distribution over a sensible range.
    def distribution_plot(distributions, var, from, to, x, y, n, title, labels, width, height)
      variable = Var.new(:x)
      lo, hi = if x || from then plot_range(var, from, to, x) else natural_range(distributions) end
      discrete = distributions.first.discrete?
      curves = distributions.each_with_index.map do |d, i|
        label = labels ? labels[i] : (distributions.size > 1 ? d.to_s : nil)
        if discrete
          points = (lo.ceil..hi.floor).map { |k| [k.to_f, numeric(d.pdf(k))] }.select { |_, v| v }
          Plot::Curve.new(label, points, :stem)
        else
          Plot::Curve.new(label, sample(d.pdf(variable), variable, lo, hi, n), false)
        end
      end
      ylo, yhi = y_range(curves, y)
      ylo = 0.0 if ylo > 0
      Plot.new(curves, var: variable, xlo: lo, xhi: hi, ylo: ylo, yhi: yhi,
               title: title || (distributions.size == 1 ? distributions.first.to_s : nil), width: width, height: height)
    end

    # Mean plus or minus four standard deviations, kept inside the support.
    def natural_range(distributions)
      los = []
      his = []
      distributions.each do |d|
        mean = numeric(d.mean)
        spread = numeric(d.stdev)
        raise Plot::Error, "plot: #{d} has no numeric mean and spread; give a range" if mean.nil? || spread.nil? || spread.zero?
        low = mean - 4 * spread
        high = mean + 4 * spread
        bottom = numeric(d.support.first)
        top = numeric(d.support.last)
        low = bottom if bottom && bottom > low
        high = top if top && top < high
        los << low
        his << high
      end
      [los.min, his.max]
    end

    # A curve given by two components: parametric([cos(t), sin(t)], t: 0..2*PI).
    # The points are joined in the order the parameter runs through them, so
    # the curve may loop and cross itself.
    def parametric(pair, var = nil, from = nil, to = nil, n: SAMPLES, title: nil, label: nil, x: nil, y: nil, width: 60, height: 15, **range)
      raise ArgumentError, "parametric: two components are needed, [x(t), y(t)]" unless pair.is_a?(Array) && pair.size == 2
      var, from, to = Functions.range_arguments(var, from, to, range, "parametric", discrete: false)
      variable = Expression.lift(var)
      lo = numeric(from)
      hi = numeric(to)
      raise ArgumentError, "parametric: the range needs two finite ends" if lo.nil? || hi.nil?
      components = pair.map { |c| Expression.lift(c) }
      points = (0..n).map do |i|
        t = lo + (hi - lo) * i / n.to_f
        values = components.map { |c| evaluate(c, variable.name, t) }
        values.all? ? values : nil
      end
      curve = Plot::Curve.new(label, points, false)
      drawn = points.compact
      raise ArgumentError, "parametric: nothing to draw" if drawn.empty?
      xlo, xhi = x ? [numeric(x.begin), numeric(x.end)] : padded(drawn.map(&:first))
      ylo, yhi = y_range([curve], y)
      Plot.new([curve], var: Var.new(:x), xlo: xlo, xhi: xhi, ylo: ylo, yhi: yhi, title: title, width: width, height: height)
    end

    # A curve in polar coordinates: polar(1 + cos(t), t: 0..2*PI), drawn as
    # the parametric curve (r*cos(t), r*sin(t)). The angle runs over a full
    # turn unless another range is given.
    def polar(r, var = nil, from = nil, to = nil, **opts)
      r = Expression.lift(r)
      unless opts.empty? || opts.keys.none? { |k| opts[k].is_a?(Range) }
        key = opts.keys.find { |k| opts[k].is_a?(Range) }
        span = opts.delete(key)
        var ||= key
        from = span.begin
        to = span.end
      end
      var ||= r.variables.first || :theta
      variable = Expression.lift(var)
      angle = [Fn.new(:cos, [variable]), Fn.new(:sin, [variable])]
      parametric(angle.map { |c| (r * c).simplify }, variable, from || Num.new(0), to || (2 * PI).simplify, **opts)
    end

    # Points of data: scatter([1, 2], [3, 4]) or scatter([[1, 3], [2, 4]])
    def scatter(xs, ys = nil, fit: false, title: nil, label: nil, x: nil, y: nil, width: 60, height: 15)
      given = if ys.nil?
                xs.map { |p| [p[0], p[1]] }
              else
                raise ArgumentError, "scatter: the lists must have the same length" unless xs.size == ys.size
                xs.zip(ys)
              end
      given = given.select { |a, b| numeric(a) && numeric(b) }
      pairs = given.map { |a, b| [numeric(a), numeric(b)] }
      raise ArgumentError, "scatter: no points to draw" if pairs.empty?
      lo, hi = x ? [numeric(x.begin), numeric(x.end)] : padded(pairs.map(&:first))
      curves = [Plot::Curve.new(label, pairs, :dot)]
      if fit # the least squares line of section 1.9
        line = Statistics.linreg(given.map(&:first), given.map(&:last), :x)
        curves << Plot::Curve.new(line.to_s, sample(line, Var.new(:x), lo, hi, 2), false)
      end
      ylo, yhi = y ? [numeric(y.begin), numeric(y.end)] : padded(curves.flat_map { |c| c.points.compact.map(&:last) })
      Plot.new(curves, var: Var.new(:x), xlo: lo, xhi: hi, ylo: ylo, yhi: yhi, title: title, width: width, height: height)
    end

    # ---- statistical plots -------------------------------------------------------

    # histogram(data, bins: 8): counts per bin, or shares with density: true.
    # The default number of bins is Sturges' rule [Stu26].
    def histogram(data, bins: nil, density: false, title: nil, label: nil, x: nil, y: nil, width: 60, height: 15)
      values = Statistics.data(data, "histogram").map { |v| numeric(v) }.compact
      raise ArgumentError, "histogram: no numeric data" if values.empty?
      lo, hi = x ? [numeric(x.begin), numeric(x.end)] : [values.min, values.max]
      lo, hi = [lo - 0.5, hi + 0.5] if (hi - lo).abs < 1e-12
      count = bins || [[Math.log2(values.size).ceil + 1, 1].max, 50].min
      raise ArgumentError, "histogram: bins must be a positive integer" unless count.is_a?(Integer) && count.positive?
      step = (hi - lo) / count
      counts = Array.new(count, 0)
      values.each do |v|
        next if v < lo || v > hi
        index = [((v - lo) / step).floor, count - 1].min
        counts[index] += 1
      end
      heights = density ? counts.map { |c| c.to_f / values.size } : counts.map(&:to_f)
      points = counts.each_index.map { |i| [lo + (i + 0.5) * step, heights[i]] }
      curve = Plot::Curve.new(label, points, :bar, step)
      top = y ? numeric(y.end) : Plot.head_room(heights)
      bottom = y ? numeric(y.begin) : 0.0
      Plot.new([curve], var: Var.new(:x), xlo: lo, xhi: hi, ylo: bottom, yhi: top <= bottom ? bottom + 1 : top,
               title: title, width: width, height: height)
    end

    # boxplot(data), boxplot([xs, ys]) or boxplot("before" => xs, "after" => ys):
    # median, quartiles, whiskers to the last value within 1.5 interquartile
    # ranges and the remaining values as outliers [Tuk77].
    def boxplot(data, title: nil, x: nil, width: 60, height: nil)
      series = series_of(data, "boxplot")
      boxes = series.map do |name, values|
        numbers = values.map { |v| numeric(v) }.compact.sort
        raise ArgumentError, "boxplot: #{name || 'the data'} has no numeric values" if numbers.empty?
        [name, numbers, five_numbers(numbers)]
      end
      all = boxes.flat_map { |_, numbers, _| numbers }
      lo, hi = x ? [numeric(x.begin), numeric(x.end)] : padded(all)
      curves = boxes.each_with_index.map do |(name, numbers, summary), i|
        y = boxes.size - i
        low, q1, median, q3, high = summary
        outliers = numbers.reject { |v| v.between?(low, high) }.map { |v| [v, y] }
        Plot::Curve.new(nil, [[low, y], [q1, y], [median, y], [q3, y], [high, y], *outliers], :box, 0.22)
      end
      labels = boxes.each_with_index.to_h { |(name, _, _), i| [boxes.size - i, name.to_s] }
      Plot.new(curves, var: Var.new(:x), xlo: lo, xhi: hi, ylo: 0.4, yhi: boxes.size + 0.6,
               title: title, width: width, height: height || [4 * boxes.size + 2, 6].max, ylabels: labels)
    end

    # [whisker low, q1, median, q3, whisker high]
    def five_numbers(sorted)
      q1 = numeric(Statistics.quantile(sorted, Rational(1, 4)))
      median = numeric(Statistics.median(sorted))
      q3 = numeric(Statistics.quantile(sorted, Rational(3, 4)))
      reach = 1.5 * (q3 - q1)
      low = sorted.find { |v| v >= q1 - reach } || sorted.first
      high = sorted.reverse.find { |v| v <= q3 + reach } || sorted.last
      [low, q1, median, q3, high]
    end

    # barchart(frequencies(data)), barchart({"apples" => 3, "pears" => 5}) or
    # barchart(%w[a b], [3, 5]): one bar per category.
    def barchart(categories, counts = nil, title: nil, label: nil, y: nil, width: 60, height: 15)
      pairs = if counts
                raise ArgumentError, "barchart: the lists must have the same length" unless categories.size == counts.size
                categories.zip(counts)
              else
                categories.to_a
              end
      raise ArgumentError, "barchart: no categories" if pairs.empty?
      heights = pairs.map { |_, c| numeric(c) or raise ArgumentError, "barchart: #{c} is not a number" }
      points = heights.each_with_index.map { |h, i| [i + 1.0, h] }
      curve = Plot::Curve.new(label, points, :bar, 0.72)
      top = y ? numeric(y.end) : Plot.head_room(heights)
      Plot.new([curve], var: Var.new(:x), xlo: 0.4, xhi: pairs.size + 0.6, ylo: y ? numeric(y.begin) : 0.0,
               yhi: top.positive? ? top : 1.0, title: title, width: width, height: height,
               xlabels: pairs.each_with_index.map { |(name, _), i| [i + 1.0, name.to_s] })
    end

    # A hash of named series, a list of series, or one series.
    def series_of(data, name)
      case data
      when Hash then data.map { |k, v| [k, Statistics.data(v, name)] }
      when Array
        if data.first.is_a?(Array)
          data.each_with_index.map { |values, i| [(i + 1).to_s, Statistics.data(values, name)] }
        else
          [["", Statistics.data(data, name)]]
        end
      else raise ArgumentError, "#{name}: give a list, a list of lists or a hash of named lists"
      end
    end

    def padded(values)
      lo = values.min
      hi = values.max
      return [lo - 1, hi + 1] if (hi - lo).abs < 1e-12
      pad = (hi - lo) * 0.05
      [lo - pad, hi + pad]
    end

    def plot_variable(functions, var, range)
      name = var || (range.is_a?(Hash) ? range.keys.first : nil)
      return Expression.lift(name) if name
      names = functions.flat_map(&:variables).uniq
      raise ArgumentError, "plot: #{functions.first} has no variable to plot over" if names.empty?
      raise ArgumentError, "plot: which variable? give a range, e.g. plot(f, x: -1..1)" if names.size > 1
      Var.new(names.first)
    end

    def plot_range(var, from, to, range)
      if range
        r = range.is_a?(Hash) ? range.values.first : range
        raise ArgumentError, "plot: expected a range, e.g. x: -5..5" unless r.is_a?(Range)
        from = r.begin
        to = r.end
      end
      return [DEFAULT_LOW, DEFAULT_HIGH] if from.nil? && to.nil?
      lo = numeric(from)
      hi = numeric(to)
      raise ArgumentError, "plot: the range must be finite, got #{from}..#{to}" if lo.nil? || hi.nil?
      raise ArgumentError, "plot: the range is empty" if hi <= lo
      [lo, hi]
    end

    DEFAULT_LOW = Plot::DEFAULT_RANGE.begin
    DEFAULT_HIGH = Plot::DEFAULT_RANGE.end

    def sample(g, variable, lo, hi, n)
      tree = Expression.floatify_tree(Expression.lift(g))
      name = variable.name
      (0..n).map do |i|
        x = lo + (hi - lo) * i / n.to_f
        v = evaluate(tree, name, x)
        v ? [x, v] : nil
      end
    end

    def evaluate(tree, name, x)
      v = tree.call(name => x)
      v = v.value if v.is_a?(Num)
      return nil unless v.is_a?(Numeric) && !v.is_a?(Complex)
      v = v.to_f
      v.finite? ? v : nil
    rescue StandardError
      nil
    end

    def numeric(value)
      return nil if value.nil?
      v = value.is_a?(Numeric) ? value : Expression.lift(value).evalf
      v.is_a?(Numeric) && !v.is_a?(Complex) && v.finite? ? v.to_f : nil
    rescue StandardError
      nil
    end

    # Auto scale, trimmed to the central 96 per cent when a pole would
    # otherwise flatten the picture.
    def y_range(curves, given)
      if given
        lo = numeric(given.begin)
        hi = numeric(given.end)
        raise ArgumentError, "plot: the y range must be finite" if lo.nil? || hi.nil?
        return [lo, hi]
      end
      values = curves.flat_map { |c| c.points.compact.map(&:last) }.sort
      raise Plot::Error, "plot: the function has no finite values in this range" if values.empty?
      lo = values.first
      hi = values.last
      if values.size > 20
        low = values[(values.size * 0.02).floor]
        high = values[(values.size * 0.98).floor]
        lo, hi = [low, high] if high > low && (hi - lo) > 8 * (high - low)
      end
      if (hi - lo).abs < 1e-12
        [lo - 1, hi + 1]
      else
        pad = (hi - lo) * 0.05
        [lo - pad, hi + pad]
      end
    end
  end
end
